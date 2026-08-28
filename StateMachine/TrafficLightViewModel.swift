import Observation

/// Which `post` semantics is currently driving the light — see
/// `TrafficLightQueued` vs `TrafficLightMailbox` for what actually differs.
enum FSMVariant: String, CaseIterable, Identifiable {
    case queued = "Explicit Queue"
    case mailbox = "Actor Mailbox"
    var id: Self { self }
}

/// Drives whichever `TrafficLightControlling` actor is currently selected,
/// republishing its state on the main actor so SwiftUI can observe it.
/// Switching `variant` tears down the old actor and spins up a fresh one in
/// its initial (`red`) state.
///
/// When automatic mode is on, the light advances itself; the UI still finds
/// out via the same path as a manual tap — every transition, automatic or
/// not, runs through the actor's shared `logger`, which is what drives
/// `appendLog` → `refreshCurrent` here. No polling needed.
@MainActor
@Observable
final class TrafficLightViewModel {
    private(set) var current: LightColor = .red
    private(set) var maintenanceMode = false
    private(set) var automaticMode = false
    private(set) var eventLog: [String] = []

    var variant: FSMVariant {
        didSet {
            guard variant != oldValue else { return }
            makeLight()
        }
    }

    private var light: any TrafficLightControlling

    init(variant: FSMVariant = .mailbox) {
        self.variant = variant
        // Placeholder so all stored properties are set before `self` can be
        // captured below; replaced immediately by `makeLight()`.
        self.light = TrafficLightMailbox(logger: { _ in })
        makeLight()
    }

    private func makeLight() {
        let newLight = Self.makeLight(for: variant) { [weak self] message in
            Task { @MainActor in
                self?.appendLog(message)
            }
        }
        light = newLight
        eventLog.removeAll()
        let maintenanceMode = self.maintenanceMode
        let automaticMode = self.automaticMode
        Task {
            await newLight.setMaintenanceMode(maintenanceMode)
            await newLight.setAutomaticMode(automaticMode)
            await refreshCurrent()
        }
    }

    private static func makeLight(
        for variant: FSMVariant,
        logger: @escaping @Sendable (String) -> Void
    ) -> any TrafficLightControlling {
        switch variant {
        case .queued: TrafficLightQueued(logger: logger)
        case .mailbox: TrafficLightMailbox(logger: logger)
        }
    }

    private func appendLog(_ message: String) {
        eventLog.append(message)
        if eventLog.count > 200 { eventLog.removeFirst(eventLog.count - 200) }
        Task { await refreshCurrent() }
    }

    private func refreshCurrent() async {
        current = await light.current
    }

    func fire(_ event: LightColor) {
        let light = self.light
        Task {
            switch event {
            case .red: await light.red()
            case .yellow: await light.yellow()
            case .green: await light.green()
            }
            await refreshCurrent()
        }
    }

    func setMaintenanceMode(_ on: Bool) {
        maintenanceMode = on
        let light = self.light
        Task { await light.setMaintenanceMode(on) }
    }

    func setAutomaticMode(_ on: Bool) {
        automaticMode = on
        let light = self.light
        Task { await light.setAutomaticMode(on) }
    }
}
