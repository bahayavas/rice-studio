import Foundation

/// SketchyBar — brew binary, config klasörü ~/.config/sketchybar/ (sketchybarrc shell ya da Lua)
final class SketchyBarModule: BinaryModule {
    init() {
        super.init(id: "sketchybar", name: "SketchyBar", kind: .bar, badge: "SB", symbol: "menubar.rectangle",
                   binary: "/opt/homebrew/bin/sketchybar",
                   installHint: "brew tap FelixKratz/formulae && brew install sketchybar")
    }

    static let dir = homeURL(".config/sketchybar")

    override var configPath: URL? { Self.dir.appendingPathComponent("sketchybarrc") }
    override var backupPaths: [URL] { [Self.dir] }

    override func reload() throws {
        guard isRunning() else { return }
        let r = Shell.run(binary, ["--reload"])
        if !r.ok { throw RiceError.failed("SketchyBar yeniden yüklenemedi: \(r.message)") }
    }
}
