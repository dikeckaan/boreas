import Foundation

/// Client bookkeeping for one XPC connection. A connection counts as a client only once its
/// first message reaches the exported object, which happens only after the code-signing
/// requirement has passed. An accepted connection that stays silent therefore cannot hold off the
/// disconnect reset.
///
/// **Threading:** like `HelperRuntime`, use it only on the runtime's serial queue.
public final class ConnectionTracker: @unchecked Sendable {
    private let runtime: HelperRuntime
    private var counted = false
    private var ended = false

    public init(runtime: HelperRuntime) {
        self.runtime = runtime
    }

    /// Call on every incoming message; counts the client on the first one.
    public func messageReceived() {
        guard !counted, !ended else { return }
        counted = true
        runtime.clientConnected()
    }

    /// Call from the invalidation and interruption handlers. Only the first call has an effect,
    /// and it un-counts the client only if it was counted.
    public func connectionEnded() {
        guard !ended else { return }
        ended = true
        if counted { runtime.clientDisconnected() }
    }
}
