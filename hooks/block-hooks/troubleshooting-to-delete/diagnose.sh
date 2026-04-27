#!/usr/bin/env bash
# Diagnostic script to identify why old keywords are still being blocked

echo "=== Xyra block-hooks Diagnostic ==="
echo ""

echo "1. Checking hook directory..."
if [[ -d ~/.agent-hooks ]]; then
  echo "   ✓ Directory exists: ~/.agent-hooks"
  ls -la ~/.agent-hooks/
else
  echo "   ✗ Directory not found: ~/.agent-hooks"
fi
echo ""

echo "2. Checking generated hook script..."
if [[ -f ~/.agent-hooks/block-hooks.sh ]]; then
  echo "   ✓ Hook script exists"
  echo "   First 25 lines (showing generated patterns):"
  head -25 ~/.agent-hooks/block-hooks.sh
  echo ""
  echo "   Searching for keyword patterns in is_blocked() function..."
  sed -n '/is_blocked()/,/^}/p' ~/.agent-hooks/block-hooks.sh | head -20
else
  echo "   ✗ Hook script not found: ~/.agent-hooks/block-hooks.sh"
fi
echo ""

echo "3. Checking agent configurations..."
echo ""
echo "   Cursor hooks.json:"
if [[ -f ~/.cursor/hooks.json ]]; then
  echo "   ✓ Found"
  cat ~/.cursor/hooks.json
else
  echo "   ✗ Not found"
fi
echo ""

echo "   Claude Code settings.json:"
if [[ -f ~/.claude/settings.json ]]; then
  echo "   ✓ Found"
  cat ~/.claude/settings.json
else
  echo "   ✗ Not found"
fi
echo ""

echo "   Codex CLI hooks.json:"
if [[ -f ~/.codex/hooks.json ]]; then
  echo "   ✓ Found"
  cat ~/.codex/hooks.json
else
  echo "   ✗ Not found"
fi
echo ""

echo "4. Checking for multiple/stale hook installations..."
find ~ -name "block-hooks.sh" 2>/dev/null | grep -v Projects
echo ""

echo "5. Recent hook activity (last 20 lines)..."
if [[ -f ~/.agent-hooks/agent-hooks.log ]]; then
  tail -20 ~/.agent-hooks/agent-hooks.log
else
  echo "   ✗ Log file not found"
fi
echo ""

echo "=== Diagnostic complete ==="
echo ""
echo "SOLUTION: If old keywords are still in the generated script:"
echo "  1. Run: bash install.sh --uninstall"
echo "  2. Fully quit all agents (Cursor, Claude, Codex)"
echo "  3. Run: bash install.sh"
echo "  4. Restart all agents"
