public struct NoError: Error {
    public init() {
    }
}

public final class Disposable {
    public init() {
    }
}

public final class Signal<Value, ErrorType> {
    private let generator: (@escaping (Value) -> Void) -> Void

    public init(_ generator: @escaping (@escaping (Value) -> Void) -> Void) {
        self.generator = generator
    }

    public static func single(_ value: Value) -> Signal<Value, ErrorType> {
        return Signal<Value, ErrorType> { subscriber in
            subscriber(value)
        }
    }

    @discardableResult
    public func start(next: @escaping (Value) -> Void) -> Disposable {
        self.generator(next)
        return Disposable()
    }
}

infix operator |> : AdditionPrecedence

public func |> <Value, ErrorType, Result>(lhs: Signal<Value, ErrorType>, rhs: (Signal<Value, ErrorType>) -> Signal<Result, ErrorType>) -> Signal<Result, ErrorType> {
    return rhs(lhs)
}

public func map<Value, ErrorType, Result>(_ transform: @escaping (Value) -> Result) -> (Signal<Value, ErrorType>) -> Signal<Result, ErrorType> {
    return { signal in
        return Signal<Result, ErrorType> { subscriber in
            signal.start(next: { value in
                subscriber(transform(value))
            })
        }
    }
}

public func distinctUntilChanged<Value: Equatable, ErrorType>(_ signal: Signal<Value, ErrorType>) -> Signal<Value, ErrorType> {
    var previous: Value?
    return Signal<Value, ErrorType> { subscriber in
        signal.start(next: { value in
            if previous != value {
                previous = value
                subscriber(value)
            }
        })
    }
}

public func switchToLatest<Value, ErrorType>(_ signal: Signal<Signal<Value, ErrorType>, ErrorType>) -> Signal<Value, ErrorType> {
    return Signal<Value, ErrorType> { subscriber in
        signal.start(next: { innerSignal in
            innerSignal.start(next: subscriber)
        })
    }
}
