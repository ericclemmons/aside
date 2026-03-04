# AGENTS.md

Agent instructions for this repository.

## Scope

- Repo root: `.`
- Swift package root: `Aside/`
- App: native macOS SwiftUI menu bar app (`.accessory` activation policy)
- Main target: executable `Aside` (SwiftPM)

## Source of Truth

- `README.md` for product/setup overview
- `CLAUDE.md` for architecture details and workflow context
- `Aside/Package.swift` for dependencies/resources
- `Aside/Sources/Aside/` for implementation

## Build, Run, Test

Run from repo root with `make` for consistency.

```bash
make build
make install
make run
make dev
make watch
make test
make test-one TEST=AsideTests/PromptBuilderTests/testIncludesContextQuote
```

Equivalent direct commands (if needed) run from `Aside/` unless noted.

```bash
swift build
swift build -c release
cp .build/arm64-apple-macosx/debug/Aside Aside.app/Contents/MacOS/Aside
open Aside.app
swift test
```

Notes:

- Launch via `Aside.app` for TCC permissions (Mic, Speech, Accessibility).
- Use `make watch` (`bash watch.sh`, requires `entr`) for iterative UI work so edits auto-rebuild and relaunch.
- `make run` relaunches the existing app bundle binary without rebuilding (best for permission-flow retesting).
- `make install` copies the latest build into `Aside.app` and re-signs with stable id `com.erriclemmons.aside.app`.
- `make dev` performs `build + install + run` when code changed.
- Current tests may report `no tests found` until test targets are added.

## Architecture Guardrails

- Right Option key drives recording/dispatch flows.
- Preserve enum-based recording state machine (`RecordingPhase`).
- Keep overlay state-driven via `OverlayState.mode`; avoid imperative show/hide.
- Keep STT backends behind `TranscriberProtocol`.
- Preserve dispatch flow: transcription -> `PromptBuilder` -> `CLIDispatcher` -> OpenCode.
- Keep resources in `Aside/Sources/Aside/Resources/` and load with `Bundle.module`.

## Code Conventions

- 4-space indentation, concise names, one import per line.
- Prefer `guard` for early exits and shallow branching.
- Use enums over boolean flag combinations for finite states.
- Mark AppKit/UI-touching types with `@MainActor`.
- Prefer async/await; do not block the main thread.
- Handle failures with `do/catch`; avoid `fatalError` for recoverable paths.

## Agent Workflow

1. Read `CLAUDE.md` before major edits.
2. Make focused changes that match existing patterns.
3. For iterative UI changes, run `make watch` and keep it active while editing.
4. Validate with `make build` then `make install` when code changed.
5. Use `make run` for plain relaunches during permission testing.
6. If tests are added/updated, run `make test` and provide `make test-one TEST=...` for a single test.
7. Do not commit or rewrite history unless explicitly requested by the user.

## Rule Files Check

- `.cursor/rules/`: not present
- `.cursorrules`: not present
- `.github/copilot-instructions.md`: not present
