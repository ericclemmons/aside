cask "aside" do
  version "0.1.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/ericclemmons/animated-tribble/releases/download/v#{version}/Aside_#{version}_universal.dmg"
  name "Aside"
  desc "macOS push-to-talk voice assistant with local Parakeet STT"
  homepage "https://github.com/ericclemmons/animated-tribble"

  depends_on macos: ">= :monterey"

  app "Aside.app"

  zap trash: [
    "~/Library/Application Support/com.aside.app",
    "~/Library/Caches/com.aside.app",
    "~/Library/Preferences/com.aside.app.plist",
  ]
end
