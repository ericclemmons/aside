# Contributing to Aside

## Repository Structure

```
Aside/          — Native macOS menu bar app (Swift/SwiftUI)
raycast-extension/  — Raycast extension (TypeScript/React)
bin/            — CLI tool (bash)
```

## Native App (Aside/)

See [CLAUDE.md](./CLAUDE.md) for build, deploy, and watch commands.

Requires macOS with Xcode and Swift toolchain.

## Raycast Extension (raycast-extension/)

```bash
cd raycast-extension
npm install
npm run dev     # Opens in Raycast dev mode
npm run build   # Production build
npm run lint    # ESLint check
```

### Testing Notes

The Raycast extension **cannot be tested in CI or on non-macOS platforms**. It requires:

1. **macOS** — uses macOS-specific APIs (AppleScript, process scanning)
2. **Raycast installed** — the `@raycast/api` runtime is provided by Raycast
3. **OpenCode Desktop running** — the extension discovers and dispatches to a live server

To test locally:
1. Start OpenCode Desktop
2. Run `npm run dev` in the extension directory
3. Open Raycast and search for "Dispatch to OpenCode"

### What to Verify When Testing

- [ ] Server discovery finds a running OpenCode Desktop instance
- [ ] Sessions are listed and sorted by most recent
- [ ] Context capture picks up selected text from the previous app
- [ ] Browser URL is captured for Chrome/Safari/Arc
- [ ] Clipboard contents appear as a context option
- [ ] Recent screenshots from Desktop appear (if any exist)
- [ ] Dispatching a prompt reaches the OpenCode session
- [ ] `Cmd+Enter` creates a new session
- [ ] `Cmd+K` opens the session picker

## CLI Tool (bin/)

The `aside` CLI is a bash script. See `bin/aside --help` for usage.
