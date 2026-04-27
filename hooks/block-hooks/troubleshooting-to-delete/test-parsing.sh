#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYWORDS_FILE="$SCRIPT_DIR/keywords.txt"

echo "=== Parsing keywords.txt ==="
echo "File: $KEYWORDS_FILE"
echo ""

keywords=()
line_num=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line_num=$((line_num + 1))
  
  # Debug: show raw line with special chars
  echo "Line $line_num (raw): $(printf '%q' "$line")"
  
  # Skip comments
  if [[ "$line" =~ ^[[:space:]]*# ]]; then
    echo "  -> SKIP: starts with #"
    continue
  fi
  
  # Skip empty lines
  if [[ -z "${line// }" ]]; then
    echo "  -> SKIP: empty line"
    continue
  fi
  
  echo "  -> ADD: '$line'"
  keywords+=("$line")
done < "$KEYWORDS_FILE"

echo ""
echo "=== Results ==="
echo "Total keywords: ${#keywords[@]}"
for i in "${!keywords[@]}"; do
  printf "  keywords[%d] = '%s'\n" "$i" "${keywords[$i]}"
done

echo ""
echo "=== Generated pattern ==="
case_patterns=""
for keyword in "${keywords[@]}"; do
  if [[ -n "$case_patterns" ]]; then
    case_patterns="${case_patterns}|\\"$'\n'"    "
  fi
  case_patterns="${case_patterns}*${keyword}*"
done
echo "$case_patterns"
