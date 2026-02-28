cask "voice-assistant" do
  version "0.1.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/ericclemmons/animated-tribble/releases/download/v#{version}/Voice%20Assistant_#{version}_universal.dmg"
  name "Voice Assistant"
  desc "macOS push-to-talk voice assistant with local Parakeet STT"
  homepage "https://github.com/ericclemmons/animated-tribble"

  depends_on macos: ">= :monterey"

  app "Voice Assistant.app"

  zap trash: [
    "~/Library/Application Support/com.voice-assistant.app",
    "~/Library/Caches/com.voice-assistant.app",
    "~/Library/Preferences/com.voice-assistant.app.plist",
  ]
end
