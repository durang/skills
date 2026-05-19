#!/usr/bin/env bash
# install.sh — Install /ec2-remote-access skill to Claude Code.
#
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/install.sh | bash
#
# Idempotent. Installs only this skill — does NOT touch anything else.
# Reads SKILL.md from this repo's master branch and writes to:
#   ~/.claude/skills/ec2-remote-access/
#
# After install, open Claude Code and run: /ec2-remote-access

set -euo pipefail

REPO="durang/ec2-remote-access"
BRANCH="master"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

SKILL_DIR="${HOME}/.claude/skills/ec2-remote-access"

echo "▶ Installing /ec2-remote-access skill"
echo "  Target: ${SKILL_DIR}"

# Sanity: do we have Claude Code?
if [ ! -d "${HOME}/.claude" ]; then
  echo ""
  echo "⚠️  ${HOME}/.claude does not exist."
  echo "    Install Claude Code first: https://claude.ai/code"
  echo "    Then re-run this installer."
  exit 1
fi

mkdir -p "${SKILL_DIR}"

# Fetch all skill files
for f in SKILL.md README.md TROUBLESHOOTING.md CHANGELOG.md; do
  echo "  → ${f}"
  if ! curl -fsSL "${RAW}/${f}" -o "${SKILL_DIR}/${f}"; then
    echo "❌ Failed to fetch ${f} from ${RAW}/${f}"
    exit 1
  fi
done

echo ""
echo "✅ Installed."
echo ""
echo "Next steps:"
echo "  1. Open Claude Code:        claude"
echo "  2. Inside Claude, run:      /ec2-remote-access"
echo "  3. The skill will guide you step by step to set up SSH + Tailscale + aliases."
echo ""
echo "After setup completes, you'll have these commands available:"
echo "  ec2          → new Claude Code session on your EC2"
echo "  ec2-tmux     → persistent session (survives laptop closes / WiFi drops)"
echo "  ec2-resume   → menu of previous sessions"
echo "  ec2-shell    → terminal only (no Claude)"
echo ""
