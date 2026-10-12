import Foundation
import Vision

struct RecipeScanOCRLine: Equatable, Sendable {
    let text: String
    let confidence: Double
}

enum RecipeScanFieldStatus: String, Equatable, Sendable {
    case ready
    case lowConfidence
    case unknownLabel
    case unsupportedValue
    case ambiguous
    case duplicate
}

struct RecipeScanField: Equatable, Identifiable, Sendable {
    let id: UUID
    var label: String
    var rawValue: String
    let sourceText: String
    let confidence: Double
    var capabilityKey: String?
    var settingValue: JSONValue?
    var status: RecipeScanFieldStatus
    var isSelected: Bool

    init(
        id: UUID = UUID(), label: String, rawValue: String, sourceText: String,
        confidence: Double, capabilityKey: String?, settingValue: JSONValue?,
        status: RecipeScanFieldStatus, isSelected: Bool
    ) {
        self.id = id
        self.label = label
        self.rawValue = rawValue
        self.sourceText = sourceText
        self.confidence = confidence
        self.capabilityKey = capabilityKey
        self.settingValue = settingValue
        self.status = status
        self.isSelected = isSelected
    }
}

enum RecipePhotoTextRecognizer {
    static func recognize(cgImage: CGImage) throws -> [RecipeScanOCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "de-DE"]
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecipeScanOCRLine(text: candidate.string, confidence: Double(candidate.confidence))
        }
    }
}

enum RecipeScanParser {
    private static let aliases: [String: [String]] = [
        "film_simulation": ["film", "film sim", "film simulation", "filmsimulation", "simulation", "filmsim"],
        "dynamic_range": ["dr", "dynamic range", "dynamikumfang"],
        "grain_effect": ["grain", "grain effect", "graining", "körnung", "körnungseffekt"],
        "color_chrome_effect": ["cc", "color chrome", "color chrome effect", "color chrome fx", "color chrome effekt"],
        "color_chrome_fx_blue": ["cc blue", "cc fx blue", "color chrome fx blue", "color chrome blue"],
        "white_balance": ["wb", "white balance", "weißabgleich", "weissabgleich"],
        "white_balance_shift": ["wb shift", "white balance shift", "wa verschiebung", "weißabgleich verschiebung"],
        "highlight_tone": ["highlight", "highlights", "highlight tone", "lichter", "lichterton"],
        "shadow_tone": ["shadow", "shadows", "shadow tone", "schatten", "schattenton"],
        "color": ["color", "colour", "farbe", "sättigung", "saturation"],
        "sharpness": ["sharpness", "schärfe", "sharpening"],
        "high_iso_noise_reduction": ["high iso nr", "high iso noise reduction", "noise reduction", "rauschreduzierung", "high iso rauschreduzierung"],
        "clarity": ["clarity", "klarheit"],
        "iso": ["iso"],
        "exposure_compensation": ["exposure compensation", "exp compensation", "belichtungskorrektur", "belichtung"],
        "white_balance_shift_red": ["wb shift red", "wa verschiebung rot"],
        "white_balance_shift_blue": ["wb shift blue", "wa verschiebung blau"]
    ]

    static func parse(_ lines: [RecipeScanOCRLine], capabilities: [CameraCapabilityTransport]) -> [RecipeScanField] {
        var fields: [RecipeScanField] = []
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if let pair = labelAndValue(from: line.text) {
                fields.append(resolve(label: pair.label, rawValue: pair.value, sourceText: line.text,
                                      confidence: line.confidence, capabilities: capabilities))
            } else if isKnownLabel(line.text, capabilities: capabilities), lines.indices.contains(lineIndex + 1) {
                let valueLine = lines[lineIndex + 1]
                fields.append(resolve(label: line.text, rawValue: valueLine.text,
                                      sourceText: "\(line.text) · \(valueLine.text)",
                                      confidence: min(line.confidence, valueLine.confidence), capabilities: capabilities))
                lineIndex += 1
            }
            lineIndex += 1
        }

        let duplicateKeys = Dictionary(grouping: fields.indices.compactMap { index in
            fields[index].capabilityKey.map { ($0, index) }
        }, by: { $0.0 }).filter { $0.value.count > 1 }
        for (_, entries) in duplicateKeys {
            for (_, index) in entries {
                fields[index].status = .duplicate
                fields[index].isSelected = false
            }
        }
        return fields
    }

    static func resolve(
        label: String, rawValue: String, sourceText: String? = nil, confidence: Double = 1,
        capabilities: [CameraCapabilityTransport]
    ) -> RecipeScanField {
        let knownMatches = capabilities.filter { capability in
            let names = [capability.key, capability.displayName] + (aliases[capability.key] ?? [])
            return names.contains { normalize($0) == normalize(label) }
        }
        guard knownMatches.count == 1, let capability = knownMatches.first else {
            return RecipeScanField(label: label, rawValue: rawValue, sourceText: sourceText ?? "\(label): \(rawValue)",
                                   confidence: confidence, capabilityKey: nil, settingValue: nil,
                                   status: knownMatches.count > 1 ? .ambiguous : .unknownLabel, isSelected: false)
        }

        let values = parseValue(rawValue, for: capability)
        guard values.count == 1, let value = values.first else {
            return RecipeScanField(label: label, rawValue: rawValue, sourceText: sourceText ?? "\(label): \(rawValue)",
                                   confidence: confidence, capabilityKey: capability.key, settingValue: nil,
                                   status: values.count > 1 ? .ambiguous : .unsupportedValue, isSelected: false)
        }

        let status: RecipeScanFieldStatus = confidence < 0.72 ? .lowConfidence : .ready
        return RecipeScanField(label: label, rawValue: rawValue, sourceText: sourceText ?? "\(label): \(rawValue)",
                               confidence: confidence, capabilityKey: capability.key, settingValue: value,
                               status: status, isSelected: status == .ready)
    }

    static func normalizedSettingValue(_ text: String, for capability: CameraCapabilityTransport) -> JSONValue? {
        let values = parseValue(text, for: capability)
        return values.count == 1 ? values.first : nil
    }

    private static func labelAndValue(from line: String) -> (label: String, value: String)? {
        let separators = [":", "=", "："]
        if let separator = separators.first(where: { line.contains($0) }),
           let range = line.range(of: separator) {
            let label = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty || value.isEmpty ? nil : (label, value)
        }

        let normalizedLine = normalize(line)
        let possibleLabels = aliases.values.flatMap { $0 }.sorted { normalize($0).count > normalize($1).count }
        for label in possibleLabels where normalizedLine.hasPrefix(normalize(label)) {
            let tokens = line.split(whereSeparator: \.isWhitespace)
            let labelTokens = label.split(whereSeparator: \.isWhitespace).count
            guard tokens.count > labelTokens else { continue }
            return (label, tokens.dropFirst(labelTokens).joined(separator: " "))
        }
        return nil
    }

    private static func isKnownLabel(_ label: String, capabilities: [CameraCapabilityTransport]) -> Bool {
        capabilities.contains { capability in
            ([capability.key, capability.displayName] + (aliases[capability.key] ?? []))
                .contains { normalize($0) == normalize(label) }
        }
    }

    private static func parseValue(_ text: String, for capability: CameraCapabilityTransport) -> [JSONValue] {
        switch capability.valueType {
        case "enum":
            guard case let .array(allowed)? = capability.allowedValues else { return [] }
            return allowed.filter { value in
                guard let value = value.stringValue else { return false }
                return normalize(value) == normalize(text)
            }
        case "integer", "decimal":
            guard let number = parseNumber(text),
                  number >= (capability.minimum ?? -.infinity),
                  number <= (capability.maximum ?? .infinity) else { return [] }
            if capability.valueType == "integer", number.rounded() != number { return [] }
            if let step = capability.step, step > 0, let minimum = capability.minimum {
                let steps = (number - minimum) / step
                guard abs(steps - steps.rounded()) < 0.0001 else { return [] }
            }
            return [.number(number)]
        case "boolean":
            switch normalize(text) {
            case "on", "yes", "true", "ein", "an": return [.boolean(true)]
            case "off", "no", "false", "aus": return [.boolean(false)]
            default: return []
            }
        case "object":
            return parseObjectValue(text, capability: capability)
        default:
            return []
        }
    }

    private static func parseObjectValue(_ text: String, capability: CameraCapabilityTransport) -> [JSONValue] {
        guard case let .object(fields)? = capability.allowedValues else { return [] }

        if case let .array(axes)? = fields["axes"] {
            let axisNames = axes.compactMap(\.stringValue)
            let assignments = numericAssignments(in: text, capability: capability)
            guard axisNames.count == 2,
                  axisNames.allSatisfy({ assignments[$0] != nil }),
                  assignments.count == axisNames.count else { return [] }
            let values = Dictionary(uniqueKeysWithValues: axisNames.compactMap { axis in
                assignments[axis].map { (axis, JSONValue.number($0)) }
            })
            return [.object(values)]
        }

        var values: [String: JSONValue] = [:]
        for (field, allowed) in fields {
            guard case let .array(options) = allowed else { return [] }
            let matches = options.compactMap { option -> JSONValue? in
                guard let optionText = option.stringValue,
                      normalize(text).contains(normalize(optionText)) else { return nil }
                return option
            }
            guard matches.count == 1, let match = matches.first else { return [] }
            values[field] = match
        }
        return values.count == fields.count ? [.object(values)] : []
    }

    private static func numericAssignments(in text: String, capability: CameraCapabilityTransport) -> [String: Double] {
        let pattern = "([a-zA-Z_]+)\\s*[:=]?\\s*([+−-]?\\d+(?:[.,]\\d+)?)"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let source = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        var assignments: [String: Double] = [:]
        for match in matches where match.numberOfRanges == 3 {
            let axisText = source.substring(with: match.range(at: 1))
            let valueText = source.substring(with: match.range(at: 2))
            guard let axis = ["warm_cool", "green_magenta"].first(where: { normalize($0) == normalize(axisText) }),
                  assignments[axis] == nil,
                  let number = parseNumber(valueText),
                  number >= (capability.minimum ?? -9),
                  number <= (capability.maximum ?? 9),
                  number.rounded() == number else { continue }
            if let step = capability.step, step > 0, let minimum = capability.minimum {
                let steps = (number - minimum) / step
                guard abs(steps - steps.rounded()) < 0.0001 else { continue }
            }
            assignments[axis] = number
        }
        return assignments
    }

    private static func parseNumber(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "ev", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "stops", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        return Double(cleaned)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0) }.joined()
    }
}
