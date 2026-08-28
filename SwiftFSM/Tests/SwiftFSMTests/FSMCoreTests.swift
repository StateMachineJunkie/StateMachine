import Testing
@testable import SwiftFSM

enum Light: Hashable {
    case red, yellow, green
}

@Suite("FSMCore")
struct FSMCoreTests {

    @Test("Legal transition changes state and fires enter/exit/action")
    func legalTransition() {
        var log: [String] = []
        let core = FSMCore<Light, Light>(initialState: .red)
        core.setBehavior(for: .red, StateBehavior(onExit: log.append("exit red")))
        core.setBehavior(for: .green, StateBehavior(onEnter: log.append("enter green")))
        core.addTransition(from: .red, on: .green, Transition(to: .green, action: log.append("action")))
        core.start()

        let fired = core.fire(.green)

        #expect(fired)
        #expect(core.currentState == .green)
        #expect(log == ["exit red", "action", "enter green"])
    }

    @Test("Missing table entry is a silent no-op")
    func illegalTransitionIsNoOp() {
        let core = FSMCore<Light, Light>(initialState: .green)
        core.addTransition(from: .red, on: .green, Transition(to: .green))
        core.start()

        let fired = core.fire(.red)

        #expect(!fired)
        #expect(core.currentState == .green)
    }

    @Test("First passing guard wins among multiple candidates")
    func guardSelectsCandidate() {
        var chosen = ""
        let core = FSMCore<Light, Light>(initialState: .red)
        core.addTransition(from: .red, on: .green, Transition(to: .yellow, guard: false, action: chosen = "wrong"))
        core.addTransition(from: .red, on: .green, Transition(to: .green, guard: true, action: chosen = "right"))
        core.start()

        core.fire(.green)

        #expect(core.currentState == .green)
        #expect(chosen == "right")
    }

    @Test("Internal transition runs its action without exit/enter or state change")
    func internalTransitionDoesNotChangeState() {
        var log: [String] = []
        let core = FSMCore<Light, Light>(initialState: .red)
        core.setBehavior(for: .red, StateBehavior(
            onEnter: log.append("enter red"),
            onExit: log.append("exit red")
        ))
        core.addTransition(from: .red, on: .red, Transition(action: log.append("internal action")))
        core.start()
        log.removeAll()

        let fired = core.fire(.red)

        #expect(fired)
        #expect(core.currentState == .red)
        #expect(log == ["internal action"])
    }

    @Test("External self-transition re-runs exit and entry")
    func externalSelfTransitionRerunsEntryExit() {
        var log: [String] = []
        let core = FSMCore<Light, Light>(initialState: .red)
        core.setBehavior(for: .red, StateBehavior(
            onEnter: log.append("enter red"),
            onExit: log.append("exit red")
        ))
        core.addTransition(from: .red, on: .red, Transition(to: .red, action: log.append("action")))
        core.start()
        log.removeAll()

        core.fire(.red)

        #expect(core.currentState == .red)
        #expect(log == ["exit red", "action", "enter red"])
    }

    @Test("Do-activity is cancelled on exit and restarted fresh on re-entry")
    func doActivityLifecycle() async {
        let core = FSMCore<Light, Light>(initialState: .red)
        let started = Counter()
        let cancelled = Counter()
        core.setBehavior(for: .red, StateBehavior(doWork: Task {
            await started.increment()
            defer { Task { await cancelled.increment() } }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }))
        core.addTransition(from: .red, on: .green, Transition(to: .green))
        core.addTransition(from: .green, on: .red, Transition(to: .red))
        core.start()

        // Let the do-activity actually start running.
        while await started.value == 0 { await Task.yield() }

        core.fire(.green)
        while await cancelled.value == 0 { await Task.yield() }
        #expect(await started.value == 1)

        core.fire(.red)
        while await started.value < 2 { await Task.yield() }
        #expect(await started.value == 2)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
