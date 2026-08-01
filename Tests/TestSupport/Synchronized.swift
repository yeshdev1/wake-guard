import Synchronization

/// A tiny `Mutex`-backed box for thread-safe, `Sendable` mutable state in test
/// doubles, so the fakes stay free of locking boilerplate and compile cleanly
/// under Swift 6 strict concurrency.
final class Synchronized<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    func get() -> Value {
        mutex.withLock { $0 }
    }

    @discardableResult
    func mutate<Result>(_ body: (inout sending Value) -> sending Result) -> sending Result {
        mutex.withLock(body)
    }
}
