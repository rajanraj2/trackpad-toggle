cask "trackpad-toggle" do
  version "1.0.0"
  sha256 "c466f3373cd607301577a86863c57a76559b2db5f018d17bc07aff8787717fed"

  url "https://github.com/rajanraj2/trackpad-toggle/releases/download/v#{version}/TrackpadToggle.dmg"
  name "Trackpad Toggle"
  desc "Menu-bar utility to disable and re-enable MacBook trackpad via global shortcut"
  homepage "https://github.com/rajanraj2/trackpad-toggle"

  depends_on macos: ">= :sonoma"

  app "TrackpadToggle.app"

  uninstall quit: "com.powertools.trackpadtoggle"

  zap trash: [
    "~/Library/Preferences/com.powertools.trackpadtoggle.plist",
    "~/Library/LaunchAgents/com.powertools.trackpadtoggle.plist",
  ]
end
