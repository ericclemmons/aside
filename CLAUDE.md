# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build
cd Aside && swift build

# Deploy (must use .app bundle — bare binary silently fails TCC permissions)
cp .build/arm64-apple-macosx/debug/Aside Aside.app/Contents/MacOS/Aside && open Aside.app

# Watch mode (auto-rebuild + relaunch on file changes, requires `brew install entr`)
cd Aside && bash watch.sh
```

## Architecture

Native SwiftUI macOS menu bar app (no dock icon, `.accessory` activation policy). Right Option key is the sole input mechanism — hold to dictate, tap-tap to dispatch to OpenCode CLI.

### Recording State Machine (`AsideApp.swift`)

The core of the app is `RecordingPhase` in `AppDelegate`:

```
idle → recording → persistent → finishingDispatch → idle
                              → finishingHoldToType → idle
```

- **idle→recording**: Right Option pressed
- **recording→finishingHoldToType**: Key released with text → type it
- **recording→persistent**: Key released with no text → wait for 2nd tap
- **persistent→finishingDispatch**: 2nd tap → show picker
- Any state→idle: Escape, chord (⌥+other key), or click outside

### Key Files

| File                           | Role                                                      |
| ------------------------------ | --------------------------------------------------------- |
| `AsideApp.swift`               | AppDelegate + RecordingPhase state machine, all wiring    |
| `HotkeyManager.swift`          | CGEvent tap for Right Option key (requires Accessibility) |
| `RecordingOverlayWindow.swift` | NSPanel + OverlayState (hidden/waveform/picker)           |
| `SetupWindow.swift`            | 7-step permission wizard + waveform banner                |
| `ContextCapture.swift`         | AppleScript: app, URL, selected text                      |
| `PromptBuilder.swift`          | Assembles `> quoted-context\n\ntranscription`             |
| `CLIDispatcher.swift`          | Spawns `opencode --attach localhost:4096 run -- <prompt>` |
| `SessionManager.swift`         | `opencode session list --format json` → session list      |

### UI Layer

`OverlayState` is the single source of truth for the floating panel — it's an `@MainActor ObservableObject` with a `mode: OverlayMode` enum (`.hidden/.waveform/.picker`). `RecordingOverlayWindow.observe(state:)` subscribes via Combine and reacts: hidden=`orderOut`, waveform=`orderFront`, picker=`makeKeyAndOrderFront` + install key/click monitors. Never call show/hide imperatively; set `overlayState.mode` instead.

The setup screen's `SetupWaveformBanner` (Canvas-based, multi-layer sine waves with gaussian envelope + glow) is the prototype for the recording overlay waveform — it will eventually replace `WaveformView`.

### STT Backends

Both implement `TranscriberProtocol` (isRecording, audioLevel, transcribedText, onTranscriptionFinished). `AppDelegate` uses whichever is active without type-checking. `MicLevelMonitor` in `SetupWindow.swift` uses `AVAudioRecorder` with `isMeteringEnabled = true` set **before** `record()` — order matters.

### Dispatch Flow

```
transcription → PromptBuilder (adds > context) → CLIDispatcher
                                               → opencode --attach localhost:4096 run -- <prompt>
```

`opencode serve --port 4096` is started at app launch. Sessions fetched from that server. PATH is augmented with `~/.opencode/bin:/opt/homebrew/bin:/usr/local/bin` for subprocess calls.

### Permissions

Three TCC permissions required (requested in order by setup wizard):

1. Microphone — recording
2. Speech Recognition — Apple STT
3. Accessibility — CGEvent tap for global hotkey

TCC entries are tied to the binary's code signature; each build gets a fresh TCC entry.

## Conventions

- Prefer `enum` state machines over boolean flags — avoids impossible states
- `@MainActor` on all AppKit/UI-touching classes
- Resources (SVGs, PNGs) in `Sources/Aside/Resources/`, loaded via `Bundle.module`
- Commit after each logical task without asking for confirmation
