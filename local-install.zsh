#!/usr/bin/env zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Grant DeFayette
# =============================================================================
# install.zsh - installer for zsh-secret-guard
# Run from the directory containing zsh_secret_guard.zsh and zsg_secrets.pl
# =============================================================================

set -euo pipefail

INSTALL_DIR="${HOME}/.config/zsh-secret-guard"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
SOURCE_LINE="source \"${INSTALL_DIR}/zsh_secret_guard.zsh\""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

print_info()    { print -P "%F{cyan}  →%f $1" }
print_success() { print -P "%F{green}  ✓%f $1" }
print_warn()    { print -P "%F{yellow}  ⚠%f $1" }
print_error()   { print -P "%F{red}  ✗%f $1" >&2 }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

SCRIPT_DIR="${${(%):-%x}:A:h}"

for f in zsh_secret_guard.zsh zsg_secrets.pl; do
    if [[ ! -f "${SCRIPT_DIR}/${f}" ]]; then
        print_error "Missing file: ${SCRIPT_DIR}/${f}"
        print_error "Run this script from the directory containing both files."
        exit 1
    fi
done

if ! command -v perl &>/dev/null; then
    print_error "perl not found on PATH, required for secret detection."
    exit 1
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

echo ""
echo "Installing zsh-secret-guard"
echo "  From : ${SCRIPT_DIR}"
echo "  To   : ${INSTALL_DIR}"
echo "  zshrc: ${ZSHRC}"
echo ""

mkdir -p "${INSTALL_DIR}"
print_success "Created ${INSTALL_DIR}"

cp "${SCRIPT_DIR}/zsh_secret_guard.zsh" "${INSTALL_DIR}/zsh_secret_guard.zsh"
cp "${SCRIPT_DIR}/zsg_secrets.pl"       "${INSTALL_DIR}/zsg_secrets.pl"
chmod +x "${INSTALL_DIR}/zsg_secrets.pl"
print_success "Copied files and set permissions"

# ---------------------------------------------------------------------------
# Wire up .zshrc (idempotent)
# ---------------------------------------------------------------------------

if [[ -f "${ZSHRC}" ]] && grep -qF "${SOURCE_LINE}" "${ZSHRC}"; then
    print_warn ".zshrc already contains the source line, skipping"
else
    [[ -f "${ZSHRC}" ]] || touch "${ZSHRC}"
    echo "" >> "${ZSHRC}"
    echo "# zsh-secret-guard prevents secrets from entering history" >> "${ZSHRC}"
    echo "${SOURCE_LINE}" >> "${ZSHRC}"
    print_success "Added source line to ${ZSHRC}"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
print_success "Installation complete."
echo ""
echo "  Reload your shell to activate:  source ${ZSHRC}"
echo "  Then verify with:               zsg_status"
echo ""
