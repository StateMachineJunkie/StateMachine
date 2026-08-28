/// A single candidate transition out of a (state, event) pair.
/// If several transitions share an event, the first whose guard passes wins
/// — this is what lets you express Harel-style guarded branches on one event.
///
/// `target == nil` makes this an *internal transition*: the event is handled
/// in place — the action fires, but there is no exit, no entry, no state
/// change, and any running `do`-activity is left completely undisturbed.
/// `target == currentState` (non-nil) is an *external self-transition*:
/// exit, action, entry, and do-activity restart all still happen, just
/// landing back in the same state — use this when you deliberately want the
/// reset behavior; use `target: nil` when you don't.
public struct Transition<State> {
    let target: State?
    let guardCondition: () -> Bool
    let action: () -> Void

    public init(
        to target: State? = nil,
        guard guardCondition: @autoclosure @escaping () -> Bool = true,
        action: @autoclosure @escaping () -> Void = ()
    ) {
        self.target = target
        self.guardCondition = guardCondition
        self.action = action
    }
}
