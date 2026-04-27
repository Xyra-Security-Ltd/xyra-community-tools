# block-hooks

A configurable pre-execution hook that blocks destructive operations before they reach infrastructure providers like Railway, AWS, GCP, or Azure. Works with Cursor, Claude Code, and Codex CLI.

Built by [Xyra Security](https://xyraSecurity.ai) in response to the April 2026 PocketOS incident, where a Cursor agent deleted production data in a 9-second API call.

---

## What happened

On April 23, 2026, a Cursor agent running Anthropic's Claude Opus 4.6 deleted a production database and all volume-level backups in a single API call to Railway's infrastructure. The deletion took 9 seconds. Recovery required a 3-month-old backup.

The agent violated its own safety rules — rules explicitly configured in Cursor's project settings. When asked to explain itself, the agent produced a written confession enumerating the specific safety principles it had ignored.

**The problem:** System prompts are advisory. Models read the rules, acknowledge them, and sometimes violate them anyway. There is nothing at the execution layer enforcing those rules.

**This tool:** Operates at the execution layer. It intercepts shell commands and MCP tool calls before they execute and blocks any operation containing keywords from `keywords.txt`. Ships with volume deletion protection by default (`volumeDelete`, `deleteVolume`, etc.), fully customizable for your infrastructure.

[Read the full incident report](https://x.com/lifeof_jer/status/2048103471019434248)

---

## What it does

This hook installs a pre-execution filter on three AI coding agents. You control what gets blocked by editing `keywords.txt` before installation.

| Agent                    | Intercepts Shell Commands | Intercepts MCP Calls          |
| ------------------------ | ------------------------- | ----------------------------- |
| **Cursor** (desktop IDE) | ✅ Yes                    | ✅ Yes                        |
| **Claude Code** (CLI)    | ✅ Yes                    | ✅ Yes                        |
| **Codex CLI** (OpenAI)   | ✅ Yes                    | ⚠️ Not yet supported by Codex |

When an agent attempts to execute a command containing a blocked keyword:

- **Cursor:** Returns `{"permission":"deny"}` and displays a user message
- **Claude Code:** Exits with code 2; stderr is fed back to the agent as context
- **Codex CLI:** Exits with code 2; stderr is fed back to the agent as context

All activity is logged to `~/.agent-hooks/agent-hooks.log`.

---

## Cursor: which text is scanned?

For **Cursor** (`HOOK_ENV=cursor`), stdin is JSON. To avoid false positives (for example a `cwd` path containing `volume-delete`), keywords are matched only against:

- **beforeShellExecution:** the `command` string only (not `cwd`, `sandbox`, etc.).
- **beforeMCPExecution:** `tool_name` and `tool_input` only (not `url` / server metadata).

If stdin is not valid JSON or does not match those shapes, the hook falls back to scanning the **full** payload (conservative).

Cursor field extraction uses **`python3`** on the PATH at hook runtime.

---

## Install behavior (merge-safe)

`install.sh` **merges** into existing `~/.cursor/hooks.json`, `~/.claude/settings.json`, and `~/.codex/hooks.json`. It does **not** remove unrelated hooks. Entries from this tool are tagged with an inline marker (`XYRA_BLOCK_HOOKS`) so reinstalls update in place.

**Uninstall** (`bash install.sh --uninstall`) removes only those tagged entries and deletes a config file if nothing else remains. Existing configs are backed up with a timestamp suffix before the first merge.

**Requirements:** macOS 12+, bash 4+, **`python3`** (for JSON merge/uninstall in the installer and for Cursor payload parsing in the hook).

---

## Configuration

### Default Protection

Ships with volume deletion protection enabled by default (see [`keywords.txt`](keywords.txt)):

- `volumeDelete`, `deleteVolume`, `volume-delete`, `volume_delete`
- `VOLUMEDELETE`, `DELETE-VOLUME`, `DELETE_VOLUME`, `VolumeDelete`

### Customizing Keywords

Edit `keywords.txt` before running `install.sh`:

```bash
# Clone the repo
git clone https://github.com/Xyra-Security-Ltd/xyra-community-tools.git
cd xyra-community-tools/hooks/block-hooks

# Edit keywords.txt - add one keyword per line
nano keywords.txt
```

**Example `keywords.txt`:**

```
# Volume deletion operations
volumeDelete
deleteVolume
volume-delete

# Database operations
dropDatabase
DROP DATABASE

# Instance termination
terminateInstance
destroyInstance
```

**Important:** Keywords are explicit **tokens** (see [Pattern matching](#pattern-matching)). If you add `dropDatabase`, it blocks when that token appears in the scanned text. Add variants you need (`drop-database`, `DROP_DATABASE`, etc.) manually to minimize false positives.

**Use `keywords.example.txt` as reference** — contains ~30 common destructive operations across AWS, GCP, Azure, Docker, Kubernetes, and Git.

### Installing with Custom Keywords

```bash
# 1. Edit keywords.txt to add your operations
nano keywords.txt

# 2. Run install.sh (reads keywords.txt and generates hook)
bash install.sh

# 3. Verify keywords loaded
tail ~/.agent-hooks/agent-hooks.log
```

To update keywords after installation:

```bash
# 1. Edit keywords.txt
nano keywords.txt

# 2. Reinstall (regenerates hook with new keywords)
bash install.sh
```

---

## Limitations

### Codex CLI: Bash only (no MCP interception)

**Important:** Codex CLI's `PreToolUse` hook currently only intercepts Bash commands. If an agent calls a destructive operation through an MCP server (e.g., Railway's `mcp.railway.com`), Codex CLI will not intercept it.

This is a Codex CLI platform limitation, not a bug in this tool. Cursor and Claude Code have full MCP interception support.

**Recommendation:** If you use Codex CLI with Railway's MCP server or similar infrastructure MCP integrations, either:

- Switch to Cursor or Claude Code for operations involving production infrastructure
- Remove the MCP server from Codex CLI's configuration
- Deploy additional network-level controls (firewall rules, API gateway policies)

### Pattern matching

The hook uses **exact token matching** to detect keywords from `keywords.txt`. Keywords must appear as distinct tokens (words) in the command, not as substrings within other words.

**Example:** If `keywords.txt` contains `deleteVolume`:

✅ **WILL block:**

- `deleteVolume myvolume`
- `echo "deleteVolume"`
- GraphQL: `mutation { deleteVolume(id: "xyz") }`
- API: `curl ... -d '{"action": "deleteVolume"}'`

❌ **WILL NOT block:**

- `deleteVolumeNow` (different word)
- `myDeleteVolume` (different word)
- `undeleteVolume` (different word)
- Base64-encoded commands
- Typos: `delteVolume`, `delete_volume`

**This is different from substring matching:** The keyword `delete` will NOT block `deleteVolume` or `undelete`. Each keyword is matched as a complete token.

**Matching contexts:**
The hook checks for keywords in several contexts:

- As quoted strings: `"keyword"`
- With spaces around them: `keyword`
- At the start/end of commands: `keyword ...` or `... keyword`

### False positives and keyword selection

**Keywords must be exact tokens** — only complete words matching your keywords.txt entries are blocked. This minimizes false positives while still requiring you to list all variants you want to block.

**Tips for choosing keywords:**

- Use full command names: `deleteVolume` not `delete` (too broad)
- Add common variants if needed: `deleteVolume`, `delete-volume`, `volume-delete`
- Test thoroughly after adding new keywords
- Check logs: `grep "BLOCK" ~/.agent-hooks/agent-hooks.log`

**Keywords will NOT block:**

- Operations through web UIs (this is agent-level protection only)
- Commands executed outside of AI agents
- Variants not in your keywords.txt

If you encounter a false positive or false negative, check the logs and file an issue.

---

## Installation

### Manual (macOS)

Requirements: macOS 12+, bash 4+, `python3` (see [Install behavior (merge-safe)](#install-behavior-merge-safe)).

```bash
# Clone the repo
git clone https://github.com/Xyra-Security-Ltd/xyra-community-tools.git
cd xyra-community-tools/hooks/block-hooks

# (Optional) Customize keywords
nano keywords.txt

# Run the installer
bash install.sh
```

Fully quit Cursor (Cmd+Q) and restart terminals for agents after install or uninstall.

**Output:**

```
[INFO] Loaded 8 keywords from keywords.txt
[INFO] Generated blocking patterns for 8 keywords
✔ Cursor (desktop IDE) hooks installed
✔ Claude Code (CLI) hooks installed
✔ Codex CLI (OpenAI) hooks installed
✔ Logging enabled at ~/.agent-hooks/agent-hooks.log
```

The installer is idempotent — safe to run multiple times.

### Silent mode (for scripting)

```bash
bash install.sh --silent
```

No console output. All activity logged to `~/.agent-hooks/agent-hooks.log`. Exit code 0 on success, 1 on failure.

### Uninstall

```bash
bash install.sh --uninstall
```

Removes only this tool’s tagged hook entries (see [Install behavior (merge-safe)](#install-behavior-merge-safe)). Fully quit Cursor (Cmd+Q) and restart terminals afterward.

---

## MDM Deployment

Deploy across macOS fleets using JAMF, Kandji, JumpCloud, Microsoft Intune, or any MDM that supports script execution.

### Prerequisites

- macOS 12+ (Monterey or later)
- `bash` 4+ and **`python3`** available to the user running the installer and hooks
- Script execution policy enabled
- User-context execution (not system-level)
- `keywords.txt` file (default or customized)

### Deploying with Custom Keywords

**Option 1: Package together** (recommended)

- Create a deployment package containing `install.sh`, `block-hooks.sh`, and your customized `keywords.txt`
- Upload all three files to your MDM
- Execute `install.sh`

**Option 2: Download from repository**

- Use the curl method below with default keywords
- Pre-deploy a custom `keywords.txt` to a known location, modify install.sh to reference it

### JAMF Pro

1. **Upload the files:**
   - Navigate to **Settings** → **Computer Management** → **Scripts**
   - Create three scripts:
     - `install.sh` (upload file contents)
     - `block-hooks.sh` (upload file contents)
     - `keywords.txt` (upload your customized keywords)
   - Or upload as a package containing all three files

2. **Create a policy:**
   - Navigate to **Computers** → **Policies** → **New**
   - **General:**
     - Name: `Deploy Xyra block-hooks`
     - Trigger: **Recurring Check-In** or **Enrollment Complete**
     - Frequency: **Once per computer**
   - **Scripts:**
     - Add the install script
     - **Parameter 4:** `--silent`
   - **Scope:**
     - Target computers or groups (e.g., "Engineering Workstations")
   - Save and enable

3. **Verify deployment:**
   - Create a Smart Group: **Criteria** → `File` → `/Users/*/‌.agent-hooks/block-hooks.sh` exists
   - Monitor membership over 24-48 hours

### Kandji

1. **Create a Custom Script:**
   - Navigate to **Library** → **Add New** → **Custom Script**
   - **Name:** `Xyra block-hooks`
   - **Execution Frequency:** Once
   - **Run As:** User
   - Upload `install.sh` (or create package with all files)
   - **Script Arguments:** `--silent`

2. **Assign to Blueprint:**
   - Navigate to your Blueprint (e.g., "Engineering Macs")
   - Add the Custom Script
   - Set as **Self-Service** or **Auto-Install**

3. **Monitor deployment:**
   - View status in **Devices** → select device → **Scripts** tab

### JumpCloud

1. **Create a Command:**
   - Navigate to **Commands** → **New Command**
   - **Name:** `Deploy Xyra block-hooks`
   - **Command Type:** Mac
   - **Launch Type:** On Trigger or Once
   - **User:** Run as current user
   - **Timeout:** 60 seconds
   - **Command:**

     ```bash
     #!/bin/bash
     cd /tmp
     curl -sSL https://raw.githubusercontent.com/Xyra-Security-Ltd/xyra-community-tools/main/hooks/block-hooks/install.sh -o install.sh
     curl -sSL https://raw.githubusercontent.com/Xyra-Security-Ltd/xyra-community-tools/main/hooks/block-hooks/block-hooks.sh -o block-hooks.sh
     curl -sSL https://raw.githubusercontent.com/Xyra-Security-Ltd/xyra-community-tools/main/hooks/block-hooks/keywords.txt -o keywords.txt
     bash install.sh --silent
     exit $?
     ```

     **For custom keywords:** Replace the keywords.txt URL with your own hosted file, or embed keywords.txt creation inline:

     ```bash
     #!/bin/bash
     cd /tmp
     curl -sSL https://raw.githubusercontent.com/Xyra-Security-Ltd/xyra-community-tools/main/hooks/block-hooks/install.sh -o install.sh
     curl -sSL https://raw.githubusercontent.com/Xyra-Security-Ltd/xyra-community-tools/main/hooks/block-hooks/block-hooks.sh -o block-hooks.sh
     # Create custom keywords.txt
     cat > keywords.txt <<'EOF'
     volumeDelete
     deleteVolume
     dropDatabase
     terminateInstance
     EOF
     bash install.sh --silent
     exit $?
     ```

2. **Target devices:**
   - **Devices** tab → select device groups (e.g., "Engineering Team")
   - Save

3. **Trigger deployment:**
   - Click **Run** or wait for next check-in

### Microsoft Intune

1. **Create a Shell Script:**
   - Navigate to **Devices** → **macOS** → **Shell scripts** → **Add**
   - **Name:** `Xyra block-hooks`
   - **Upload:** `install.sh` (or package containing all files)
   - **Run script as signed-in user:** Yes
   - **Hide script notifications:** Yes
   - **Script frequency:** Once
   - **Max retries:** 3

2. **Assign to group:**
   - **Assignments** → **Add group**
   - Select target group (e.g., "Engineering-Macs")

3. **Monitor:**
   - **Device status** shows success/failure per device

### Verification (all MDM platforms)

After deployment, spot-check a few devices:

```bash
# SSH into a managed device
ssh user@workstation.local

# Verify hook installed
ls -la ~/.agent-hooks/block-hooks.sh

# Check configurations created
ls -la ~/.cursor/hooks.json ~/.claude/settings.json ~/.codex/hooks.json

# View installation log (should show keyword count)
tail -20 ~/.agent-hooks/agent-hooks.log
```

### Rollback

Deploy the uninstall command:

```bash
bash install.sh --uninstall --silent
```

Or via MDM:

- JAMF: Create a policy with `--uninstall --silent` parameter
- Kandji: Upload new script with uninstall flag
- JumpCloud: Modify command to include `--uninstall`
- Intune: Upload new script with uninstall flag

---

## Testing

### Automated regression tests

From the **repository root** (parent of `hooks/`):

```bash
bash tests/run.sh
```

These cover Cursor JSON field extraction and token matching (safe `cwd` vs blocked `command`, MCP `tool_input` vs ignored `url`).

### Test that blocks work

Start Cursor, Claude Code, or Codex and ask the agent:

> "Run this command: `curl -X POST https://backboard.railway.app/graphql/v2 -H "Authorization: Bearer test" -d '{"query":"mutation { volumeDelete(volumeId: \"test-123\") }"}'`"

**Expected result:** The command is blocked. In Cursor, you'll see "Blocked by Xyra policy." In Claude Code and Codex CLI, the agent will receive the block message and should not retry.

### Test that normal commands work

Ask the agent to run a safe command:

> "List all files in the current directory"

**Expected result:** Command executes normally.

### View logs

```bash
# Watch logs in real-time
tail -f ~/.agent-hooks/agent-hooks.log

# See recent blocks
grep "BLOCK" ~/.agent-hooks/agent-hooks.log | tail -10

# See recent allows
grep "ALLOW" ~/.agent-hooks/agent-hooks.log | tail -10
```

---

## How it works

### Architecture

```
AI Agent (Cursor/Claude/Codex)
    ↓ attempts to execute command
    ↓
Pre-execution hook (this tool)
    ↓ reads stdin (tool call payload)
    ↓ pattern match: volumeDelete?
    ├─ YES → block (exit 2 or deny JSON)
    └─ NO  → allow (exit 0 or allow JSON)
    ↓
Shell / MCP Server (if allowed)
    ↓
Infrastructure API (Railway, AWS, etc.)
```

### Configuration files created

- **Cursor:** `~/.cursor/hooks.json` — configures `beforeShellExecution` and `beforeMCPExecution`
- **Claude Code:** `~/.claude/settings.json` — configures `PreToolUse` with matcher `Bash|mcp__.*`
- **Codex CLI:** `~/.codex/hooks.json` — configures `PreToolUse` with matcher `Bash` (MCP not supported)
- **Hook script:** `~/.agent-hooks/block-hooks.sh` — the actual blocking logic (generated from repo `block-hooks.sh` with injected `BLOCKED_KEYWORDS` from `keywords.txt`)
- **Logs:** `~/.agent-hooks/agent-hooks.log` — all hook activity (ALLOW/BLOCK decisions)

### Detection logic

The hook reads the tool call payload from stdin, derives the text to scan (for Cursor, only the fields described in [Cursor: which text is scanned?](#cursor-which-text-is-scanned); for other agents, typically the full payload), then runs **case-sensitive token matching** for each keyword in `keywords.txt`. A keyword matches only when it appears as a full token—bounded by non alphanumeric/underscore characters or start/end of the scanned string (see [Pattern matching](#pattern-matching)).

**Default keywords** (volume operations) match [`keywords.txt`](keywords.txt).

If any keyword matches: **block**. Otherwise: **allow**.

---

## FAQ

### Does this require the Xyra platform?

No. This tool is independent and open source. No account, no telemetry, no vendor dependency.

### Will this slow down my agents?

No. The hook adds ~1-5ms per command (pattern matching overhead). Imperceptible in practice.

### What if I need to legitimately perform a blocked operation?

The hook blocks all operations containing keywords from `keywords.txt`. If you need to perform a blocked operation:

**Option 1: Temporarily uninstall**

1. Uninstall the hook: `bash install.sh --uninstall`
2. Perform the operation manually (not via agent)
3. Reinstall: `bash install.sh`

**Option 2: Remove keyword temporarily**

1. Edit `keywords.txt` and comment out the keyword (add `#` at start)
2. Reinstall: `bash install.sh`
3. Perform the operation
4. Uncomment the keyword and reinstall

**Option 3: Perform operation outside agent**
Use the web console, CLI, or API directly (not via AI agent). The hook only affects agent operations.

### Does this protect against all destructive operations?

No. This hook only blocks operations containing keywords from your `keywords.txt`. By default, it ships with volume deletion protection only.

To block additional operations:

1. Check `keywords.example.txt` for common destructive operations
2. Copy the keywords you want to block into `keywords.txt`
3. Run `bash install.sh` to apply

Recommended additional keywords:

- Database: `dropDatabase`, `DROP DATABASE`, `deleteDatabase`
- Instances: `terminateInstance`, `destroyInstance`, `stopInstance`
- Storage: `deleteObject`, `deleteBucket`, `emptyBucket`
- Git: `push --force`, `git reset --hard`

### What about Windows or Linux?

Currently macOS only. The agents (Cursor, Claude Code, Codex) have different hook mechanisms on other platforms, and some don't support hooks at all yet.

We're tracking Windows and Linux support. Star the repo for updates.

---

## Support

- **Issues:** [GitHub Issues](https://github.com/Xyra-Security-Ltd/xyra-community-tools/issues)
- **Discussions:** [GitHub Discussions](https://github.com/Xyra-Security-Ltd/xyra-community-tools/discussions)
- **Security:** For security issues, email security@xyraSecurity.ai (do not file a public issue)

---

## Contributing

Repository-wide guidelines: [CONTRIBUTING.md](../../CONTRIBUTING.md).

Found a way to improve this hook? Have ideas for better keyword patterns or additional destructive operations to block?

1. Fork the repo
2. Make your changes:
   - To add keywords: update `keywords.txt` and `keywords.example.txt`
   - To improve detection: modify `block-hooks.sh`
   - To improve deployment: modify `install.sh`
3. Test on all three agents (Cursor, Claude Code, Codex)
4. Open a pull request with:
   - Clear description of the change
   - Test results showing it works
   - Updated documentation if needed
   - Example of the keyword/operation you're blocking

**Keyword contribution guidelines:**

- Add to `keywords.example.txt` (not `keywords.txt`) unless it's a critical default
- Include a comment explaining what infrastructure/API the keyword protects
- Test for false positives on real codebases
- Be specific to minimize false positives

---

## Disclaimer

**Use at your own risk.** This tool is provided "as is" without warranty of any kind, express or implied. Xyra Security Ltd. and contributors are not liable for any damages, data loss, or security incidents that occur while using this tool.

**This is not a complete security solution.** This hook provides one layer of defense against destructive agent operations. It does not replace:

- Proper infrastructure access controls
- Token scoping and least-privilege principles
- Regular backups stored separately from production
- Security monitoring and incident response capabilities
- Human review of critical operations

**Test thoroughly before production deployment.** Verify that:

- Your keywords block intended operations
- False positives don't disrupt legitimate workflows
- The hook is actually invoked (check logs after test operations)
- Your team understands what is and isn't protected

See [LICENSE](../../LICENSE) for full warranty disclaimer and terms of use.

---

## License

Apache License 2.0. See [LICENSE](../../LICENSE) for full text.

---

## About Xyra Security

Xyra Security is an AI agent security platform for enterprise environments. We provide observability, detection, and response for AI coding tools, MCP servers, and agentic workflows.

This tool is part of our community contribution to securing the AI agent ecosystem.

[xyraSecurity.ai](https://xyraSecurity.ai)
