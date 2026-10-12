import CoreTransferable
import PhotosUI
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RecipeCardSetting: Equatable, Sendable {
    let name: String
    let value: String
}

struct RecipeShareCardContent: Equatable, Sendable {
    let name: String
    let cameraName: String
    let filmSimulation: String
    let settings: [RecipeCardSetting]
    let publicURL: URL?

    static func make(from recipe: RecipeTransport) -> RecipeShareCardContent {
        let settings = recipe.settings.map { setting in
            RecipeCardSetting(name: displayName(for: setting.key), value: displayValue(for: setting.value))
        }
        let filmSimulation = recipe.settings
            .first(where: { $0.key == "film_simulation" })
            .map { displayValue(for: $0.value) } ?? "Film simulation recipe"

        return RecipeShareCardContent(
            name: recipe.name,
            cameraName: recipe.cameraModelName ?? recipe.cameraModelID,
            filmSimulation: filmSimulation,
            settings: settings,
            publicURL: RecipeShareLink.url(for: recipe)
        )
    }

    private static func displayName(for key: String) -> String {
        let names = [
            "film_simulation": "Film simulation", "dynamic_range": "Dynamic range",
            "grain_effect": "Grain", "color_chrome_effect": "Color Chrome",
            "color_chrome_fx_blue": "Color Chrome FX Blue", "white_balance": "White balance",
            "white_balance_shift": "WB shift", "highlight_tone": "Highlights",
            "shadow_tone": "Shadows", "color": "Color", "sharpness": "Sharpness",
            "high_iso_noise_reduction": "High ISO NR", "clarity": "Clarity", "iso": "ISO",
            "exposure_compensation": "Exposure compensation", "smooth_skin_effect": "Smooth skin"
        ]
        if let name = names[key] { return name }
        return key.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    private static func displayValue(for value: JSONValue) -> String {
        switch value {
        case let .string(value): value
        case let .number(value): value.rounded() == value ? String(Int(value)) : String(value)
        case let .boolean(value): value ? "On" : "Off"
        case let .object(values):
            values.keys.sorted().compactMap { key in
                values[key].map { "\(displayName(for: key)): \(displayValue(for: $0))" }
            }.joined(separator: ", ")
        case let .array(values): values.map { displayValue(for: $0) }.joined(separator: ", ")
        case .null: "—"
        }
    }
}

enum RecipeCardLayout: String, CaseIterable, Identifiable, Sendable {
    case darkroom
    case editorial

    var id: String { rawValue }
    var title: String { self == .darkroom ? "Dark" : "Editorial" }
}

enum RecipeCardCrop: String, CaseIterable, Identifiable, Sendable {
    case top
    case center
    case bottom

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var alignment: Alignment {
        switch self {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }
}

enum RecipeCardDetail: String, CaseIterable, Identifiable, Sendable {
    case summary
    case allSettings

    var id: String { rawValue }
    var title: String { self == .summary ? "Summary" : "All settings" }
}

enum RecipeCardError: LocalizedError, Equatable {
    case missingPhoto
    case unableToRender

    var errorDescription: String? {
        switch self {
        case .missingPhoto: "Choose a recipe photo or select one from your photo library."
        case .unableToRender: "The recipe card could not be created. Try another photo."
        }
    }
}

@MainActor enum RecipeShareCardRenderer {
    static func decodePhoto(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_800
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    static func renderPNG(
        content: RecipeShareCardContent,
        photo: UIImage?,
        layout: RecipeCardLayout,
        crop: RecipeCardCrop,
        detail: RecipeCardDetail
    ) throws -> Data {
        guard let photo else { throw RecipeCardError.missingPhoto }
        let renderer = ImageRenderer(
            content: RecipeShareCardCanvas(content: content, photo: photo, layout: layout, crop: crop, detail: detail)
        )
        renderer.scale = 3
        renderer.isOpaque = true
        guard let data = renderer.uiImage?.pngData(), !data.isEmpty else {
            throw RecipeCardError.unableToRender
        }
        return data
    }

    static func filename(for recipeName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let slug = recipeName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { !$0.unicodeScalars.allSatisfy(allowed.contains) })
            .map(String.init)
            .joined(separator: "-")
        return "\(slug.isEmpty ? "film-recipe" : String(slug.prefix(80))).png"
    }
}

private struct RecipeShareCardCanvas: View {
    let content: RecipeShareCardContent
    let photo: UIImage
    let layout: RecipeCardLayout
    let crop: RecipeCardCrop
    let detail: RecipeCardDetail

    private var foreground: Color { layout == .darkroom ? .white : Color(red: 0.12, green: 0.12, blue: 0.12) }
    private var secondaryForeground: Color { layout == .darkroom ? .white.opacity(0.72) : .black.opacity(0.65) }
    private var background: Color { layout == .darkroom ? Color(red: 0.08, green: 0.08, blue: 0.08) : Color(red: 0.95, green: 0.92, blue: 0.86) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 360, height: 188, alignment: crop.alignment)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 7) {
                    Text(content.filmSimulation.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4).lineLimit(1).minimumScaleFactor(0.75)
                    Text(content.name)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.68).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .frame(height: 188)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(content.cameraName).font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 8)
                    Text("SIMRECIPES").font(.system(size: 8, weight: .bold, design: .rounded)).tracking(1.4)
                }
                .foregroundStyle(secondaryForeground)
                if detail == .summary { summarySettings } else { allSettings }
                Spacer(minLength: 0)
                if let publicURL = content.publicURL {
                    Text(publicURL.absoluteString).font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryForeground).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
        }
        .frame(width: 360, height: 450)
        .background(background)
        .environment(\.colorScheme, .light)
    }

    private var summarySettings: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(content.settings.filter { $0.name != "Film simulation" }.prefix(4).enumerated()), id: \.offset) { _, setting in
                settingRow(setting, fontSize: 10)
            }
        }
    }

    private var allSettings: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            horizontalSpacing: 10,
            verticalSpacing: 5
        ) {
            ForEach(Array(content.settings.enumerated()), id: \.offset) { _, setting in
                settingRow(setting, fontSize: 8.5)
            }
        }
    }

    private func settingRow(_ setting: RecipeCardSetting, fontSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(setting.name).foregroundStyle(secondaryForeground).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(setting.value).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.65)
        }
        .font(.system(size: fontSize, design: .rounded))
    }
}

struct RecipeCardPNGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    static var writableContentTypes: [UTType] { [.png] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct RecipeCardPNGShareItem: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
    }
}

@MainActor struct RecipeShareCardEditorView: View {
    let recipe: RecipeTransport

    @Environment(\.dismiss) private var dismiss
    @State private var layout: RecipeCardLayout = .darkroom
    @State private var crop: RecipeCardCrop = .center
    @State private var detail: RecipeCardDetail = .summary
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var renderedData: Data?
    @State private var document: RecipeCardPNGDocument?
    @State private var isExporting = false
    @State private var isLoadingPhoto = false
    @State private var message: String?

    private var content: RecipeShareCardContent { RecipeShareCardContent.make(from: recipe) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let photo {
                    RecipeShareCardCanvasPreview(content: content, photo: photo, layout: layout, crop: crop, detail: detail)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Preview of the recipe share card")
                } else if isLoadingPhoto {
                    ProgressView("Loading recipe photo…").frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ContentUnavailableView(
                        "Choose a photo", systemImage: "photo",
                        description: Text("Select a recipe image or choose one from your photo library.")
                    ).frame(maxWidth: .infinity, minHeight: 220)
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Picker("Layout", selection: $layout) {
                    ForEach(RecipeCardLayout.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Crop focus", selection: $crop) {
                    ForEach(RecipeCardCrop.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Settings shown", selection: $detail) {
                    ForEach(RecipeCardDetail.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)

                Button(action: renderCard) {
                    Label("Create card image", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let renderedData {
                    ShareLink(item: RecipeCardPNGShareItem(data: renderedData), preview: SharePreview(recipe.name)) {
                        Label("Share image", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        document = RecipeCardPNGDocument(data: renderedData)
                        isExporting = true
                    } label: {
                        Label("Save image to Files", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Text(recipe.isPublished
                     ? "The card links to the public recipe."
                     : "This private card contains no recipe link or private image URL.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("recipe-card-privacy-note")
            }
            .padding()
        }
        .navigationTitle("Recipe card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        .task { await loadRecipePhoto() }
        .onChange(of: selectedPhoto) { _, item in Task { await loadSelectedPhoto(item) } }
        .onChange(of: layout) { _, _ in renderedData = nil }
        .onChange(of: crop) { _, _ in renderedData = nil }
        .onChange(of: detail) { _, _ in renderedData = nil }
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: .png,
            defaultFilename: RecipeShareCardRenderer.filename(for: recipe.name)
        ) { result in
            if case let .failure(error) = result { message = "The image could not be saved: \(error.localizedDescription)" }
        }
        .alert("Recipe card", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func renderCard() {
        do {
            renderedData = try RecipeShareCardRenderer.renderPNG(
                content: content, photo: photo, layout: layout, crop: crop, detail: detail
            )
        } catch { message = error.localizedDescription }
    }

    private func loadRecipePhoto() async {
        guard photo == nil else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        for image in recipe.images {
            guard let url = image.localURL ?? image.url else { continue }
            do {
                let data: Data
                if url.isFileURL { data = try Data(contentsOf: url) }
                else { (data, _) = try await URLSession.shared.data(from: url) }
                if let loaded = RecipeShareCardRenderer.decodePhoto(from: data) { photo = loaded; return }
            } catch { continue }
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = RecipeShareCardRenderer.decodePhoto(from: data) else {
                throw RecipeCardError.unableToRender
            }
            photo = image
            renderedData = nil
        } catch { message = "The selected photo could not be loaded: \(error.localizedDescription)" }
    }
}

private struct RecipeShareCardCanvasPreview: View {
    let content: RecipeShareCardContent
    let photo: UIImage
    let layout: RecipeCardLayout
    let crop: RecipeCardCrop
    let detail: RecipeCardDetail

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 360, 1)
            RecipeShareCardCanvas(content: content, photo: photo, layout: layout, crop: crop, detail: detail)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: 360, height: 450, alignment: .topLeading)
        }
            .aspectRatio(0.8, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
}
