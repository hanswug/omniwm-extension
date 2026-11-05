/// Reconnect delays for the OmniWM subscription: 1 → 2 → 5 → 10 s, capped; reset on success (PDR §6.7).
public struct Backoff: Sendable, Equatable {
    public static let steps: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10)]
    private var index = 0

    public init() {}

    /// The delay before the next attempt; advances towards the cap.
    public mutating func next() -> Duration {
        let delay = Self.steps[min(index, Self.steps.count - 1)]
        index += 1
        return delay
    }

    public mutating func reset() { index = 0 }
}
