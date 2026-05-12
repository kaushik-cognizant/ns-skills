#!/usr/bin/env bash
#
# ns-skills installer (macOS / Linux / WSL / Git Bash)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kaushik-cognizant/ns-skills/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/kaushik-cognizant/ns-skills/main/install.sh | bash -s -- --local
#   curl -fsSL https://raw.githubusercontent.com/kaushik-cognizant/ns-skills/main/install.sh | SCOPE=local bash
#
# Flags:
#   --global, -g          Install to ~/.claude/skills (default)
#   --local,  -l          Install to ./.claude/skills (current directory)
#   --repo OWNER/REPO     Override source repo
#   --branch BRANCH       Override source branch
#   -h, --help            Show this help

set -euo pipefail

REPO="${NS_SKILLS_REPO:-kaushik-cognizant/ns-skills}"
BRANCH="${NS_SKILLS_BRANCH:-main}"
SCOPE="${SCOPE:-global}"

print_help() {
  cat <<'EOF'
ns-skills installer

Flags:
  --global, -g          Install to ~/.claude/skills (default)
  --local,  -l          Install to ./.claude/skills (current directory)
  --repo OWNER/REPO     Override source repo (default: kaushik-cognizant/ns-skills)
  --branch BRANCH       Override source branch (default: main)
  -h, --help            Show this help

Environment overrides: SCOPE, NS_SKILLS_REPO, NS_SKILLS_BRANCH.
EOF
}

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2:0:1}" == "-" ]]; then
    echo "Missing value for $1" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global|-g) SCOPE="global"; shift ;;
    --local|-l)  SCOPE="local";  shift ;;
    --repo)      require_value "$@"; REPO="$2";   shift 2 ;;
    --branch)    require_value "$@"; BRANCH="$2"; shift 2 ;;
    -h|--help)   print_help; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$SCOPE" in
  global) TARGET="$HOME/.claude/skills" ;;
  local)  TARGET="$(pwd)/.claude/skills" ;;
  *) echo "Invalid SCOPE: $SCOPE (use 'global' or 'local')" >&2; exit 1 ;;
esac

for cmd in curl tar mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

echo "Installing ns-skills"
echo "  Source: github.com/$REPO@$BRANCH"
echo "  Scope:  $SCOPE"
echo "  Target: $TARGET"

mkdir -p "$TARGET"

TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t ns-skills)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL_URL="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
echo "  Downloading tarball..."
curl -fsSL "$TARBALL_URL" | tar -xz -C "$TMPDIR"

SRC_DIR=""
for d in "$TMPDIR"/*/skills; do
  [[ -d "$d" ]] && SRC_DIR="$d" && break
done

if [[ -z "$SRC_DIR" ]]; then
  echo "Could not find skills/ directory in tarball" >&2
  exit 1
fi

installed=0
for skill_path in "$SRC_DIR"/*/; do
  [[ -d "$skill_path" ]] || continue
  name=$(basename "$skill_path")
  echo "  Installing skill: $name"
  rm -rf "$TARGET/$name"
  cp -R "$skill_path" "$TARGET/$name"
  installed=$((installed + 1))
done

if [[ "$installed" -eq 0 ]]; then
  echo "No skills found to install." >&2
  exit 1
fi

echo ""
echo "Installed $installed skill(s) to $TARGET"
echo "Restart Claude Code and run /help to verify."
