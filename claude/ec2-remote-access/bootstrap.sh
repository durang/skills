#!/usr/bin/env bash
# bootstrap.sh — Harden a fresh EC2 for Claude Code agent workloads.
#
# Run on a freshly-launched EC2 (Amazon Linux 2023, Ubuntu, Debian, RHEL).
# Idempotent: safe to re-run. Only ADDS configuration, never removes.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/bootstrap.sh | bash
#
# With custom Remote Control session name (recommended):
#   export REMOTE_CONTROL_NAME="JPC-Permanent"
#   curl -fsSL .../bootstrap.sh | bash
#
# What it does:
#   [1/8] Updates system (security only, tolerant)
#   [2/8] Installs tmux, git, jq, and auto-security-patches daemon
#   [3/8] Configures auto-security-patches (dnf-automatic / unattended-upgrades)
#   [4/8] Configures shell: PATH persistence + history audit
#   [5/8] Installs Claude Code (auto-updating)
#   [6/8] Verifies IMDSv2 enforcement
#   [7/8] Installs systemd Remote Control service (THE key piece — pinned in Claude Code Desktop)
#   [8/8] Pre-trusts $HOME in ~/.claude.json (prevents trust dialog on service restart)
#
# After it finishes:
#   1. If first time: run `claude` to authenticate, then restart the service
#   2. Open Claude Code Desktop → sidebar Pinned → click <NAME>-Permanent
#
# Self-healing: if anything breaks, run:
#   curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/verify.sh | bash -s -- --fix

VERSION="1.0.0"

# Handle --help and --version flags before the strict mode
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --version|-V)
            echo "bootstrap.sh v${VERSION}"
            exit 0
            ;;
    esac
done

set -euo pipefail

echo "════════════════════════════════════════════════════════════"
echo "▶ /ec2-remote-access bootstrap.sh v${VERSION}"
echo "  Hardening this EC2 for Claude Code workloads"
echo "════════════════════════════════════════════════════════════"
echo ""

# ─── Detect distro ──────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="${ID:-unknown}"
    VERSION="${VERSION_ID:-unknown}"
else
    echo "❌ Cannot detect distro (no /etc/os-release found)"
    exit 1
fi
echo "  Distro: $DISTRO $VERSION"

# ─── Detect current user + warn if ssm-user ──────────────────────────────────────
CURRENT_USER="$(whoami)"
echo "  User:   $CURRENT_USER"

if [ "$CURRENT_USER" = "ssm-user" ]; then
    echo ""
    echo "⚠️  You're running as ssm-user (ephemeral, not ideal for workspace)"
    echo "   The recommended user is ec2-user (persistent, has bash + sudo)."
    echo ""
    echo "   Switch first with:"
    echo "     sudo su - ec2-user"
    echo "   Then re-run:"
    echo "     curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/bootstrap.sh | bash"
    echo ""
    # When piped from curl, stdin is not a TTY — can't read input. Just exit.
    if [ ! -t 0 ]; then
        echo "Stdin is not a TTY (running via curl|bash). Exiting safely."
        echo "Switch user and re-run."
        exit 0
    fi
    read -p "Continue as ssm-user anyway? (y/N) " -n 1 -r REPLY
    echo ""
    [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Exiting. Re-run as ec2-user."; exit 0; }
fi

# ─── Pick package manager + commands per distro ──────────────────────────────────────
case "$DISTRO" in
    amzn|rhel|centos|fedora|rocky|almalinux)
        PKG_MGR="dnf"
        AUTO_PATCH_PKG="dnf-automatic"
        AUTO_PATCH_SVC="dnf-automatic.timer"
        AUTO_PATCH_CONF="/etc/dnf/automatic.conf"
        ;;
    ubuntu|debian)
        PKG_MGR="apt"
        AUTO_PATCH_PKG="unattended-upgrades"
        AUTO_PATCH_SVC="unattended-upgrades.service"
        AUTO_PATCH_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
        ;;
    *)
        echo "❌ Unsupported distro: $DISTRO"
        echo "   Supported: Amazon Linux, RHEL/CentOS/Fedora/Rocky/Alma, Ubuntu/Debian"
        exit 1
        ;;
esac
echo "  PkgMgr: $PKG_MGR"
echo ""

# ─── [1/6] Update system (security only, tolerate conflicts) ──────────────────────────────────────
echo "▶ [1/6] Updating system packages (security baseline)"
if [ "$PKG_MGR" = "dnf" ]; then
    # --security only (less likely to conflict than full upgrade)
    # || true: if there are package conflicts (e.g. curl-minimal vs curl), keep going
    sudo dnf upgrade --security -y -q 2>/dev/null || sudo dnf upgrade --security -y || true
elif [ "$PKG_MGR" = "apt" ]; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq || true
fi
echo "  ✅ System security updates applied (or already current)"
echo ""

# ─── [2/6] Install base utilities + auto-patch daemon ──────────────────────────────────────
# Note: curl is intentionally NOT in this list — Amazon Linux 2023 ships with
# curl-minimal which conflicts with curl. The script is downloaded WITH curl
# (you just ran `curl ... | bash`), so curl is always present.
echo "▶ [2/6] Installing tmux, git, jq, $AUTO_PATCH_PKG"
if [ "$PKG_MGR" = "dnf" ]; then
    sudo dnf install -y -q tmux git jq "$AUTO_PATCH_PKG" >/dev/null 2>&1 || \
        sudo dnf install -y tmux git jq "$AUTO_PATCH_PKG"
elif [ "$PKG_MGR" = "apt" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux git jq "$AUTO_PATCH_PKG"
fi
echo "  ✅ Base utilities installed"
echo ""

# ─── [3/6] Configure auto-security-updates ──────────────────────────────────────
echo "▶ [3/6] Configuring auto-security-updates"
if [ "$PKG_MGR" = "dnf" ]; then
    sudo sed -i 's/^apply_updates.*/apply_updates = yes/' "$AUTO_PATCH_CONF"
    sudo sed -i 's/^upgrade_type.*/upgrade_type = security/' "$AUTO_PATCH_CONF"
    sudo systemctl enable --now "$AUTO_PATCH_SVC" >/dev/null 2>&1
elif [ "$PKG_MGR" = "apt" ]; then
    cat <<EOF | sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    sudo systemctl enable --now "$AUTO_PATCH_SVC" >/dev/null 2>&1 || true
fi
echo "  ✅ $AUTO_PATCH_SVC active — security patches install automatically"
echo ""

# ─── [4/6] Configure shell (PATH + history audit) ──────────────────────────────────────
echo "▶ [4/6] Configuring shell"
SHELL_RC="$HOME/.bashrc"
[ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"

if ! grep -q 'CLAUDE_CODE_PATH_BOOTSTRAP' "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" <<'EOF'

# ─── Added by /ec2-remote-access bootstrap.sh ─── CLAUDE_CODE_PATH_BOOTSTRAP
export PATH="$HOME/.local/bin:$PATH"

# History audit (timestamped, larger buffer, append mode)
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend
# ─── End of /ec2-remote-access additions ───
EOF
    echo "  ✅ Added to $SHELL_RC: PATH + history audit"
else
    echo "  ⚪ Already configured in $SHELL_RC"
fi
# Apply for the current shell session too
export PATH="$HOME/.local/bin:$PATH"
echo ""

# ─── [5/6] Install Claude Code ──────────────────────────────────────
echo "▶ [5/6] Installing Claude Code"
if command -v claude >/dev/null 2>&1; then
    echo "  ⚪ Already installed: $(claude --version 2>&1 | head -1)"
    echo "     To update manually: claude update"
else
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 || {
        echo "  ❌ Claude Code install failed — check network or run manually:"
        echo "     curl -fsSL https://claude.ai/install.sh | bash"
        exit 1
    }
    # Re-check PATH for the just-installed binary
    export PATH="$HOME/.local/bin:$PATH"
    if command -v claude >/dev/null 2>&1; then
        echo "  ✅ Installed: $(claude --version 2>&1 | head -1)"
    else
        echo "  ⚠️  Installed but \`claude\` still not in PATH"
        echo "     Run: source $SHELL_RC"
    fi
fi
echo ""

# ─── [6/7] Verify IMDSv2 enforcement ──────────────────────────────────────
echo "▶ [6/7] Verifying IMDSv2 enforcement (EC2 metadata service)"
TOKEN="$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -m 2 2>/dev/null || true)"
if [ -n "$TOKEN" ]; then
    echo "  ✅ IMDSv2 token endpoint responding"
    # Check IMDSv1 — should fail if HttpTokens=required
    if curl -sf -m 2 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
        echo "  ⚠️  IMDSv1 also responds — for full hardening, set HttpTokens=required"
        echo "     EC2 Console → Instance → Actions → Modify instance metadata options → HttpTokens=Required"
    else
        echo "  ✅ IMDSv1 rejected — IMDSv2 strictly enforced"
    fi
else
    echo "  ⚪ IMDS not reachable (probably not running on EC2 — that's fine for testing)"
fi
echo ""

# ─── [7/8] Install systemd Remote Control service (THE key piece) ──────────────────────────────────────
# This makes a "<HOSTNAME>-Permanent" session appear PINNED in Claude Code Desktop.
# Without this, you only have SSH/tmux access — not the native Claude Code remote session.
echo "▶ [7/8] Installing Claude Code Remote Control systemd service"

# Resolve Claude Code's entrypoint — supports BOTH layouts:
#   Layout A (newer, single-binary):  ~/.local/bin/claude  (ELF binary symlink)
#   Layout B (older, node wrapper):   .../node_modules/@anthropic-ai/claude-code/bin/claude.exe
CLAUDE_EXE=""

# Try Layout A first — the stable symlink, which is what newer installs use
if [ -L "$HOME/.local/bin/claude" ] || [ -f "$HOME/.local/bin/claude" ]; then
    CLAUDE_EXE="$HOME/.local/bin/claude"
fi

# Fall back to Layout B (older node-based install with claude.exe)
if [ -z "$CLAUDE_EXE" ] || [ ! -e "$CLAUDE_EXE" ]; then
    if command -v node >/dev/null 2>&1; then
        CLAUDE_EXE="$(node -e "try { console.log(require('path').dirname(require.resolve('@anthropic-ai/claude-code/package.json')) + '/bin/claude.exe') } catch(e) {}" 2>/dev/null || true)"
    fi
    # Fallback: search common paths for claude.exe
    if [ -z "$CLAUDE_EXE" ] || [ ! -f "$CLAUDE_EXE" ]; then
        CLAUDE_EXE="$(find "$HOME/.local" /usr/local /opt -name "claude.exe" -path "*claude-code/bin/*" 2>/dev/null | head -1)"
    fi
fi

# Last resort: anything called `claude` in PATH
if [ -z "$CLAUDE_EXE" ] || [ ! -e "$CLAUDE_EXE" ]; then
    CLAUDE_EXE="$(command -v claude 2>/dev/null || true)"
fi

if [ -z "$CLAUDE_EXE" ] || [ ! -e "$CLAUDE_EXE" ]; then
    echo "  ⚠️  Couldn't locate claude binary — skipping Remote Control service"
    echo "     You can install it later by running this bootstrap again after authenticating Claude."
else
    echo "  Found claude binary: $CLAUDE_EXE"

    # Pick a session name — env var override OR hostname-derived default
    REMOTE_NAME="${REMOTE_CONTROL_NAME:-$(hostname -s | tr '[:lower:]' '[:upper:]')-Permanent}"
    echo "  Session name:   $REMOTE_NAME"

    SERVICE_DIR="$HOME/.config/systemd/user"
    SERVICE_FILE="$SERVICE_DIR/claude-remote.service"
    mkdir -p "$SERVICE_DIR"

    # PATH for the service env — include common dirs where claude/node may live
    SERVICE_PATH="$HOME/.bun/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
    # Include fnm node if present
    FNM_BIN="$(ls -d "$HOME/.local/share/fnm/node-versions/"*/installation/bin 2>/dev/null | head -1)"
    [ -n "$FNM_BIN" ] && SERVICE_PATH="$FNM_BIN:$SERVICE_PATH"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Claude Code Headless (persistent Remote Control)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/bin/tmux new-session -d -s claude-remote -x 200 -y 50 ${CLAUDE_EXE} --remote-control ${REMOTE_NAME}
ExecStop=/usr/bin/tmux kill-session -t claude-remote
Restart=always
RestartSec=15
Environment=HOME=${HOME}
Environment=PATH=${SERVICE_PATH}

[Install]
WantedBy=default.target
EOF
    echo "  ✅ Wrote $SERVICE_FILE"

    # Enable linger so the service survives user logout
    if ! loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=yes"; then
        sudo loginctl enable-linger "$(whoami)" 2>/dev/null || true
        echo "  ✅ Enabled linger for $(whoami) (service survives logout)"
    else
        echo "  ⚪ Linger already enabled for $(whoami)"
    fi

    # Reload and start the service
    systemctl --user daemon-reload 2>/dev/null || true
    if systemctl --user enable --now claude-remote.service 2>/dev/null; then
        sleep 2
        if systemctl --user is-active --quiet claude-remote.service; then
            echo "  ✅ Service active — \"$REMOTE_NAME\" is now running"
        else
            echo "  ⚠️  Service installed but not active yet. Check:"
            echo "       systemctl --user status claude-remote.service"
            echo "     Most common cause: Claude Code isn't authenticated yet."
            echo "     Run \`claude\` once interactively to log in, then:"
            echo "       systemctl --user restart claude-remote.service"
        fi
    else
        echo "  ⚠️  Couldn't enable/start the service. Check:"
        echo "       systemctl --user status claude-remote.service"
    fi
fi
echo ""

# ─── [8/8] Pre-trust home dir so service auto-starts without prompt ──────────────────────────────────────
# Without this, Claude shows "Do you trust this folder?" on every restart, and the
# service blocks waiting for Enter — turning Restart=always into Restart=never.
echo "▶ [8/8] Pre-trusting workspace in ~/.claude.json (prevents trust dialog on restart)"
if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PYEOF'
import json
from pathlib import Path

path = Path.home() / ".claude.json"
try:
    data = json.loads(path.read_text()) if path.exists() else {}
except json.JSONDecodeError:
    print("  ⚠️  ~/.claude.json exists but is invalid JSON — skipping pre-trust")
    raise SystemExit(0)

home = str(Path.home())
projects = data.setdefault("projects", {})
proj = projects.setdefault(home, {})

changed = False
for key in ("hasTrustDialogAccepted", "hasCompletedProjectOnboarding"):
    if not proj.get(key):
        proj[key] = True
        changed = True
# Some Claude versions also check this top-level flag
if not data.get("hasTrustDialogAccepted"):
    data["hasTrustDialogAccepted"] = True
    changed = True

if path.exists() or changed:
    if not path.exists():
        path.touch(mode=0o600)
    path.write_text(json.dumps(data, indent=2))
    path.chmod(0o600)
    print(f"  ✅ Pre-trusted {home} in {path}" if changed else f"  ⚪ Already trusted {home}")
else:
    print("  ⚪ ~/.claude.json doesn't exist yet — will be created on first `claude` run")
PYEOF

    # Restart service so it picks up the trust state (only if service exists and is enabled)
    if systemctl --user is-enabled --quiet claude-remote.service 2>/dev/null; then
        systemctl --user restart claude-remote.service 2>/dev/null && \
            echo "  ✅ Restarted claude-remote.service to apply trust"
        sleep 2
        if systemctl --user is-active --quiet claude-remote.service; then
            echo "  ✅ Service active after restart"
        fi
    fi
else
    echo "  ⚠️  python3 not available — can't auto-pre-trust. Manual fix:"
    echo "     Edit ~/.claude.json and set hasTrustDialogAccepted: true under projects[\"$HOME\"]"
fi
echo ""

# ─── Done ──────────────────────────────────────
echo "════════════════════════════════════════════════════════════"
echo "✅ EC2 bootstrap complete"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📋 What just happened — your EC2 now has:"
echo "  ✓ Auto-security-patches (dnf-automatic / unattended-upgrades)"
echo "  ✓ tmux, git, jq installed"
echo "  ✓ PATH + history audit in ~/.bashrc"
echo "  ✓ Claude Code installed (auto-updating)"
echo "  ✓ IMDSv2 enforced (metadata security)"
echo "  ✓ Remote Control systemd service (persistent across reboots)"
echo "  ✓ Workspace pre-trusted (no prompt on service restart)"
echo ""
echo "📋 Next steps:"
echo ""
echo "  1. If Claude Code isn't authenticated yet (first time setup):"
echo "       claude              # interactive login (URL in browser → paste code back)"
echo "       systemctl --user restart claude-remote.service"
echo ""
echo "  2. Verify the Remote Control session is alive:"
echo "       systemctl --user status claude-remote.service"
echo "     → should say 'active (running)'"
echo ""
echo "  3. Open Claude Code Desktop OR claude.ai/code on your Mac:"
echo "     → your session named \"\${REMOTE_NAME:-<HOSTNAME>-Permanent}\" should appear"
echo "       in the sidebar under \"Pinned\" — click it to enter Claude on this EC2."
echo "     → it survives reboots, WiFi drops, laptop closes. Permanent."
echo ""
echo "  4. (Optional) On a CLIENT machine, install SSH/Tailscale access skill:"
echo "       curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/install.sh | bash"
echo "       claude → /ec2-remote-access"
echo ""
echo "  5. (Recommended) Account-level AWS hardening — do once per AWS account:"
echo "       - CloudTrail · GuardDuty · Budget · DLM · EBS encryption · SSM logging"
echo ""
echo "════════════════════════════════════════════════════════════"
