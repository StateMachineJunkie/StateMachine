/// The table + current-state bookkeeping + dispatch logic for a flat
/// (non-hierarchical) statechart: guards, entry/exit actions, a `do`-activity,
/// and internal-vs-external transitions.
///
/// `FSMCore` is a plain, non-actor, non-`Sendable` class. It holds no
/// concurrency semantics of its own — it is deliberately dumb and
/// synchronous. It is **not** thread-safe on its own: it relies entirely on
/// being owned and exclusively touched by a single actor (or otherwise
/// confined to one isolation domain), which the owning actor guarantees by
/// keeping its `FSMCore` instance private and never letting it escape.
public final class FSMCore<State: Hashable, Event: Hashable> {
    public private(set) var currentState: State
    private var table: [State: [Event: [Transition<State>]]] = [:]
    private var behaviors: [State: StateBehavior] = [:]
    private var activeDoTask: Task<Void, Never>?

    public init(initialState: State) {
        currentState = initialState
    }

    public func addTransition(from state: State, on event: Event, _ transition: Transition<State>) {
        table[state, default: [:]][event, default: []].append(transition)
    }

    public func setBehavior(for state: State, _ behavior: StateBehavior) {
        behaviors[state] = behavior
    }

    /// Runs entry action / spawns do-activity for the initial state.
    /// Call once, after the table is fully wired.
    public func start() {
        if let enter = behaviors[currentState]?.onEnter { enter() }
        activeDoTask = behaviors[currentState]?.doWork()
    }

    /// Immediate, synchronous transition attempt. Mirrors the original C
    /// `sendEvent`: index the table, and if there's no matching entry or no
    /// guard passes, silently do nothing — this is what makes an illegal
    /// transition unrepresentable rather than merely "discouraged."
    @discardableResult
    public func fire(_ event: Event) -> Bool {
        guard let candidates = table[currentState]?[event],
              let transition = candidates.first(where: { $0.guardCondition() })
        else { return false }

        guard let target = transition.target else {
            // Internal transition: run the action, touch nothing else.
            // The do-activity, if any, keeps running exactly as it was.
            transition.action()
            return true
        }

        activeDoTask?.cancel()
        activeDoTask = nil
        if let exit = behaviors[currentState]?.onExit { exit() }

        transition.action()
        currentState = target

        if let enter = behaviors[currentState]?.onEnter { enter() }
        activeDoTask = behaviors[currentState]?.doWork()

        return true
    }
}
