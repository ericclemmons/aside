---
name: aside
description: Create new or append to existing OpenCode sessions via the Aside CLI — dispatch prompts, list sessions, check server status, and open the TUI.
---

# Aside CLI

Use this skill when the user wants to create new OpenCode sessions or append prompts to existing ones via the [Aside](https://github.com/ericclemmons/aside) CLI.

## Install

```bash
brew install ericclemmons/tap/aside
```

## Commands

### `aside prompt` — Dispatch a prompt

Auto-connects to the running server and defaults to the most recent session's workspace directory.

```bash
aside prompt "your prompt here"
aside --session ses_abc123 prompt "continue this session"
aside prompt -d /path/to/project "prompt in specific dir"
aside prompt -f /path/to/file "prompt with file attachment"
echo "piped prompt" | aside prompt
```

Global flags (before subcommand):
- `--session <id>` / `-s <id>` — target a specific session

Subcommand flags:
- `-d <dir>` — override working directory (defaults to most recent session's dir)
- `-f <file>` — attach a file to the prompt

### `aside sessions` — List sessions

Returns JSON array of all sessions from the active server.

```bash
aside sessions
aside sessions | jq '.[].title'
```

### `aside server` — Show active server

Returns JSON with the current server target, URL, and auth status.

```bash
aside server
```

Example output:
```json
{"target": "aside", "url": "http://127.0.0.1:4096", "auth": false}
```

### `aside attach` — Open OpenCode TUI

Opens the OpenCode terminal UI, continuing the most recent session.

```bash
aside attach
```

## Typical Workflow

1. Check the server: `aside server`
2. List sessions: `aside sessions`
3. Create a new session: `aside prompt "do the thing"`
4. Append to an existing session: `aside --session <id> prompt "follow up"`

## Notes

- The CLI auto-discovers the active server (Aside on port 4096 or OpenCode Desktop)
- Without `-d`, defaults to the most recent session's workspace directory
- Use `jq` for parsing JSON output (e.g., `aside sessions | jq '.[] | select(.title | test("bug"))'`)
