import Foundation

/// AeroSpace — config ~/.config/aerospace/aerospace.toml (~/.aerospace.toml da desteklenir)
final class AeroSpaceModule: AppModule {
    static let cli = "/opt/homebrew/bin/aerospace"

    init() {
        super.init(id: "aerospace", name: "AeroSpace", kind: .wm, badge: "A", symbol: "square.grid.3x2",
                   bundleID: "bobko.aerospace", appPath: "/Applications/AeroSpace.app",
                   installHint: "brew install --cask nikitabobko/tap/aerospace")
    }

    override var configPath: URL? {
        let xdg = homeURL(".config/aerospace/aerospace.toml")
        let legacy = homeURL(".aerospace.toml")
        return FileManager.default.fileExists(atPath: legacy.path) && !FileManager.default.fileExists(atPath: xdg.path) ? legacy : xdg
    }

    override func reload() throws {
        guard isRunning() else { return }
        let r = Shell.run(Self.cli, ["reload-config", "--no-gui"])
        if !r.ok { throw RiceError.failed("AeroSpace config yüklenemedi: \(r.message)") }
    }
}
