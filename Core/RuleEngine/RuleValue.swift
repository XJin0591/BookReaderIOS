import Foundation
import CoreFoundation

public enum RuleValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: RuleValue])
    case array([RuleValue])
    case null

    public var stringValue: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return ""
        case .object, .array: return ""
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var objectValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues(\.objectValue)
        case .array(let value): return value.map(\.objectValue)
        case .null: return NSNull()
        }
    }

    init(any: Any) {
        switch any {
        case let value as String: self = .string(value)
        case let value as NSNumber where CFGetTypeID(value) == CFBooleanGetTypeID(): self = .bool(value.boolValue)
        case let value as NSNumber: self = .number(value.doubleValue)
        case let value as [String: Any]: self = .object(value.mapValues(RuleValue.init(any:)))
        case let value as [Any]: self = .array(value.map(RuleValue.init(any:)))
        default: self = .null
        }
    }
}
