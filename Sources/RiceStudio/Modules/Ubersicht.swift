import Foundation

/// Übersicht ve simple-bar aynı uygulamayı (Übersicht) paylaşır; aralarındaki fark hangi widget'ların açık olduğu.
/// Widget'lar silinmez/taşınmaz: yalnızca Übersicht'in kendi "hidden" ayarı değişir.
///   kapalıyken: WidgetSettings.json önceden düzenlenir (açılışta yanıp sönmesin)
///   açıkken:    AppleScript `hidden of widget id …` (Übersicht dosyayı kendisi kaydeder)
/// Widget id'si klasör yolundan gelir: widgets/simple-bar/index.jsx → "simple-bar-index-jsx".
class UbersichtFamily: AppModule {
    enum Mode: String { case only, except }

    static let widgetsDir = homeURL("Library/Application Support/Übersicht/widgets")
    static let settingsFile = homeURL("Library/Application Support/tracesOf.Uebersicht/WidgetSettings.json")
    static let family: Set<String> = ["simplebar", "ubersicht"]

    let mode: Mode
    let folder: String

    init(id: String, name: String, badge: String, symbol: String, mode: Mode, folder: String) {
        self.mode = mode
        self.folder = folder
        super.init(id: id, name: name, kind: .bar, badge: badge, symbol: symbol,
                   bundleID: "tracesOf.Uebersicht", appPath: "/Applications/Übersicht.app",
                   installHint: "brew install --cask ubersicht")
    }

    /// Übersicht çalışıyor mu (hangi modda olursa olsun)
    var processRunning: Bool { processAlive }

    /// Übersicht açıksa hangi modda: kayıtlı bar ailedense o, değilse "ubersicht"
    static var activeMode: String {
        let bar = RiceState.load().bar
        return family.contains(bar) ? bar : "ubersicht"
    }

    override func isRunning() -> Bool { processRunning && Self.activeMode == id }

    // Übersicht normal Quit'i yok sayıyor; 3 sn sonra TERM ile kapanır
    override func stop() throws {
        // Aynı süreç: yalnızca o an aktif olan mod kapatır (öteki no-op), günlük doğru adı yazsın
        guard processRunning, Self.activeMode == id else { return }
        try super.stop()
    }

    override func start() throws {
        guard isInstalled else { throw RiceError.notInstalled(name) }
        if processRunning {
            Log.write("Übersicht açık, widget'lar \(id) için ayarlanıyor")
            applyLive()
            return
        }
        Log.write("\(id) başlatılıyor")
        applyToFile()
        try Shell.openApp(appPath)
        Shell.wait(5) { self.processRunning }
        applyLive()
    }

    override func restart() throws {
        if processRunning { try super.stop() }
        try start()
    }

    /// TERM ile ölünce node widget sunucusu öksüz kalıyor
    override func afterStop() {
        Shell.signal(Shell.pids(pathPrefix: appPath + "/Contents/Resources/"), SIGTERM)
    }

    func shouldHide(_ widgetID: String) -> Bool {
        let inFolder = widgetID == folder || widgetID.hasPrefix(folder + "-")
        return mode == .only ? !inFolder : inFolder
    }

    /// Widget'lar: id → gizli mi (ayar dosyasından; Übersicht kapalıyken de çalışır)
    static func widgetStates() -> [(id: String, hidden: Bool)] {
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return json.keys.sorted().map { ($0, json[$0]?["hidden"] as? Bool ?? false) }
    }

    private func applyToFile() {
        guard let data = try? Data(contentsOf: Self.settingsFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
        var changed = false
        for (wid, var s) in json where (s["hidden"] as? Bool) != shouldHide(wid) {
            s["hidden"] = shouldHide(wid)
            json[wid] = s
            changed = true
        }
        if changed, let out = try? JSONSerialization.data(withJSONObject: json) {
            try? out.write(to: Self.settingsFile, options: .atomic)
        }
    }

    /// Widget'lar sunucu derleyince listede belirir (birkaç sn). Ayrılmış osascript bekler ve ayarlar:
    /// CLI hemen dönebilsin, Rice Studio kapansa da iş bitsin.
    private func applyLive() {
        let script = Paths.dataDir.appendingPathComponent("ubersicht-widgets.js")
        try? Self.liveScript.write(to: script, atomically: true, encoding: .utf8)
        try? Shell.spawnDetached("/usr/bin/osascript", ["-l", "JavaScript", script.path, mode.rawValue, folder])
    }

    private static let liveScript = """
    // Rice Studio: Übersicht widget'larını gizle/göster — osascript -l JavaScript <bu dosya> <only|except> <klasör>
    function run(argv) {
        const [mode, folder] = argv
        const hide = id => { const f = id === folder || id.startsWith(folder + '-'); return mode === 'only' ? !f : f }
        const app = Application('tracesOf.Uebersicht')
        let passes = 0
        for (let tries = 0; tries < 40; tries++) {
            let ids = []
            // widgets() öğeleri doğrudan okunamıyor (-1700); id listesi + byId çalışıyor
            try { ids = app.widgets.id() } catch (e) { }
            if (ids.length > 0) {
                for (const id of ids) {
                    const w = app.widgets.byId(id)
                    if (w.hidden() !== hide(id)) w.hidden = hide(id)
                }
                if (++passes >= 2) break   // geç derlenen widget'lar için bir tur daha
                delay(2)
                continue
            }
            delay(0.5)
        }
    }
    """
}

/// simple-bar — Übersicht'te yalnızca widgets/simple-bar açık. Kendi ayarları ~/.simplebarrc (JSON).
final class SimpleBarModule: UbersichtFamily {
    init() {
        super.init(id: "simplebar", name: "simple-bar", badge: "SM", symbol: "rectangle.topthird.inset.filled",
                   mode: .only, folder: "simple-bar")
    }

    override var configPath: URL? { homeURL(".simplebarrc") }
    override var backupPaths: [URL] { [homeURL(".simplebarrc"), Self.settingsFile] }

    override func validateConfig(_ text: String) -> ValidationResult {
        do {
            _ = try JSONSerialization.jsonObject(with: Data(text.utf8))
            return .valid
        } catch {
            return .invalid(".simplebarrc geçerli JSON değil: \(error.localizedDescription)")
        }
    }
}

/// Übersicht — kendi widget'ların, simple-bar kapalı
final class UbersichtModule: UbersichtFamily {
    init() {
        super.init(id: "ubersicht", name: "Übersicht", badge: "ÜB", symbol: "square.stack.3d.up",
                   mode: .except, folder: "simple-bar")
    }

    override var configPath: URL? { Self.settingsFile }
    override var backupPaths: [URL] { [Self.settingsFile] }
}
