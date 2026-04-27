#!/usr/bin/env bash
# Runs block-hooks.sh fixture tests (Cursor JSON field extraction + token match).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_HOOK="$REPO_ROOT/hooks/block-hooks/block-hooks.sh"
TMP_HOOK="$(mktemp)"
trap 'rm -f "$TMP_HOOK"' EXIT

awk '/^# @@BLOCKED_KEYWORDS@@ - DO NOT REMOVE THIS LINE$/ {
  print "BLOCKED_KEYWORDS=(\"deleteVolume\")"
  next
}
{ print }' "$SRC_HOOK" > "$TMP_HOOK"
chmod +x "$TMP_HOOK"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Benign command; cwd contains volume-delete — must ALLOW (full JSON would false-positive).
out="$(printf '%s' '{"command":"ls","cwd":"/tmp/volume-delete","sandbox":false}' | HOOK_ENV=cursor bash "$TMP_HOOK")"
[[ "$out" == *'"permission":"allow"'* ]] || fail "expected allow for safe command with risky cwd, got: $out"

# Destructive token in command — must DENY.
out="$(printf '%s' '{"command":"echo deleteVolume","cwd":"/tmp/volume-delete","sandbox":false}' | HOOK_ENV=cursor bash "$TMP_HOOK")"
[[ "$out" == *'"permission":"deny"'* ]] || fail "expected deny when command contains keyword, got: $out"

# MCP-shaped JSON: tool_input only — must not scan unrelated url field for this keyword.
out="$(printf '%s' '{"tool_name":"read_file","tool_input":"{}","url":"https://example.com/volume-delete"}' | HOOK_ENV=cursor bash "$TMP_HOOK")"
[[ "$out" == *'"permission":"allow"'* ]] || fail "expected allow when keyword only in url, got: $out"

out="$(printf '%s' '{"tool_name":"railway","tool_input":"{\"mutation\":\"deleteVolume\"}"}' | HOOK_ENV=cursor bash "$TMP_HOOK")"
[[ "$out" == *'"permission":"deny"'* ]] || fail "expected deny when tool_input contains keyword, got: $out"

echo "OK: all tests passed"
