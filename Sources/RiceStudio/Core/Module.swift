import AppKit
import SwiftUI

enum ModuleKind: String, Codable, CaseIterable {
    case wm, bar, extra

    var title: String {
        switch self {
        case .wm: return "Pencere Yöneticileri"
        case .bar: return "Barlar"
        case .extra: return "Ekstralar"
        }
    }
}

enum ModuleStatus: Equatable {
    case notInstalled, stopped, running

    var label: String {
        switch self {
        case .notInstalled: return "kurulu değil"
        case .stopped: return "kapalı"
        case .running: return "çalışıyor"
        }
    }
}

struct ValidationResult {
    var ok: Bool
    var message: String
    static let valid = ValidationResult(ok: true, message: "")
    static func invalid(_ m: String) -> ValidationResult { ValidationResult(ok: false, message: m) }
}

/// Bir WM, bar ya da ekstra. Yeni bir araç eklemek = bu protokolü uygulayan tek bir dosya
/// (çoğu zaman AppModule / BinaryModule'den türetip birkaç satır) + Registry'ye bir satır.
protocol RiceModule: AnyObject {
    var id: String { get }
    var name: String { get }
    var kind: ModuleKind { get }
    /// Dock rozeti ve kısa gösterim: "A", "SB"…
    var badge: String { get }
    /// SF Symbol
    var symbol: String { get }
    /// Kurulu değilse gösterilecek komut (çalıştırılmaz)
    var installHint: String { get }

    var isInstalled: Bool { get }
    func isRunning() -> Bool

    /// Kendisi zaten açıksa dokunmaz
    func start() throws
    /// Önce normal quit, 3 sn bekle, sonra TERM, sonra KILL
    func stop() throws
    func restart() throws
    /// Çalışırken config'i yeniden yükle (varsayılan: yeniden başlat)
    func reload() throws

    /// Ana config dosyası (ham editörde açılan); klasör tabanlı modüllerde ana dosya
    var configPath: URL? { get }
    /// Yedeğe giren tüm dosyalar/klasörler
    var backupPaths: [URL] { get }
    func readConfig() throws -> String
    func writeConfig(_ text: String) throws
    func validateConfig(_ text: String) -> ValidationResult

    /// Görsel düzenleyici (aşama 3-4'te modül modül doluyor)
    @MainActor var customizationView: AnyView { get }
}

extension RiceModule {
    var status: ModuleStatus { !isInstalled ? .notInstalled : (isRunning() ? .running : .stopped) }

    var backupPaths: [URL] { configPath.map { [$0] } ?? [] }

    func readConfig() throws -> String { try defaultReadConfig() }
    func writeConfig(_ text: String) throws { try defaultWriteConfig(text) }

    func defaultReadConfig() throws -> String {
        guard let url = configPath else { throw RiceError.failed("\(name) için config dosyası yok") }
        do { return try String(contentsOf: url, encoding: .utf8) } catch {
            throw RiceError.failed("\(url.path) okunamadı: \(error.localizedDescription)")
        }
    }

    func defaultWriteConfig(_ text: String) throws {
        guard let url = configPath else { throw RiceError.failed("\(name) için config dosyası yok") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func validateConfig(_ text: String) -> ValidationResult { .valid }

    func restart() throws {
        try stop()
        try start()
    }

    func reload() throws { try restart() }

    @MainActor var customizationView: AnyView { placeholderView }

    @MainActor var placeholderView: AnyView {
        AnyView(Text("Görsel düzenleyici sonraki aşamada").foregroundStyle(.secondary).padding())
    }
}

// Not: AppModule ve BinaryModule bu isteklerin hepsini kendileri tanımlar; alt sınıflar `override` edebilsin diye
// (protokol uzantısındaki varsayılanlar alt sınıfta ezilemez).

let home = FileManager.default.homeDirectoryForCurrentUser
func homeURL(_ path: String) -> URL { home.appendingPathComponent(path) }

/// Normal bir .app (AeroSpace, Barik…)
class AppModule: RiceModule {
    let id: String
    let name: String
    let kind: ModuleKind
    let badge: String
    let symbol: String
    let bundleID: String
    let appPath: String
    let installHint: String
    var configPath: URL? { nil }

    /// Kapanırken normal quit'i bekleme süresi
    var quitWait: TimeInterval { 3 }

    init(id: String, name: String, kind: ModuleKind, badge: String, symbol: String,
         bundleID: String, appPath: String, installHint: String) {
        self.id = id; self.name = name; self.kind = kind; self.badge = badge; self.symbol = symbol
        self.bundleID = bundleID; self.appPath = appPath; self.installHint = installHint
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: appPath) }

    var mainPids: [pid_t] { Shell.pids(pathPrefix: appPath + "/Contents/MacOS/") }

    /// Süreç düzeyinde: Übersicht ailesi isRunning'i moda göre ezer, durdurma yine süreçe bakmalı
    var processAlive: Bool { !mainPids.isEmpty }
    func isRunning() -> Bool { processAlive }

    func start() throws {
        guard isInstalled else { throw RiceError.notInstalled(name) }
        guard !isRunning() else { return }
        Log.write("\(id) başlatılıyor")
        try Shell.openApp(appPath)
        Shell.wait(5) { self.isRunning() }
    }

    func stop() throws {
        guard processAlive else { return }
        Log.write("\(id) kapatılıyor")
        // Normal quit: AeroSpace/hyprmac gizledikleri pencereleri kapanırken geri getirir
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.terminate() }
        if Shell.wait(quitWait, until: { !self.processAlive }) { return afterStop() }
        Log.write("\(id) kapanmadı, TERM")
        Shell.signal(mainPids, SIGTERM)
        if Shell.wait(1, until: { !self.processAlive }) { return afterStop() }
        Log.write("\(id) hâlâ açık, KILL")
        Shell.signal(mainPids, SIGKILL)
        afterStop()
    }

    /// Kapandıktan sonra artakalan yardımcı süreçleri temizlemek için
    func afterStop() {}

    var backupPaths: [URL] { configPath.map { [$0] } ?? [] }
    func readConfig() throws -> String { try defaultReadConfig() }
    func writeConfig(_ text: String) throws { try defaultWriteConfig(text) }
    func validateConfig(_ text: String) -> ValidationResult { .valid }
    func restart() throws { try stop(); try start() }
    func reload() throws { try restart() }
    @MainActor var customizationView: AnyView { placeholderView }
}

/// Tek bir program (SketchyBar, borders): normal kapanış TERM
class BinaryModule: RiceModule {
    let id: String
    let name: String
    let kind: ModuleKind
    let badge: String
    let symbol: String
    let binary: String
    let installHint: String
    var configPath: URL? { nil }
    var arguments: [String] { [] }

    init(id: String, name: String, kind: ModuleKind, badge: String, symbol: String, binary: String, installHint: String) {
        self.id = id; self.name = name; self.kind = kind; self.badge = badge; self.symbol = symbol
        self.binary = binary; self.installHint = installHint
    }

    var processName: String { (binary as NSString).lastPathComponent }
    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: binary) }
    func isRunning() -> Bool { !Shell.pids(named: processName).isEmpty }

    func start() throws {
        guard isInstalled else { throw RiceError.notInstalled(name) }
        guard !isRunning() else { return }
        Log.write("\(id) başlatılıyor")
        try Shell.spawnDetached(binary, arguments)
        Shell.wait(3) { self.isRunning() }
    }

    func stop() throws {
        guard isRunning() else { return }
        Log.write("\(id) kapatılıyor")
        Shell.signal(Shell.pids(named: processName), SIGTERM)
        if Shell.wait(3, until: { !self.isRunning() }) { return }
        Log.write("\(id) kapanmadı, KILL")
        Shell.signal(Shell.pids(named: processName), SIGKILL)
    }

    var backupPaths: [URL] { configPath.map { [$0] } ?? [] }
    func readConfig() throws -> String { try defaultReadConfig() }
    func writeConfig(_ text: String) throws { try defaultWriteConfig(text) }
    func validateConfig(_ text: String) -> ValidationResult { .valid }
    func restart() throws { try stop(); try start() }
    func reload() throws { try restart() }
    @MainActor var customizationView: AnyView { placeholderView }
}
