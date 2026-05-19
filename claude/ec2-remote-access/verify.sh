#!/usr/bin/env bash
# verify.sh — Self-diagnostic + auto-healer for /ec2-remote-access.
#
# Runs all 8 checks from bootstrap.sh in READ-ONLY mode + offers to auto-fix
# anything red. Idempotent. Safe to re-run anytime.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/verify.sh | bash
#
# With auto-fix:
#   curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/verify.sh | bash -s -- --fix

VERSION="1.0.0"
set -uo pipefail

AUTO_FIX=0
for arg in "$@"; do
    case "$arg" in
        --fix|-f) AUTO_FIX=1 ;;
        --help|-h)
            cat <<EOF
verify.sh v${VERSION} — diagnose + heal /ec2-remote-access bootstrap state

Usage:
  verify.sh           # diagnostic only (read-only)
  verify.sh --fix     # diagnose + auto-fix anything broken
  verify.sh --help    # this help

What it checks (8 items):
  1. Running as ec2-user (not ssm-user)
  2. dnf-automatic / unattended-upgrades active
  3. tmux + git + jq installed
  4. Shell config (PATH + history audit) in .bashrc
  5. Claude Code installed and resolvable
  6. IMDSv2 enforced
  7. claude-remote.service active (--remote-control)
  8. Workspace pre-trusted in ~/.claude.json (no prompt on restart)
EOF
            exit 0
            ;;
    esac
done

# ─── Output helpers ──────────────────────────────────────
PASS=0; FAIL=0; FIXED=0; SKIPPED=0
declare -a ISSUES=()

green="\033[32m"; red="\033[31m"; yellow="\033[33m"; reset="\033[0m"
check_ok()   { echo -e "  ${green}✅${reset} $1"; PASS=$((PASS+1)); }
check_warn() { echo -e "  ${yellow}⚠️${reset}  $1"; SKIPPED=$((SKIPPED+1)); }
check_fail() { echo -e "  ${red}❌${reset} $1"; FAIL=$((FAIL+1)); ISSUES+=("$2"); }
fixed_ok()   { echo -e "  ${green}🔧${reset} $1"; FIXED=$((FIXED+1)); }

echo "════════════════════════════════════════════════════════════"
echo "▶ /ec2-remote-access verify.sh v${VERSION}"
[ "$AUTO_FIX" = "1" ] && echo "  Auto-fix: ENABLED" || echo "  Auto-fix: disabled (use --fix to enable)"
echo "════════════════════════════════════════════════════════════"
echo ""

# ─── Detect distro ──────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="${ID:-unknown}"
else
    DISTRO="unknown"
fi

case "$DISTRO" in
    amzn|rhel|centos|fedora|rocky|almalinux) PKG_MGR="dnf"; AUTO_PATCH_SVC="dnf-automatic.timer" ;;
    ubuntu|debian)                            PKG_MGR="apt"; AUTO_PATCH_SVC="unattended-upgrades.service" ;;
    *) PKG_MGR="?"; AUTO_PATCH_SVC="?" ;;
esac

# ─── 1. User ──────────────────────────────────────
echo "▶ [1/8] User"
if [ "$(whoami)" = "ec2-user" ]; then
    check_ok "Running as ec2-user (persistent, has bash + sudo)"
elif [ "$(whoami)" = "ssm-user" ]; then
    check_fail "Running as ssm-user (ephemeral)" "switch_user"
    echo "    Fix manual: sudo su - ec2-user && curl ... verify.sh | bash"
else
    check_warn "Running as $(whoami) (not ec2-user or ssm-user)"
fi
echo ""

# ─── 2. Auto-patches daemon ──────────────────────────────────────
echo "▶ [2/8] Auto-security-patches daemon"
if [ "$PKG_MGR" = "?" ]; then
    check_warn "Unknown distro — skipped"
elif systemctl is-active --quiet "$AUTO_PATCH_SVC" 2>/dev/null; then
    check_ok "$AUTO_PATCH_SVC active"
elif systemctl is-enabled --quiet "$AUTO_PATCH_SVC" 2>/dev/null; then
    check_fail "$AUTO_PATCH_SVC enabled but not active" "start_autopatch"
    if [ "$AUTO_FIX" = "1" ]; then
        sudo systemctl start "$AUTO_PATCH_SVC" 2>/dev/null && fixed_ok "Started $AUTO_PATCH_SVC"
    fi
else
    check_fail "$AUTO_PATCH_SVC not installed/enabled" "install_autopatch"
    [ "$AUTO_FIX" = "1" ] && echo "    To fix: re-run bootstrap.sh (it installs + enables)"
fi
echo ""

# ─── 3. Base utilities ──────────────────────────────────────
echo "▶ [3/8] Base utilities (tmux git jq)"
missing=()
for tool in tmux git jq; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ ${#missing[@]} -eq 0 ]; then
    check_ok "tmux, git, jq all installed"
else
    check_fail "Missing: ${missing[*]}" "install_utils"
    if [ "$AUTO_FIX" = "1" ] && [ "$PKG_MGR" = "dnf" ]; then
        sudo dnf install -y -q "${missing[@]}" >/dev/null 2>&1 && fixed_ok "Installed: ${missing[*]}"
    elif [ "$AUTO_FIX" = "1" ] && [ "$PKG_MGR" = "apt" ]; then
        sudo apt-get install -y -qq "${missing[@]}" 2>/dev/null && fixed_ok "Installed: ${missing[*]}"
    fi
fi
echo ""

# ─── 4. Shell config ──────────────────────────────────────
echo "▶ [4/8] Shell config (PATH + history audit)"
SHELL_RC="$HOME/.bashrc"
[ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"
if grep -q 'CLAUDE_CODE_PATH_BOOTSTRAP' "$SHELL_RC" 2>/dev/null; then
    check_ok "Bootstrap marker present in $SHELL_RC"
else
    check_fail "Bootstrap shell config missing in $SHELL_RC" "add_shell"
    if [ "$AUTO_FIX" = "1" ]; then
        cat >> "$SHELL_RC" <<'EOF'

# ─── Added by /ec2-remote-access verify.sh ─── CLAUDE_CODE_PATH_BOOTSTRAP
export PATH="$HOME/.local/bin:$PATH"
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend
# ─── End ───
EOF
        fixed_ok "Added PATH + history audit to $SHELL_RC"
    fi
fi
echo ""

# ─── 5. Claude Code installed ──────────────────────────────────────
echo "▶ [5/8] Claude Code installed"
CLAUDE_EXE=""
for cand in "$HOME/.local/bin/claude" "$(command -v claude 2>/dev/null || true)"; do
    if [ -n "$cand" ] && [ -e "$cand" ]; then CLAUDE_EXE="$cand"; break; fi
done
if [ -z "$CLAUDE_EXE" ]; then
    CLAUDE_EXE="$(find "$HOME/.local" -name "claude.exe" -path "*claude-code/bin/*" 2>/dev/null | head -1)"
fi
if [ -n "$CLAUDE_EXE" ] && [ -e "$CLAUDE_EXE" ]; then
    VERSION_LINE="$(${CLAUDE_EXE} --version 2>&1 | head -1 || echo "version unknown")"
    check_ok "Found: $CLAUDE_EXE — $VERSION_LINE"
else
    check_fail "Claude Code not found in standard paths" "install_claude"
    if [ "$AUTO_FIX" = "1" ]; then
        curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 && fixed_ok "Installed Claude Code"
    fi
fi
echo ""

# ─── 6. IMDSv2 enforced ──────────────────────────────────────
echo "▶ [6/8] IMDSv2 enforcement"
TOKEN="$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -m 2 2>/dev/null || true)"
if [ -z "$TOKEN" ]; then
    check_warn "IMDS not reachable (not on EC2?)"
elif curl -sf -m 2 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
    check_fail "IMDSv1 still responds — should be rejected for full hardening" "imds_v1"
    echo "    Fix manual: EC2 console → instance → Actions → Modify metadata options → HttpTokens=Required"
else
    check_ok "IMDSv2 enforced (v1 rejected)"
fi
echo ""

# ─── 7. Remote Control systemd service ──────────────────────────────────────
echo "▶ [7/8] Remote Control systemd service"
SERVICE_FILE="$HOME/.config/systemd/user/claude-remote.service"
if [ ! -f "$SERVICE_FILE" ]; then
    check_fail "Service unit file not found" "no_service"
    [ "$AUTO_FIX" = "1" ] && echo "    To fix: re-run bootstrap.sh (creates the unit)"
elif systemctl --user is-active --quiet claude-remote.service 2>/dev/null; then
    REMOTE_NAME="$(grep -oP -- '--remote-control \K\S+' "$SERVICE_FILE" 2>/dev/null || echo "?")"
    check_ok "claude-remote.service ACTIVE — session name: $REMOTE_NAME"
elif systemctl --user is-enabled --quiet claude-remote.service 2>/dev/null; then
    check_fail "Service enabled but not active" "service_stopped"
    if [ "$AUTO_FIX" = "1" ]; then
        systemctl --user restart claude-remote.service 2>/dev/null && fixed_ok "Restarted service"
    fi
else
    check_fail "Service file exists but not enabled" "service_disabled"
    if [ "$AUTO_FIX" = "1" ]; then
        systemctl --user enable --now claude-remote.service 2>/dev/null && fixed_ok "Enabled + started"
    fi
fi

# Check linger
if loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=yes"; then
    check_ok "Linger enabled — service survives logout"
else
    check_fail "Linger NOT enabled — service dies on logout" "linger"
    if [ "$AUTO_FIX" = "1" ]; then
        sudo loginctl enable-linger "$(whoami)" 2>/dev/null && fixed_ok "Enabled linger"
    fi
fi
echo ""

# ─── 8. Workspace pre-trusted ──────────────────────────────────────
echo "▶ [8/8] Workspace pre-trusted in ~/.claude.json"
CLAUDE_JSON="$HOME/.claude.json"
if [ ! -f "$CLAUDE_JSON" ]; then
    check_warn "~/.claude.json doesn't exist (run \`claude\` once to authenticate first)"
elif command -v python3 >/dev/null 2>&1; then
    STATE=$(python3 -c "
import json
try:
    d = json.load(open('$CLAUDE_JSON'))
    p = d.get('projects', {}).get('$HOME', {})
    print('OK' if p.get('hasTrustDialogAccepted') else 'NO')
except: print('ERR')
")
    if [ "$STATE" = "OK" ]; then
        check_ok "$HOME is pre-trusted in ~/.claude.json"
    elif [ "$STATE" = "NO" ]; then
        check_fail "$HOME NOT pre-trusted — will block on service restart" "no_trust"
        if [ "$AUTO_FIX" = "1" ]; then
            python3 -c "
import json
path = '$CLAUDE_JSON'
d = json.load(open(path))
d.setdefault('projects', {}).setdefault('$HOME', {})['hasTrustDialogAccepted'] = True
d['projects']['$HOME']['hasCompletedProjectOnboarding'] = True
json.dump(d, open(path, 'w'), indent=2)
" && fixed_ok "Pre-trusted $HOME in ~/.claude.json"
            systemctl --user restart claude-remote.service 2>/dev/null && fixed_ok "Restarted service"
        fi
    fi
else
    check_warn "python3 not available — can't check ~/.claude.json"
fi
echo ""

# ─── Summary ──────────────────────────────────────
echo "════════════════════════════════════════════════════════════"
echo "📊 Summary"
echo "  ✅ Passed:  $PASS"
[ $FIXED  -gt 0 ] && echo "  🔧 Fixed:   $FIXED"
[ $FAIL   -gt 0 ] && echo "  ❌ Failed:  $FAIL"
[ $SKIPPED -gt 0 ] && echo "  ⚠️  Skipped: $SKIPPED"
echo "════════════════════════════════════════════════════════════"

if [ $FAIL -gt 0 ] && [ "$AUTO_FIX" = "0" ]; then
    echo ""
    echo "💡 To auto-fix everything: re-run with --fix"
    echo "   curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/verify.sh | bash -s -- --fix"
    exit 1
fi

[ $FAIL -gt 0 ] && exit 1 || exit 0
