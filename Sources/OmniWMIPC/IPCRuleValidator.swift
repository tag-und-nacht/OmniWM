import Foundation

public struct IPCRuleValidationReport: Equatable, Sendable {
    public let bundleIdError: String?
    public let invalidRegexMessage: String?

    public init(bundleIdError: String?, invalidRegexMessage: String?) {
        self.bundleIdError = bundleIdError
        self.invalidRegexMessage = invalidRegexMessage
    }

    public var isValid: Bool {
        bundleIdError == nil && invalidRegexMessage == nil
    }
}

public enum IPCRuleValidator {
    public static func bundleIdError(for bundleId: String) -> String? {
        switch ZigIPCSupport.bundleIDValidationCode(for: bundleId) {
        case ZigIPCSupport.bundleIDValidationNone:
            return nil
        case ZigIPCSupport.bundleIDValidationRequired:
            return "Bundle ID is required"
        case ZigIPCSupport.bundleIDValidationInvalid:
            return "Invalid bundle ID format"
        default:
            return "Invalid bundle ID format"
        }
    }

    public static func invalidRegexMessage(for pattern: String?) -> String? {
        guard let pattern = pattern?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty else {
            return nil
        }

        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public static func validate(_ rule: IPCRuleDefinition) -> IPCRuleValidationReport {
        IPCRuleValidationReport(
            bundleIdError: bundleIdError(for: rule.bundleId),
            invalidRegexMessage: invalidRegexMessage(for: rule.titleRegex)
        )
    }
}
