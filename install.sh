#!/usr/bin/env bash
# kontrolg — global install for Claude Code
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$HOME/.claude/skills/kontrolg"
CMD_DIR="$HOME/.claude/commands"

if [ ! -f "$SRC/skills/kontrolg/SKILL.md" ]; then
  echo "error: run this from inside the cloned repo" >&2
  exit 1
fi

mkdir -p "$SKILL_DIR/references" "$CMD_DIR"
cp "$SRC/skills/kontrolg/SKILL.md" "$SKILL_DIR/"
cp "$SRC/skills/kontrolg/references/"*.md "$SKILL_DIR/references/"
cp "$SRC/commands/kontrolg.md" "$CMD_DIR/kontrolg.md"

echo "installed:"
echo "  skill   $SKILL_DIR"
echo "  command $CMD_DIR/kontrolg.md"
echo
echo "Open a new Claude Code session and type /kontrolg"
