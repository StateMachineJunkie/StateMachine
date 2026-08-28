/// Per-state behavior: entry action, exit action, and an optional long-running
/// "do" activity that lives only as long as the FSM remains in this state.
///
/// `doWork` is a factory, not a task: it's re-invoked (and a fresh Task
/// created) every time the state is entered, and whatever it returns is
/// cancelled the moment the state is exited.
public struct StateBehavior {
    let onEnter: () -> Void
    let onExit: () -> Void
    let doWork: () -> Task<Void, Never>?

    public init(
        onEnter: @autoclosure @escaping () -> Void = (),
        onExit: @autoclosure @escaping () -> Void = (),
        doWork: @autoclosure @escaping () -> Task<Void, Never>? = nil
    ) {
        self.onEnter = onEnter
        self.onExit = onExit
        self.doWork = doWork
    }
}
