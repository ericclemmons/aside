# Voice Assistant

A macOS push-to-talk voice assistant — like SuperWhisper but open source. Press a global hotkey from any app, speak a command, and dispatch it to a Claude or OpenCode CLI session with full active window context.

## How it works

1. **Press Option+Space** from anywhere in macOS
2. **Speak** — your voice is transcribed locally using NVIDIA Parakeet (fast, accurate, offline)
3. **Context is captured** — the app detects your active window, grabs the URL (if browser), and any selected text
4. **Choose a session** — arrow keys to pick "New Session" or an existing Claude/OpenCode session
5. **Press Enter** — the prompt (transcription + context) is dispatched to the CLI in the background

You never leave what you're doing. The overlay appears, captures your intent, and disappears.

## Prerequisites

- **macOS 12+** (Monterey or later)
- **Rust** — install via [rustup](https://rustup.rs/)
- **Node.js 20+** — install via [nvm](https://github.com/nvm-sh/nvm) or [Homebrew](https://brew.sh/)
- **Claude CLI** and/or **OpenCode CLI** — installed and authenticated
- **Parakeet model** — downloaded locally (see below)

## Setup

```bash
# 1. Clone the repo
git clone https://github.com/ericclemmons/animated-tribble.git
cd animated-tribble

# 2. Install frontend dependencies
npm install

# 3. Download the Parakeet speech-to-text model (~160MB INT8 quantized)
#    Requires: pip install huggingface-hub
huggingface-cli download altunenes/parakeet-tdt-0.6b-v2-onnx-int8 --local-dir ./models

# 4. Run in development mode
npm run tauri dev
```

On first run, macOS will prompt for:
- **Microphone access** — required for voice recording
- **Accessibility access** (System Settings > Privacy > Accessibility) — required for capturing selected text from other apps

## Install via Homebrew

```bash
brew tap ericclemmons/tap
brew install --cask voice-assistant
```

## Usage

| Action | Key |
|--------|-----|
| Start recording | Hold **Option+Space** |
| Stop recording | Release **Option+Space** |
| Switch provider tab | **Left/Right** arrows |
| Navigate sessions | **Up/Down** arrows |
| Send prompt | **Enter** |
| Cancel | **Escape** |

The prompt sent to the CLI includes your transcription plus any captured context:

```
[Context: Chrome — https://github.com/org/repo/issues/42]
[Selected: "TypeError: Cannot read property 'map' of undefined"]

Fix this bug
```

## Architecture

```
React/TypeScript Frontend (Vite + React 18)
├── OverlayWindow — transparent always-on-top overlay
├── Waveform — real-time canvas audio visualization
├── TranscriptionBox — editable transcribed text
└── SessionPicker — tabbed Claude/OpenCode session carousel

Tauri IPC (Commands + Events)

Rust Backend
├── audio.rs — mic capture via cpal (16kHz mono f32 PCM)
├── transcribe.rs — local STT via parakeet-rs (ONNX Runtime)
└── context.rs — AppleScript: active app, browser URL, selected text
```

- **No database** — state is ephemeral, config stored as JSON via `tauri-plugin-store`
- **No external state library** — vanilla React `useContext` + `useReducer`
- **Sessions come from the CLI** — we read what Claude/OpenCode already stores
- **Zero cloud dependency for STT** — Parakeet runs entirely on-device

## Releasing

```bash
# Bump version across package.json, tauri.conf.json, and Cargo.toml
./scripts/release.sh 0.2.0

# Push to trigger the CI release workflow
git push && git push --tags
```

CI builds a macOS universal binary DMG, creates a draft GitHub release, and auto-updates the Homebrew tap.

## Project structure

```
├── src/                          # React/TypeScript frontend
│   ├── components/               # OverlayWindow, Waveform, SessionPicker, etc.
│   ├── hooks/                    # useHotkey, useAudioStream, useSessions, etc.
│   ├── services/                 # cliService, promptBuilder
│   └── context/                  # React Context + useReducer state
├── src-tauri/                    # Rust backend
│   └── src/                      # audio.rs, transcribe.rs, context.rs
├── .github/workflows/            # CI release workflow
├── homebrew/                     # Homebrew cask formula + tap setup script
├── scripts/                      # Version bump / release helper
└── models/                       # Parakeet ONNX model files (gitignored)
```

## License

MIT
