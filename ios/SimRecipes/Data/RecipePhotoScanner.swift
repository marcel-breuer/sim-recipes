import Foundation
import ImageIO
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

struct RecipeCaptureExposure: Codable, Equatable, Sendable {
    var iso: Double?
    var exposureTimeSeconds: Double?
    var fNumber: Double?
    var focalLengthMM: Double?
    var exposureCompensationEV: Double?

    enum CodingKeys: String, CodingKey {
        case iso
        case exposureTimeSeconds = "exposure_time_seconds"
        case fNumber = "f_number"
        case focalLengthMM = "focal_length_mm"
        case exposureCompensationEV = "exposure_compensation_ev"
    }

    var summary: [String] {
        var values: [String] = []
        if let iso { values.append("ISO \(iso.formatted(.number.precision(.fractionLength(0))))") }
        if let exposureTimeSeconds {
            let reciprocal = 1 / exposureTimeSeconds
            values.append(exposureTimeSeconds < 1 && reciprocal.isFinite && reciprocal <= 1_000_000_000
                ? "1/\(reciprocal.rounded().formatted(.number.precision(.fractionLength(0)))) s"
                : "\(exposureTimeSeconds.formatted(.number.precision(.fractionLength(1)))) s")
        }
        if let fNumber { values.append("f/\(fNumber.formatted(.number.precision(.fractionLength(1))))") }
        if let focalLengthMM { values.append("\(focalLengthMM.formatted(.number.precision(.fractionLength(1)))) mm") }
        if let exposureCompensationEV {
            values.append("\(exposureCompensationEV > 0 ? "+" : "")\(exposureCompensationEV.formatted(.number.precision(.fractionLength(1)))) EV")
        }
        return values
    }
}

struct RecipeCaptureLocation: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct RecipeCaptureSetting: Codable, Equatable, Identifiable, Sendable {
    let settingKey: String
    var value: JSONValue
    var source: String
    var wasEdited: Bool

    var id: String { settingKey }

    enum CodingKeys: String, CodingKey {
        case settingKey = "setting_key"
        case value, source
        case wasEdited = "was_edited"
    }
}

struct RecipeCaptureMetadata: Codable, Equatable, Sendable {
    var source = "fujifilm_jpeg"
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var exposure: RecipeCaptureExposure?
    var settings: [RecipeCaptureSetting] = []
    var sceneNotes: String?
    var lightingNotes: String?
    var location: RecipeCaptureLocation?
    var locationShared = false

    enum CodingKeys: String, CodingKey {
        case source
        case cameraMake = "camera_make"
        case cameraModel = "camera_model"
        case lensModel = "lens_model"
        case exposure, settings
        case sceneNotes = "scene_notes"
        case lightingNotes = "lighting_notes"
        case location
        case locationShared = "location_shared"
    }
}

struct RecipeCaptureImportResult: Equatable, Sendable {
    var metadata: RecipeCaptureMetadata
    var fields: [RecipeScanField]
    var isFujifilmJPEG: Bool
}

enum RecipeCaptureMetadataError: LocalizedError, Equatable {
    case unsupportedJPEG
    case unreadableMetadata

    var errorDescription: String? {
        switch self {
        case .unsupportedJPEG:
            "Choose a JPEG photo. Other image formats are not scanned for Fujifilm recipe metadata."
        case .unreadableMetadata:
            "The JPEG metadata could not be read. The image has not been saved or uploaded."
        }
    }
}

enum RecipeCaptureMetadataParser {
    private static let filmModeNames: [Int: String] = [
        0x0000: "PROVIA/STANDARD",
        0x0120: "ASTIA/SOFT",
        0x0200: "Velvia/VIVID",
        0x0500: "PRO Neg. Std",
        0x0501: "PRO Neg. Hi",
        0x0600: "CLASSIC CHROME",
        0x0700: "ETERNA/CINEMA",
        0x0800: "CLASSIC Neg.",
        0x0900: "ETERNA BLEACH BYPASS",
        0x0a00: "NOSTALGIC Neg.",
        0x0b00: "REALA ACE"
    ]

    private static let colorChromeNames: [Int: String] = [
        0: "OFF",
        32: "WEAK",
        64: "STRONG"
    ]

    private static let sharpnessNames: [Int: String] = [
        0: "-4",
        1: "-3",
        2: "-2",
        3: "0",
        4: "2",
        5: "3",
        6: "4",
        0x82: "-1",
        0x84: "1"
    ]

    private static let saturationNames: [Int: String] = [
        0: "0",
        0x80: "1",
        0xc0: "3",
        0xe0: "4",
        0x100: "2",
        0x180: "-1",
        0x200: "-2",
        0x400: "-2",
        0x4c0: "-3",
        0x4e0: "-4"
    ]

    private static let whiteBalanceNames: [Int: String] = [
        0: "AUTO",
        1: "WHITE PRIORITY",
        2: "AMBIENCE PRIORITY",
        0x100: "DAYLIGHT",
        0x400: "INCANDESCENT",
        0x600: "UNDERWATER",
        0xff0: "COLOR TEMPERATURE"
    ]

    static func parse(_ data: Data, capabilities: [CameraCapabilityTransport]) throws -> RecipeCaptureImportResult {
        guard data.starts(with: [0xff, 0xd8, 0xff]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) == "public.jpeg" as CFString,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw RecipeCaptureMetadataError.unsupportedJPEG
        }

        return parse(properties: properties, capabilities: capabilities)
    }

    static func parse(
        properties: [CFString: Any],
        capabilities: [CameraCapabilityTransport]
    ) -> RecipeCaptureImportResult {
        let tiff = dictionary(properties[kCGImagePropertyTIFFDictionary])
        let exif = dictionary(properties[kCGImagePropertyExifDictionary])
        let exifAux = dictionary(properties[kCGImagePropertyExifAuxDictionary])
        let maker = dictionary(properties[kCGImagePropertyMakerFujiDictionary])
        let cameraMake = string(tiff["Make"])
        let cameraModel = string(tiff["Model"])
        let lensModel = string(exif["LensModel"]) ?? string(exifAux["LensModel"])
        let exposure = RecipeCaptureExposure(
            iso: number(exif["ISOSpeedRatings"]) ?? number(exif["ISOSpeed"]),
            exposureTimeSeconds: positiveNumber(exif["ExposureTime"]),
            fNumber: positiveNumber(exif["FNumber"]),
            focalLengthMM: positiveNumber(exif["FocalLength"]),
            exposureCompensationEV: number(exif["ExposureBiasValue"])
        )
        let isFujifilmJPEG = cameraMake?.localizedCaseInsensitiveContains("fujifilm") == true
        let location = parseLocation(dictionary(properties[kCGImagePropertyGPSDictionary]))
        let fields = isFujifilmJPEG ? parseRecipeSettings(maker: maker, capabilities: capabilities) : []
        let settings = fields.compactMap { field -> RecipeCaptureSetting? in
            guard field.isSelected, let key = field.capabilityKey, let value = field.settingValue else { return nil }
            return RecipeCaptureSetting(settingKey: key, value: value, source: field.sourceText, wasEdited: false)
        }

        return RecipeCaptureImportResult(
            metadata: RecipeCaptureMetadata(
                source: isFujifilmJPEG ? "fujifilm_jpeg" : "jpeg_exif",
                cameraMake: cameraMake,
                cameraModel: cameraModel,
                lensModel: lensModel,
                exposure: exposure.summary.isEmpty ? nil : exposure,
                settings: settings,
                location: location
            ),
            fields: fields,
            isFujifilmJPEG: isFujifilmJPEG
        )
    }

    private static func parseRecipeSettings(
        maker: [String: Any],
        capabilities: [CameraCapabilityTransport]
    ) -> [RecipeScanField] {
        let mappedTags: [(tag: String, key: String)] = [
            ("FilmMode", "film_simulation"),
            ("DynamicRangeSetting", "dynamic_range"),
            ("ColorChromeEffect", "color_chrome_effect"),
            ("ColorChromeFXBlue", "color_chrome_fx_blue"),
            ("WhiteBalance", "white_balance"),
            ("HighlightTone", "highlight_tone"),
            ("ShadowTone", "shadow_tone"),
            ("Saturation", "color"),
            ("Sharpness", "sharpness"),
            ("HighISONoiseReduction", "high_iso_noise_reduction"),
            ("Clarity", "clarity")
        ]
        var fields: [RecipeScanField] = []
        for mapping in mappedTags {
            guard let rawValue = maker[mapping.tag],
                  let capability = capabilities.first(where: { $0.key == mapping.key }) else { continue }

            let valueText: String?
            valueText = mappedValue(for: mapping.tag, rawValue: rawValue)
            guard let valueText else {
                fields.append(RecipeScanField(
                    label: capability.displayName,
                    rawValue: String(describing: rawValue),
                    sourceText: "Fujifilm MakerNote.\(mapping.tag)",
                    confidence: 1,
                    capabilityKey: capability.key,
                    settingValue: nil,
                    status: .unsupportedValue,
                    isSelected: false
                ))
                continue
            }

            let field = RecipeScanParser.resolve(
                label: capability.displayName,
                rawValue: valueText,
                sourceText: "Fujifilm MakerNote.\(mapping.tag): \(valueText)",
                confidence: 1,
                capabilities: capabilities
            )
            fields.append(field)
        }

        if let grainCapability = capabilities.first(where: { $0.key == "grain_effect" }) {
            let roughness = maker["GrainEffectRoughness"]
            let size = maker["GrainEffectSize"]
            if roughness != nil || size != nil {
                let rawValue = [
                    roughness.map { "roughness: \(String(describing: $0))" },
                    size.map { "size: \(String(describing: $0))" }
                ].compactMap { $0 }.joined(separator: ", ")
                let sourceText = "Fujifilm MakerNotes.GrainEffectRoughness/GrainEffectSize: \(rawValue)"
                let field: RecipeScanField
                if let roughnessText = string(roughness), let sizeText = string(size) {
                    field = RecipeScanParser.resolve(
                        label: grainCapability.displayName,
                        rawValue: "\(roughnessText) \(sizeText)",
                        sourceText: sourceText,
                        confidence: 1,
                        capabilities: capabilities
                    )
                } else {
                    field = RecipeScanField(
                        label: grainCapability.displayName,
                        rawValue: rawValue,
                        sourceText: sourceText,
                        confidence: 1,
                        capabilityKey: grainCapability.key,
                        settingValue: nil,
                        status: .unsupportedValue,
                        isSelected: false
                    )
                }
                fields.append(field)
            }
        }

        let duplicateCapabilityKeys = Dictionary(grouping: fields.indices.compactMap { index in
            fields[index].capabilityKey.map { ($0, index) }
        }, by: { $0.0 }).filter { $0.value.count > 1 }
        for (_, entries) in duplicateCapabilityKeys {
            for (_, index) in entries {
                fields[index].status = .duplicate
                fields[index].isSelected = false
            }
        }

        return fields
    }

    private static func mappedValue(for tag: String, rawValue: Any) -> String? {
        if let text = string(rawValue) { return text }
        guard let code = integer(rawValue) else { return nil }

        switch tag {
        case "FilmMode": return filmModeNames[code]
        case "ColorChromeEffect", "ColorChromeFXBlue": return colorChromeNames[code]
        case "Sharpness": return sharpnessNames[code]
        case "Saturation": return saturationNames[code]
        case "WhiteBalance": return whiteBalanceNames[code]
        case "DynamicRangeSetting":
            return [0: "AUTO", 0x100: "100%", 0x201: "400%"][code]
        case "HighlightTone", "ShadowTone":
            guard (-64...64).contains(code), code.isMultiple(of: 16) else { return nil }
            return String(-code / 16)
        default: return nil
        }
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        if let value = value as? [String: Any] { return value }
        if let value = value as? [CFString: Any] {
            return Dictionary(uniqueKeysWithValues: value.map { (String(describing: $0.key), $0.value) })
        }
        guard let value = value as? NSDictionary else { return [:] }
        var result: [String: Any] = [:]
        for (key, item) in value where key is String || key is CFString {
            result[String(describing: key)] = item
        }
        return result
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func number(_ value: Any?) -> Double? {
        if let values = value as? [NSNumber] { return values.first?.doubleValue }
        guard let value = value as? NSNumber else { return nil }
        let number = value.doubleValue
        return number.isFinite ? number : nil
    }

    private static func positiveNumber(_ value: Any?) -> Double? {
        guard let value = number(value), value > 0 else { return nil }
        return value
    }

    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded() == value, value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    private static func parseLocation(_ gps: [String: Any]) -> RecipeCaptureLocation? {
        guard let latitude = number(gps["Latitude"]),
              let longitude = number(gps["Longitude"]),
              abs(latitude) <= 90,
              abs(longitude) <= 180 else { return nil }
        let latitudeRef = string(gps["LatitudeRef"])?.uppercased()
        let longitudeRef = string(gps["LongitudeRef"])?.uppercased()
        guard ["N", "S"].contains(latitudeRef ?? ""),
              ["E", "W"].contains(longitudeRef ?? "") else { return nil }
        return RecipeCaptureLocation(
            latitude: latitudeRef == "S" ? -latitude : latitude,
            longitude: longitudeRef == "W" ? -longitude : longitude
        )
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
