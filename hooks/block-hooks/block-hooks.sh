#!/usr/bin/env bash
# =============================================================================
# Xyra Community Tools - block-hooks
# https://github.com/XyraSecurity/community-tools
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
  printf "%s | agent=%s | decision=%s | payload=\"%s\"\n" \
    "$(timestamp)" "$agent" "$decision" "$snippet" >> "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Read payload from stdin
# -----------------------------------------------------------------------------
payload="$(cat || true)"

# -----------------------------------------------------------------------------
# Detection - matches blocked keywords from keywords.txt
# @@BLOCKED_KEYWORDS@@ - DO NOT REMOVE THIS LINE
# Array above is injected by install.sh at installation time
# -----------------------------------------------------------------------------

is_blocked() {
  local keyword escaped
  for keyword in "${BLOCKED_KEYWORDS[@]}"; do
    escaped=$(printf '%s' "$keyword" | sed -e 's/\./\\./g' -e 's/\[/\\[/g' -e 's/\^/\\^/g' -e 's/\$/\\$/g' -e 's/\*/\\*/g' -e 's/+/\\+/g' -e 's/?/\\?/g' -e 's/(/\\(/g' -e 's/)/\\)/g' -e 's/|/\\|/g')
    if printf '%s\n' "$payload" | grep -qE "(^|[^[:alnum:]_])${escaped}([^[:alnum:]_]|$)"; then
      return 0
    fi
  done
  return 1
}

# -----------------------------------------------------------------------------
# Enforce policy
# -----------------------------------------------------------------------------
if is_blocked; then
  log "BLOCK"

  if [[ "${HOOK_ENV:-}" == "cursor" ]]; then
    # Cursor: JSON on stdout, exit 0
    # Ref: https://cursor.com/docs/hooks (beforeShellExecution response format)
    printf '{"permission":"deny","continue":false,"agentMessage":"Blocked by Xyra policy","userMessage":"Blocked by Xyra: This operation contains a blocked keyword"}\n'
    exit 0
  fi

  # Claude Code and Codex CLI: exit 2 feeds stderr back to the agent as context
  # Ref: https://docs.anthropic.com/en/docs/claude-code/hooks
  # Ref: https://developers.openai.com/codex/hooks
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