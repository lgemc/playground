import Foundation

/// A Result type similar to TypeScript's neverthrow
/// Represents either a success (Ok) or failure (Err)
enum Result<T, E: Error> {
    case ok(T)
    case err(E)

    // MARK: - Inspection

    /// Check if this is an error result
    var isErr: Bool {
        switch self {
        case .err:
            return true
        case .ok:
            return false
        }
    }

    /// Check if this is a success result
    var isOk: Bool {
        return !isErr
    }

    // MARK: - Unwrapping

    /// Unwrap the success value, crash if error
    /// WARNING: Use only when you're certain the result is Ok
    func unwrap() -> T {
        switch self {
        case .ok(let value):
            return value
        case .err(let error):
            fatalError("Called unwrap() on an Err result: \(error)")
        }
    }

    /// Unwrap the error value, crash if success
    /// WARNING: Use only when you're certain the result is Err
    func unwrapErr() -> E {
        switch self {
        case .ok(let value):
            fatalError("Called unwrapErr() on an Ok result: \(value)")
        case .err(let error):
            return error
        }
    }

    /// Safely get the value if Ok, nil otherwise
    var value: T? {
        switch self {
        case .ok(let value):
            return value
        case .err:
            return nil
        }
    }

    /// Safely get the error if Err, nil otherwise
    var error: E? {
        switch self {
        case .ok:
            return nil
        case .err(let error):
            return error
        }
    }

    // MARK: - Transformations

    /// Map the success value to another type
    func map<U>(_ transform: (T) -> U) -> Result<U, E> {
        switch self {
        case .ok(let value):
            return .ok(transform(value))
        case .err(let error):
            return .err(error)
        }
    }

    /// Map the error to another error type
    func mapErr<F: Error>(_ transform: (E) -> F) -> Result<T, F> {
        switch self {
        case .ok(let value):
            return .ok(value)
        case .err(let error):
            return .err(transform(error))
        }
    }

    /// Flat map for chaining operations that return Results
    func flatMap<U>(_ transform: (T) -> Result<U, E>) -> Result<U, E> {
        switch self {
        case .ok(let value):
            return transform(value)
        case .err(let error):
            return .err(error)
        }
    }

    // MARK: - Pattern Matching Helpers

    /// Execute a closure if the result is Ok
    @discardableResult
    func onOk(_ closure: (T) -> Void) -> Self {
        if case .ok(let value) = self {
            closure(value)
        }
        return self
    }

    /// Execute a closure if the result is Err
    @discardableResult
    func onErr(_ closure: (E) -> Void) -> Self {
        if case .err(let error) = self {
            closure(error)
        }
        return self
    }

    /// Match both cases with closures
    func match<U>(onOk: (T) -> U, onErr: (E) -> U) -> U {
        switch self {
        case .ok(let value):
            return onOk(value)
        case .err(let error):
            return onErr(error)
        }
    }

    // MARK: - Default Values

    /// Get the value or a default if Err
    func valueOr(_ defaultValue: T) -> T {
        switch self {
        case .ok(let value):
            return value
        case .err:
            return defaultValue
        }
    }

    /// Get the value or compute a default if Err
    func valueOrElse(_ compute: (E) -> T) -> T {
        switch self {
        case .ok(let value):
            return value
        case .err(let error):
            return compute(error)
        }
    }
}

// MARK: - Convenience Constructors
// Note: Swift automatically provides static constructors for enum cases
// so Result.ok(value) and Result.err(error) already work without explicit definitions

// MARK: - Converting from throwing functions

extension Result {
    /// Catch a throwing function and convert to Result
    init(catching body: () throws -> T) where E == Error {
        do {
            self = .ok(try body())
        } catch {
            self = .err(error)
        }
    }

    /// Catch an async throwing function and convert to Result
    static func catching(async body: () async throws -> T) async -> Result<T, E> where E == Error {
        do {
            return .ok(try await body())
        } catch {
            return .err(error)
        }
    }
}

// MARK: - Converting to throwing functions

extension Result where E == Error {
    /// Convert Result to throwing function
    func get() throws -> T {
        switch self {
        case .ok(let value):
            return value
        case .err(let error):
            throw error
        }
    }
}

// MARK: - Equatable conformance

extension Result: Equatable where T: Equatable, E: Equatable {
    static func == (lhs: Result<T, E>, rhs: Result<T, E>) -> Bool {
        switch (lhs, rhs) {
        case (.ok(let lValue), .ok(let rValue)):
            return lValue == rValue
        case (.err(let lError), .err(let rError)):
            return lError == rError
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension Result: CustomStringConvertible {
    var description: String {
        switch self {
        case .ok(let value):
            return "Ok(\(value))"
        case .err(let error):
            return "Err(\(error))"
        }
    }
}

// MARK: - Collection Helpers

extension Array {
    /// Combine an array of Results into a Result of array
    /// Returns Err if any element is Err, otherwise Ok with all values
    func combineResults<T, E>() -> Result<[T], E> where Element == Result<T, E> {
        var values: [T] = []
        for result in self {
            switch result {
            case .ok(let value):
                values.append(value)
            case .err(let error):
                return .err(error)
            }
        }
        return .ok(values)
    }
}

// MARK: - Optional Integration

extension Result {
    /// Convert Result to Optional, discarding error
    func toOptional() -> T? {
        return value
    }
}

extension Optional {
    /// Convert Optional to Result with custom error
    func toResult<E: Error>(error: E) -> Result<Wrapped, E> {
        switch self {
        case .some(let value):
            return .ok(value)
        case .none:
            return .err(error)
        }
    }
}
