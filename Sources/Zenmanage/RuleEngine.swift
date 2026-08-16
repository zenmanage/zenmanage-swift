import Foundation

struct RolloutBucketer {
    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)

        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xEDB88320
            } else {
                crc = crc >> 1
            }
        }

        return crc
    }

    static func crc32b(_ input: String) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF

        for byte in input.utf8 {
            let lookupIndex = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[lookupIndex]
        }

        return crc ^ 0xFFFF_FFFF
    }

    static func isInBucket(salt: String, contextIdentifier: String?, percentage: Double) throws -> Bool {
        guard (0...100).contains(percentage) else {
            throw ZenmanageError.evaluation("Percentage must be between 0 and 100")
        }

        guard let contextIdentifier, !contextIdentifier.isEmpty else {
            return false
        }

        let hash = crc32b("\(salt):\(contextIdentifier)")
        let bucket = Double(hash % 100)
        return bucket < percentage
    }
}

final class RuleEngine {
    func evaluate(_ rules: [Rule], context: Context) -> Rule? {
        for rule in rules {
            if evaluate(rule, context: context) {
                return rule
            }
        }

        return nil
    }

    private func evaluate(_ rule: Rule, context: Context) -> Bool {
        if !rule.clauses.isEmpty {
            return rule.clauses.allSatisfy { evaluate($0, context: context) }
        }

        if let criteria = rule.criteria {
            return evaluate(criteria, context: context)
        }

        return true
    }

    private func evaluate(_ clause: RuleCondition, context: Context) -> Bool {
        if clause.attribute == "context" || clause.attribute == "segment" {
            return evaluateContextClause(clause, context: context)
        }

        guard let attribute = context.attribute(forKey: clause.attribute) else {
            switch clause.comparison {
            case "isnull", "notequal", "notin", "notcontains", "notstartswith", "notendswith":
                return true
            default:
                return false
            }
        }

        if clause.comparison == "isnull" {
            return attribute.values.allSatisfy { $0.isEmpty }
        }
        if clause.comparison == "notnull" {
            return attribute.values.contains { !$0.isEmpty }
        }

        guard let targets = clause.value?.stringValues else {
            return false
        }

        return evaluate(values: attribute.values, comparison: clause.comparison, targets: targets)
    }

    private func evaluateContextClause(_ clause: RuleCondition, context: Context) -> Bool {
        guard let identifier = context.identifier else {
            return false
        }

        let matchingTargets = clause.value?.targets
            .filter { $0.type == nil || $0.type == context.type }
            .map(\.identifier) ?? []

        guard !matchingTargets.isEmpty else {
            return false
        }

        return evaluate(values: [identifier], comparison: clause.comparison, targets: matchingTargets)
    }

    private func evaluate(values: [String], comparison: String, targets: [String]) -> Bool {
        guard let target = targets.first, !targets.isEmpty else {
            return false
        }

        switch comparison {
        case "equal":
            return values.contains(target)
        case "notequal":
            return !values.contains(target)
        case "contains":
            return values.contains(where: { $0.contains(target) })
        case "notcontains":
            return !values.contains(where: { $0.contains(target) })
        case "in":
            return values.contains(where: { targets.contains($0) })
        case "notin":
            return !values.contains(where: { targets.contains($0) })
        case "startswith":
            return values.contains(where: { $0.hasPrefix(target) })
        case "notstartswith":
            return !values.contains(where: { $0.hasPrefix(target) })
        case "endswith":
            return values.contains(where: { $0.hasSuffix(target) })
        case "notendswith":
            return !values.contains(where: { $0.hasSuffix(target) })
        case "gt":
            return compareNumbers(values: values, target: target, comparator: >)
        case "gte":
            return compareNumbers(values: values, target: target, comparator: >=)
        case "lt":
            return compareNumbers(values: values, target: target, comparator: <)
        case "lte":
            return compareNumbers(values: values, target: target, comparator: <=)
        default:
            return false
        }
    }

    private func compareNumbers(
        values: [String],
        target: String,
        comparator: (Double, Double) -> Bool
    ) -> Bool {
        guard let targetNumber = Double(target) else {
            return false
        }

        return values.contains { value in
            guard let number = Double(value) else {
                return false
            }

            return comparator(number, targetNumber)
        }
    }
}