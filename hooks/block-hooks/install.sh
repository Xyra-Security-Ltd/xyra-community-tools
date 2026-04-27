#!/usr/bin/env bash
# =============================================================================
# Xyra Community Tools - block-hooks installer
# https://github.com/Xyra-Security-Ltd/xyra-community-tools
#
# Installs a pre-execution hook on Cursor, Claude Code, and Codex CLI that
# blocks destructive operations specified in keywords.txt before they reach
# any API or infrastructure provider.
#
# Merges into existing agent hook configs (does not overwrite other hooks).
# Uninstall removes only entries tagged with XYRA_BLOCK_HOOKS.
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
HOOK_MARKER="XYRA_BLOCK_HOOKS"
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
# Backup existing file
# -----------------------------------------------------------------------------
# Backs up an existing config before merge. Missing file is normal (first install);
# must always exit 0 so set -e does not abort the installer.
backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local backup="${file}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$file" "$backup"
    log "INFO" "Backed up existing file to $backup"
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Merge hook into Cursor JSON config
# Args: $1=config_file, $2=hook_command, $3=hook_type (beforeShellExecution|beforeMCPExecution)
# -----------------------------------------------------------------------------
merge_cursor_hook() {
  local config_file="$1"
  local hook_command="$2"
  local hook_type="$3"
  local marker="$HOOK_MARKER"

  python3 - "$config_file" "$hook_command" "$hook_type" "$marker" << 'PYEOF'
import sys, json, os

config_file, hook_command, hook_type, marker = sys.argv[1:]

config = {"version": 1, "hooks": {}}
if os.path.exists(config_file):
    with open(config_file) as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pass

config.setdefault("hooks", {})
config.setdefault("version", 1)
config["hooks"].setdefault(hook_type, [])

hook_list = config["hooks"][hook_type]
updated = False
for h in hook_list:
    if isinstance(h.get("command"), str) and marker in h["command"]:
        h["command"] = hook_command
        updated = True
        break
if not updated:
    hook_list.append({"command": hook_command})

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PYEOF
}

# -----------------------------------------------------------------------------
# Merge hook into Claude/Codex PreToolUse config
# Args: $1=config_file, $2=matcher, $3=hook_command, $4=timeout (optional)
# -----------------------------------------------------------------------------
merge_pretooluse_hook() {
  local config_file="$1"
  local matcher="$2"
  local hook_command="$3"
  local timeout="${4:-}"
  local marker="$HOOK_MARKER"

  python3 - "$config_file" "$matcher" "$hook_command" "$timeout" "$marker" << 'PYEOF'
import sys, json, os

config_file, matcher, hook_command, timeout, marker = sys.argv[1:]

config = {"hooks": {}}
if os.path.exists(config_file):
    with open(config_file) as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pass

config.setdefault("hooks", {})
config["hooks"].setdefault("PreToolUse", [])

matcher_entry = None
for entry in config["hooks"]["PreToolUse"]:
    if entry.get("matcher") == matcher:
        matcher_entry = entry
        break
if matcher_entry is None:
    matcher_entry = {"matcher": matcher, "hooks": []}
    config["hooks"]["PreToolUse"].append(matcher_entry)

matcher_entry.setdefault("hooks", [])

new_hook = {"type": "command", "command": hook_command}
if timeout:
    new_hook["timeout"] = int(timeout)

updated = False
for h in matcher_entry["hooks"]:
    if isinstance(h.get("command"), str) and marker in h["command"]:
        h.update(new_hook)
        updated = True
        break
if not updated:
    matcher_entry["hooks"].append(new_hook)

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PYEOF
}

# -----------------------------------------------------------------------------
# Remove our hooks from config file
# Args: $1=config_file, $2=config_type (cursor|claude|codex)
# Prints: DELETE | UPDATED | UNCHANGED
# -----------------------------------------------------------------------------
remove_hooks() {
  local config_file="$1"
  local config_type="$2"
  local marker="$HOOK_MARKER"

  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  python3 - "$config_file" "$config_type" "$marker" << 'PYEOF'
import sys, json, os

config_file, config_type, marker = sys.argv[1:]

with open(config_file) as f:
    config = json.load(f)

modified = False

if config_type == "cursor":
    hooks = config.get("hooks", {})
    for key in ["beforeShellExecution", "beforeMCPExecution"]:
        if key in hooks:
            before = len(hooks[key])
            hooks[key] = [h for h in hooks[key]
                          if not (isinstance(h.get("command"), str) and marker in h["command"])]
            if len(hooks[key]) != before:
                modified = True
            if not hooks[key]:
                del hooks[key]
    if not hooks:
        config.pop("hooks", None)
else:
    pre = config.get("hooks", {}).get("PreToolUse", [])
    for entry in pre:
        if "hooks" in entry:
            before = len(entry["hooks"])
            entry["hooks"] = [h for h in entry["hooks"]
                              if not (isinstance(h.get("command"), str) and marker in h["command"])]
            if len(entry["hooks"]) != before:
                modified = True
    if "hooks" in config and "PreToolUse" in config["hooks"]:
        config["hooks"]["PreToolUse"] = [e for e in config["hooks"]["PreToolUse"]
                                          if e.get("hooks")]
        if not config["hooks"]["PreToolUse"]:
            del config["hooks"]["PreToolUse"]
        if not config["hooks"]:
            del config["hooks"]


def is_empty(cfg, cfg_type):
    if cfg_type == "cursor":
        keys = set(cfg.keys()) - {"version"}
        return len(keys) == 0
    return len(cfg) == 0

if modified and is_empty(config, config_type):
    print("DELETE")
elif modified:
    with open(config_file, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
    print("UPDATED")
else:
    print("UNCHANGED")
PYEOF
}

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------
if [[ "$UNINSTALL" == true ]]; then
  log "INFO" "Uninstalling $TOOL_NAME hooks"

  [[ -f "$HOOK_PATH" ]] && rm -f "$HOOK_PATH" && \
    log "INFO" "Removed hook script"

  if [[ -f "$HOME/.cursor/hooks.json" ]]; then
    result=$(remove_hooks "$HOME/.cursor/hooks.json" "cursor")
    if [[ "$result" == "DELETE" ]]; then
      rm -f "$HOME/.cursor/hooks.json"
      log "INFO" "Removed Cursor config (no other hooks present)"
    elif [[ "$result" == "UPDATED" ]]; then
      log "INFO" "Removed Xyra hooks from Cursor (preserved other hooks)"
    fi
  fi

  if [[ -f "$HOME/.claude/settings.json" ]]; then
    result=$(remove_hooks "$HOME/.claude/settings.json" "claude")
    if [[ "$result" == "DELETE" ]]; then
      rm -f "$HOME/.claude/settings.json"
      log "INFO" "Removed Claude Code config (no other settings present)"
    elif [[ "$result" == "UPDATED" ]]; then
      log "INFO" "Removed Xyra hooks from Claude Code (preserved other settings)"
    fi
  fi

  if [[ -f "$HOME/.codex/hooks.json" ]]; then
    result=$(remove_hooks "$HOME/.codex/hooks.json" "codex")
    if [[ "$result" == "DELETE" ]]; then
      rm -f "$HOME/.codex/hooks.json"
      log "INFO" "Removed Codex CLI config (no other hooks present)"
    elif [[ "$result" == "UPDATED" ]]; then
      log "INFO" "Removed Xyra hooks from Codex CLI (preserved other hooks)"
    fi
  fi

  log "INFO" "Uninstall complete"
  log "WARN" "Remember to fully quit and restart agents (Cursor, Codex, Claude) for changes to take effect"
  if [[ "$SILENT" == false ]]; then
    echo ""
    echo "IMPORTANT: Fully quit and restart your agents:"
    echo "  - Cursor: Press Cmd+Q, then relaunch"
    echo "  - Codex/Claude CLI: Close all terminals, open new ones"
  fi
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

keywords=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line//$'\r'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
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
if [[ "$SILENT" == false ]]; then
  echo "Keywords to block:"
  for kw in "${keywords[@]}"; do
    echo "  - $kw"
  done
fi

keywords_array_items=""
for keyword in "${keywords[@]}"; do
  escaped_keyword=$(printf '%s' "$keyword" | sed 's/"/\\"/g')
  keywords_array_items="${keywords_array_items} \"${escaped_keyword}\""
done

log "INFO" "Prepared ${#keywords[@]} keywords for injection (token-oriented matching)"

# -----------------------------------------------------------------------------
# Install hook script
# -----------------------------------------------------------------------------
log "INFO" "Installing $TOOL_NAME"
mkdir -p "$HOOK_DIR"

substitution_done=false
{
  echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "# Keywords: ${keywords[*]}"
  echo "# Total patterns: ${#keywords[@]}"
  echo ""

  while IFS= read -r line; do
    line_trimmed="$(echo "$line" | sed 's/[[:space:]]*$//')"
    if [[ "$line_trimmed" == "# @@BLOCKED_KEYWORDS@@ - DO NOT REMOVE THIS LINE" ]]; then
      echo "BLOCKED_KEYWORDS=(${keywords_array_items})"
      substitution_done=true
    else
      echo "$line"
    fi
  done < "$HOOK_SOURCE"
} > "$HOOK_PATH"

if [[ "$substitution_done" != true ]]; then
  log "ERROR" "Failed to inject keywords - placeholder not found in $HOOK_SOURCE"
  log "ERROR" "Make sure block-hooks.sh contains: # @@BLOCKED_KEYWORDS@@ - DO NOT REMOVE THIS LINE"
  exit 1
fi

chmod +x "$HOOK_PATH"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
log "INFO" "Hook script installed at $HOOK_PATH"

if ! grep -q "return 0" "$HOOK_PATH" 2>/dev/null; then
  log "ERROR" "Hook script verification failed - patterns not found"
  exit 1
fi
log "INFO" "Hook script verified - patterns successfully injected"

# -----------------------------------------------------------------------------
# Detect installed agents
# -----------------------------------------------------------------------------
has_cursor=false
has_claude=false
has_codex=false

command -v cursor >/dev/null 2>&1 && has_cursor=true
command -v claude  >/dev/null 2>&1 && has_claude=true
command -v codex   >/dev/null 2>&1 && has_codex=true

[[ -d "/Applications/Cursor.app" ]] && has_cursor=true
[[ -d "$HOME/.cursor"            ]] && has_cursor=true
[[ -d "$HOME/.claude"            ]] && has_claude=true
[[ -d "$HOME/.codex"             ]] && has_codex=true

# -----------------------------------------------------------------------------
# Cursor (desktop IDE)
# -----------------------------------------------------------------------------
if [[ "$has_cursor" == true ]]; then
  mkdir -p "$HOME/.cursor"
  CURSOR_CONFIG="$HOME/.cursor/hooks.json"
  backup_file "$CURSOR_CONFIG"
  HOOK_CMD="HOOK_ENV=cursor bash $HOOK_PATH # $HOOK_MARKER"
  merge_cursor_hook "$CURSOR_CONFIG" "$HOOK_CMD" "beforeShellExecution"
  merge_cursor_hook "$CURSOR_CONFIG" "$HOOK_CMD" "beforeMCPExecution"
  log "INFO" "Cursor (desktop IDE) hooks configured"
fi

# -----------------------------------------------------------------------------
# Claude Code (CLI)
# -----------------------------------------------------------------------------
if [[ "$has_claude" == true ]]; then
  mkdir -p "$HOME/.claude"
  CLAUDE_CONFIG="$HOME/.claude/settings.json"
  backup_file "$CLAUDE_CONFIG"
  HOOK_CMD="bash $HOOK_PATH # $HOOK_MARKER"
  merge_pretooluse_hook "$CLAUDE_CONFIG" "Bash|mcp__.*" "$HOOK_CMD"
  log "INFO" "Claude Code (CLI) hooks configured"
fi

# -----------------------------------------------------------------------------
# Codex CLI (OpenAI)
# -----------------------------------------------------------------------------
if [[ "$has_codex" == true ]]; then
  mkdir -p "$HOME/.codex"
  CODEX_CONFIG="$HOME/.codex/hooks.json"
  backup_file "$CODEX_CONFIG"
  HOOK_CMD="bash $HOOK_PATH # $HOOK_MARKER"
  merge_pretooluse_hook "$CODEX_CONFIG" "Bash" "$HOOK_CMD" "30"

  CONFIG_FILE="$HOME/.codex/config.toml"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<'TOML'
[features]
codex_hooks = true
TOML
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
  echo "✔ Existing agent hooks preserved (backups created when configs existed)"

  if [[ "$has_cursor" == false ]] && \
     [[ "$has_claude" == false ]] && \
     [[ "$has_codex"  == false ]]; then
    echo ""
    echo "⚠ No supported agents detected"
    echo "  Install Cursor, Claude Code, or Codex CLI and re-run this script"
  fi

  echo ""
  echo "============================================================"
  echo "IMPORTANT: Fully QUIT and restart your agents"
  echo "============================================================"
  echo ""
  echo "Agents cache hooks in memory. You MUST fully quit:"
  echo ""
  [[ "$has_cursor" == true ]] && echo "  Cursor:      Press Cmd+Q (not just close window), then relaunch"
  [[ "$has_claude" == true ]] && echo "  Claude CLI:  Close all terminals, open new one, run 'claude'"
  [[ "$has_codex"  == true ]] && echo "  Codex CLI:   Close all terminals, open new one, run 'codex'"
  echo ""
  echo "After restarting:"
  echo "  Verify logs: tail -f $LOG_FILE"
  echo "  Debug hook:  cat ~/.agent-hooks/block-hooks.sh | grep -A 5 'is_blocked()'"
  echo "  Uninstall:   bash install.sh --uninstall"
  echo "============================================================"
fi

exit 0
