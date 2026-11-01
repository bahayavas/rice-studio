import Foundation

enum Paths {
    static let configDir = homeURL(".config/rice-studio")
    static let settings = configDir.appendingPathComponent("settings.json")
    static let state = configDir.appendingPathComponent("state.json")
    static let log = configDir.appendingPathComponent("rice.log")
    static let lock = configDir.appendingPathComponent(".lock")
    static let menubarBackup = configDir.appendingPathComponent("menubar.backup")
    static let profiles = configDir.appendingPathComponent("profiles")
    static let dataDir = homeURL(".rice-studio")
    static let backups = dataDir.appendingPathComponent("backups")

    static func ensure() {
        for d in [configDir, profiles, backups] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }
}

enum Log {
    static var echo = false   // CLI'da stderr'e de yaz

    static func write(_ msg: String) {
        if echo { FileHandle.standardError.write(Data("[rice] \(msg)\n".utf8)) }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) \(msg)\n"
        Paths.ensure()
        if let h = try? FileHandle(forWritingTo: Paths.log) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: Paths.log, atomically: true, encoding: .utf8)
        }
    }

    /// Günlük büyümesin
    static func trim() {
        guard let text = try? String(contentsOf: Paths.log, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 1000 { try? lines.suffix(400).joined(separator: "\n").write(to: Paths.log, atomically: true, encoding: .utf8) }
    }
}

/// ~/.config/rice-studio/settings.json — elle düzenlenebilir; eksik anahtar varsayılanı alır.
struct Settings: Codable, Equatable {
    var launchAtLogin = true
    var notifications = true
    /// Bar seçiliyse macOS menü barı otomatik gizlensin, "Hiçbiri"de geri gelsin
    var manageMenuBar = true
    var loadLastProfileOnLaunch = false
    /// Sidebar sırası ve gizlenen modüller
    var moduleOrder: [String] = []
    var hiddenModules: [String] = []
    var backupsToKeep = 30
    /// "system" | "light" | "dark"
    var appearance = "dark"
    /// "#7aa2f7" biçiminde
    var accentColor = "#7aa2f7"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? d.notifications
        manageMenuBar = try c.decodeIfPresent(Bool.self, forKey: .manageMenuBar) ?? d.manageMenuBar
        loadLastProfileOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .loadLastProfileOnLaunch) ?? d.loadLastProfileOnLaunch
        moduleOrder = try c.decodeIfPresent([String].self, forKey: .moduleOrder) ?? d.moduleOrder
        hiddenModules = try c.decodeIfPresent([String].self, forKey: .hiddenModules) ?? d.hiddenModules
        backupsToKeep = try c.decodeIfPresent(Int.self, forKey: .backupsToKeep) ?? d.backupsToKeep
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? d.appearance
        accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor) ?? d.accentColor
    }

    /// Dosya yoksa nil; bozuksa hata
    static func load() throws -> Settings? {
        guard let data = try? Data(contentsOf: Paths.settings) else { return nil }
        return try JSONDecoder().decode(Settings.self, from: data)
    }

    /// CLI ve geçiş mantığı için: okunamazsa varsayılan
    static var current: Settings { ((try? load()) ?? nil) ?? Settings() }

    func save() throws {
        Paths.ensure()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: Paths.settings, options: .atomic)
    }
}

/// ~/.config/rice-studio/state.json — seçili WM, bar ve profil (login'de geri yüklenir)
struct RiceState: Codable, Equatable {
    var wm: String = "none"
    var bar: String = "none"
    var profile: String?

    static func load() -> RiceState {
        if let data = try? Data(contentsOf: Paths.state), let s = try? JSONDecoder().decode(RiceState.self, from: data) {
            return s
        }
        // İlk açılış: eski switcher'ların seçimini devral
        var s = RiceState()
        func old(_ p: String) -> String? {
            (try? String(contentsOf: homeURL(p), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        s.wm = old(".config/wm-switcher/current") ?? "none"
        s.bar = old(".config/bar-switcher/current") ?? "none"
        return s
    }

    func save() {
        Paths.ensure()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Paths.state, options: .atomic)
    }
}
