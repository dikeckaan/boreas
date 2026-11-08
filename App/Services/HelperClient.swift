import BoreasCore
import Foundation
import os

private let log = Logger(subsystem: "com.kaandikec.boreas", category: "xpc")

enum HelperClientError: LocalizedError {
    case timedOut
    case badReply
    case helper(String)

    var errorDescription: String? {
        switch self {
        case .timedOut: String(localized: "The helper did not answer in time.")
        case .badReply: String(localized: "The helper sent an unreadable reply.")
        // The helper's own message is English and technical; it is logged by the caller.
        case .helper: String(localized: "The helper did not accept the settings.")
        }
    }
}

/// XPC client for BoreasHelper.
///
/// - The connection is created lazily. On interruption or invalidation it is dropped, and the
///   next call opens a new one; `connectionGeneration()` changes then, which tells `AppModel` to
///   send the configuration again (the helper may have idle-exited and lost it).
/// - Every call gives up after `timeout`; a timeout also drops the connection.
/// - Replies arrive on XPC queues and resume a continuation, so callers never block.
final class HelperClient: @unchecked Sendable {
    static let timeout: TimeInterval = 2

    private let lock = NSLock()
    // Guarded by `lock`.
    private var connection: NSXPCConnection?
    private var generation: UInt64 = 0

    /// Opens a connection if there is none and returns its generation.
    func connectionGeneration() -> UInt64 {
        lock.withLock {
            _ = currentConnectionLocked()
            return generation
        }
    }

    func snapshot() async throws -> HelperSnapshot {
        try await call { helper, done in
            helper.snapshot { data in
                guard let data, let s = try? JSONDecoder().decode(HelperSnapshot.self, from: data) else {
                    done(.failure(HelperClientError.badReply))
                    return
                }
                done(.success(s))
            }
        }
    }

    func apply(_ c: HelperConfiguration) async throws {
        let data = try JSONEncoder().encode(c)
        try await call { (helper, done: @escaping @Sendable (Result<Void, Error>) -> Void) in
            helper.apply(configuration: data) { error in
                done(error.map { .failure(HelperClientError.helper($0)) } ?? .success(()))
            }
        }
    }

    func resetAllToAuto() async throws {
        try await call { (helper, done: @escaping @Sendable (Result<Void, Error>) -> Void) in
            helper.resetAllToAuto { done(.success(())) }
        }
    }

    func version() async throws -> String {
        try await call { helper, done in
            helper.version { done(.success($0)) }
        }
    }

    /// Closes the connection; the next call opens a new one.
    func invalidate() {
        let c = lock.withLock { () -> NSXPCConnection? in
            defer { connection = nil }
            return connection
        }
        c?.invalidate()
    }

    // MARK: - Internals

    /// Caller holds `lock`.
    private func currentConnectionLocked() -> NSXPCConnection {
        if let connection { return connection }
        generation &+= 1
        let gen = generation
        let c = NSXPCConnection(machServiceName: boreasHelperMachServiceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: BoreasHelperXPC.self)
        c.interruptionHandler = { [weak self] in
            log.info("helper connection interrupted")
            self?.drop(generation: gen)
        }
        c.invalidationHandler = { [weak self] in
            log.info("helper connection invalidated")
            self?.drop(generation: gen)
        }
        c.resume()
        connection = c
        return c
    }

    /// Drops the connection if it is still the one of generation `gen`.
    private func drop(generation gen: UInt64) {
        let c = lock.withLock { () -> NSXPCConnection? in
            guard gen == generation, let c = connection else { return nil }
            connection = nil
            return c
        }
        c?.invalidate()
    }

    private func call<T: Sendable>(
        _ body: (BoreasHelperXPC, @escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let (conn, gen) = lock.withLock { (currentConnectionLocked(), generation) }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let once = ResumeOnce(cont)
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                once.resume(.failure(error))
            }
            guard let helper = proxy as? BoreasHelperXPC else {
                once.resume(.failure(HelperClientError.badReply))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
                if once.resume(.failure(HelperClientError.timedOut)) {
                    log.error("helper call timed out")
                    self?.drop(generation: gen)
                }
            }
            body(helper) { once.resume($0) }
        }
    }
}

/// Resumes a continuation at most once (reply, error handler and timeout race).
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ c: CheckedContinuation<T, Error>) { continuation = c }

    /// Returns false if the continuation had already been resumed.
    @discardableResult
    func resume(_ result: Result<T, Error>) -> Bool {
        let c = lock.withLock { () -> CheckedContinuation<T, Error>? in
            defer { continuation = nil }
            return continuation
        }
        c?.resume(with: result)
        return c != nil
    }
}
