# claude-statusline-ui

A three-line status line for [Claude Code](https://claude.com/claude-code).

```
➜  my-project git:(main)
Opus 4 (high) ▓▓▓▓░░░░░░░░░░░░░░░░ 40k/200k (20%)
Prompt Cache Status: Warm · ~38.2k tokens cached · expires in 4m
```

1. **Project**: current folder and git branch.
2. **Context**: model (and effort level), a context-window usage bar, tokens used / max, and percent used.
3. **Prompt cache**: whether the prompt cache is warm or cold, how many tokens are cached (or would need to be re-cached), and minutes until it expires. Requires Claude Code >= 2.1.251.

Requires `jq` and `git`.

## How to use it

### Option 1: Automatic install

Paste this into Claude Code:

```
/statusline Set up the status line from https://github.com/tinder-allensun/claude-cli-statusline-ui

Do NOT write or generate your own script. Reuse the existing statusline.sh from that repo exactly as-is:
1. Download statusline.sh from that repo (raw file from the main branch) to ~/.claude/statusline.sh.
2. Check that jq is installed; if not, tell me how to install it.
3. Use the statusline setup to add a "statusLine" entry to ~/.claude/settings.json with type "command",
   command "bash ~/.claude/statusline.sh", and "refreshInterval": 30. Keep all my existing settings, and
   if I already have a statusLine configured, ask me before replacing it.
4. Test it by piping sample JSON into the script and show me the output.
```

Restart Claude Code (or open a new session) to see the new status line.

### Option 2: Manual setup

1. Install `jq` if you don't have it (`brew install jq` on macOS, `sudo apt install jq` on Debian/Ubuntu).

2. Copy the script into your Claude config folder:

   ```bash
   curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/tinder-allensun/claude-cli-statusline-ui/main/statusline.sh
   ```

   Or clone this repo and copy `statusline.sh` to `~/.claude/statusline.sh`.

3. Open `~/.claude/settings.json` (create it if it doesn't exist) and add:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline.sh",
       "refreshInterval": 30
     }
   }
   ```

   If the file already has other settings, add `statusLine` alongside them.

4. Restart Claude Code.

To test the script on its own:

```bash
echo '{"model":{"display_name":"Opus"},"context_window":{"context_window_size":200000,"total_input_tokens":40000,"used_percentage":20}}' | bash ~/.claude/statusline.sh
```
