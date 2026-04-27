#!/usr/bin/env bash
# Force reinstall and verify

set -euo pipefail

cd "$(dirname "$0")"

echo "=== Step 1: Uninstall old hooks ===" 
bash install.sh --uninstall
sleep 1

echo ""
echo "=== Step 2: Clean up stale hook files ===" 
if [[ -d ~/.agent-hooks ]]; then
  echo "Removing ALL .sh files in ~/.agent-hooks/ (including stale ones):"
  ls -la ~/.agent-hooks/*.sh 2>/dev/null || echo "  (no .sh files found)"
  rm -f ~/.agent-hooks/*.sh 2>/dev/null || true
  echo "✓ Cleaned up stale files"
else
  echo "  (no ~/.agent-hooks directory found)"
fi

echo ""
echo "=== Step 3: Verify keywords.txt ===" 
echo "Active keywords (uncommented lines):"
grep -v "^[[:space:]]*#" keywords.txt | grep -v "^[[:space:]]*$" || echo "  (none found - ERROR!)"

echo ""
echo "=== Step 4: Reinstall hooks ==="
bash install.sh

echo ""
echo "=== Step 5: Verify installed hook ===" 
if [[ -f ~/.agent-hooks/block-hooks.sh ]]; then
  echo "✓ Hook file exists"
  echo ""
  echo "Header (shows keywords used):"
  head -4 ~/.agent-hooks/block-hooks.sh | tail -3
  echo ""
  echo "Blocking patterns:"
  sed -n '/case "\$payload" in/,/return 1/p' ~/.agent-hooks/block-hooks.sh | head -10
else
  echo "✗ ERROR: Hook file not created!"
  exit 1
fi

echo ""
echo "==================================================================="
echo "=== CRITICAL: You MUST fully quit and restart your agents! ==="
echo "==================================================================="
echo ""
echo "Agents cache hooks in memory. Just closing windows is NOT enough."
echo ""
echo "For Cursor:"
echo "  1. Press Cmd+Q (macOS) or close from menu"
echo "  2. Wait 3 seconds"
echo "  3. Relaunch Cursor.app"
echo ""
echo "For Codex CLI:"
echo "  1. Close ALL terminal windows running 'codex'"
echo "  2. Open a NEW terminal"
echo "  3. Run 'codex' again"
echo ""
echo "For Claude CLI:"
echo "  1. Close ALL terminal windows running 'claude'"
echo "  2. Open a NEW terminal"
echo "  3. Run 'claude' again"
echo ""
echo "Test after restarting:"
echo "  - echo 'yossirachman' (should block)"
echo "  - echo 'hello world' (should work)"
echo "==================================================================="
