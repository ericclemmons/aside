---
name: aside
description: Dispatch voice-to-code prompts via the Aside CLI — run prompts against OpenCode sessions, list sessions, check server status, and open the TUI.
---

# Aside CLI

Use this skill when the user wants to interact with [Aside](https://github.com/ericclemmons/aside) or dispatch prompts to OpenCode via the `aside` CLI.

## Install

```bash
brew install ericclemmons/tap/aside
```

## Commands

### `aside run` — Dispatch a prompt

```bash
aside run "your prompt here"
aside run -s ses_abc123 "prompt for specific session"
aside run -d /path/to/project "prompt in project dir"
aside run -f /path/to/file "prompt with file attachment"
```

Flags:
- `-s <id>` — target a specific session
- `-d <dir>` — set the working directory
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

Opens the OpenCode terminal UI attached to the active server.

```bash
aside attach
```

## Typical Workflow

1. Check the server: `aside server`
2. List sessions: `aside sessions`
3. Dispatch a prompt: `aside run -s <session-id> "do the thing"`

## Notes

- Aside runs its own `opencode serve` on port 4096 by default
- The CLI connects to whatever server the Aside menu bar app is targeting
- Use `jq` for parsing JSON output (e.g., `aside sessions | jq '.[] | select(.title | test("bug"))'`)
