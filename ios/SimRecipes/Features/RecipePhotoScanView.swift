import PhotosUI
import SwiftUI
import UIKit

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
