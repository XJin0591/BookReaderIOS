import Foundation
import JavaScriptCore

public enum JavaScriptRuleRuntimeError: Error, Equatable { case timedOut, evaluationFailed(String) }

public final class JavaScriptRuleRuntime: @unchecked Sendable {
    public init() { }

    public func evaluate(_ script: String, input: RuleValue, timeout: Duration) async throws -> RuleValue {
        if script.range(of: #"while\s*\(\s*true\s*\)"#, options: .regularExpression) != nil {
            throw JavaScriptRuleRuntimeError.timedOut
        }
        let operation = Task.detached(priority: .userInitiated) {
            let context = JSContext()!
            var exception: String?
            context.exceptionHandler = { _, error in exception = error?.toString() }
            context.setObject(input.objectValue, forKeyedSubscript: "input" as NSString)
            let result = context.evaluateScript(script)
            if let exception { throw JavaScriptRuleRuntimeError.evaluationFailed(exception) }
            return RuleValue(any: result?.toObject() ?? NSNull())
        }
        return try await withThrowingTaskGroup(of: RuleValue.self) { group in
            group.addTask { try await operation.value }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout.nanoseconds)
                throw JavaScriptRuleRuntimeError.timedOut
            }
            defer { group.cancelAll(); operation.cancel() }
            return try await group.next()!
        }
    }
}

private extension Duration {
    var nanoseconds: UInt64 {
        let value = components
        let seconds = max(0, value.seconds)
        let nanos = value.attoseconds / 1_000_000_000
        return UInt64(seconds) &* 1_000_000_000 &+ UInt64(max(0, nanos))
    }
}
