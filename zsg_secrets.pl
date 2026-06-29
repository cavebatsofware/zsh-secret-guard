#!/usr/bin/env perl
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Grant DeFayette
# =============================================================================
# zsg_secrets.pl - Secret detection and redaction for zsh_secret_guard
#
# MODES (first argument):
#   check   <cmd>     exit 0 if secret found, exit 1 if clean
#   redact  <cmd>     print redacted version of cmd to stdout
#   scrub   <file>    filter a history file, printing clean lines to stdout
#   audit   <file>    print matched (redacted) lines with line numbers to stdout
# =============================================================================
use strict;
use warnings;
use 5.010;

# ---------------------------------------------------------------------------
# Patterns - each is a compiled qr// with an inline comment describing it.
# All matched case-insensitively via the /i flag on each pattern.
# ---------------------------------------------------------------------------

my @PATTERNS = (

    # -- Env-var style assignments -------------------------------------------
    # export API_KEY=..., TOKEN=..., MY_PASSWORD='...', etc.
    qr/
        (?:^|[\s;|&])
        (?:export\s+)?
        [A-Z0-9_]*                      # optional prefix (e.g. MY_, AWS_, or empty)
        (?:TOKEN|SECRET|KEY|PASS(?:WORD)?|PWD|AUTH|CRED(?:ENTIAL)?S?
          |APIKEY|API_KEY|ACCESS_KEY|PRIVATE_KEY|CLIENT_SECRET)
        \s*=\s*\S
    /xi,

    # -- AWS credentials -----------------------------------------------------
    qr/ AWS_ (?:ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN|SECURITY_TOKEN) \s*= /xi,
    qr/ (?:AKIA|ASIA|AROA|ABIA|ACCA) [A-Z0-9]{16} /x,

    # -- GCP / Google --------------------------------------------------------
    qr/ GOOGLE_ (?:APPLICATION_CREDENTIALS|API_KEY|CLOUD_KEY) \s*= /xi,
    qr/ "type" \s*:\s* "service_account" /x,

    # -- Azure ---------------------------------------------------------------
    qr/ AZURE_ (?:CLIENT_SECRET|STORAGE_KEY|SUBSCRIPTION_KEY|SAS_TOKEN) \s*= /xi,

    # -- Common CLI flags ----------------------------------------------------
    # --password, --token, --secret, --api-key, etc.
    qr/
        --
        (?:password|passwd|token|secret|api[-_]?key
          |auth[-_]?token|client[-_]?secret
          |private[-_]?key|access[-_]?key)
        [\s=]\S
    /xi,
    # -p <password>  (short flag, must have a non-flag argument)
    qr/ \s -p \s+ [^-\s]\S+ /x,

    # -- curl / wget with embedded credentials -------------------------------
    qr/ curl .{0,200}? (?: -u\s+\S+:\S+ | -H\s+['"]?Authorization ) /xi,
    qr/ wget .{0,200}? --http-(?:user|password)= /xi,

    # -- Database / service connection strings with password -----------------
    qr{
        (?:postgres(?:ql)?|mysql|mariadb|mongodb(?:\+srv)?|redis|amqps?)
        :// [^:@\s]+ : [^@\s]+ @
    }xi,

    # -- HTTPS URLs with embedded credentials --------------------------------
    qr{ https?:// [^:@\s]+ : [^@\s]+ @ }xi,

    # -- Docker login with password ------------------------------------------
    qr/ docker \s+ login .{0,100}? -p \s+ \S /xi,

    # -- SSH private key material --------------------------------------------
    qr/ -----BEGIN \s+ (?:RSA|EC|DSA|OPENSSH|PGP|GPG) \s+ PRIVATE /xi,

    # -- GitHub tokens -------------------------------------------------------
    qr/ gh [pousr]_ [A-Za-z0-9]{36,} /x,
    qr/ github [._-]? token [\s=]+ [A-Za-z0-9_]{20,} /xi,

    # -- Stripe keys ---------------------------------------------------------
    qr/ (?:sk|pk|rk)_ (?:live|test)_ [A-Za-z0-9]{24,} /xi,

    # -- Slack tokens --------------------------------------------------------
    qr/ xox[baprs]- [A-Za-z0-9-]{10,} /x,

    # -- Twilio --------------------------------------------------------------
    qr/ SK [0-9a-f]{32} /xi,   # API key SID

    # -- npm / pip tokens ----------------------------------------------------
    qr/ NPM_TOKEN \s*= /xi,
    qr/ npm \s+ (?:login|publish|adduser) .{0,100}? --_auth /xi,

    # -- Vault / Terraform ---------------------------------------------------
    qr/ VAULT_TOKEN \s*= /xi,
    qr/ TF_VAR_ [A-Z0-9_]* (?:secret|key|token|pass) \s*= /xi,

    # -- Kubernetes ----------------------------------------------------------
    qr/ kubectl .{0,200}? --token[\s=]\S /xi,

    # -- Long high-entropy strings -------------------------------------------
    # Hex strings ≥ 40 chars (SHA-1 hashes, raw tokens, etc.)
    qr/ [0-9a-f]{40,} /xi,
    # Base64-ish ≥ 32 chars after an = sign (header values, env assignments)
    qr/ = [A-Za-z0-9+\/]{32,} ={0,2} (?:\s|$) /x,

);

# ---------------------------------------------------------------------------
# Redaction substitution - applied with s/// to mask secret values.
# Runs multiple passes so overlapping patterns are all caught.
# ---------------------------------------------------------------------------

sub redact {
    my ($cmd) = @_;

    # Mask = assignments: KEY=value → KEY=<REDACTED>
    $cmd =~ s{
        ( [A-Z][A-Z0-9_]* \s*=\s* )   # capture the VAR= part
        \S{4,}                          # at least 4 non-space chars (the value)
    }{$1<REDACTED>}xgi;

    # Mask --flag=value and --flag value
    $cmd =~ s{
        ( -- [\w-]+ [\s=] )
        (\S{4,})
    }{$1<REDACTED>}xgi;

    # Mask Authorization / Bearer / Basic header values
    $cmd =~ s{
        ( (?:Bearer|Basic|Token) \s+ )
        [A-Za-z0-9._+\/\-]{8,}
    }{$1<REDACTED>}xgi;

    # Mask passwords in connection strings: proto://user:PASS@host
    $cmd =~ s{
        ( (?:https?|postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqps?) :// [^:@\s]+ : )
        [^@\s]+
        ( @ )
    }{$1<REDACTED>$2}xgi;

    # Mask -p <value>
    $cmd =~ s{ ( \s -p \s+ ) \S+ }{$1<REDACTED>}xg;

    # Mask long hex / base64 tokens
    $cmd =~ s/ [0-9a-f]{40,} /<REDACTED>/xgi;
    $cmd =~ s{ (=) [A-Za-z0-9+\/]{32,} ={0,2} }{$1<REDACTED>}xg;

    return $cmd;
}

# ---------------------------------------------------------------------------
# Core predicate
# ---------------------------------------------------------------------------

sub is_secret {
    my ($cmd) = @_;
    for my $pat (@PATTERNS) {
        return 1 if $cmd =~ $pat;
    }
    return 0;
}

# Strip zsh extended history prefix:  ": <timestamp>:<elapsed>;"
sub strip_hist_prefix {
    my ($line) = @_;
    (my $cmd = $line) =~ s/^: \d+:\d+;//;
    return $cmd;
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

my $mode = shift @ARGV // die "Usage: $0 <check|redact|scrub|audit> [args]\n";

if ($mode eq 'check') {
    # Exit 0 = secret found, exit 1 = clean  (mirrors grep convention)
    my $cmd = join(' ', @ARGV);
    exit(is_secret($cmd) ? 0 : 1);

} elsif ($mode eq 'redact') {
    my $cmd = join(' ', @ARGV);
    print redact($cmd), "\n";

} elsif ($mode eq 'scrub') {
    my $file = shift @ARGV // die "scrub requires a filename\n";
    open(my $fh, '<', $file) or die "Cannot open $file: $!\n";
    while (my $line = <$fh>) {
        chomp $line;
        my $cmd = strip_hist_prefix($line);
        if (is_secret($cmd)) {
            # Preserve any zsh extended history prefix, redact the command part
            my ($prefix) = $line =~ /^(: \d+:\d+;)/;
            print(($prefix // '') . redact($cmd) . "\n");
        } else {
            print "$line\n";
        }
    }
    close($fh);

} elsif ($mode eq 'audit') {
    my $file = shift @ARGV // die "audit requires a filename\n";
    open(my $fh, '<', $file) or die "Cannot open $file: $!\n";
    my $lineno  = 0;
    my $matches = 0;
    while (my $line = <$fh>) {
        chomp $line;
        $lineno++;
        my $cmd = strip_hist_prefix($line);
        if (is_secret($cmd)) {
            $matches++;
            printf "  line %5d: %s\n", $lineno, redact($cmd);
        }
    }
    close($fh);
    print "\nTotal matches: $matches\n";
    exit($matches > 0 ? 0 : 1);

} else {
    die "Unknown mode: $mode\n";
}
