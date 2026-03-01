# Aside

A macOS menu bar app for voice-driven coding. Press a hotkey, speak, and dispatch prompts to OpenCode with full window context — selected text, URLs, everything.

## How it works

1. **Tap Right Option** from anywhere in macOS
2. **Speak** — transcribed locally via Apple Speech or WhisperKit (on-device)
3. **Context is captured** — active window, browser URL, selected text (via accessibility, browser JS, or clipboard)
4. **Tap again** — pick a session with arrow keys
5. **Enter** — prompt + context dispatched to OpenCode CLI

Two modes:

- **Hold to type** — hold Right Option, speak, release to type text into the active field
- **Tap to dispatch** — tap to start, tap to stop, choose a session, send to OpenCode

## Setup

```bash
cd Aside && swift build
cp .build/arm64-apple-macosx/debug/Aside Aside.app/Contents/MacOS/Aside
open Aside.app
```

Must launch via `.app` bundle for TCC permissions (Accessibility, Microphone, Speech Recognition).

## Prerequisites

- **macOS 14+** (Sonoma or later)
- **Xcode / Swift toolchain**
- **OpenCode CLI** — installed and authenticated

## Architecture

Native SwiftUI macOS app — menu bar only (no dock icon).

```
Aside/Sources/Aside/
├── AsideApp.swift              — AppDelegate, recording state machine, hotkey setup
├── HotkeyManager.swift         — CGEvent tap for Right Option key
├── RecordingOverlayWindow.swift — NSPanel overlay, state-driven via Combine
├── WaveformView.swift           — Recording waveform UI
├── SpeechTranscriber.swift      — Apple SFSpeechRecognizer
├── WhisperTranscriber.swift     — WhisperKit (on-device Whisper)
├── ContextCapture.swift         — AppleScript context: app, URL, selection
├── CLIDispatcher.swift          — Shell dispatch to opencode
├── SessionManager.swift         — Fetches opencode sessions
├── PromptBuilder.swift          — Assembles prompt with context
└── SetupWindow.swift            — Permission walkthrough wizard
```

Key design choices:

- **State machine** (`RecordingPhase`) over boolean flags — no impossible states
- **State-driven overlay** — panel visibility derived from `OverlayMode` via Combine, no imperative show/hide
- **Universal text selection** — AX accessibility, browser JS, clipboard fallback (Cmd+C save/restore)
- **Zero cloud dependency for STT** — all transcription runs on-device

## Prior Art & Inspiration

This project builds on ideas from:

- **[Superwhisper](https://superwhisper.com/)** — the gold standard for voice-to-text on macOS. Aside's hold-to-type UX and floating overlay are directly inspired by Superwhisper's approach to ambient voice input.
- **[Kaze](https://github.com/nicklama/kaze)** — a minimal macOS hotkey utility. Influenced the CGEvent tap approach for global hotkey capture via Right Option.
- **[WhisperKit](https://github.com/argmaxinc/WhisperKit)** — on-device Whisper inference for Swift/CoreML. Used as the optional STT backend.
- **[OpenCode](https://opencode.ai/)** — the CLI coding assistant that Aside dispatches to.

## License

MIT
