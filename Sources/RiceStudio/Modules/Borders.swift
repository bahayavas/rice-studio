import Foundation

/// JankyBorders — `borders` açılışta ~/.config/borders/bordersrc'yi çalıştırır.
/// brew services ile kuruluysa launchd işi KeepAlive'dır: öldürülürse geri gelir, bu yüzden
/// durdurma/başlatma launchctl üzerinden yapılır.
final class BordersModule: BinaryModule {
    static let label = "sh.brew.borders"
    static let plist = homeURL("Library/LaunchAgents/sh.brew.borders.plist")

    init() {
        super.init(id: "borders", name: "JankyBorders", kind: .extra, badge: "JB", symbol: "square.dashed",
                   binary: "/opt/homebrew/bin/borders",
                   installHint: "brew tap FelixKratz/formulae && brew install borders")
    }

    override var configPath: URL? { homeURL(".config/borders/bordersrc") }

    private var domain: String { "gui/\(getuid())" }
    private var launchdLoaded: Bool { Shell.run("/bin/launchctl", ["print", "\(domain)/\(Self.label)"]).ok }

    override func start() throws {
        guard isInstalled else { throw RiceError.notInstalled(name) }
        guard !isRunning() else { return }
        Log.write("borders başlatılıyor")
        if FileManager.default.fileExists(atPath: Self.plist.path) {
            if !launchdLoaded { Shell.run("/bin/launchctl", ["bootstrap", domain, Self.plist.path]) }
            Shell.run("/bin/launchctl", ["kickstart", "\(domain)/\(Self.label)"])
        } else {
            try Shell.spawnDetached(binary)
        }
        Shell.wait(3) { self.isRunning() }
    }

    override func stop() throws {
        guard isRunning() || launchdLoaded else { return }
        Log.write("borders kapatılıyor")
        // bootout: KeepAlive yeniden başlatmasın (plist yerinde kalır, login'de yine yüklenir)
        if launchdLoaded { Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(Self.label)"]) }
        try super.stop()
    }

    override func reload() throws {
        guard isRunning(), let path = configPath?.path else { return }
        // bordersrc `borders <seçenekler>` çağırır; çalışan borders yeni seçenekleri canlı alır
        let r = Shell.run("/bin/bash", [path])
        if !r.ok { throw RiceError.failed("bordersrc çalışmadı: \(r.message)") }
    }
}
