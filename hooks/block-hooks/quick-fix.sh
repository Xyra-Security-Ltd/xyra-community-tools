#!/usr/bin/env bash
# ONE-LINE FIX: Clean up and reinstall hooks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔧 Cleaning up stale hooks..."
bash install.sh --uninstall >/dev/null 2>&1 || true
rm -f ~/.agent-hooks/*.sh 2>/dev/null || true

echo "📦 Reinstalling with current keywords..."
bash install.sh

echo ""
echo "✅ Fix complete!"
echo ""
echo "⚠️  CRITICAL: You MUST now do this:"
echo ""
echo "1. **Cursor users**: Press Cmd+Q, then relaunch Cursor"
echo "2. **Codex/Claude CLI users**: Close terminals, open new ones"
echo ""
echo "Test after restarting:"
echo "  echo 'yossirachman'  → should block"
echo "  echo 'hello world'   → should work"
