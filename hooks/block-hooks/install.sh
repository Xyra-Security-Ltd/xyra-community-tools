#!/usr/bin/env bash
# =============================================================================
# Xyra Community Tools - block-hooks installer
# https://github.com/XyraSecurity/community-tools
#
# Installs a pre-execution hook on Cursor, Claude Code, and Codex CLI that
# blocks destructive operations specified in keywords.txt before they reach
# any API or infrastructure provider.
#
# Usage:
#   Manual:    bash install.sh
#   Silent:    bash install.sh --silent
#   Uninstall: bash install.sh --uninstall
#
# MDM deployment (JAMF, Kandji, JumpCloud, Microsoft Intune):
#   Deploy install.sh as a script policy with --silent flag.
#   The script is idempotent - safe to run multiple times.
#   Exit codes: 0 = success, 1 = failure
#
# Requirements:
#   - macOS 12+ (Monterey or later)
#   - bash 4.0+ (pre-installed on macOS)
#   - keywords.txt file in the same directory as install.sh
#   - At least one supported agent:
#       Cursor      (desktop IDE, hooks via ~/.cursor/hooks.json)
#       Claude Code (CLI, hooks via ~/.claude/settings.json)
#       Codex CLI   (OpenAI CLI, hooks via ~/.codex/hooks.json)
#
# Verified against official docs (April 2026):
#   Cursor:      https://cursor.com/docs/hooks
#   Claude Code: https://docs.anthropic.com/en/docs/claude-code/hooks
#   Codex CLI:   https://developers.openai.com/codex/hooks
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# macOS only
# -----------------------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then
  echo "[ERROR] This script supports macOS only."
  exit 1
fi

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
TOOL_NAME="block-hooks"
HOOK_DIR="$HOME/.agent-hooks"
HOOK_PATH="$HOOK_DIR/$TOOL_NAME.sh"
LOG_FILE="$HOOK_DIR/agent-hooks.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SOURCE="$SCRIPT_DIR/$TOOL_NAME.sh"
KEYWORDS_FILE="$SCRIPT_DIR/keywords.txt"
SILENT=false
UNINSTALL=false

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --silent)    SILENT=true ;;
    --uninstall) UNINSTALL=true ;;
  esac
done

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log() {
  local level="$1"
  local message="$2"
  if [[ "$SILENT" == false ]]; then
    echo "[$level] $message"
  fi
  mkdir -p "$HOOK_DIR"
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $level | $message" >> "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------
if [[ "$UNINSTALL" == true ]]; then
  log "INFO" "Uninstalling $TOOL_NAME hooks"

  [[ -f "$HOOK_PATH" ]] && rm -f "$HOOK_PATH" && \
    log "INFO" "Removed hook script"

  if [[ -f "$HOME/.cursor/hooks.json" ]]; then
    rm -f "$HOME/.cursor/hooks.json"
    log "INFO" "Removed Cursor hooks config"
  fi

  if [[ -f "$HOME/.claude/settings.json" ]]; then
    rm -f "$HOME/.claude/settings.json"
    log "INFO" "Removed Claude Code hooks config"
  fi

  if [[ -f "$HOME/.codex/hooks.json" ]]; then
    rm -f "$HOME/.codex/hooks.json"
    log "INFO" "Removed Codex CLI hooks config"
  fi

  log "INFO" "Uninstall complete"
  exit 0
fi

# -----------------------------------------------------------------------------
# Validate hook source exists
# -----------------------------------------------------------------------------
if [[ ! -f "$HOOK_SOURCE" ]]; then
  log "ERROR" "$TOOL_NAME.sh not found at $HOOK_SOURCE"
  log "ERROR" "Make sure install.sh and $TOOL_NAME.sh are in the same directory"
  exit 1
fi

# -----------------------------------------------------------------------------
# Read and process keywords.txt
# -----------------------------------------------------------------------------
if [[ ! -f "$KEYWORDS_FILE" ]]; then
  log "ERROR" "keywords.txt not found at $KEYWORDS_FILE"
  log "ERROR" "Make sure keywords.txt exists in the same directory as install.sh"
  exit 1
fi

# Read keywords (skip comments and empty lines)
keywords=()
while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip comments and empty lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  keywords+=("$line")
done < "$KEYWORDS_FILE"

if [[ ${#keywords[@]} -eq 0 ]]; then
  log "ERROR" "No keywords found in keywords.txt"
  log "ERROR" "Add at least one keyword to keywords.txt (one per line)"
  exit 1
fi

log "INFO" "Loaded ${#keywords[@]} keywords from keywords.txt"

# Generate case statement patterns
case_patterns=""
for keyword in "${keywords[@]}"; do
  if [[ -n "$case_patterns" ]]; then
    case_patterns="${case_patterns}|\\
    "
  fi
  case_patterns="${case_patterns}*${keyword}*"
done

log "INFO" "Generated blocking patterns for ${#keywords[@]} keywords"

# -----------------------------------------------------------------------------
# Install hook script
# -----------------------------------------------------------------------------
log "INFO" "Installing $TOOL_NAME"
mkdir -p "$HOOK_DIR"

# Create hook script with injected keywords
# Read source file and replace placeholder with generated patterns
{
  while IFS= read -r line; do
    if [[ "$line" == "    # @@KEYWORD_PATTERNS@@ - DO NOT REMOVE THIS LINE" ]]; then
      # Output the generated case patterns
      echo "    ${case_patterns})"
      echo "      return 0"
      echo "      ;;"
    else
      echo "$line"
    fi
  done < "$HOOK_SOURCE"
} > "$HOOK_PATH"

chmod +x "$HOOK_PATH"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
log "INFO" "Hook script installed at $HOOK_PATH"

# -----------------------------------------------------------------------------
# Detect installed agents
# macOS-specific paths checked in addition to PATH
# MDM environments often have restricted PATH - check app/config directories
# -----------------------------------------------------------------------------
has_cursor=false
has_claude=false
has_codex=false

command -v cursor >/dev/null 2>&1 && has_cursor=true
command -v claude  >/dev/null 2>&1 && has_claude=true
command -v codex   >/dev/null 2>&1 && has_codex=true

# macOS install path fallbacks
[[ -d "/Applications/Cursor.app" ]] && has_cursor=true
[[ -d "$HOME/.cursor"            ]] && has_cursor=true
[[ -d "$HOME/.claude"            ]] && has_claude=true
[[ -d "$HOME/.codex"             ]] && has_codex=true

# -----------------------------------------------------------------------------
# Cursor (desktop IDE)
# Docs: https://cursor.com/docs/hooks
# Config: ~/.cursor/hooks.json
# beforeShellExecution: intercepts shell commands before execution
# beforeMCPExecution: intercepts MCP tool calls before execution
# Response: JSON on stdout with permission=allow|deny
# -----------------------------------------------------------------------------
if [[ "$has_cursor" == true ]]; then
  mkdir -p "$HOME/.cursor"
  cat > "$HOME/.cursor/hooks.json" <<EOF
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      { "command": "HOOK_ENV=cursor bash $HOOK_PATH" }
    ],
    "beforeMCPExecution": [
      { "command": "HOOK_ENV=cursor bash $HOOK_PATH" }
    ]
  }
}
EOF
  log "INFO" "Cursor (desktop IDE) hooks configured"
fi

# -----------------------------------------------------------------------------
# Claude Code (CLI)
# Docs: https://docs.anthropic.com/en/docs/claude-code/hooks
# Config: ~/.claude/settings.json
# PreToolUse: intercepts Bash and MCP tool calls before execution
# Block: exit code 2, stderr is fed back to the agent
# -----------------------------------------------------------------------------
if [[ "$has_claude" == true ]]; then
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" <<EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOOK_PATH"
          }
        ]
      }
    ]
  }
}
EOF
  log "INFO" "Claude Code (CLI) hooks configured"
fi

# -----------------------------------------------------------------------------
# Codex CLI (OpenAI)
# Docs: https://developers.openai.com/codex/hooks
# Config: ~/.codex/hooks.json
# PreToolUse: intercepts Bash commands before execution
# Block: exit code 2, stderr is fed back to the agent
# Note: Codex CLI PreToolUse currently only supports Bash interception.
#       MCP tool call interception is not yet available in Codex CLI.
# Note: requires [features] codex_hooks = true in ~/.codex/config.toml
# -----------------------------------------------------------------------------
if [[ "$has_codex" == true ]]; then
  mkdir -p "$HOME/.codex"

  # Write hooks.json
  cat > "$HOME/.codex/hooks.json" <<EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOOK_PATH",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
EOF

  # Enable hooks feature flag in config.toml
  CONFIG_FILE="$HOME/.codex/config.toml"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<EOF
[features]
codex_hooks = true
EOF
  elif ! grep -q "codex_hooks" "$CONFIG_FILE"; then
    printf "\n[features]\ncodex_hooks = true\n" >> "$CONFIG_FILE"
  fi

  log "INFO" "Codex CLI (OpenAI) hooks configured"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
log "INFO" "Installation complete"

if [[ "$SILENT" == false ]]; then
  echo ""
  echo "===== DONE ====="
  [[ "$has_cursor" == true ]] && echo "✔ Cursor (desktop IDE) hooks installed"
  [[ "$has_claude" == true ]] && echo "✔ Claude Code (CLI) hooks installed"
  [[ "$has_codex"  == true ]] && echo "✔ Codex CLI (OpenAI) hooks installed"
  echo "✔ Logging enabled at $LOG_FILE"

  if [[ "$has_cursor" == false ]] && \
     [[ "$has_claude" == false ]] && \
     [[ "$has_codex"  == false ]]; then
    echo ""
    echo "⚠ No supported agents detected"
    echo "  Install Cursor, Claude Code, or Codex CLI and re-run this script"
  fi

  echo ""
  echo "To verify:    tail -f $LOG_FILE"
  echo "To uninstall: bash install.sh --uninstall"
fi

exit 0