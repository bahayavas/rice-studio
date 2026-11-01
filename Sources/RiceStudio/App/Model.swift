import AppKit
import SwiftUI

/// Arayüzün durumu. Engine çağrıları bloklayıcı (quit bekleme vb.), arka plan kuyruğunda çalışır.
@MainActor
final class AppModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let kind: ModuleKind
        let badge: String
        let symbol: String
        let status: ModuleStatus
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var activeWM = "none"
    @Published private(set) var activeBar = "none"
    /// İşlem sürerken modül id'si (ya da "wm:none" gibi)
    @Published private(set) var busy: String?
    @Published var error: String?

    private let queue = DispatchQueue(label: "rice.engine")
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.busy == nil { self?.refresh() } }
        }
    }

    func rows(_ kind: ModuleKind) -> [Row] { rows.filter { $0.kind == kind } }

    func refresh() {
        queue.async {
            let rows = Registry.all.map {
                Row(id: $0.id, name: $0.name, kind: $0.kind, badge: $0.badge, symbol: $0.symbol, status: $0.status)
            }
            let wm = Engine.activeID(.wm), bar = Engine.activeID(.bar)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if self.rows != rows { self.rows = rows }
                    self.activeWM = wm
                    self.activeBar = bar
                    self.updateBadge()
                }
            }
        }
    }

    /// Dock rozeti: "A·SB"
    func updateBadge() {
        let parts = [activeWM, activeBar].compactMap { id in Registry.module(id)?.badge }
        NSApp.dockTile.badgeLabel = parts.isEmpty ? nil : parts.joined(separator: "·")
    }

    func perform(_ label: String, _ action: @escaping () throws -> Void) {
        guard busy == nil else { return }
        busy = label
        error = nil
        queue.async {
            var err: String?
            do { try action() } catch { err = error.localizedDescription }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.busy = nil
                    self.error = err
                    self.refresh()
                }
            }
        }
    }

    func activate(_ kind: ModuleKind, _ id: String) {
        perform(id == "none" ? "\(kind.rawValue):none" : id) { try Engine.switchTo(kind, id) }
    }
}
