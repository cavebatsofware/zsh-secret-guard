#!/usr/bin/env zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Grant DeFayette
# =============================================================================
# zsh_secret_guard.zsh
# Prevents secrets from entering zsh history and provides cleanup utilities.
# Delegates all pattern matching and redaction to zsg_secrets.pl.
#
# INSTALLATION:
#   1. Place both files in the same directory (e.g. ~/.zsh_secret_guard/)
#   2. Add to your ~/.zshrc:
#        source ~/.zsh_secret_guard/zsh_secret_guard.zsh
#
# USAGE:
#   Automatic : secrets are silently blocked from history as you type.
#   history_audit  : preview what would be removed from ~/.zsh_history
#   history_scrub  : remove matched lines from ~/.zsh_history (backs up first)
#   zsg_status     : show current configuration
# =============================================================================
 
# ---------------------------------------------------------------------------
# Locate the Perl helper relative to this script
# ---------------------------------------------------------------------------

_ZSG_DIR="${${(%):-%x}:A:h}"
_ZSG_PERL="${_ZSG_DIR}/zsg_secrets.pl"

if [[ ! -x "$_ZSG_PERL" ]]; then
    print -P "%F{red}[secret-guard]%f Cannot find/execute $_ZSG_PERL" >&2
    print -P "%F{red}[secret-guard]%f Run: chmod +x $_ZSG_PERL" >&2
    return 1
fi

# ---------------------------------------------------------------------------
# Configuration — override before sourcing if needed
# ---------------------------------------------------------------------------

: ${ZSH_SECRET_GUARD_WARN:=1}
: ${ZSH_SECRET_GUARD_LOG:=0}
: ${ZSH_SECRET_GUARD_LOG_FILE:="${HOME}/.zsh_secret_guard.log"}

# ---------------------------------------------------------------------------
# zshaddhistory hook
# ---------------------------------------------------------------------------

_zsg_zshaddhistory() {
    local cmd="${1%%$'\n'}"

    [[ ${#cmd} -lt 6 ]] && return 0

    if perl "$_ZSG_PERL" check "$cmd"; then
        if (( ZSH_SECRET_GUARD_WARN )); then
            print -P "%F{yellow}[secret-guard]%f Potential secret detected — not saved to history." >&2
        fi
        if (( ZSH_SECRET_GUARD_LOG )); then
            local redacted
            redacted=$(perl "$_ZSG_PERL" redact "$cmd")
            echo "[$(date '+%Y-%m-%d %T')] BLOCKED: $redacted" >> "$ZSH_SECRET_GUARD_LOG_FILE"
        fi
        return 1   # suppress from history
    fi

    return 0
}

autoload -Uz add-zsh-hook
add-zsh-hook zshaddhistory _zsg_zshaddhistory

# ---------------------------------------------------------------------------
# history_audit — preview secret-matching lines in existing history
# ---------------------------------------------------------------------------

history_audit() {
    local histfile="${HISTFILE:-$HOME/.zsh_history}"
    if [[ ! -f "$histfile" ]]; then
        echo "History file not found: $histfile"
        return 1
    fi

    echo "=== Secret Guard Audit: $histfile ==="
    echo "Lines that WOULD be removed:"
    echo ""
    perl "$_ZSG_PERL" audit "$histfile"
    echo ""
    echo "Run 'history_scrub' to remove them."
}

# ---------------------------------------------------------------------------
# history_scrub — remove secret-matching lines from history
# ---------------------------------------------------------------------------

history_scrub() {
    local histfile="${HISTFILE:-$HOME/.zsh_history}"
    if [[ ! -f "$histfile" ]]; then
        echo "History file not found: $histfile"
        return 1
    fi

    local backup="${histfile}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$histfile" "$backup"
    echo "Backup saved: $backup"

    local tmpfile
    tmpfile=$(mktemp) || { echo "mktemp failed"; return 1 }

    perl "$_ZSG_PERL" scrub "$histfile" > "$tmpfile"

    local before after removed
    before=$(wc -l < "$histfile")
    after=$(wc -l < "$tmpfile")
    removed=$(( before - after ))

    mv "$tmpfile" "$histfile"
    fc -p "$histfile" 2>/dev/null   # reload zsh's in-memory history

    echo "Done. Removed $removed entr$(( removed == 1 ? 'y' : 'ies' )), $after remaining."
    echo "To undo: cp \"$backup\" \"$histfile\""
}

# ---------------------------------------------------------------------------
# zsg_status
# ---------------------------------------------------------------------------

zsg_status() {
    echo "=== zsh Secret Guard ==="
    echo "  Perl helper   : $_ZSG_PERL"
    echo "  Warn on block : $ZSH_SECRET_GUARD_WARN"
    echo "  Logging       : $ZSH_SECRET_GUARD_LOG"
    if (( ZSH_SECRET_GUARD_LOG )); then
        echo "  Log file      : $ZSH_SECRET_GUARD_LOG_FILE"
    fi
    echo ""
    echo "Commands:"
    echo "  history_audit   preview secret-matching lines in your history"
    echo "  history_scrub   remove secret-matching lines from history"
    echo "  zsg_status      show this status"
}
