import Foundation

enum CameraCompatibilityEvidenceLevel: String, Equatable, Sendable {
    case unknown
    case catalogOnly = "catalog_only"
    case manufacturerDocumented = "manufacturer_documented"
    case cameraVerified = "camera_verified"

    var confidence: Int {
        switch self {
        case .unknown: 0
        case .catalogOnly: 1
        case .manufacturerDocumented: 2
        case .cameraVerified: 3
        }
    }

    var title: String {
        switch self {
        case .unknown: "Unknown"
        case .catalogOnly: "Capability catalogue"
        case .manufacturerDocumented: "Manufacturer documented"
        case .cameraVerified: "Camera verified"
        }
    }

    var explanation: String {
        switch self {
        case .unknown:
            "Compatibility evidence is missing for one or more settings."
        case .catalogOnly:
            "Values match the stored capability catalogue; camera behavior has not been verified."
        case .manufacturerDocumented:
            "Manufacturer documentation supports these settings; transfer behavior has not been verified."
        case .cameraVerified:
            "These settings were checked on camera hardware and firmware recorded in the evidence."
        }
    }
}

struct CameraCompatibilityIssue: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case missingCapability
        case unsupportedValue
        case outOfRange
        case invalidShape
    }

    let settingKey: String
    let displayName: String
    let kind: Kind
    let detail: String

    var id: String {
        "\(settingKey)-\(kind.rawValue)"
    }
}

struct CameraCompatibilitySettingEvidence: Equatable, Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case unknown
        case catalogueMatch
        case unsupported
    }

    let settingKey: String
    let displayName: String
    let status: Status
    let evidenceLevel: CameraCompatibilityEvidenceLevel
    let source: String?
    let firmware: String?
    let issues: [CameraCompatibilityIssue]

    var id: String { settingKey }

    var statusTitle: String {
        switch status {
        case .unknown: "Unknown compatibility"
        case .catalogueMatch: "Matches capability catalogue"
        case .unsupported: "Unsupported recipe value"
        }
    }

    var statusSymbol: String {
        switch status {
        case .unknown: "questionmark.circle"
        case .catalogueMatch: "checkmark.circle"
        case .unsupported: "xmark.circle"
        }
    }
}

struct CameraPreflightResult: Equatable, Sendable {
    let cameraID: String
    let cameraName: String
    let issues: [CameraCompatibilityIssue]
    let evidenceLevel: CameraCompatibilityEvidenceLevel
    let evidenceRecords: [CameraCapabilityEvidenceTransport]
    let settingEvidence: [CameraCompatibilitySettingEvidence]

    var isTransferSafe: Bool {
        issues.isEmpty
    }
}

enum CameraCompatibilityEvaluator {
    static func evaluate(
        recipe: RecipeTransport,
        camera: SupportedCameraTransport
    ) -> CameraPreflightResult {
        let capabilities = Dictionary(uniqueKeysWithValues: camera.capabilities.map { ($0.key, $0) })
        let settingEvidence = recipe.settings.map { setting -> CameraCompatibilitySettingEvidence in
            guard let capability = capabilities[setting.key] else {
                let issue = CameraCompatibilityIssue(
                    settingKey: setting.key,
                    displayName: setting.key,
                    kind: .missingCapability,
                    detail: "No capability record exists for this setting, so compatibility is unknown."
                )
                return CameraCompatibilitySettingEvidence(
                    settingKey: setting.key,
                    displayName: setting.key,
                    status: .unknown,
                    evidenceLevel: .unknown,
                    source: nil,
                    firmware: nil,
                    issues: [issue]
                )
            }

            let settingIssues = validate(setting: setting, capability: capability)
            return CameraCompatibilitySettingEvidence(
                settingKey: setting.key,
                displayName: capability.displayName,
                status: settingIssues.isEmpty ? .catalogueMatch : .unsupported,
                evidenceLevel: capability.evidence?.evidenceLevel ?? .unknown,
                source: capability.evidence?.source,
                firmware: capability.evidence?.firmware,
                issues: settingIssues
            )
        }
        let evidenceRecords = settingEvidence.compactMap { setting in
            capabilities[setting.settingKey]?.evidence
        }
        let issues = settingEvidence.flatMap(\.issues)

        return CameraPreflightResult(
            cameraID: camera.id,
            cameraName: camera.name,
            issues: issues,
            evidenceLevel: settingEvidence.map(\.evidenceLevel).min { $0.confidence < $1.confidence } ?? .unknown,
            evidenceRecords: evidenceRecords,
            settingEvidence: settingEvidence
        )
    }

    private static func validate(
        setting: RecipeSettingTransport,
        capability: CameraCapabilityTransport
    ) -> [CameraCompatibilityIssue] {
        let displayName = capability.displayName
        let issue = { (kind: CameraCompatibilityIssue.Kind, detail: String) in
            CameraCompatibilityIssue(
                settingKey: setting.key,
                displayName: displayName,
                kind: kind,
                detail: detail
            )
        }

        switch (capability.valueType, setting.value) {
        case let ("integer", value):
            guard let number = value.numberValue, number.rounded() == number else {
                return [issue(.invalidShape, "Expected a whole-number value.")]
            }
            return validate(number: number, setting: setting, capability: capability, issue: issue)
        case let ("decimal", value), let ("number", value):
            guard let number = value.numberValue else {
                return [issue(.invalidShape, "Expected a numeric value.")]
            }
            return validate(number: number, setting: setting, capability: capability, issue: issue)
        case ("boolean", .boolean):
            return []
        case let ("object", .object(value)):
            return validate(object: value, setting: setting, capability: capability, issue: issue)
        case let ("enum", value), let ("string", value), let (_, value):
            guard let string = value.stringValue else {
                return [issue(.invalidShape, "Expected a text value.")]
            }
            guard isAllowed(string, in: capability.allowedValues) else {
                return [issue(.unsupportedValue, "\"\(string)\" is not supported by this camera.")]
            }
            return []
        }
    }

    private static func validate(
        number: Double,
        setting: RecipeSettingTransport,
        capability: CameraCapabilityTransport,
        issue: (CameraCompatibilityIssue.Kind, String) -> CameraCompatibilityIssue
    ) -> [CameraCompatibilityIssue] {
        if let minimum = capability.minimum, number < minimum {
            return [issue(.outOfRange, "The value must be at least \(minimum.formatted()).")]
        }
        if let maximum = capability.maximum, number > maximum {
            return [issue(.outOfRange, "The value must be at most \(maximum.formatted()).")]
        }
        if !isAllowed(number, in: capability.allowedValues) {
            return [issue(.unsupportedValue, "This numeric value is not supported by the camera.")]
        }
        return []
    }

    private static func validate(
        object: [String: JSONValue],
        setting: RecipeSettingTransport,
        capability: CameraCapabilityTransport,
        issue: (CameraCompatibilityIssue.Kind, String) -> CameraCompatibilityIssue
    ) -> [CameraCompatibilityIssue] {
        guard case let .object(allowed) = capability.allowedValues else {
            return validateObjectRange(object, capability: capability, issue: issue)
        }

        if case let .array(axes)? = allowed["axes"],
           Set(object.keys).isDisjoint(with: Set(axes.compactMap(\.stringValue))) {
            return [issue(.unsupportedValue, "This object does not contain a supported axis.")]
        }

        for (key, allowedValue) in allowed where key != "axes" {
            guard let value = object[key] else {
                return [issue(.invalidShape, "The required field \"\(key)\" is missing.")]
            }
            if case let .array(options) = allowedValue,
               !options.contains(value) {
                return [issue(.unsupportedValue, "The value for \"\(key)\" is not supported.")]
            }
        }

        return validateObjectRange(object, capability: capability, issue: issue)
    }

    private static func validateObjectRange(
        _ object: [String: JSONValue],
        capability: CameraCapabilityTransport,
        issue: (CameraCompatibilityIssue.Kind, String) -> CameraCompatibilityIssue
    ) -> [CameraCompatibilityIssue] {
        let numbers = object.values.compactMap(\.numberValue)
        if let minimum = capability.minimum, numbers.contains(where: { $0 < minimum }) {
            return [issue(.outOfRange, "All numeric values must be at least \(minimum.formatted()).")]
        }
        if let maximum = capability.maximum, numbers.contains(where: { $0 > maximum }) {
            return [issue(.outOfRange, "All numeric values must be at most \(maximum.formatted()).")]
        }
        return []
    }

    private static func isAllowed(_ value: String, in allowedValues: JSONValue?) -> Bool {
        guard let allowedValues else { return true }
        guard case let .array(values) = allowedValues else { return true }
        return values.contains(.string(value))
    }

    private static func isAllowed(_ value: Double, in allowedValues: JSONValue?) -> Bool {
        guard let allowedValues else { return true }
        guard case let .array(values) = allowedValues else { return true }
        return values.contains { $0.numberValue == value }
    }
}
