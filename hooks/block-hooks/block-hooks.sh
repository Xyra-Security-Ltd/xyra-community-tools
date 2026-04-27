#!/usr/bin/env bash
# =============================================================================
# Xyra Community Tools - block-hooks
# https://github.com/Xyra-Security-Ltd/xyra-community-tools
#
# Pre-execution hook for Cursor, Claude Code, and Codex CLI.
# Intercepts shell commands and MCP tool calls before execution.
# Blocks destructive operations based on keywords defined in keywords.txt.
#
# This script is installed automatically by install.sh.
# Do not run this script directly.
#
# Verified against official docs (April 2026):
#   Cursor:      https://cursor.com/docs/hooks
#   Claude Code: https://docs.anthropic.com/en/docs/claude-code/hooks
#   Codex CLI:   https://developers.openai.com/codex/hooks
#
# Exit codes:
#   Cursor:      exit 0 + JSON stdout (allow or deny)
#   Claude Code: exit 0 (allow) or exit 2 + stderr (block)
#   Codex CLI:   exit 0 (allow) or exit 2 + stderr (block)
#
# Known limitation:
#   Codex CLI PreToolUse currently only intercepts Bash commands.
#   MCP tool call interception is not yet supported by Codex CLI.
# =============================================================================

set -u

LOG_FILE="$HOME/.agent-hooks/agent-hooks.log"

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  local decision="$1"
  local agent="${HOOK_ENV:-unknown}"
  local snippet
  snippet="$(printf "%s" "$payload" | head -c 300 | tr '\n' ' ')"
  mkdir -p "$(dirname "$LOG_FILE")"
  printf "%s | agent=%s | decision=%s | payload=\"%s\"\n" \
    "$(timestamp)" "$agent" "$decision" "$snippet" >> "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Read payload from stdin
# -----------------------------------------------------------------------------
payload="$(cat || true)"

# -----------------------------------------------------------------------------
# Cursor: scan only execution-relevant JSON fields (avoids false positives
# from cwd, urls, etc.). Other agents / non-JSON stdin: scan full payload.
# -----------------------------------------------------------------------------
cursor_scan_text_from_payload() {
  printf '%s' "$payload" | python3 -c '
import json, sys

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.stdout.write(raw)
    raise SystemExit(0)
if not isinstance(data, dict):
    sys.stdout.write(raw)
    raise SystemExit(0)
if "tool_name" in data or "tool_input" in data:
    lines = []
    for key in ("tool_name", "tool_input"):
        val = data.get(key)
        if val is None:
            continue
        if isinstance(val, str):
            lines.append(val)
        else:
            lines.append(json.dumps(val, separators=(",", ":")))
    sys.stdout.write("\n".join(lines))
    raise SystemExit(0)
if isinstance(data.get("command"), str):
    sys.stdout.write(data["command"])
    raise SystemExit(0)
sys.stdout.write(raw)
raise SystemExit(0)
'
}

scan_text_for_keywords() {
  if [[ "${HOOK_ENV:-}" == "cursor" ]]; then
    cursor_scan_text_from_payload
  else
    printf '%s' "$payload"
  fi
}

# -----------------------------------------------------------------------------
# Detection - matches blocked keywords from keywords.txt
# @@BLOCKED_KEYWORDS@@ - DO NOT REMOVE THIS LINE
# Array above is injected by install.sh at installation time
# -----------------------------------------------------------------------------

is_blocked() {
  local haystack="$1"
  local keyword escaped
  for keyword in "${BLOCKED_KEYWORDS[@]}"; do
    escaped=$(printf '%s' "$keyword" | sed -e 's/\./\\./g' -e 's/\[/\\[/g' -e 's/\^/\\^/g' -e 's/\$/\\$/g' -e 's/\*/\\*/g' -e 's/+/\\+/g' -e 's/?/\\?/g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/|/\\|/g')
    if printf '%s\n' "$haystack" | grep -qE "(^|[^[:alnum:]_])${escaped}([^[:alnum:]_]|$)"; then
      return 0
    fi
  done
  return 1
}

# -----------------------------------------------------------------------------
# Enforce policy
# -----------------------------------------------------------------------------
scan_text="$(scan_text_for_keywords)"

if is_blocked "$scan_text"; then
  log "BLOCK"

  if [[ "${HOOK_ENV:-}" == "cursor" ]]; then
    printf '{"permission":"deny","continue":false,"agentMessage":"Blocked by Xyra policy","userMessage":"Blocked by Xyra: This operation contains a blocked keyword"}\n'
    exit 0
  fi

  echo "Blocked by Xyra policy: This operation contains a blocked keyword and is not permitted." >&2
  exit 2
fi

# -----------------------------------------------------------------------------
# Allow
# -----------------------------------------------------------------------------
log "ALLOW"

if [[ "${HOOK_ENV:-}" == "cursor" ]]; then
  printf '{"permission":"allow"}\n'
fi

exit 0
