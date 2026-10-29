import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecipePhotoScanView: View {
    let initialCameraID: String
    let loadCameras: () async throws -> [SupportedCameraTransport]
    let loadCapabilities: (String) async throws -> [CameraCapabilityTransport]
    let onApply: (String, [RecipeSettingTransport]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameras: [SupportedCameraTransport] = []
    @State private var capabilities: [CameraCapabilityTransport] = []
    @State private var cameraID = ""
    @State private var fields: [RecipeScanField] = []
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isScanning = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Scan a recipe photo on this iPhone. The image is used only for text recognition and is discarded afterward.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Target camera", selection: $cameraID) {
                        ForEach(cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                    .disabled(cameras.isEmpty || isScanning)
                }

                Section("Recipe image") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose from photo library", systemImage: "photo")
                    }
                    .disabled(cameraID.isEmpty || isScanning)
                    .onChange(of: selectedPhoto) {
                        let item = selectedPhoto
                        selectedPhoto = nil
                        Task { await scan(item) }
                    }

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take a photo", systemImage: "camera")
                        }
                        .disabled(cameraID.isEmpty || isScanning)
                    }

                    if isScanning { ProgressView("Recognizing text on this iPhone…") }
                }

                if !fields.isEmpty {
                    Section {
                        Text("Review every field against the source recipe. Unknown and uncertain values are never applied automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach($fields) { $field in
                            RecipeScanFieldRow(field: $field, capabilities: capabilities) {
                                recheck(field.id)
                            }
                        }
                    } header: {
                        Text("Review \(fields.count) recognized fields")
                    } footer: {
                        Text("Scanning creates no saved, published, uploaded, or camera-installed recipe. Verify all settings before saving the draft.")
                    }

                    Section {
                        Button("Apply selected settings to draft") {
                            Task {
                                await onApply(cameraID, selectedSettings)
                                dismiss()
                            }
                        }
                        .disabled(selectedSettings.isEmpty || hasSelectedDuplicates)
                    }
                }
            }
            .navigationTitle("Scan Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadInitialData() }
            .onChange(of: cameraID) {
                Task { await changeCamera() }
            }
            .sheet(isPresented: $showCamera) {
                CameraPhotoPicker { image in
                    showCamera = false
                    guard let image, let data = image.jpegData(compressionQuality: 0.92) else { return }
                    Task { await scan(data: data) }
                }
                .ignoresSafeArea()
            }
            .alert("Recipe Scan", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var selectedSettings: [RecipeSettingTransport] {
        fields.compactMap { field in
            guard field.isSelected, let key = field.capabilityKey, let value = field.settingValue else { return nil }
            return RecipeSettingTransport(key: key, value: value)
        }
    }

    private var hasSelectedDuplicates: Bool {
        let keys = selectedSettings.map(\.key)
        return Set(keys).count != keys.count
    }

    private func loadInitialData() async {
        do {
            cameras = try await loadCameras()
            cameraID = cameras.first(where: { $0.id == initialCameraID })?.id ?? cameras.first?.id ?? ""
            await changeCamera()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeCamera() async {
        guard !cameraID.isEmpty else { capabilities = []; return }
        do {
            capabilities = try await loadCapabilities(cameraID)
            fields = fields.map { field in
                var updated = RecipeScanParser.resolve(
                    label: field.label, rawValue: field.rawValue, sourceText: field.sourceText,
                    confidence: field.confidence, capabilities: capabilities
                )
                updated.isSelected = field.isSelected && updated.settingValue != nil
                updated = preservingIdentity(updated, from: field)
                return updated
            }
            markDuplicates()
        } catch {
            capabilities = []
            errorMessage = error.localizedDescription
        }
    }

    private func scan(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "The selected photo could not be read."
                return
            }
            await scan(data: data)
        } catch {
            errorMessage = "The selected photo could not be read."
        }
    }

    private func scan(data: Data) async {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            errorMessage = "The selected file is not a supported image."
            return
        }
        isScanning = true
        defer { isScanning = false }
        do {
            let lines = try await Task.detached(priority: .userInitiated) {
                try RecipePhotoTextRecognizer.recognize(cgImage: cgImage)
            }.value
            fields = RecipeScanParser.parse(lines, capabilities: capabilities)
            if fields.isEmpty { errorMessage = "No recipe settings were recognized. Try a sharper photo with readable setting labels." }
        } catch {
            errorMessage = "Text recognition failed. Try another photo."
        }
    }

    private func recheck(_ id: UUID) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        let previous = fields[index]
        var updated = RecipeScanParser.resolve(
            label: previous.label, rawValue: previous.rawValue, sourceText: previous.sourceText,
            confidence: previous.confidence, capabilities: capabilities
        )
        updated = preservingIdentity(updated, from: previous)
        fields[index] = updated
        markDuplicates()
    }

    private func markDuplicates() {
        for index in fields.indices {
            let previous = fields[index]
            var resolved = RecipeScanParser.resolve(
                label: previous.label, rawValue: previous.rawValue, sourceText: previous.sourceText,
                confidence: previous.confidence, capabilities: capabilities
            )
            resolved.isSelected = previous.isSelected && resolved.settingValue != nil
            fields[index] = preservingIdentity(resolved, from: previous)
        }
        let counts = Dictionary(grouping: fields.compactMap(\.capabilityKey), by: { $0 }).mapValues(\.count)
        for index in fields.indices where fields[index].capabilityKey.map({ counts[$0, default: 0] > 1 }) == true {
            fields[index].status = .duplicate
            fields[index].isSelected = false
        }
    }

    private func preservingIdentity(_ field: RecipeScanField, from previous: RecipeScanField) -> RecipeScanField {
        RecipeScanField(id: previous.id, label: field.label, rawValue: field.rawValue,
                        sourceText: previous.sourceText, confidence: previous.confidence,
                        capabilityKey: field.capabilityKey, settingValue: field.settingValue,
                        status: field.status, isSelected: field.isSelected)
    }
}

private struct RecipeScanFieldRow: View {
    @Binding var field: RecipeScanField
    let capabilities: [CameraCapabilityTransport]
    let recheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $field.isSelected) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.capabilityKey.flatMap { key in capabilities.first(where: { $0.key == key })?.displayName } ?? "Unmatched setting")
                        .font(.subheadline.weight(.semibold))
                    Text("\(statusTitle) · \(Int(field.confidence * 100))% confidence")
                        .font(.caption)
                        .foregroundStyle(field.status == .ready ? Color.secondary : Color.orange)
                }
            }
            .disabled(field.settingValue == nil)

            TextField("Setting label", text: $field.label)
                .textInputAutocapitalization(.words)
                .onChange(of: field.label) {
                    field.settingValue = nil
                    field.isSelected = false
                }
            Text("Source: \(field.sourceText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let capability = capabilities.first(where: { $0.key == field.capabilityKey }),
               capability.valueType == "enum",
               case let .array(values)? = capability.allowedValues {
                Picker("Value", selection: valueBinding) {
                    Text("Choose recognized value").tag(field.rawValue)
                    ForEach(values.compactMap(\.stringValue), id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
            } else {
                TextField("Recognized value", text: $field.rawValue)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: field.rawValue) {
                        field.settingValue = nil
                        field.isSelected = false
                    }
            }

            Button("Check corrected field", action: recheck)
                .font(.caption.weight(.medium))
        }
        .padding(.vertical, 5)
    }

    private var statusTitle: String {
        switch field.status {
        case .ready: "Ready to review"
        case .lowConfidence: "Low confidence · confirm source"
        case .unknownLabel: "Unknown label · edit to match a camera setting"
        case .unsupportedValue: "Unsupported value · correct it before applying"
        case .ambiguous: "Ambiguous · resolve manually"
        case .duplicate: "Duplicate setting · choose one result"
        }
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: { field.rawValue },
            set: { value in
                field.rawValue = value
                field.settingValue = nil
                field.isSelected = false
            }
        )
    }
}

struct RecipeCaptureImportView: View {
    let initialCameraID: String
    let canAttachImage: Bool
    let loadCameras: () async throws -> [SupportedCameraTransport]
    let loadCapabilities: (String) async throws -> [CameraCapabilityTransport]
    let onApply: (String, RecipeCaptureMetadata, [RecipeSettingTransport], RecipeDraftImage?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameras: [SupportedCameraTransport] = []
    @State private var capabilities: [CameraCapabilityTransport] = []
    @State private var cameraID = ""
    @State private var result: RecipeCaptureImportResult?
    @State private var sourceData: Data?
    @State private var sourceFilename = "capture.jpg"
    @State private var fields: [RecipeScanField] = []
    @State private var lensText = ""
    @State private var sceneNotes = ""
    @State private var lightingNotes = ""
    @State private var attachSourceImage = false
    @State private var shareExactLocation = false
    @State private var showingFileImporter = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Metadata is read on this iPhone. The source JPEG stays local unless you choose to attach a sanitized copy to this draft.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Recipe camera", selection: $cameraID) {
                        ForEach(cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                    .disabled(cameras.isEmpty || isLoadingPhoto)
                    .onChange(of: cameraID) {
                        Task { await changeCamera() }
                    }
                }

                Section("Fujifilm JPEG") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo")
                    }
                    .disabled(isLoadingPhoto)
                    .onChange(of: selectedPhoto) {
                        let item = selectedPhoto
                        selectedPhoto = nil
                        Task { await importPhoto(item) }
                    }

                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Choose JPEG from Files", systemImage: "folder")
                    }
                    .disabled(isLoadingPhoto)

                    if isLoadingPhoto { ProgressView("Reading JPEG metadata locally…") }
                    if let result {
                        Label(
                            result.isFujifilmJPEG ? "Fujifilm camera metadata found" : "Fujifilm camera not identified",
                            systemImage: result.isFujifilmJPEG ? "checkmark.seal" : "questionmark.circle"
                        )
                        .foregroundStyle(result.isFujifilmJPEG ? Color.primary : Color.orange)
                        if let model = result.metadata.cameraModel {
                            LabeledContent("Camera in JPEG", value: model)
                        }
                        if let make = result.metadata.cameraMake {
                            LabeledContent("Manufacturer", value: make)
                        }
                        if let lens = result.metadata.lensModel {
                            TextField("Lens", text: $lensText)
                                .textInputAutocapitalization(.words)
                        }
                        if let exposure = result.metadata.exposure, !exposure.summary.isEmpty {
                            LabeledContent("Capture settings", value: exposure.summary.joined(separator: " · "))
                                .font(.subheadline)
                        }
                        if !result.isFujifilmJPEG {
                            Text("Recipe settings were not inferred because the file does not identify a Fujifilm camera.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let result {
                    Section {
                        Text("Only values that match this camera’s capability data are selected. Unsupported, missing, and ambiguous values remain unselected for review.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if fields.isEmpty {
                            Text("No supported recipe settings were found in the JPEG MakerNotes. You can still attach the photo and add context.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach($fields) { $field in
                            RecipeCaptureSettingReviewRow(field: $field, capabilities: capabilities) {
                                recheck(field.id)
                            }
                        }
                    } header: {
                        Text("Review \(fields.count) camera settings")
                    }

                    Section("Scene and lighting notes") {
                        TextField("Scene or subject", text: $sceneNotes, axis: .vertical)
                            .lineLimit(2...4)
                        TextField("Lighting", text: $lightingNotes, axis: .vertical)
                            .lineLimit(2...4)
                        Text("These notes are supplied by you; they are not extracted from the JPEG.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Notes are retained with the example image, so attach the sanitized copy to keep them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Example image privacy") {
                        Toggle("Attach a sanitized copy to this recipe draft", isOn: $attachSourceImage)
                            .disabled(sourceData == nil || !canAttachImage)
                        Text("The source file is never uploaded. The attached JPEG is re-encoded without its original EXIF or GPS metadata.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let location = result.metadata.location {
                            Toggle("Share exact GPS coordinates with this example", isOn: $shareExactLocation)
                                .disabled(!attachSourceImage)
                            if shareExactLocation {
                                Text("\(location.latitude), \(location.longitude)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                Text("This JPEG contains location data; it will not be shared.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !canAttachImage {
                            Text("This recipe already has the maximum of five example images.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Section {
                        Button("Apply reviewed data to draft") {
                            Task { await applyReviewedData() }
                        }
                        .disabled(isLoadingPhoto)
                    } footer: {
                        Text("Capture details and notes are retained with the example image. Nothing is uploaded until you choose a recipe editor action.")
                    }
                }
            }
            .navigationTitle("Import Capture Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadInitialData() }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.jpeg],
                allowsMultipleSelection: false
            ) { selection in
                switch selection {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    Task { await importFile(url) }
                case let .failure(error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Capture Import", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try another JPEG.")
            }
        }
    }

    private func loadInitialData() async {
        do {
            cameras = try await loadCameras()
            cameraID = cameras.first(where: { $0.id == initialCameraID })?.id ?? cameras.first?.id ?? ""
            await changeCamera()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeCamera() async {
        guard !cameraID.isEmpty else { capabilities = []; return }
        do {
            capabilities = try await loadCapabilities(cameraID)
            guard let sourceData else { return }
            result = try RecipeCaptureMetadataParser.parse(sourceData, capabilities: capabilities)
            fields = result?.fields ?? []
        } catch {
            capabilities = []
            errorMessage = error.localizedDescription
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "The selected JPEG could not be read."
                return
            }
            await inspect(data: data, filename: "capture.jpg")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            await inspect(data: data, filename: url.lastPathComponent)
        } catch {
            errorMessage = "The selected JPEG could not be read."
        }
    }

    private func inspect(data: Data, filename: String) async {
        guard data.count <= 25 * 1024 * 1024 else {
            errorMessage = "The JPEG must be 25 MB or smaller to import metadata."
            return
        }
        guard !capabilities.isEmpty else {
            errorMessage = "Camera capability data is not available. Connect to the API or choose a cached camera first."
            return
        }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            let cameraCapabilities = capabilities
            let imported = try await Task.detached(priority: .userInitiated) {
                try RecipeCaptureMetadataParser.parse(data, capabilities: cameraCapabilities)
            }.value
            sourceData = data
            sourceFilename = filename
            result = imported
            fields = imported.fields
            lensText = imported.metadata.lensModel ?? ""
            sceneNotes = ""
            lightingNotes = ""
            shareExactLocation = false
            attachSourceImage = false
        } catch {
            sourceData = nil
            result = nil
            fields = []
            errorMessage = error.localizedDescription
        }
    }

    private func recheck(_ id: UUID) {
        guard let index = fields.firstIndex(where: { $0.id == id }) else { return }
        let previous = fields[index]
        var updated = RecipeScanParser.resolve(
            label: previous.label,
            rawValue: previous.rawValue,
            sourceText: previous.sourceText,
            confidence: 1,
            capabilities: capabilities
        )
        updated = RecipeScanField(
            id: previous.id,
            label: updated.label,
            rawValue: updated.rawValue,
            sourceText: previous.sourceText,
            confidence: 1,
            capabilityKey: updated.capabilityKey,
            settingValue: updated.settingValue,
            status: updated.status,
            isSelected: updated.settingValue != nil
        )
        fields[index] = updated
    }

    private func applyReviewedData() async {
        guard var metadata = result?.metadata else { return }
        let selectedSettings = fields.compactMap { field -> RecipeSettingTransport? in
            guard field.isSelected, let key = field.capabilityKey, let value = field.settingValue else { return nil }
            return RecipeSettingTransport(key: key, value: value)
        }
        metadata.settings = fields.compactMap { field in
            guard field.isSelected, let key = field.capabilityKey, let value = field.settingValue else { return nil }
            let corrected = field.status == .ready && field.sourceText.contains("MakerNote")
                && field.sourceText.split(separator: ":").last.map(String.init)?.trimmingCharacters(in: .whitespaces) != field.rawValue
            return RecipeCaptureSetting(
                settingKey: key,
                value: value,
                source: corrected ? "user_corrected" : field.sourceText,
                wasEdited: corrected
            )
        }
        metadata.lensModel = lensText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : lensText.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.sceneNotes = trimmedNote(sceneNotes)
        metadata.lightingNotes = trimmedNote(lightingNotes)
        metadata.locationShared = attachSourceImage && shareExactLocation && metadata.location != nil
        if !metadata.locationShared { metadata.location = nil }

        var attachedImage: RecipeDraftImage?
        if attachSourceImage, let sourceData {
            do {
                attachedImage = try RecipeImagePreparer.prepare(
                    sourceData,
                    filename: sourceFilename,
                    captureMetadata: metadata
                )
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        await onApply(cameraID, metadata, selectedSettings, attachedImage)
        dismiss()
    }

    private func trimmedNote(_ value: String) -> String? {
        let note = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? nil : String(note.prefix(500))
    }
}

private struct RecipeCaptureSettingReviewRow: View {
    @Binding var field: RecipeScanField
    let capabilities: [CameraCapabilityTransport]
    let recheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: $field.isSelected) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.capabilityKey.flatMap { key in capabilities.first(where: { $0.key == key })?.displayName } ?? field.label)
                        .font(.subheadline.weight(.semibold))
                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(field.settingValue == nil ? Color.orange : Color.secondary)
                }
            }
            .disabled(field.settingValue == nil)

            Text("Source: \(field.sourceText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            TextField("Confirm or correct value", text: $field.rawValue)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: field.rawValue) {
                    field.settingValue = nil
                    field.isSelected = false
                }

            Button("Check value against camera settings", action: recheck)
                .font(.caption.weight(.medium))
        }
        .padding(.vertical, 5)
    }

    private var statusTitle: String {
        switch field.status {
        case .ready: "Matches a camera setting · review before applying"
        case .lowConfidence: "Needs confirmation"
        case .unknownLabel: "Unknown setting · not applied"
        case .unsupportedValue: "Unsupported value · correct before applying"
        case .ambiguous: "Ambiguous · select a setting manually"
        case .duplicate: "Duplicate setting · resolve manually"
        }
    }
}

private struct CameraPhotoPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCapture(nil) }
    }
}
