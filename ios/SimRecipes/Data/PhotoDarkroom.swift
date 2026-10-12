import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum PhotoDarkroomFrame: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case white
    case black

    var id: String { rawValue }
}

struct PhotoDarkroomEdits: Codable, Equatable, Sendable {
    var recipeID: String?
    var recipeName: String?
    var recipeSettings: [RecipeSettingTransport] = []
    var capabilities: [CameraCapabilityTransport] = []
    var exposure = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var temperature = 0.0
    var tint = 0.0
    var cropScale = 1.0
    var cropOffsetX = 0.0
    var cropOffsetY = 0.0
    var straightenDegrees = 0.0
    var frame: PhotoDarkroomFrame = .none

    var hasRecipe: Bool { recipeID != nil && !recipeSettings.isEmpty }
}

struct PhotoDarkroomProject: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let filename: String
    let displayName: String
    let sourceSHA256: String
    let importedAt: Date
    var edits: PhotoDarkroomEdits

    init(id: UUID = UUID(), filename: String, displayName: String, sourceSHA256: String,
         importedAt: Date = Date(), edits: PhotoDarkroomEdits = PhotoDarkroomEdits()) {
        self.id = id
        self.filename = filename
        self.displayName = displayName
        self.sourceSHA256 = sourceSHA256
        self.importedAt = importedAt
        self.edits = edits
    }
}

enum PhotoDarkroomSyncSelection: Hashable, Sendable {
    case recipe
    case lightAndColor
    case cropAndStraighten
}

enum PhotoDarkroomBatchSync {
    static func apply(
        source: PhotoDarkroomEdits,
        to target: PhotoDarkroomEdits,
        selection: Set<PhotoDarkroomSyncSelection>
    ) -> PhotoDarkroomEdits {
        var result = target
        if selection.contains(.recipe) {
            result.recipeID = source.recipeID
            result.recipeName = source.recipeName
            result.recipeSettings = source.recipeSettings
            result.capabilities = source.capabilities
        }
        if selection.contains(.lightAndColor) {
            result.exposure = source.exposure
            result.contrast = source.contrast
            result.saturation = source.saturation
            result.temperature = source.temperature
            result.tint = source.tint
            result.frame = source.frame
        }
        if selection.contains(.cropAndStraighten) {
            result.cropScale = source.cropScale
            result.cropOffsetX = source.cropOffsetX
            result.cropOffsetY = source.cropOffsetY
            result.straightenDegrees = source.straightenDegrees
        }
        return result
    }
}

enum PhotoDarkroomError: LocalizedError, Equatable {
    case invalidJPEG
    case unableToImport
    case missingSource
    case unableToRender
    case unableToExport

    var errorDescription: String? {
        switch self {
        case .invalidJPEG: "Choose a valid JPEG photo."
        case .unableToImport: "The photo could not be added to the darkroom."
        case .missingSource: "The original photo is no longer available. Import it again to continue editing."
        case .unableToRender: "The photo could not be rendered."
        case .unableToExport: "The edited JPEG could not be exported."
        }
    }
}

actor PhotoDarkroomStore {
    private let directoryURL: URL
    private let indexURL: URL

    init(directoryURL: URL? = nil) {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let resolvedDirectory = directoryURL ?? supportURL.appendingPathComponent("PhotoDarkroom", isDirectory: true)
        self.directoryURL = resolvedDirectory
        self.indexURL = resolvedDirectory.appendingPathComponent("projects.json")
    }

    func load() throws -> [PhotoDarkroomProject] {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode([PhotoDarkroomProject].self, from: Data(contentsOf: indexURL))
            .filter { FileManager.default.fileExists(atPath: sourceURL(for: $0).path) }
    }

    func importJPEG(_ data: Data, filename: String) throws -> (project: PhotoDarkroomProject, wasDuplicate: Bool) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source), UTType(type as String)?.conforms(to: .jpeg) == true,
              CGImageSourceGetCount(source) > 0 else { throw PhotoDarkroomError.invalidJPEG }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var projects = try load()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let duplicate = projects.first(where: { $0.sourceSHA256 == digest }) {
            return (duplicate, true)
        }

        let id = UUID()
        let sourceURL = directoryURL.appendingPathComponent("\(id.uuidString).source.jpg")
        do {
            try data.write(to: sourceURL, options: .atomic)
            let safeName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            let project = PhotoDarkroomProject(
                id: id, filename: sourceURL.lastPathComponent,
                displayName: safeName.isEmpty ? "Photo" : safeName,
                sourceSHA256: digest
            )
            projects.append(project)
            try save(projects)
            return (project, false)
        } catch {
            try? FileManager.default.removeItem(at: sourceURL)
            throw PhotoDarkroomError.unableToImport
        }
    }

    func update(_ project: PhotoDarkroomProject) throws {
        var projects = try load()
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            throw PhotoDarkroomError.missingSource
        }
        projects[index] = project
        try save(projects)
    }

    func delete(_ project: PhotoDarkroomProject) throws {
        var projects = try load()
        projects.removeAll { $0.id == project.id }
        try FileManager.default.removeItem(at: sourceURL(for: project))
        try save(projects)
    }

    func sourceURL(for project: PhotoDarkroomProject) -> URL {
        directoryURL.appendingPathComponent(project.filename)
    }

    func newExportURL(for project: PhotoDarkroomProject) -> URL {
        directoryURL.appendingPathComponent("\(project.id.uuidString)-edited-\(UUID().uuidString).jpg")
    }

    private func save(_ projects: [PhotoDarkroomProject]) throws {
        let data = try JSONEncoder().encode(projects)
        try data.write(to: indexURL, options: .atomic)
    }
}

struct PhotoDarkroomPreview: Sendable {
    let originalJPEG: Data
    let editedJPEG: Data
    let unsupportedRecipeSettings: [String]
    let notSimulatedRecipeSettings: [String]
}

struct PhotoDarkroomRenderer: Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let maximumExportDimension = 5000

    func preview(sourceURL: URL, edits: PhotoDarkroomEdits, maximumDimension: CGFloat = 1800) async throws -> PhotoDarkroomPreview {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: Int(maximumDimension)
                  ]) else {
                throw PhotoDarkroomError.missingSource
            }
            let input = CIImage(cgImage: thumbnail)
            try Task.checkCancellation()
            guard let before = self.context.jpegRepresentation(
                of: input, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]
            ) else { throw PhotoDarkroomError.unableToRender }
            let rendered = try self.editedImage(input, edits: edits)
            try Task.checkCancellation()
            guard let after = self.context.jpegRepresentation(
                of: rendered.image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]
            ) else { throw PhotoDarkroomError.unableToRender }
            return PhotoDarkroomPreview(
                originalJPEG: before, editedJPEG: after,
                unsupportedRecipeSettings: rendered.unsupportedSettings,
                notSimulatedRecipeSettings: rendered.notSimulatedSettings
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func export(sourceURL: URL, edits: PhotoDarkroomEdits, preservingMetadata: Bool) async throws -> URL {
        try Task.checkCancellation()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimRecipes-\(UUID().uuidString).jpg")
        do {
            let task = Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary),
                      let inputImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: self.maximumExportDimension
                      ]) else {
                    throw PhotoDarkroomError.missingSource
                }
                let input = CIImage(cgImage: inputImage)
                try Task.checkCancellation()
                let rendered = try self.editedImage(input, edits: edits)
                try Task.checkCancellation()
                guard let cgImage = self.context.createCGImage(rendered.image, from: rendered.image.extent),
                      let destination = CGImageDestinationCreateWithURL(
                        outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
                      ) else { throw PhotoDarkroomError.unableToExport }

                let properties: NSMutableDictionary
                if preservingMetadata,
                   let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                    properties = NSMutableDictionary(dictionary: sourceProperties)
                    properties.removeObject(forKey: kCGImagePropertyOrientation)
                    properties.removeObject(forKey: kCGImagePropertyPixelWidth)
                    properties.removeObject(forKey: kCGImagePropertyPixelHeight)
                } else {
                    properties = NSMutableDictionary()
                }
                properties[kCGImageDestinationLossyCompressionQuality] = 0.92
                CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw PhotoDarkroomError.unableToExport }
            }
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private func editedImage(_ input: CIImage, edits: PhotoDarkroomEdits) throws -> (image: CIImage, unsupportedSettings: [String], notSimulatedSettings: [String]) {
        var image = input
        var unsupported: [String] = []
        var notSimulated: [String] = []
        if edits.hasRecipe {
            let application = RecipePreviewEngine().apply(
                settings: edits.recipeSettings, capabilities: edits.capabilities, to: image
            )
            image = application.image
            unsupported = application.unsupportedSettingKeys
            notSimulated = application.notSimulatedSettingKeys
        }

        if edits.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(max(-3, min(3, edits.exposure)))
            guard let output = filter.outputImage else { throw PhotoDarkroomError.unableToRender }
            image = output
        }
        if edits.contrast != 0 || edits.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.contrast = Float(max(0.5, min(1.5, 1 + edits.contrast)))
            filter.saturation = Float(max(0, min(2, 1 + edits.saturation)))
            guard let output = filter.outputImage else { throw PhotoDarkroomError.unableToRender }
            image = output
        }
        if edits.temperature != 0 || edits.tint != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 6500 + CGFloat(edits.temperature * 45), y: CGFloat(edits.tint * 20))
            guard let output = filter.outputImage else { throw PhotoDarkroomError.unableToRender }
            image = output
        }

        image = cropAndStraighten(image, edits: edits)
        if edits.frame != .none { image = addFrame(to: image, style: edits.frame) }
        return (image, unsupported, notSimulated)
    }

    private func cropAndStraighten(_ image: CIImage, edits: PhotoDarkroomEdits) -> CIImage {
        let extent = image.extent.integral
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let radians = CGFloat(edits.straightenDegrees * .pi / 180)
        let rotated = image.transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
            .rotated(by: radians).translatedBy(x: center.x, y: center.y))
        let rotatedExtent = rotated.extent.integral
        let zoom = max(1, min(2.5, CGFloat(edits.cropScale)))
        let width = min(extent.width, rotatedExtent.width) / zoom
        let height = min(extent.height, rotatedExtent.height) / zoom
        let originX = rotatedExtent.midX - width / 2 + CGFloat(edits.cropOffsetX) * width
        let originY = rotatedExtent.midY - height / 2 + CGFloat(edits.cropOffsetY) * height
        let cropRect = CGRect(x: originX, y: originY, width: width, height: height)
            .intersection(rotatedExtent)
        let cropped = rotated.cropped(to: cropRect)
        return cropped.transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
    }

    private func addFrame(to image: CIImage, style: PhotoDarkroomFrame) -> CIImage {
        let border = max(12, image.extent.width * 0.035)
        let color = CIColor(red: style == .white ? 1 : 0, green: style == .white ? 1 : 0, blue: style == .white ? 1 : 0)
        let background = CIImage(color: color).cropped(to: CGRect(
            x: 0, y: 0, width: image.extent.width + border * 2, height: image.extent.height + border * 2
        ))
        let placed = image.transformed(by: CGAffineTransform(translationX: border, y: border))
        return placed.composited(over: background)
    }
}

struct PhotoDarkroomJPEGDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.jpeg]
    let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    init(configuration: ReadConfiguration) throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try (configuration.file.regularFileContents ?? Data()).write(to: temporary, options: .atomic)
        fileURL = temporary
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: fileURL, options: [])
    }
}
