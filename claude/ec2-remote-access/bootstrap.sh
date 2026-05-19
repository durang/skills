#!/usr/bin/env bash
# bootstrap.sh — Harden a fresh EC2 for Claude Code agent workloads.
#
# Run on a freshly-launched EC2 (Amazon Linux 2023, Ubuntu, Debian, RHEL).
# Idempotent: safe to re-run. Only ADDS configuration, never removes.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/bootstrap.sh | bash
#
# What it does:
#   [1/6] Updates all system packages once (security baseline)
#   [2/6] Installs tmux, git, jq, curl, and auto-security-patches daemon
#   [3/6] Configures auto-security-patches (dnf-automatic or unattended-upgrades)
#   [4/6] Configures shell: PATH persistence + history audit
#   [5/6] Installs Claude Code (auto-updating)
#   [6/6] Verifies IMDSv2 enforcement
#
# After it finishes, on the EC2 run `claude` to authenticate.
# Then on your CLIENT machine run the install.sh + /ec2-remote-access flow.

set -euo pipefail

echo "════════════════════════════════════════════════════════════"
echo "▶ /ec2-remote-access bootstrap.sh"
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

# ─── [6/6] Verify IMDSv2 enforcement ──────────────────────────────────────
echo "▶ [6/6] Verifying IMDSv2 enforcement (EC2 metadata service)"
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

# ─── Done ──────────────────────────────────────
echo "════════════════════════════════════════════════════════════"
echo "✅ EC2 bootstrap complete"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📋 Next steps:"
echo ""
echo "  1. Authenticate Claude Code (run on this EC2):"
echo "       claude"
echo "     A URL appears → open in browser on your Mac → login → paste code back."
echo ""
echo "  2. Run Claude inside tmux for persistence (sobrevives session close):"
echo "       tmux new -s claude"
echo "       claude"
echo "       # Ctrl+B then D to detach (Claude keeps running)"
echo "       # tmux attach -t claude to reattach later"
echo ""
echo "  3. On your CLIENT machine (Mac/laptop), set up daily remote access:"
echo "       curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/install.sh | bash"
echo "       claude"
echo "       /ec2-remote-access"
echo ""
echo "  4. (Recommended) Account-level AWS hardening — do once per AWS account:"
echo "       - CloudTrail (multi-region, S3 encrypted)"
echo "       - GuardDuty (~\$3-5/mo per region)"
echo "       - Budget alert (\$X/month, alerts at 50/80/100%)"
echo "       - DLM (daily EBS snapshots, 7-day retention)"
echo "       - EBS default encryption (account toggle)"
echo "       - SSM Session Manager logging (to S3/CloudWatch)"
echo ""
echo "════════════════════════════════════════════════════════════"
