import AppKit

/// Geçiş mantığı: aynı anda 1 WM + 1 bar. Uygulama ve CLI ikisi de bunu kullanır;
/// aynı anda iki geçiş olmasın diye ~/.config/rice-studio/.lock üzerinde flock.
enum Engine {
    enum Outcome: Equatable {
        case switched, alreadyActive
    }

    // MARK: Durum

    /// Çalışan WM (birden fazlaysa kayıtlı olan öncelikli), yoksa "none"
    static func activeID(_ kind: ModuleKind) -> String {
        let saved = kind == .wm ? RiceState.load().wm : RiceState.load().bar
        let running = Registry.modules(kind).filter { $0.isRunning() }.map(\.id)
        if running.contains(saved) { return saved }
        return running.first ?? "none"
    }

    // MARK: Geçiş

    /// kind: .wm ya da .bar; target: modül id'si ya da "none"
    @discardableResult
    static func switchTo(_ kind: ModuleKind, _ target: String) throws -> Outcome {
        precondition(kind != .extra)
        return try withLock {
            let mods = Registry.modules(kind)
            var t: RiceModule?
            if target != "none" {
                guard let m = mods.first(where: { $0.id == target }) else { throw RiceError.unknownModule(target) }
                guard m.isInstalled else { throw RiceError.notInstalled(m.name) }
                t = m
            }
            let others = mods.filter { $0.id != target && $0.processGroup != t?.processGroup }

            // Zaten açık ve tek başına çalışıyorsa hiçbir şey yapma
            if (t?.isRunning() ?? true) && !others.contains(where: { $0.isRunning() }) {
                save(kind, target)
                if kind == .bar { applyMenuBar(bar: target) }
                Log.write("\(target) zaten aktif")
                return .alreadyActive
            }

            Log.write("istek: \(kind.rawValue) \(target)")
            // Übersicht ailesi hangi modda çalıştığını kayıttan okuyor: kapatırken eski kayıt,
            // başlatırken yeni kayıt geçerli olmalı
            for m in others { try m.stop() }
            save(kind, target)
            try t?.start()
            if kind == .bar { applyMenuBar(bar: target) }
            return .switched
        }
    }

    /// Görünen ve kurulu modüller arasında sıradakine (Hiçbiri → ilk)
    @discardableResult
    static func next(_ kind: ModuleKind, order: [String]? = nil) throws -> String {
        var list = Registry.modules(kind).filter(\.isInstalled).map(\.id)
        if let order { list = order.filter(list.contains) }
        guard !list.isEmpty else { throw RiceError.failed("kurulu \(kind.title.lowercased()) yok") }
        let cur = activeID(kind)
        let i = list.firstIndex(of: cur).map { ($0 + 1) % list.count } ?? 0
        try switchTo(kind, list[i])
        return list[i]
    }

    static func stopAll() throws {
        try switchTo(.wm, "none")
        try switchTo(.bar, "none")
    }

    /// Login'de: kayıtlı WM ve barı geri yükle
    static func restore() throws {
        let s = RiceState.load()
        Log.write("geri yükleniyor: wm=\(s.wm) bar=\(s.bar)")
        var errors: [String] = []
        do { try switchTo(.wm, s.wm) } catch { errors.append(error.localizedDescription) }
        do { try switchTo(.bar, s.bar) } catch { errors.append(error.localizedDescription) }
        if !errors.isEmpty { throw RiceError.failed(errors.joined(separator: "; ")) }
    }

    // Tek modül işlemleri (sayfadaki Başlat/Durdur/Yeniden başlat). Başlat, "aktif yap"tan farklı olarak
    // diğerlerini kapatmaz — ama WM/bar için kural gereği "aktif yap"a yönlendirilir.
    static func start(_ id: String) throws {
        guard let m = Registry.module(id) else { throw RiceError.unknownModule(id) }
        if m.kind == .extra { return try withLock { try m.start() } }
        try switchTo(m.kind, id)
    }

    static func stop(_ id: String) throws {
        guard let m = Registry.module(id) else { throw RiceError.unknownModule(id) }
        try withLock {
            try m.stop()
            if m.kind != .extra, (m.kind == .wm ? RiceState.load().wm : RiceState.load().bar) == id {
                save(m.kind, "none")
                if m.kind == .bar { applyMenuBar(bar: "none") }
            }
        }
    }

    static func restart(_ id: String) throws {
        guard let m = Registry.module(id) else { throw RiceError.unknownModule(id) }
        guard m.isRunning() else { throw RiceError.failed("\(m.name) çalışmıyor") }
        try withLock {
            Log.write("\(id) yeniden başlatılıyor")
            try m.restart()
        }
    }

    private static func save(_ kind: ModuleKind, _ id: String) {
        var s = RiceState.load()
        if kind == .wm { s.wm = id } else { s.bar = id }
        s.save()
    }

    // MARK: Kilit

    static func withLock<T>(_ body: () throws -> T) throws -> T {
        Paths.ensure()
        let fd = open(Paths.lock.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        // 20 sn'ye kadar bekle (Übersicht kapanışı + açılışı ~6 sn sürebilir)
        let deadline = Date().addingTimeInterval(20)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if Date() > deadline { throw RiceError.busy }
            usleep(100_000)
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    // MARK: macOS menü barı

    private static let hideKey = "_HIHideMenuBar" as CFString

    static var menuBarHidden: Bool? {
        CFPreferencesCopyValue(hideKey, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            .flatMap { ($0 as? NSNumber)?.boolValue }
    }

    private static func setMenuBarHidden(_ value: Bool?) {
        CFPreferencesSetValue(hideKey, value.map { $0 as CFBoolean }, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        // Çıkış/giriş gerekmeden uygulanır
        DistributedNotificationCenter.default().postNotificationName(
            .init("AppleInterfaceMenuBarHidingChangedNotification"), object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Bar seçiliyse otomatik gizle, "Hiçbiri"de göster. İlk dokunuştan önce eski değer yedeklenir.
    static func applyMenuBar(bar: String) {
        guard Settings.current.manageMenuBar else { return }
        let want = bar != "none"
        let cur = menuBarHidden
        if !FileManager.default.fileExists(atPath: Paths.menubarBackup.path) {
            try? (cur.map { $0 ? "1" : "0" } ?? "unset").write(to: Paths.menubarBackup, atomically: true, encoding: .utf8)
        }
        guard cur != want else { return }
        Log.write("menü barı otomatik gizleme: \(want ? "açık" : "kapalı")")
        setMenuBarHidden(want)
    }

    /// Yönetim kapatılınca yedekteki değere dön
    static func restoreMenuBar() {
        guard let v = try? String(contentsOf: Paths.menubarBackup, encoding: .utf8) else { return }
        setMenuBarHidden(v == "unset" ? nil : v == "1")
        try? FileManager.default.removeItem(at: Paths.menubarBackup)
        Log.write("menü barı yedekten geri yüklendi (\(v))")
    }
}
