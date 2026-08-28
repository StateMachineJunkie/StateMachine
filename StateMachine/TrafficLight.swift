import Foundation
import Synchronization
import SwiftFSM

// MARK: - Domain type shared by both traffic light variants

enum LightColor: Hashable, CustomStringConvertible, CaseIterable {
    case red, yellow, green
    var description: String {
        switch self {
        case .red: "red"
        case .yellow: "yellow"
        case .green: "green"
        }
    }
}

/// The public surface both traffic light variants expose, so the app's view
/// model can hold either one behind a single existential and switch between
/// them at runtime without caring which `post` semantics is underneath.
protocol TrafficLightControlling: Actor {
    var current: LightColor { get async }
    func red() async
    func yellow() async
    func green() async
    func setMaintenanceMode(_ on: Bool) async
    func setAutomaticMode(_ on: Bool) async
    func setAutomaticTiming(red: Duration, green: Duration) async
}

/// A plain, non-actor box for the one piece of mutable state a transition
/// guard needs to read live.
///
/// Guard closures must be built *before* the owning actor exists (see below),
/// so they cannot capture `self`. Capturing this box instead gives the same
/// "live read at dispatch time" behavior described for guards generally:
/// the box is only ever touched from inside the owning actor's isolated
/// methods once construction finishes, so it stays exactly as safe as the
/// `FSMCore` it sits next to — safe by being exclusively owned, not by the
/// type system.
private final class MaintenanceFlag {
    var isOn = false
}

/// Whether the light currently advances itself on a timer, and how long it
/// dwells in `red`/`green` when it does (`yellow`'s dwell time is fixed by
/// its existing 3-second countdown). Read live by the do-activities in
/// `buildTrafficLightCore`, below — including from *inside* their `Task`
/// bodies, not just from a synchronous guard closure. Swift's concurrency
/// checking treats that as genuinely concurrent access, so this box has to
/// actually *be* `Sendable`, not just behave safely by single-actor
/// discipline the way `MaintenanceFlag` does. `Mutex` (from the
/// `Synchronization` module) gives that as a *checked* conformance — the
/// compiler verifies safety through `Mutex`'s own guarantees, rather than
/// this type asserting it with `@unchecked Sendable`.
final class AutomaticMode: Sendable {
    private struct State {
        var isOn = false
        var redDuration: Duration = .seconds(4)
        var greenDuration: Duration = .seconds(4)
    }
    private let lock = Mutex(State())

    var isOn: Bool {
        get { lock.withLock { $0.isOn } }
        set { lock.withLock { $0.isOn = newValue } }
    }
    var redDuration: Duration {
        get { lock.withLock { $0.redDuration } }
        set { lock.withLock { $0.redDuration = newValue } }
    }
    var greenDuration: Duration {
        get { lock.withLock { $0.greenDuration } }
        set { lock.withLock { $0.greenDuration = newValue } }
    }
}

/// How a do-activity's timer gets a new event back into the actor that owns
/// it, once the timer fires.
///
/// This has to be a two-step affair. Building the transition table (below)
/// happens *before* the owning actor exists — a synchronous actor
/// initializer can't call its own isolated methods, and an *escaping*
/// closure formed inside it can't capture `self` either, because the
/// actor's isolation domain isn't "live" until construction finishes. So
/// the table is built referencing this plain, `Sendable` box instead of
/// `self`, and the box starts out with no handler connected. Once — and
/// only once — `init` reaches its *last* statement (after every other
/// stored property has already been read), a handler that *does* capture
/// `self` gets connected. Splitting it this way, in this order, matters:
/// reading other actor-isolated properties (`core`, `maintenance`,
/// `automatic`) is fine before a self-capturing closure is formed in `init`,
/// but not after — so the self-capturing `connect` call has to come last.
final class EventSink: Sendable {
    private let handler = Mutex<(@Sendable (LightColor) -> Void)?>(nil)

    func post(_ event: LightColor) {
        if let handler = handler.withLock({ $0 }) { handler(event) }
    }

    func connect(_ handler: @escaping @Sendable (LightColor) -> Void) {
        self.handler.withLock { $0 = handler }
    }
}

/// Shared table-wiring: both variants use an identical transition table and
/// per-state behavior, differing only in how `post` is implemented (see
/// `TrafficLightQueued` and `TrafficLightMailbox` below).
private func buildTrafficLightCore(
    maintenance: MaintenanceFlag,
    automatic: AutomaticMode,
    sink: EventSink,
    logger: @escaping @Sendable (String) -> Void
) -> FSMCore<LightColor, LightColor> {
    let core = FSMCore<LightColor, LightColor>(initialState: .red)

    core.addTransition(
        from: .red, on: .green,
        Transition(to: .green, guard: !maintenance.isOn, action: logger("red -> green"))
    )
    core.addTransition(
        from: .green, on: .yellow,
        Transition(to: .yellow, action: logger("green -> yellow"))
    )
    core.addTransition(
        from: .yellow, on: .red,
        Transition(to: .red, action: logger("yellow -> red"))
    )
    // Note: there is no `.red` entry under `.green` — that's the whole
    // enforcement mechanism. Calling red() while green just misses.

    // Internal transition: red() while already red. No `to:` argument,
    // so no exit/enter, no state change — just the action.
    core.addTransition(
        from: .red, on: .red,
        Transition(action: logger("red() ignored as a transition, logged at \(Date())"))
    )

    // Automatic-mode do-activities. `automatic.isOn` is read once, live, at
    // the moment each state is entered — turning automatic mode on while
    // already sitting in a state doesn't retroactively arm a timer for the
    // dwell already in progress; it takes effect from the next state
    // entered onward. See the design document for why this was the chosen
    // tradeoff.
    core.setBehavior(for: .red, StateBehavior(
        doWork: automatic.isOn ? Task {
            try? await Task.sleep(for: automatic.redDuration)
            guard !Task.isCancelled else { return }
            sink.post(.green)
        } : nil
    ))

    core.setBehavior(for: .green, StateBehavior(
        doWork: automatic.isOn ? Task {
            try? await Task.sleep(for: automatic.greenDuration)
            guard !Task.isCancelled else { return }
            sink.post(.yellow)
        } : nil
    ))

    core.setBehavior(for: .yellow, StateBehavior(
        onEnter: logger("entering YELLOW"),
        onExit: logger("leaving YELLOW"),
        doWork: Task {
            for secondsLeft in stride(from: 3, through: 1, by: -1) {
                if Task.isCancelled { return }
                logger("  yellow countdown: \(secondsLeft)")
                try? await Task.sleep(for: .seconds(1))
            }
            // Read live, at the end of the countdown, not at task creation —
            // so a mode flip mid-countdown still takes effect.
            if automatic.isOn { sink.post(.red) }
        }
    ))

    return core
}

// MARK: - Variant 1: explicit queue, exact C `postEvent` semantics
//
// `post` appends to an array and only the outermost call drains it,
// run-to-completion, before returning — identical to the original.
// `send` is the direct, non-queued dispatch, for use by code that is
// already executing inside the actor (e.g. cascading from an action).

actor TrafficLightQueued: TrafficLightControlling {
    private let core: FSMCore<LightColor, LightColor>
    private let maintenance = MaintenanceFlag()
    private let automatic = AutomaticMode()
    private let sink = EventSink()
    private var eventQueue: [LightColor] = []
    private var isDraining = false

    init(logger: @escaping @Sendable (String) -> Void = { print($0) }) {
        core = buildTrafficLightCore(maintenance: maintenance, automatic: automatic, sink: sink, logger: logger)
        core.start()
        // Must be the last statement in init — see `EventSink`.
        sink.connect { [weak self] event in
            Task { await self?.post(event) }
        }
    }

    // Internal only — matches the original sendEvent. Never exposed publicly;
    // callers should have no idea the FSM exists.
    private func send(_ event: LightColor) {
        core.fire(event)
    }

    // Internal only — matches the original postEvent exactly.
    private func post(_ event: LightColor) {
        eventQueue.append(event)
        guard !isDraining else { return }   // reentrant post just enqueues
        isDraining = true
        while !eventQueue.isEmpty {
            send(eventQueue.removeFirst())
        }
        isDraining = false
    }

    // MARK: Public domain API

    func red() { post(.red) }
    func yellow() { post(.yellow) }
    func green() { post(.green) }

    func setMaintenanceMode(_ on: Bool) { maintenance.isOn = on }

    func setAutomaticMode(_ on: Bool) { automatic.isOn = on }
    func setAutomaticTiming(red: Duration, green: Duration) {
        automatic.redDuration = red
        automatic.greenDuration = green
    }

    var current: LightColor { core.currentState }
}

// MARK: - Variant 2: default actor mailbox behavior
//
// No explicit queue. `post` just calls `send` directly; the actor runtime's
// own mailbox is what serializes concurrent external callers, playing the
// role your eventQueue + drain loop used to play.
//
// For this example the two variants behave identically, because every
// action here is synchronous. They diverge only when:
//   (a) an action needs to `await` mid-transition (Variant 1 still finishes
//       today's whole cascade before yielding to the next external caller
//       only up to the point where *something* awaits — past that, both
//       variants can interleave; Variant 1 just gives you an explicit,
//       inspectable, boundable queue up to that point), or
//   (b) you want to inspect/bound/log the pending event backlog, which
//       Variant 2 can't do — the actor's mailbox isn't introspectable.
//
// See the design document, §6, for a concretely verified example of (a):
// a reentrant post from within an action sees a stale, soon-to-be-clobbered
// state in this variant but not in Variant 1.

actor TrafficLightMailbox: TrafficLightControlling {
    private let core: FSMCore<LightColor, LightColor>
    private let maintenance = MaintenanceFlag()
    private let automatic = AutomaticMode()
    private let sink = EventSink()

    init(logger: @escaping @Sendable (String) -> Void = { print($0) }) {
        core = buildTrafficLightCore(maintenance: maintenance, automatic: automatic, sink: sink, logger: logger)
        core.start()
        // Must be the last statement in init — see `EventSink`.
        sink.connect { [weak self] event in
            Task { await self?.post(event) }
        }
    }

    private func send(_ event: LightColor) {
        core.fire(event)
    }

    private func post(_ event: LightColor) {
        send(event)   // the mailbox itself is the queue
    }

    func red() { post(.red) }
    func yellow() { post(.yellow) }
    func green() { post(.green) }

    func setMaintenanceMode(_ on: Bool) { maintenance.isOn = on }

    func setAutomaticMode(_ on: Bool) { automatic.isOn = on }
    func setAutomaticTiming(red: Duration, green: Duration) {
        automatic.redDuration = red
        automatic.greenDuration = green
    }

    var current: LightColor { core.currentState }
}
