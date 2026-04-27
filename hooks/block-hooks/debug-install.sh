#!/usr/bin/env bash
# Debug script to identify keyword blocking issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYWORDS_FILE="$SCRIPT_DIR/keywords.txt"
HOOK_SOURCE="$SCRIPT_DIR/block-hooks.sh"

echo "=== Step 1: Check keywords.txt content ==="
echo "File: $KEYWORDS_FILE"
if [[ -f "$KEYWORDS_FILE" ]]; then
  echo "---"
  cat -n "$KEYWORDS_FILE"
  echo "---"
else
  echo "ERROR: keywords.txt not found!"
  exit 1
fi

echo ""
echo "=== Step 2: Parse keywords (simulating install.sh logic) ==="
keywords=()
line_num=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line_num=$((line_num + 1))
  
  # Skip comments
  if [[ "$line" =~ ^[[:space:]]*# ]]; then
    echo "Line $line_num: SKIP (comment) - '$line'"
    continue
  fi
  
  # Skip empty lines
  if [[ -z "${line// }" ]]; then
    echo "Line $line_num: SKIP (empty)"
    continue
  fi
  
  echo "Line $line_num: ADD - '$line'"
  keywords+=("$line")
done < "$KEYWORDS_FILE"

echo ""
echo "=== Step 3: Keywords array ==="
echo "Total keywords parsed: ${#keywords[@]}"
if [[ ${#keywords[@]} -eq 0 ]]; then
  echo "ERROR: No keywords found!"
else
  for i in "${!keywords[@]}"; do
    printf "  [%d]: '%s'\n" "$i" "${keywords[$i]}"
  done
fi

echo ""
echo "=== Step 4: Generated case patterns ==="
case_patterns=""
for keyword in "${keywords[@]}"; do
  if [[ -n "$case_patterns" ]]; then
    case_patterns="${case_patterns}|\\"$'\n'"    "
  fi
  case_patterns="${case_patterns}*${keyword}*"
done
echo "---"
echo "$case_patterns"
echo "---"

echo ""
echo "=== Step 5: Check placeholder in source ==="
echo "File: $HOOK_SOURCE"
if grep -n "@@KEYWORD_PATTERNS@@" "$HOOK_SOURCE"; then
  echo "✓ Placeholder found"
else
  echo "✗ Placeholder NOT found - installation will fail!"
fi

echo ""
echo "=== Step 6: Check installed hook script ==="
if [[ -f "$HOME/.agent-hooks/block-hooks.sh" ]]; then
  echo "Found: ~/.agent-hooks/block-hooks.sh"
  echo ""
  echo "Generation info:"
  head -5 "$HOME/.agent-hooks/block-hooks.sh"
  echo ""
  echo "Patterns in is_blocked() function:"
  echo "---"
  grep -A 15 "is_blocked()" "$HOME/.agent-hooks/block-hooks.sh" | tail -n +2
  echo "---"
else
  echo "✗ Hook script NOT installed"
  echo "  Run: bash install.sh"
fi

echo ""
echo "=== Step 7: Check agent configurations ==="
for config in "$HOME/.cursor/hooks.json" "$HOME/.claude/settings.json" "$HOME/.codex/hooks.json"; do
  if [[ -f "$config" ]]; then
    echo "✓ Found: $config"
  else
    echo "✗ Not found: $config"
  fi
done

echo ""
echo "=== Step 8: Test pattern matching ==="
echo "Testing if 'deletevolume' would match current patterns..."
if [[ ${#keywords[@]} -gt 0 ]]; then
  test_command="echo deletevolume"
  matched=false
  for keyword in "${keywords[@]}"; do
    if [[ "$test_command" == *"$keyword"* ]]; then
      echo "  ✗ WOULD BLOCK - matches keyword: '$keyword'"
      matched=true
    fi
  done
  if [[ "$matched" == false ]]; then
    echo "  ✓ Would NOT block - no match"
  fi
fi

echo ""
echo "=== Step 9: Recommendations ==="
if [[ ${#keywords[@]} -eq 0 ]]; then
  echo "⚠ No keywords found - add at least one keyword to keywords.txt"
elif [[ ! -f "$HOME/.agent-hooks/block-hooks.sh" ]]; then
  echo "⚠ Hook script not installed - run: bash install.sh"
else
  echo "✓ Configuration looks good"
  echo "  To apply changes: bash install.sh --uninstall && bash install.sh"
  echo "  Then restart your AI agent or start a new terminal session"
fi
