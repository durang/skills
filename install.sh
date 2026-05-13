#!/usr/bin/env bash
# install.sh — Sync skills monorepo → local skill directories.
#
# Idempotent. Reads frontmatter `distribute-to:` from each SKILL.md and copies
# to the matching directory (~/.claude/skills/ for claude, ~/.openclaw/skills/
# for openclaw, both for shared).
#
# Flags:
#   (no flag)        Apply current state (default behavior)
#   --interactive    Ask about orphan skills (those without distribute-to:)
#   --prune          Remove skills from local dirs that no longer exist in the repo
#   --dry-run        Show what would happen without applying
#
# Exit codes:
#   0  success
#   1  errors during sync
#   2  --interactive needed but ran in non-interactive mode

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude/skills"
OPENCLAW_DIR="${HOME}/.openclaw/skills"

INTERACTIVE=0
PRUNE=0
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --interactive) INTERACTIVE=1 ;;
    --prune)       PRUNE=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    -h|--help)     sed -n '2,/^$/p' "$0" | sed 's/^# //'; exit 0 ;;
    *)             echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

mkdir -p "$CLAUDE_DIR" "$OPENCLAW_DIR"

# ─── Helpers ────────────────────────────────────────────────────────
extract_distribute_to() {
  # Read distribute-to: [...] from frontmatter. Returns space-separated list.
  local file="$1"
  awk '/^---$/{c++; next} c==1{print}' "$file" 2>/dev/null \
    | grep -E '^distribute-to:' \
    | sed -E 's/distribute-to:\s*\[([^]]+)\]/\1/' \
    | tr -d '"' | tr ',' ' '
}

infer_target_from_path() {
  # Subdirectory convention wins. Returns space-separated targets.
  local rel="$1"  # e.g. "claude/foo/SKILL.md" or "shared/bar/SKILL.md"
  case "$rel" in
    claude/*)   echo "claude" ;;
    openclaw/*) echo "openclaw" ;;
    shared/*)   echo "claude openclaw" ;;
    *)          echo "" ;;
  esac
}

infer_target_from_name() {
  # Heuristic by skill name (last resort, only used if root-level + no frontmatter).
  local name="$1"
  case "$name" in
    gsap-*|mcp-*|claude-*|*-track|*-monitor|*-security) echo "claude" ;;
    brain-*|signal-*|*-detector|*-ingest|*-ingestion)   echo "openclaw" ;;
    *)                                                  echo "" ;;
  esac
}

copy_skill() {
  local src_dir="$1"  # full path to skill dir in repo
  local target="$2"   # "claude" or "openclaw"
  local skill_name; skill_name=$(basename "$src_dir")
  local dest_dir
  case "$target" in
    claude)   dest_dir="$CLAUDE_DIR/$skill_name" ;;
    openclaw) dest_dir="$OPENCLAW_DIR/$skill_name" ;;
    *)        echo "  ✗ unknown target: $target" >&2; return 1 ;;
  esac

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] would copy $src_dir → $dest_dir"
    return 0
  fi

  mkdir -p "$dest_dir"
  cp -a "$src_dir/." "$dest_dir/"
  echo "  ✓ $skill_name → $target"
}

# ─── Phase 1: Apply ─────────────────────────────────────────────────
echo "▶ Sync repo → local skill directories"
echo ""

orphans=()
applied=0

while IFS= read -r -d '' skill_md; do
  skill_dir=$(dirname "$skill_md")
  rel_skill_md="${skill_md#$SCRIPT_DIR/}"
  rel_skill_dir="${skill_dir#$SCRIPT_DIR/}"

  # Skip top-level files (README.md etc.) and legacy folders (handled by .gitignore at git level)
  case "$rel_skill_dir" in
    landing-gen/*|lead-scraper/*|.git/*|.githooks/*|node_modules/*) continue ;;
  esac

  # Subfolder convention takes precedence
  targets=$(infer_target_from_path "$rel_skill_md")

  # If no subfolder match, look at frontmatter
  if [ -z "$targets" ]; then
    targets=$(extract_distribute_to "$skill_md")
  fi

  # Last resort: name-based heuristic
  if [ -z "$targets" ]; then
    skill_name=$(basename "$skill_dir")
    targets=$(infer_target_from_name "$skill_name")
  fi

  # Still nothing? It's an orphan
  if [ -z "$targets" ]; then
    orphans+=("$rel_skill_dir")
    continue
  fi

  for t in $targets; do
    copy_skill "$skill_dir" "$t"
    applied=$((applied+1))
  done
done < <(find "$SCRIPT_DIR" -name SKILL.md -not -path '*/.git/*' -not -path '*/landing-gen/*' -not -path '*/lead-scraper/*' -print0)

# ─── Phase 1b: External skills (.external-source pointer files) ─────
# A skill directory can replace SKILL.md with a .external-source file containing
# the absolute path to a SKILL.md that lives in another repo. Install.sh resolves
# the path and deploys that SKILL.md as if it lived here. This avoids duplicating
# SKILL.md across repos (e.g., whatsapp lives canonically in whatsapp-monitor).
while IFS= read -r -d '' ext_marker; do
  skill_dir=$(dirname "$ext_marker")
  rel_skill_dir="${skill_dir#$SCRIPT_DIR/}"
  # Read the external path (expand $HOME and other env vars)
  external_path=$(envsubst < "$ext_marker" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | head -1)
  if [ -z "$external_path" ] || [ ! -f "$external_path" ]; then
    echo "  ⚠️  external skill $rel_skill_dir: source not found ($external_path) — skip"
    continue
  fi
  # Targets: subfolder convention first, then distribute-to of external SKILL.md
  targets=$(infer_target_from_path "$rel_skill_dir/SKILL.md")
  [ -z "$targets" ] && targets=$(extract_distribute_to "$external_path")
  if [ -z "$targets" ]; then
    orphans+=("$rel_skill_dir (external, no targets)")
    continue
  fi
  for t in $targets; do
    skill_name=$(basename "$skill_dir")
    case "$t" in
      claude)   dest_dir="$CLAUDE_DIR/$skill_name" ;;
      openclaw) dest_dir="$OPENCLAW_DIR/$skill_name" ;;
      *)        echo "  ✗ unknown target: $t" >&2; continue ;;
    esac
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  [dry-run] would copy $external_path → $dest_dir/SKILL.md"
    else
      mkdir -p "$dest_dir"
      cp "$external_path" "$dest_dir/SKILL.md"
      echo "  ✓ $skill_name → $t (external: $external_path)"
    fi
    applied=$((applied+1))
  done
done < <(find "$SCRIPT_DIR" -name .external-source -not -path '*/.git/*' -print0)

echo ""
echo "▶ Applied: $applied skill copies"

# ─── Phase 2: Orphans ───────────────────────────────────────────────
if [ ${#orphans[@]} -gt 0 ]; then
  echo ""
  echo "⚠ Orphan skills (no distribute-to: tag, no subfolder, no name match):"
  for o in "${orphans[@]}"; do echo "    - $o"; done
  echo ""

  if [ "$INTERACTIVE" -eq 1 ]; then
    echo "Tagging interactively..."
    for o in "${orphans[@]}"; do
      skill_md="$SCRIPT_DIR/$o/SKILL.md"
      echo ""
      echo "  $o — Target?"
      echo "    [c] claude only    [o] openclaw only    [b] both    [s] skip"
      read -r -p "  > " ans
      case "$ans" in
        c|C) sed -i '/^---$/,/^---$/ { /^name:/a\distribute-to: [claude]
}' "$skill_md" ;;
        o|O) sed -i '/^---$/,/^---$/ { /^name:/a\distribute-to: [openclaw]
}' "$skill_md" ;;
        b|B) sed -i '/^---$/,/^---$/ { /^name:/a\distribute-to: [claude, openclaw]
}' "$skill_md" ;;
        s|S) echo "    skipped" ;;
        *)   echo "    invalid, skipped" ;;
      esac
    done
    echo ""
    echo "Re-run ./install.sh to apply tagged orphans."
    exit 0
  else
    echo "  Run with --interactive to tag them."
  fi
fi

# ─── Phase 3: Prune ─────────────────────────────────────────────────
if [ "$PRUNE" -eq 1 ]; then
  echo ""
  echo "▶ Pruning skills no longer in the repo"

  prune_dir() {
    local target_dir="$1"  # e.g. ~/.claude/skills
    local repo_subdir="$2" # e.g. "claude shared"  (space-separated)

    local dest_skills_in_repo=()
    for sub in $repo_subdir; do
      [ -d "$SCRIPT_DIR/$sub" ] && for d in "$SCRIPT_DIR/$sub"/*/; do
        [ -d "$d" ] && dest_skills_in_repo+=("$(basename "$d")")
      done
    done

    for installed in "$target_dir"/*/; do
      [ -d "$installed" ] || continue
      name=$(basename "$installed")
      found=0
      for valid in "${dest_skills_in_repo[@]}"; do
        if [ "$name" = "$valid" ]; then found=1; break; fi
      done
      if [ "$found" -eq 0 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          echo "  [dry-run] would remove $installed"
        else
          rm -rf "$installed"
          echo "  ✗ pruned $installed"
        fi
      fi
    done
  }

  prune_dir "$CLAUDE_DIR"   "claude shared"
  prune_dir "$OPENCLAW_DIR" "openclaw shared"
fi

# ─── Phase 4: OpenClaw reload hint ──────────────────────────────────
if [ "$applied" -gt 0 ] && [ -d "$OPENCLAW_DIR" ]; then
  if find "$SCRIPT_DIR/openclaw" "$SCRIPT_DIR/shared" -name "*.md" -newer "$OPENCLAW_DIR" 2>/dev/null | head -1 | grep -q .; then
    echo ""
    echo "💡 OpenClaw skills changed. To reload immediately:"
    echo "   systemctl --user restart openclaw-gateway openclaw-node"
    echo "   (Otherwise next agent restart picks them up)"
  fi
fi

echo ""
echo "✓ install.sh done."
