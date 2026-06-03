#!/usr/bin/env bash
# do-tool uninstaller — removes everything cleanly
# Run with: bash ~/.local/share/do-tool/uninstall.sh
# Or one-liner: curl -fsSL https://raw.githubusercontent.com/ethanmccartney/do-tool/main/uninstall.sh | bash

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

info()    { echo -e "${CYAN}  →${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }

INSTALL_DIR="$HOME/.local/share/do-tool"
BIN_DIR="$HOME/.local/bin"

echo -e "
${BOLD}${RED}┌─────────────────────────────────────────┐
│         do-tool  uninstaller            │
└─────────────────────────────────────────┘${RESET}
"

# ── confirm ────────────────────────────────────────────────────────────────────
# skip prompt if running non-interactively (piped from curl)
if [[ -t 0 ]]; then
    read -rp "  This will remove do-tool completely. Continue? [y/N] " confirm
    echo ""
    case "${confirm,,}" in
        y|yes) ;;
        *) echo -e "${DIM}  Cancelled.${RESET}"; exit 0 ;;
    esac
fi

# ── stop server ────────────────────────────────────────────────────────────────
info "Stopping model server…"
if [[ -f "$INSTALL_DIR/daemon.sh" ]]; then
    bash "$INSTALL_DIR/daemon.sh" stop 2>/dev/null || true
    success "Server stopped"
else
    echo -e "  ${DIM}(no daemon found)${RESET}"
fi

# ── kill any stray reaper processes ───────────────────────────────────────────
info "Cleaning up background processes…"
pkill -f "do-tool/reaper.sh" 2>/dev/null || true
success "Processes cleared"

# ── remove binary ──────────────────────────────────────────────────────────────
info "Removing 'do' command…"
if [[ -f "$BIN_DIR/do" ]]; then
    rm -f "$BIN_DIR/do"
    success "Removed $BIN_DIR/do"
else
    echo -e "  ${DIM}($BIN_DIR/do not found, skipping)${RESET}"
fi

# ── remove install dir ────────────────────────────────────────────────────────
info "Removing program files and model…"
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
    success "Removed $INSTALL_DIR"
else
    echo -e "  ${DIM}($INSTALL_DIR not found, skipping)${RESET}"
fi

# ── remove temp files ─────────────────────────────────────────────────────────
info "Cleaning temp files…"
rm -f /tmp/do-stop-* 2>/dev/null || true
success "Temp files cleared"

# ── remove PATH line from shell rc ────────────────────────────────────────────
info "Cleaning up shell PATH entry…"
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$rc" ]] && grep -q 'do-tool\|\.local/bin' "$rc" 2>/dev/null; then
        # only remove the line if it was added by do-tool
        if grep -q 'local/bin' "$rc"; then
            # check if ~/.local/bin is actually still useful (other tools may use it)
            other_tools=$(find "$BIN_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
            if [[ "$other_tools" -eq 0 ]]; then
                sed -i '/export PATH.*\.local\/bin/d' "$rc"
                success "Removed PATH entry from $rc"
            else
                warn "Other tools exist in $BIN_DIR — leaving PATH entry in $rc"
            fi
        fi
    fi
done

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}  do-tool has been completely removed.${RESET}"
echo -e "  ${DIM}Open a new terminal for shell changes to take effect.${RESET}"
echo ""
