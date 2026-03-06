# Aside

A macOS menu bar app for voice-driven coding. Press a hotkey, speak, and dispatch prompts to [OpenCode](https://opencode.ai/) with full window context — selected text, URLs, everything.

## How it works

1. **Tap Right Option** from anywhere in macOS
2. **Speak** — transcribed locally via Apple Speech, WhisperKit, or Parakeet (all on-device)
3. **Context is captured** — active window, browser URL, selected text
4. **Tap again** — pick a session with arrow keys
5. **Enter** — prompt + context dispatched to OpenCode CLI

Two modes:

- **Hold to type** — hold Right Option, speak, release to type text into the active field
- **Tap to dispatch** — tap to start, tap to stop, choose a session, send to OpenCode

## Install

```bash
brew install ericclemmons/tap/aside
```

## Development

Requires **macOS 14+** (Sonoma), **Xcode / Swift toolchain**, and [OpenCode CLI](https://opencode.ai/).

```bash
make dev        # build, sign, and launch the app
make watch      # auto-rebuild + relaunch on file changes (requires `brew install entr`)
make test       # run all tests
make clean      # clean build artifacts
```

Must launch via `.app` bundle for TCC permissions (Accessibility, Microphone, Speech Recognition).

### All make targets

| Target | What it does |
|--------|-------------|
| `make build` | Debug build (`swift build`) |
| `make dev` | Build + Developer ID codesign + lsregister + launch |
| `make watch` | File watcher — rebuilds and relaunches on save |
| `make test` | Run all tests |
| `make test-one TEST=...` | Run a single test (e.g. `TEST=AsideCoreTests/ReducerTests/testIdleKeyDown`) |
| `make clean` | `swift package clean` |
| `make build-release` | Optimized release build |
| `make release` | Release build + bundle + optional codesign |

## Publishing

Releases are fully automated via GitHub Actions:

1. **Push to `main`** — [prepare-release](.github/workflows/prepare-release.yml) auto-bumps the patch version and creates a `vX.Y.Z` tag
2. **Tag push** — [release](.github/workflows/release.yml) builds, codesigns with Developer ID, notarizes with Apple, creates a GitHub Release, and updates the [Homebrew tap](https://github.com/ericclemmons/homebrew-tap)

No manual steps needed. Just push to main.

## Architecture

Native SwiftUI macOS app — menu bar only (no dock icon, `.accessory` activation policy).

### State machine

The app uses a unidirectional architecture: `AppStore` (ObservableObject) + pure `reduce()` function + `EffectExecutor` for side effects.

```
idle → recording → persistent → finishing(dispatch) → dispatching → idle
                 → finishing(holdToType) → idle
```

### Key files

```
Aside/Sources/
├── Aside/
│   ├── AsideApp.swift                  — AppDelegate, store wiring, menu bar
│   ├── HotkeyManager.swift             — CGEvent tap for Right Option key
│   ├── RecordingOverlayWindow.swift     — NSPanel overlay (waveform + picker)
│   ├── SpeechTranscriber.swift          — Apple SFSpeechRecognizer
│   ├── WhisperTranscriber.swift         — WhisperKit (on-device Whisper)
│   ├── ParakeetTranscriber.swift        — Parakeet (NVIDIA, on-device)
│   ├── ContextCapture.swift             — AppleScript: app, URL, selected text
│   ├── CLIDispatcher.swift              — Shell dispatch to opencode CLI
│   ├── Effects/EffectExecutor.swift     — Maps Effects to service calls
│   ├── Services/                        — TranscriptionService, PermissionService, etc.
│   └── Views/                           — SettingsView, SetupView, onboarding
└── AsideCore/
    └── StateMachine/                    — AppPhase, AppEvent, Effect, reduce()
```

## Prior Art & Inspiration

- **[Superwhisper](https://superwhisper.com/)** — the gold standard for voice-to-text on macOS. Aside's hold-to-type UX and floating overlay are directly inspired by Superwhisper.
- **[Kaze](https://github.com/nicklama/kaze)** — minimal macOS hotkey utility. Influenced the CGEvent tap approach for Right Option.
- **[WhisperKit](https://github.com/argmaxinc/WhisperKit)** — on-device Whisper inference for Swift/CoreML.
- **[OpenCode](https://opencode.ai/)** — the CLI coding assistant that Aside dispatches to.

## License

MIT
