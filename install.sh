#!/usr/bin/env bash
# do-tool installer — by Ethan McCartney
# https://github.com/ethanmccartney/do-tool
#
# Usage: curl -fsSL https://raw.githubusercontent.com/ethanmccartney/do-tool/main/install.sh | bash

set -euo pipefail

# ── colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

info()    { echo -e "${CYAN}  →${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }
die()     { echo -e "${RED}  ✗ ERROR:${RESET} $*" >&2; exit 1; }

# ── banner ────────────────────────────────────────────────────────────────────
echo -e "
${BOLD}${CYAN}┌─────────────────────────────────────────┐
│           do-tool  installer            │
│   plain-english → shell command, fast  │
└─────────────────────────────────────────┘${RESET}
"

# ── config ────────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/.local/share/do-tool"
BIN_DIR="$HOME/.local/bin"
MODELS_DIR="$INSTALL_DIR/models"
LOG_DIR="$INSTALL_DIR/logs"

# llama.cpp release
LLAMA_VERSION="b5620"
LLAMA_ASSET="llama-${LLAMA_VERSION}-bin-ubuntu-x64.zip"
LLAMA_URL="https://github.com/ggerganov/llama.cpp/releases/download/${LLAMA_VERSION}/${LLAMA_ASSET}"

# model: Unsloth LFM2.5-1.2B-Instruct Q8_0 (~1.3 GB)
MODEL_FILENAME="LFM2.5-1.2B-Instruct-Q8_0.gguf"
MODEL_URL="https://huggingface.co/unsloth/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q8_0.gguf"

# ── preflight ─────────────────────────────────────────────────────────────────
info "Checking dependencies…"
command -v unzip &>/dev/null || die "'unzip' not found. Run: sudo apt install unzip"
command -v python3 &>/dev/null || die "'python3' not found. Run: sudo apt install python3"

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$MODELS_DIR" "$LOG_DIR"

# ensure ~/.local/bin is on PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR is not on your PATH."
    SHELL_RC="$HOME/.bashrc"
    [[ "$SHELL" == */zsh ]] && SHELL_RC="$HOME/.zshrc"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
    export PATH="$BIN_DIR:$PATH"
    warn "Added to $SHELL_RC — run 'source $SHELL_RC' after install, or open a new terminal."
fi
success "Dependencies OK"

# ── llama.cpp binary ──────────────────────────────────────────────────────────
LLAMA_SERVER="$INSTALL_DIR/bin/llama-server"

if [[ -x "$LLAMA_SERVER" ]]; then
    success "llama.cpp already installed, skipping"
else
    info "Downloading llama.cpp ${LLAMA_VERSION} (precompiled, Ubuntu x64)…"
    TMP_ZIP="$(mktemp /tmp/llama-XXXXXX.zip)"
    if ! curl -fL --progress-bar -o "$TMP_ZIP" "$LLAMA_URL"; then
        rm -f "$TMP_ZIP"
        die "Failed to download llama.cpp. Check your connection."
    fi

    info "Extracting…"
    TMP_DIR="$(mktemp -d)"
    unzip -q "$TMP_ZIP" -d "$TMP_DIR"
    rm -f "$TMP_ZIP"

    mkdir -p "$INSTALL_DIR/bin"
    find "$TMP_DIR" -name "llama-server" -exec cp {} "$LLAMA_SERVER" \; 2>/dev/null || true
    chmod +x "$LLAMA_SERVER" 2>/dev/null || true
    rm -rf "$TMP_DIR"

    [[ -x "$LLAMA_SERVER" ]] || die "llama-server binary not found after extraction. Please report this at github.com/ethanmccartney/do-tool/issues"
    success "llama.cpp installed"
fi

# ── model ─────────────────────────────────────────────────────────────────────
MODEL_PATH="$MODELS_DIR/$MODEL_FILENAME"

if [[ -f "$MODEL_PATH" ]]; then
    success "Model already downloaded, skipping"
else
    info "Downloading Unsloth LFM2.5-1.2B Q8_0 (~1.3 GB) — this takes a minute…"
    if ! curl -fL --progress-bar -o "$MODEL_PATH" "$MODEL_URL"; then
        rm -f "$MODEL_PATH"
        die "Failed to download model. Check your connection."
    fi
    success "Model downloaded"
fi

# ── daemon manager ────────────────────────────────────────────────────────────
cat > "$INSTALL_DIR/daemon.sh" << 'EOF'
#!/usr/bin/env bash
INSTALL_DIR="$HOME/.local/share/do-tool"
PID_FILE="$INSTALL_DIR/server.pid"
PORT=8491

start_server() {
    is_running && return 0
    "$INSTALL_DIR/bin/llama-server" \
        --model     "$INSTALL_DIR/models/LFM2.5-1.2B-Instruct-Q8_0.gguf" \
        --port      "$PORT" \
        --ctx-size  2048 \
        --n-predict 128 \
        --threads   "$(( $(nproc) - 1 ))" \
        --log-disable \
        > "$INSTALL_DIR/logs/server.log" 2>&1 &
    echo $! > "$PID_FILE"
    local i=0
    while (( i < 20 )); do
        sleep 0.5
        curl -sf "http://127.0.0.1:${PORT}/health" &>/dev/null && return 0
        (( i++ ))
    done
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
    return 1
}

stop_server() {
    [[ -f "$PID_FILE" ]] || return 0
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
}

is_running() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid; pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null && curl -sf "http://127.0.0.1:${PORT}/health" &>/dev/null; then
        return 0
    fi
    rm -f "$PID_FILE"
    return 1
}

touch_activity() { date +%s > "$INSTALL_DIR/last_activity"; }

case "${1:-}" in
    start)  start_server  ;;
    stop)   stop_server   ;;
    status) is_running && echo "running" || echo "stopped" ;;
    touch)  touch_activity ;;
esac
EOF
chmod +x "$INSTALL_DIR/daemon.sh"

# ── idle reaper ───────────────────────────────────────────────────────────────
cat > "$INSTALL_DIR/reaper.sh" << 'EOF'
#!/usr/bin/env bash
INSTALL_DIR="$HOME/.local/share/do-tool"
IDLE_TIMEOUT=300
while true; do
    sleep 30
    [[ "$("$INSTALL_DIR/daemon.sh" status)" == "running" ]] || exit 0
    ACTIVITY_FILE="$INSTALL_DIR/last_activity"
    if [[ -f "$ACTIVITY_FILE" ]]; then
        idle=$(( $(date +%s) - $(cat "$ACTIVITY_FILE") ))
        (( idle >= IDLE_TIMEOUT )) && { "$INSTALL_DIR/daemon.sh" stop; exit 0; }
    fi
done
EOF
chmod +x "$INSTALL_DIR/reaper.sh"

# ── the `do` command ──────────────────────────────────────────────────────────
cat > "$BIN_DIR/do" << 'EOF'
#!/usr/bin/env bash
# do — plain-english → shell command
# https://github.com/ethanmccartney/do-tool

set -euo pipefail

INSTALL_DIR="$HOME/.local/share/do-tool"
PORT=8491

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

die()  { echo -e "${RED}✗${RESET} $*" >&2; exit 1; }
info() { echo -e "${DIM}$*${RESET}" >&2; }

# ── safe / blocked lists ──────────────────────────────────────────────────────
SAFE_COMMANDS=(
    ls ll la tree
    cat less head tail wc
    pwd whoami id hostname uname date uptime
    df du free
    find grep egrep fgrep rg fd
    ps top htop
    echo printf
    stat file
    lsblk lscpu lspci lsusb
    ip addr ifconfig netstat ss
    env printenv
    which type whereis
    dmesg journalctl
    systemctl
    ping traceroute
    sort uniq cut awk sed tr
    diff
)

BLOCKED_PATTERNS=(
    "^rm " "^rmdir " "^sudo rm" "^sudo rmdir"
    "^dd " "^sudo dd"
    "mkfs" "fdisk" "parted" "gdisk"
    "chmod 777" "chown root"
    "> /dev/"
    "\|.*bash" "\|.*sh$" "curl.*\|" "wget.*\|"
    ":(){ :|:& };:"
    "/dev/sd" "/dev/nvme" "/dev/mmcblk"
)

is_safe() {
    local cmd="$1"
    local first; first=$(echo "$cmd" | awk '{print $1}' | sed 's|.*/||')
    [[ "$first" == "sudo" ]] && return 1
    for s in "${SAFE_COMMANDS[@]}"; do [[ "$first" == "$s" ]] && return 0; done
    return 1
}

is_blocked() {
    local cmd="$1"
    for p in "${BLOCKED_PATTERNS[@]}"; do
        echo "$cmd" | grep -qE "$p" 2>/dev/null && return 0
    done
    return 1
}

# ── usage ─────────────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    echo -e "${BOLD}do${RESET} — plain-english shell commands"
    echo -e "  ${CYAN}do list all files and their sizes${RESET}"
    echo -e "  ${CYAN}do show disk usage of each folder here${RESET}"
    echo -e "  ${CYAN}do find all log files modified in the last week${RESET}"
    exit 0
fi

QUERY="$*"

# ── ensure server is up ───────────────────────────────────────────────────────
if [[ "$("$INSTALL_DIR/daemon.sh" status)" != "running" ]]; then
    info "Loading model…"
    "$INSTALL_DIR/daemon.sh" start \
        || die "Could not start model server. Check logs: $INSTALL_DIR/logs/server.log"
fi

"$INSTALL_DIR/daemon.sh" touch
pgrep -f "reaper.sh" &>/dev/null || (nohup "$INSTALL_DIR/reaper.sh" &>/dev/null &)

# ── build the prompt ──────────────────────────────────────────────────────────
# The model MUST output a <cmd> block first so we can parse the command
# before/during explanation generation. We stream the response and read it
# in two passes handled by the python helper below.
SYSTEM_PROMPT='You are a Linux shell command generator for Ubuntu/Debian.

The user will describe what they want in plain English.

You MUST respond in this exact format and no other:
<cmd>the shell command here</cmd>
<why>one sentence (max 12 words) explaining what it does</why>

Rules:
- The <cmd> tag must come first, before anything else.
- Output only a single shell command. No markdown, no backticks, no $ prefix.
- The <why> tag is a plain English explanation, one sentence, max 12 words.
- Do not add any other text before, between, or after the tags.'

USER_PROMPT="Linux shell command for: $QUERY"

# ── stream response and parse in parallel ─────────────────────────────────────
# The python script below:
#   1. Opens a streaming SSE connection to llama-server
#   2. Accumulates tokens until </cmd> is seen
#   3. Emits CMD:<command> on stdout immediately
#   4. If the caller signals STOP (via a temp file), kills the stream
#   5. Otherwise continues accumulating until </why> and emits WHY:<explanation>

STOP_FILE="$(mktemp /tmp/do-stop-XXXXXX)"
rm -f "$STOP_FILE"   # exists = stop; not-exists = keep going

RESPONSE="$(python3 - "$PORT" "$STOP_FILE" << 'PYEOF'
import sys, json, urllib.request, os, time

port      = sys.argv[1]
stop_file = sys.argv[2]

system_prompt = os.environ.get("DO_SYSTEM_PROMPT", "")
user_prompt   = os.environ.get("DO_USER_PROMPT",   "")

payload = json.dumps({
    "model": "local",
    "max_tokens": 128,
    "temperature": 0.1,
    "top_p": 0.1,
    "repeat_penalty": 1.1,
    "repeat_last_n": 64,
    "stream": True,
    "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user",   "content": user_prompt}
    ]
}).encode()

req = urllib.request.Request(
    f"http://127.0.0.1:{port}/v1/chat/completions",
    data=payload,
    headers={"Content-Type": "application/json"}
)

buf = ""
cmd_emitted = False
why_emitted = False
token_count = 0

# repetition detector: track last N characters for loop detection
LOOP_WINDOW = 80   # chars to check for repeating pattern
LOOP_REPEATS = 3   # how many times a pattern must repeat to be flagged

def is_looping(text, window=LOOP_WINDOW, repeats=LOOP_REPEATS):
    if len(text) < window * repeats:
        return False
    tail = text[-(window * repeats):]
    chunk = tail[:window]
    return tail.count(chunk) >= repeats

try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        for raw in resp:
            # honour stop signal
            if os.path.exists(stop_file):
                break

            line = raw.decode("utf-8", errors="replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                chunk = json.loads(data)
                delta = chunk["choices"][0]["delta"].get("content", "")
                buf += delta
                token_count += 1
            except Exception:
                continue

            # repetition / loop detection
            if is_looping(buf):
                if not cmd_emitted:
                    print("ERR:model appears to be looping — no command produced", file=sys.stderr)
                    sys.exit(1)
                # cmd was already emitted; just stop, don't bother with why
                break

            # emit command as soon as </cmd> is complete
            if not cmd_emitted and "</cmd>" in buf:
                try:
                    cmd = buf.split("<cmd>")[1].split("</cmd>")[0].strip()
                    cmd = cmd.strip("`").lstrip("$ ").splitlines()[0].strip()
                    print(f"CMD:{cmd}", flush=True)
                    cmd_emitted = True
                except Exception:
                    pass

            # emit explanation when </why> is complete
            if cmd_emitted and not why_emitted and "</why>" in buf:
                try:
                    why = buf.split("<why>")[1].split("</why>")[0].strip()
                    print(f"WHY:{why}", flush=True)
                    why_emitted = True
                except Exception:
                    pass

            if cmd_emitted and why_emitted:
                break
except Exception as e:
    print(f"ERR:{e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)" DO_SYSTEM_PROMPT="$SYSTEM_PROMPT" DO_USER_PROMPT="$USER_PROMPT"

# parse CMD and WHY from helper output
CMD=""; WHY=""
while IFS= read -r line; do
    [[ "$line" == CMD:* ]] && CMD="${line#CMD:}"
    [[ "$line" == WHY:* ]] && WHY="${line#WHY:}"
done <<< "$RESPONSE"

rm -f "$STOP_FILE"

[[ -z "$CMD" ]] && die "Model returned an empty command. Try rephrasing."

echo ""

# ── blocked? hard stop ────────────────────────────────────────────────────────
if is_blocked "$CMD"; then
    echo -e "${RED}  ✗ Blocked${RESET}"
    echo -e "  ${BOLD}Command:${RESET} ${CYAN}$CMD${RESET}"
    echo -e "  ${DIM}This command pattern is never run automatically.${RESET}"
    echo -e "  ${DIM}Review it carefully before running manually.${RESET}"
    echo ""
    exit 1
fi

# ── safe → run immediately ────────────────────────────────────────────────────
if is_safe "$CMD"; then
    # Signal the stream to stop (explanation not needed for safe commands)
    touch "$STOP_FILE" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Running:${RESET} ${BOLD}${CYAN}$CMD${RESET}"
    echo ""
    eval "$CMD"
    exit $?
fi

# ── needs approval — explanation already generated in parallel ─────────────────
[[ -z "$WHY" ]] && WHY="(no explanation generated)"

echo -e "${YELLOW}  ⚠  Needs approval${RESET}"
echo -e "  ${BOLD}Command:${RESET}    ${CYAN}$CMD${RESET}"
echo -e "  ${BOLD}What it does:${RESET} $WHY"
echo ""
read -rp "  Run this? [y/N] " answer
echo ""

case "${answer,,}" in
    y|yes)
        echo -e "${GREEN}  ✓ Running…${RESET}"
        echo ""
        eval "$CMD"
        ;;
    *)
        echo -e "${DIM}  Cancelled.${RESET}"
        exit 0
        ;;
esac
EOF
chmod +x "$BIN_DIR/do"

# ── uninstaller ───────────────────────────────────────────────────────────────
cat > "$INSTALL_DIR/uninstall.sh" << 'EOF'
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
EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}┌─────────────────────────────────────────┐
│         Installation complete!          │
└─────────────────────────────────────────┘${RESET}"
echo ""
echo -e "  Try it:  ${CYAN}${BOLD}do list all files and their sizes${RESET}"
echo -e "  Or:      ${CYAN}${BOLD}do show how much disk space each folder is using${RESET}"
echo ""
echo -e "  ${DIM}Model stays warm for 5 minutes after last use.${RESET}"
echo -e "  ${DIM}Uninstall: bash ~/.local/share/do-tool/uninstall.sh${RESET}"
echo -e "  ${DIM}Or:        curl -fsSL https://raw.githubusercontent.com/ethanmccartney/do-tool/main/uninstall.sh | bash${RESET}"
echo ""
warn "If 'do' isn't found yet, run: source ~/.bashrc  (or open a new terminal)"
echo ""
