# Fix for Stale Keyword Blocking Issue

## The Problem

Even after removing keywords from `keywords.txt` and reinstalling, old keywords are still being blocked. This happens because:

1. **Agents cache hooks in memory** - Cursor, Codex CLI, and Claude CLI load hook scripts when they start and keep them in memory
2. **Stale hook files** - Old `.sh` files in `~/.agent-hooks/` can cause confusion

## The Solution

Run the `force-reinstall.sh` script, then **fully quit and restart your agents**.

### Steps to Fix

```bash
# 1. Run force reinstall (cleans up stale files)
cd /Users/yossirachman/Projects/xyra-community-tools/hooks/block-hooks
bash force-reinstall.sh
```

The script will show you the current keywords and verify the installation.

### 2. CRITICAL: Fully Quit and Restart Agents

**For Cursor:**
1. Press `Cmd+Q` (or File → Quit)
2. Wait 3-5 seconds
3. Relaunch Cursor.app from Applications
4. ⚠️ Just closing the window is NOT enough!

**For Codex CLI:**
1. Close ALL terminals running `codex`
2. Open a NEW terminal window
3. Run `codex` again

**For Claude CLI:**
1. Close ALL terminals running `claude`
2. Open a NEW terminal window  
3. Run `claude` again

### 3. Test

After restarting:

```bash
# Should be blocked:
echo "yossirachman"

# Should work:
echo "hello world"
```

## What I Fixed

I've improved the codebase to prevent this issue in the future:

### 1. Enhanced `force-reinstall.sh`
- Now cleans up ALL `.sh` files in `~/.agent-hooks/` before reinstalling
- Shows exactly what keywords are active
- Verifies the generated hook script
- Provides clear restart instructions

### 2. Improved `install.sh` Uninstall
- Now removes ALL stale `.sh` files during uninstall
- Reminds you to fully quit and restart agents

### 3. Added `diagnose.sh`
- Run `bash diagnose.sh` to see:
  - What hooks are installed
  - What keywords are configured
  - Recent blocking activity
  - Potential issues

## Why "Just Restarting" Doesn't Work

- **Closing the window** ≠ Quitting the app
- Cursor keeps running in the background (check menu bar)
- The hook script stays loaded in memory
- You must fully quit (Cmd+Q) to reload hooks

## Quick Check

To see what keywords are currently in your generated hook:

```bash
grep -A 5 "is_blocked()" ~/.agent-hooks/block-hooks.sh
```

You should only see `*yossirachman*)` in the output if that's the only keyword in your `keywords.txt`.

## Still Not Working?

If commands are still being blocked after following all steps:

1. **Verify you fully quit**: Check Activity Monitor (macOS) to ensure Cursor isn't still running
2. **Check the generated hook**: Run `bash diagnose.sh` to see what's actually installed
3. **Manual cleanup**: Remove hooks entirely, then reinstall:
   ```bash
   bash install.sh --uninstall
   rm -rf ~/.agent-hooks/*.sh
   bash install.sh
   ```
4. **Check logs**: `tail -f ~/.agent-hooks/agent-hooks.log` to see what's being blocked

## Files in This Fix

- **force-reinstall.sh** - Complete cleanup and reinstall with verification
- **diagnose.sh** - Diagnostic tool to inspect current state
- **install.sh** - Improved with better uninstall and restart reminders
- **TROUBLESHOOTING.md** - This file
