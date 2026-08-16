#!/usr/bin/env bash
# kontrolg — global install for Claude Code
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$HOME/.claude/skills"
CMD_DIR="$HOME/.claude/commands"

if [ ! -f "$SRC/skills/kontrolg/SKILL.md" ]; then
  echo "error: run this from inside the cloned repo" >&2
  exit 1
fi

mkdir -p "$SKILL_DIR" "$CMD_DIR"
cp -r "$SRC/skills/." "$SKILL_DIR/"

cp "$SRC/commands/"*.md "$CMD_DIR/"

echo "installed:"
echo "  skills   kontrolg, store-preflight"
echo "  commands /kontrolg, /store-preflight"
echo
echo "Open a new Claude Code session and type /kontrolg or /store-preflight"
