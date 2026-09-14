import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum RecipePreviewState: Equatable {
    case idle
    case loading
    case loaded(RecipePreviewResult)
    case failed(String)
}

struct RecipePreviewResult: Equatable, Sendable {
    let imageData: Data
    let simulatedSettingKeys: [String]
    let unsupportedSettingKeys: [String]
}

enum RecipePreviewError: LocalizedError, Equatable {
    case invalidImage
    case unableToRender

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The selected image could not be previewed. Choose another image."
        case .unableToRender:
            "The recipe preview could not be generated."
        }
    }
}

protocol RecipePreviewRendering: Sendable {
    func render(
        imageData: Data,
        settings: [RecipeSettingTransport],
        capabilities: [CameraCapabilityTransport]
    ) async throws -> RecipePreviewResult
}

struct RecipePreviewEngine: RecipePreviewRendering {
    private let context = CIContext()

    func render(
        imageData: Data,
        settings: [RecipeSettingTransport],
        capabilities: [CameraCapabilityTransport]
    ) async throws -> RecipePreviewResult {
        guard let inputImage = CIImage(data: imageData) else {
            throw RecipePreviewError.invalidImage
        }

        let supportedKeys = Set(capabilities.map(\.key))
        let supportedSettings = settings.filter { supportedKeys.contains($0.key) }
        let unsupportedSettingKeys = settings
            .filter { !supportedKeys.contains($0.key) }
            .map(\.key)
        var outputImage = inputImage
        var simulatedSettingKeys: [String] = []

        for setting in supportedSettings {
            if let transformed = apply(setting: setting, to: outputImage) {
                simulatedSettingKeys.append(setting.key)
                outputImage = transformed
            }
        }

        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent),
              let renderedData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9) else {
            throw RecipePreviewError.unableToRender
        }

        return RecipePreviewResult(
            imageData: renderedData,
            simulatedSettingKeys: simulatedSettingKeys,
            unsupportedSettingKeys: unsupportedSettingKeys
        )
    }

    private func apply(setting: RecipeSettingTransport, to image: CIImage) -> CIImage? {
        switch setting.key {
        case "film_simulation":
            return applyFilmSimulation(setting.value.stringValue ?? "", to: image)
        case "dynamic_range":
            let amount: Double
            switch setting.value.stringValue?.uppercased() {
            case "400%": amount = -0.12
            case "200%": amount = -0.06
            default: amount = 0
            }
            return colorControls(image, saturation: 1, contrast: 1 + amount, brightness: 0)
        case "exposure_compensation", "iso":
            guard let value = setting.value.numberValue else { return nil }
            let exposure = setting.key == "iso" ? log2(max(value, 100) / 100) * 0.08 : value
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(max(-2, min(2, exposure)))
            return filter.outputImage
        case "highlight_tone", "shadow_tone":
            guard let value = setting.value.numberValue else { return nil }
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = image
            let amount = max(0, min(1, 0.5 + value * 0.12))
            if setting.key == "highlight_tone" {
                filter.highlightAmount = Float(amount)
                filter.shadowAmount = 0.5
            } else {
                filter.highlightAmount = 0.5
                filter.shadowAmount = Float(amount)
            }
            return filter.outputImage
        case "color":
            guard let value = setting.value.numberValue else { return nil }
            return colorControls(image, saturation: 1 + value * 0.08, contrast: 1, brightness: 0)
        case "sharpness", "clarity":
            guard let value = setting.value.numberValue else { return nil }
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = image
            filter.sharpness = Float(max(0, min(1, value * 0.2)))
            filter.radius = setting.key == "clarity" ? 2 : 1
            return filter.outputImage
        case "high_iso_noise_reduction":
            guard let value = setting.value.numberValue else { return nil }
            let filter = CIFilter.noiseReduction()
            filter.inputImage = image
            filter.noiseLevel = Float(max(0, min(0.08, value * 0.01)))
            filter.sharpness = 0.4
            return filter.outputImage
        case "grain_effect":
            return applyGrain(setting.value, to: image)
        case "white_balance", "white_balance_shift", "color_chrome_effect", "color_chrome_fx_blue":
            return applyColorAdjustment(setting.value, to: image)
        default:
            return nil
        }
    }

    private func applyFilmSimulation(_ value: String, to image: CIImage) -> CIImage? {
        let normalized = value.replacingOccurrences(of: "_", with: " ").uppercased()
        switch normalized {
        case "ACROS", "MONOCHROME":
            return image.applyingFilter("CIPhotoEffectNoir")
        case "VELVIA", "VELVIA/VIVID":
            return colorControls(image, saturation: 1.35, contrast: 1.12, brightness: 0)
        case "ETERNA/CINEMA", "ETERNA":
            return colorControls(image, saturation: 0.78, contrast: 0.94, brightness: 0.02)
        case "PRO NEG HI", "PRO NEG HIGH":
            return colorControls(image, saturation: 0.92, contrast: 1.05, brightness: 0)
        case "PRO NEG STD", "PRO NEG STANDARD":
            return colorControls(image, saturation: 0.86, contrast: 1.02, brightness: 0)
        case "CLASSIC NEG":
            return colorControls(image, saturation: 0.95, contrast: 1.08, brightness: 0)
        case "CLASSIC CHROME":
            return colorControls(image, saturation: 0.84, contrast: 1.08, brightness: 0)
        case "REALA ACE":
            return colorControls(image, saturation: 1.06, contrast: 1.04, brightness: 0)
        default:
            return colorControls(image, saturation: 1, contrast: 1, brightness: 0)
        }
    }

    private func applyColorAdjustment(_ value: JSONValue, to image: CIImage) -> CIImage? {
        guard case let .object(values) = value else { return nil }
        let temperature = values["temperature"]?.numberValue ?? 6500
        let tint = values["tint"]?.numberValue ?? 0
        guard temperature != 6500 || tint != 0 else { return nil }

        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: 6500, y: 0)
        filter.targetNeutral = CIVector(x: CGFloat(temperature), y: CGFloat(tint))
        return filter.outputImage
    }

    private func applyGrain(_ value: JSONValue, to image: CIImage) -> CIImage? {
        guard case let .object(values) = value,
              let roughness = values["roughness"]?.stringValue,
              roughness.uppercased() != "OFF" else { return nil }

        let opacity: CGFloat = roughness.uppercased() == "STRONG" ? 0.12 : 0.06
        guard let random = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: image.extent),
              let monochrome = CIFilter(name: "CIColorMatrix", parameters: [
                  kCIInputImageKey: random,
                  "inputRVector": CIVector(x: 0.2126, y: 0, z: 0, w: 0),
                  "inputGVector": CIVector(x: 0.7152, y: 0, z: 0, w: 0),
                  "inputBVector": CIVector(x: 0.0722, y: 0, z: 0, w: 0),
                  "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
              ])?.outputImage,
              let blend = CIFilter(name: "CISoftLightBlendMode", parameters: [
                  kCIInputImageKey: monochrome,
                  kCIInputBackgroundImageKey: image
              ]) else {
            return nil
        }
        return blend.outputImage
    }

    private func colorControls(
        _ image: CIImage,
        saturation: Double,
        contrast: Double,
        brightness: Double
    ) -> CIImage? {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.saturation = Float(saturation)
        filter.contrast = Float(contrast)
        filter.brightness = Float(brightness)
        return filter.outputImage
    }
}

@MainActor
final class RecipePreviewViewModel: ObservableObject {
    @Published private(set) var state: RecipePreviewState = .idle

    private let renderer: any RecipePreviewRendering

    init(renderer: any RecipePreviewRendering = RecipePreviewEngine()) {
        self.renderer = renderer
    }

    func load(
        imageData: Data,
        settings: [RecipeSettingTransport],
        capabilities: [CameraCapabilityTransport]
    ) async {
        state = .loading
        do {
            let result = try await renderer.render(
                imageData: imageData,
                settings: settings,
                capabilities: capabilities
            )
            state = .loaded(result)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct RecipePreviewView: View {
    let imageData: Data
    let settings: [RecipeSettingTransport]
    let capabilities: [CameraCapabilityTransport]
    @StateObject private var viewModel: RecipePreviewViewModel

    init(
        imageData: Data,
        settings: [RecipeSettingTransport],
        capabilities: [CameraCapabilityTransport]
    ) {
        self.imageData = imageData
        self.settings = settings
        self.capabilities = capabilities
        _viewModel = StateObject(wrappedValue: RecipePreviewViewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approximate preview")
                .font(.headline)
            Text("This local preview illustrates supported recipe adjustments. It does not reproduce Fujifilm color science exactly.")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Generating preview…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            case let .loaded(result):
                loadedPreview(result)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .task(id: requestID) {
            await viewModel.load(imageData: imageData, settings: settings, capabilities: capabilities)
        }
    }

    @ViewBuilder
    private func loadedPreview(_ result: RecipePreviewResult) -> some View {
        if let originalImage = UIImage(data: imageData),
           let previewImage = UIImage(data: result.imageData) {
            RecipeBeforeAfterView(
                originalImage: originalImage,
                previewImage: previewImage
            )
            .frame(height: 240)
        } else {
            Label("The preview image could not be displayed.", systemImage: "photo.slash")
                .foregroundStyle(.secondary)
        }

        if !result.unsupportedSettingKeys.isEmpty {
            Text("Not simulated because the camera does not support: \(result.unsupportedSettingKeys.joined(separator: ", ")).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !result.simulatedSettingKeys.isEmpty {
            Text("Simulated settings: \(result.simulatedSettingKeys.joined(separator: ", ")).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var requestID: RecipePreviewRequest {
        RecipePreviewRequest(
            imageData: imageData,
            settings: settings,
            capabilityKeys: capabilities.map(\.key)
        )
    }
}

private struct RecipePreviewRequest: Equatable {
    let imageData: Data
    let settings: [RecipeSettingTransport]
    let capabilityKeys: [String]
}

struct RecipeBeforeAfterView: View {
    let originalImage: UIImage
    let previewImage: UIImage
    @State private var revealAmount = 0.5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                imageView(originalImage)
                imageView(previewImage)
                    .frame(width: proxy.size.width * revealAmount)
                    .clipped()

                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .offset(x: proxy.size.width * revealAmount - 1)

                Circle()
                    .fill(.white)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "chevron.left.chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                    }
                    .shadow(radius: 2)
                    .offset(x: proxy.size.width * revealAmount - 17)

                VStack {
                    HStack {
                        label("Original", alignment: .leading)
                        Spacer()
                        label("Approximate preview", alignment: .trailing)
                    }
                    Spacer()
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        revealAmount = max(0, min(1, value.location.x / max(proxy.size.width, 1)))
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recipe preview comparison")
            .accessibilityValue("\(Int(revealAmount * 100)) percent approximate preview")
            .accessibilityHint("Swipe up or down to adjust the comparison. Drag left or right to reveal the preview.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    revealAmount = min(1, revealAmount + 0.1)
                case .decrement:
                    revealAmount = max(0, revealAmount - 0.1)
                @unknown default:
                    break
                }
            }
        }
    }

    private func imageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func label(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}
