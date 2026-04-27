#!/usr/bin/env bash
# Quick test to verify hooks are working correctly

echo "=== Testing block-hooks ==="
echo ""

echo "1. Checking what keywords are configured..."
echo "   In keywords.txt:"
grep -v "^[[:space:]]*#" keywords.txt | grep -v "^[[:space:]]*$" || echo "   (none)"
echo ""

echo "2. Checking generated hook script..."
if [[ -f ~/.agent-hooks/block-hooks.sh ]]; then
  echo "   Generated patterns in hook:"
  grep -A 8 "is_blocked()" ~/.agent-hooks/block-hooks.sh | grep "^\s*\*" || echo "   (no patterns found)"
else
  echo "   ✗ No hook file found at ~/.agent-hooks/block-hooks.sh"
  echo "   Run: bash install.sh"
fi
echo ""

echo "3. Testing hook directly (bypassing agents)..."
echo ""

# Test with a command that should be blocked
test_blocked="echo yossirachman"
echo "   Testing: $test_blocked"
if echo "$test_blocked" | HOOK_ENV=test bash ~/.agent-hooks/block-hooks.sh 2>/dev/null; then
  echo "   ✓ Hook script executed successfully"
else
  result=$?
  if [[ $result -eq 2 ]]; then
    echo "   ✓ Correctly blocked!"
  else
    echo "   ? Unexpected exit code: $result"
  fi
fi
echo ""

# Test with a command that should be allowed
test_allowed="echo hello world"
echo "   Testing: $test_allowed"
if echo "$test_allowed" | HOOK_ENV=test bash ~/.agent-hooks/block-hooks.sh 2>/dev/null; then
  echo "   ✓ Correctly allowed!"
else
  echo "   ✗ This should have been allowed (exit $?)"
fi
echo ""

echo "=== Test Complete ==="
echo ""
echo "If patterns match keywords.txt: hooks are configured correctly"
echo "If they don't match: run 'bash force-reinstall.sh'"
echo ""
echo "Remember: Changes only take effect after fully quitting and restarting agents!"
