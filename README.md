# Aside

A macOS push-to-talk voice assistant — like SuperWhisper but open source. Press a global hotkey from any app, speak a command, and dispatch it to a Claude or OpenCode CLI session with full active window context.

## How it works

1. **Press Right Option** from anywhere in macOS
2. **Speak** — your voice is transcribed locally using Whisper (runs entirely on-device)
3. **Context is captured** — the app detects your active window, grabs the URL (if browser), and any selected text
4. **Choose a session** — arrow keys to pick "New Session" or an existing Claude/OpenCode session
5. **Press Enter** — the prompt (transcription + context) is dispatched to the CLI in the background

You never leave what you're doing. The overlay appears, captures your intent, and disappears.

## Prerequisites

- **macOS 12+** (Monterey or later)
- **Rust** — install via [rustup](https://rustup.rs/)
- **Node.js 20+** and **pnpm** — install Node via [nvm](https://github.com/nvm-sh/nvm), then `npm i -g pnpm`
- **Claude CLI** and/or **OpenCode CLI** — installed and authenticated

## Setup

```bash
# 1. Clone the repo
git clone https://github.com/ericclemmons/animated-tribble.git
cd animated-tribble

# 2. Install frontend dependencies
pnpm install

# 3. Run in development mode
pnpm dev
```

On first run, the setup screen will:

1. **Check Accessibility** — needed for the Right Option hotkey (System Settings > Privacy > Accessibility)
2. **Download Whisper model** (~148 MB, one time) — the default speech-to-text engine
3. **Load the model** — verify it works before you start

## STT Backends

Aside supports multiple speech-to-text engines, switchable from the tray menu:

| Backend                     | Setup                                  | Speed | Accuracy                           |
| --------------------------- | -------------------------------------- | ----- | ---------------------------------- |
| **Whisper** (default)       | Auto-downloaded on first run (~148 MB) | Fast  | Excellent for short commands       |
| **Apple Speech** (fallback) | Built into macOS, zero setup           | Fast  | Good, but may need on-device model |

Switch backends from the menu bar icon > **STT Backend**.

## Install via Homebrew

```bash
brew tap ericclemmons/tap
brew install --cask aside
```

## Usage

| Action              | Key                      |
| ------------------- | ------------------------ |
| Start recording     | Hold **Right Option**    |
| Stop recording      | Release **Right Option** |
| Switch provider tab | **Left/Right** arrows    |
| Navigate sessions   | **Up/Down** arrows       |
| Send prompt         | **Enter**                |
| Cancel              | **Escape**               |

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
├── SetupScreen — first-run dependency checker & onboarding
├── Waveform — real-time canvas audio visualization
├── TranscriptionBox — editable transcribed text
└── SessionPicker — tabbed Claude/OpenCode session carousel

Tauri IPC (Commands + Events)

Rust Backend
├── audio.rs — mic capture via cpal (16kHz mono f32 PCM)
├── transcribe.rs — STT via whisper-rs (default) or Apple SFSpeechRecognizer
└── context.rs — AppleScript: active app, browser URL, selected text

Swift Bridge (swift-rs)
└── SpeechBridge.swift — SFSpeechRecognizer FFI for Apple STT fallback
```

- **No database** — state is ephemeral, config stored as JSON via `tauri-plugin-store`
- **No external state library** — vanilla React `useContext` + `useReducer`
- **Sessions come from the CLI** — we read what Claude/OpenCode already stores
- **Zero cloud dependency for STT** — all backends run entirely on-device

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
│   ├── components/               # OverlayWindow, SetupScreen, Waveform, etc.
│   ├── hooks/                    # useHotkey, useAudioStream, useSessions, etc.
│   ├── services/                 # cliService, promptBuilder
│   └── context/                  # React Context + useReducer state
├── src-tauri/                    # Rust backend
│   ├── src/                      # audio.rs, transcribe.rs, context.rs
│   └── swift-lib/                # Swift bridge for Apple Speech Recognition
├── models/                       # Whisper ggml model (auto-downloaded, gitignored)
├── scripts/                      # Model download, version bump, release
├── .github/workflows/            # CI release workflow
└── homebrew/                     # Homebrew cask formula + tap setup script
```

## License

MIT

---

## TODO: Code signing and distribution setup

These steps are needed before the first public release. Without code signing, macOS Gatekeeper blocks the app on other machines.

- [ ] **Enroll in the Apple Developer Program** ($99/year) at https://developer.apple.com/programs/ — required for Developer ID certificates
- [ ] **Create a Developer ID Application certificate** in Xcode (Settings → Accounts → Manage Certificates → +) or via the Apple Developer portal
- [ ] **Export the certificate as .p12** from Keychain Access (right-click the certificate → Export), then base64 encode: `base64 -i certificate.p12 -o certificate-base64.txt`
- [ ] **Create an app-specific password** for notarization at https://appleid.apple.com/account/manage (App-Specific Passwords → Generate)
- [ ] **Find your Team ID** by running `security find-identity -v -p codesigning` — it's the 10-char code in parentheses
- [ ] **Add GitHub repo secrets** (Settings → Secrets → Actions):
  - `APPLE_CERTIFICATE` — contents of `certificate-base64.txt`
  - `APPLE_CERTIFICATE_PASSWORD` — password used when exporting the .p12
  - `APPLE_SIGNING_IDENTITY` — full string, e.g. `Developer ID Application: Your Name (TEAMID)`
  - `APPLE_ID` — your Apple ID email
  - `APPLE_PASSWORD` — the app-specific password from above
  - `APPLE_TEAM_ID` — your 10-character Team ID
  - `HOMEBREW_TAP_TOKEN` — a GitHub PAT with `repo` scope (so CI can push to your tap repo)
- [ ] **Create the Homebrew tap repo**: `./homebrew/setup-tap.sh ericclemmons`
- [ ] **Test a release**: `./scripts/release.sh 0.1.0 && git push && git push --tags`
- [ ] **Verify the signed build**: download the DMG, extract, then run `spctl --assess --type execute --verbose "Aside.app"` — should output "accepted"

References:

- [Tauri v2 code signing docs](https://v2.tauri.app/distribute/sign/macos/)
- [Apple Developer ID overview](https://developer.apple.com/developer-id/)
- [tauri-apps/tauri-action](https://github.com/tauri-apps/tauri-action) — handles signing + notarization automatically when secrets are present
