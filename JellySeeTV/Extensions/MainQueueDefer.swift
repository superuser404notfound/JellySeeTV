import Foundation

/// Run `work` on the next main-queue turn, optionally after a small
/// delay. Use this — not `Task.sleep` — for any `@FocusState` write
/// that has to land *after* the SwiftUI tick currently committing
/// the focus engine, and for the scroll calls that need to chase a
/// just-written focus target.
///
/// Background: `Task.sleep` resumes on a cooperative thread and the
/// follow-up MainActor hop occasionally lands inside the same focus
/// commit it was meant to dodge — particularly on tvOS when the
/// remote's button press already drives one focus update. The
/// `DispatchQueue.main.asyncAfter` path always lands on a fresh
/// main-queue turn after the deadline, which is exactly the
/// "tomorrow's runloop" semantics the focus engine needs.
///
/// Default `delay` of 0.05 s is the smallest interval that's been
/// reliable on the focus-write call sites. Callers that need a
/// different value (e.g. waiting on a 0.2 s scroll animation
/// before the focus write lands) pass their own number.
@inlinable
func deferOnMain(by delay: TimeInterval = 0.05, _ work: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
}
