cask "codename" do
  version "0.0.2"
  sha256 "7fd79273ccbdc0abbaeb8a3532752a4323f35da30b757bf3cefdaf39237f9476"

  url "https://github.com/Lonkins/CODENAME/releases/download/v#{version}/CODENAME-#{version}.dmg"
  name "CODENAME"
  desc "Native Apple Silicon frontend for libretro cores"
  homepage "https://github.com/Lonkins/CODENAME"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "CODENAME.app"

  zap trash: [
    "~/Library/Application Support/CODENAME",
    "~/Library/Caches/dev.CODENAME.app",
    "~/Library/Preferences/dev.CODENAME.app.plist",
  ]
end
