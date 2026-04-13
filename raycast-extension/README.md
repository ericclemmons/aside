# Aside — Raycast Extension

Context-aware dispatch to AI coding agents. Auto-captures what you're looking at and sends it to OpenCode.

## What It Does

You're working in your editor or browser. You want to tell your AI agent something. Instead of switching to a terminal, manually pasting URLs and code snippets, and losing your flow — hit a hotkey.

Aside auto-gathers context from your environment (selected text, browser URLs, clipboard, recent screenshots) and dispatches your prompt to a running OpenCode Desktop session.

**Aside is not a dictation tool.** Use SuperWhisper, macOS dictation, or just type. Aside is the bridge between "what I'm looking at" and "what I want my agent to do."

## Requirements

- [OpenCode Desktop](https://opencode.ai) must be running with a server active
- [Raycast](https://raycast.com) installed

## Commands

### Dispatch to OpenCode

The main command. Opens a form with:

- **Prompt field** — type, paste, or it's pre-filled by your dictation tool
- **Context checkboxes** — auto-detected from your environment:
  - Selected text from the previous app
  - Browser URL (Chrome, Safari, Arc, Edge, Brave)
  - Clipboard contents
  - Recent screenshots from your Desktop
- **Session selection** via keyboard shortcuts:
  - `Enter` — send to most recent session
  - `Cmd+Enter` — send to new session
  - `Cmd+K` — browse and pick a session

### Browse Sessions

List all OpenCode sessions, grouped by project directory. Useful for seeing what's running.

## Configuration

| Preference | Default | Description |
|---|---|---|
| Screenshot Directory | `~/Desktop` | Where to scan for recent screenshots |
| Screenshot Max Age | `5` minutes | Only show screenshots taken within this window |

## Development

```bash
cd raycast-extension
npm install
npm run dev
```

> **Note:** This extension requires macOS with OpenCode Desktop running. It cannot be tested in CI or on non-macOS platforms. See the [CONTRIBUTING.md](../CONTRIBUTING.md) in the repo root.

## Architecture

```
src/
  dispatch.tsx  — Main dispatch form UI
  sessions.tsx  — Session browser
  context.ts    — Context capture (selected text, URL, clipboard, screenshots)
  opencode.ts   — Server discovery, session fetching, CLI dispatch
```

The extension mirrors the dispatch logic from the native Aside app's `CLIDispatcher.swift`, `SessionManager.swift`, and `ContextCapture.swift`, adapted for the Raycast/Node.js runtime.

## Related

- [Issue #4](https://github.com/ericclemmons/aside/issues/4) — Original spec and discussion
- [Aside native app](../Aside/) — The macOS menu bar app this extension complements
