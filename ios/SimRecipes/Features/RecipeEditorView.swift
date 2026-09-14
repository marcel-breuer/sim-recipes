import PhotosUI
import SwiftUI
import UIKit

struct RecipeEditorView: View {
    @StateObject private var viewModel: RecipeEditorViewModel
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPublishConfirmation = false

    init(viewModel: RecipeEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.canEdit {
                editorForm
            } else {
                ContentUnavailableView(
                    "Published recipe",
                    systemImage: "lock.fill",
                    description: Text("Published recipes are immutable. Duplicate this recipe to make changes.")
                )
            }
        }
        .navigationTitle(viewModel.draft.id == nil ? "New Recipe" : "Edit Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .alert("Recipe Editor", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
        .confirmationDialog(
            "Publish recipe?",
            isPresented: $showPublishConfirmation,
            titleVisibility: .visible
        ) {
            Button("Publish", role: .destructive) {
                viewModel.startPublish()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Publishing makes this recipe public and immutable. You will need to duplicate it to make future changes.")
        }
    }

    private var editorForm: some View {
        Form {
            Section("Recipe") {
                TextField("Name", text: $viewModel.draft.name)
                    .textInputAutocapitalization(.words)
                TextField("Description", text: $viewModel.draft.description, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Style or recommendation", text: $viewModel.draft.recommendation, axis: .vertical)
                    .lineLimit(2...5)
                TextField("Lens (optional)", text: $viewModel.draft.lens)
            }

            Section("Camera") {
                if viewModel.cameras.isEmpty {
                    ProgressView("Loading supported cameras…")
                } else {
                    Picker("Camera", selection: $viewModel.draft.cameraModelID) {
                        ForEach(viewModel.cameras) { camera in
                            Text(camera.name).tag(camera.id)
                        }
                    }
                    .onChange(of: viewModel.draft.cameraModelID) {
                        Task { await viewModel.cameraDidChange() }
                    }
                }
            }

            Section("Categories") {
                if viewModel.categories.isEmpty {
                    Text("Categories are unavailable until the API is reachable.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading) {
                        ForEach(viewModel.categories) { category in
                            Button {
                                toggleCategory(category.name)
                            } label: {
                                Text(category.name)
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        viewModel.draft.categories.contains(category.name)
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(
                                        viewModel.draft.categories.contains(category.name)
                                            ? .white
                                            : .primary
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Tags") {
                TextField("street, muted, daylight", text: tagsBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Separate tags with commas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("X-S20 settings") {
                if viewModel.capabilities.isEmpty {
                    ProgressView("Loading camera settings…")
                } else {
                    ForEach(viewModel.capabilities) { capability in
                        RecipeSettingEditorRow(
                            capability: capability,
                            value: settingBinding(for: capability.key)
                        )
                    }
                }
            }

            Section("Visual preview") {
                if let imageData = viewModel.draft.images.first?.data,
                   !viewModel.capabilities.isEmpty {
                    RecipePreviewView(
                        imageData: imageData,
                        settings: viewModel.draft.settings,
                        capabilities: viewModel.capabilities
                    )
                } else if viewModel.draft.images.isEmpty {
                    Label(
                        "Select an example image below to preview this local draft.",
                        systemImage: "photo.on.rectangle"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        "Preview controls are loading for the selected camera.",
                        systemImage: "camera.aperture"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section("Example images") {
                if viewModel.draft.totalImageCount > 0 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.draft.images) { image in
                                ZStack(alignment: .topTrailing) {
                                    if let uiImage = UIImage(data: image.data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 110, height: 110)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    Button {
                                        viewModel.removePhoto(image)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.65))
                                    }
                                    .padding(5)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: max(1, 5 - viewModel.draft.totalImageCount),
                    matching: .images
                ) {
                    Label("Add example images", systemImage: "photo.on.rectangle.angled")
                }
                .onChange(of: selectedPhotoItems) {
                    let items = selectedPhotoItems
                    selectedPhotoItems = []
                    Task {
                        var imageData: [Data] = []
                        for item in items {
                            do {
                                if let data = try await item.loadTransferable(type: Data.self) {
                                    imageData.append(data)
                                }
                            } catch {
                                viewModel.errorMessage = "The selected image could not be loaded."
                            }
                        }
                        viewModel.addPhotos(imageData)
                    }
                }

                Text("Up to five images. Originals are retained securely when the recipe is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isUploadInProgress {
                Section("Upload") {
                    if case .preparing = viewModel.uploadState {
                        ProgressView("Preparing images…")
                    } else {
                        ProgressView(value: viewModel.uploadProgress) {
                            Text("Uploading images…")
                        }
                        Text("\(Int(viewModel.uploadProgress * 100))% complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Cancel upload", role: .cancel) {
                        viewModel.cancelUpload()
                    }
                }
            } else if viewModel.canRetryUpload {
                Section("Upload") {
                    Text("The upload failed. Check your connection or storage quota and try again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry upload") {
                        viewModel.retryUpload()
                    }
                }
            }

            Section {
                Button("Save Draft Offline") {
                    viewModel.saveDraftLocally()
                }

                Button("Save Private Recipe") {
                    viewModel.startSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSaving || viewModel.isLoading)

                Button("Publish Recipe") {
                    showPublishConfirmation = true
                }
                .disabled(viewModel.isSaving || viewModel.isLoading)
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { viewModel.draft.tags.joined(separator: ", ") },
            set: { value in
                viewModel.draft.tags = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func settingBinding(for key: String) -> Binding<JSONValue> {
        Binding(
            get: { viewModel.value(for: key) },
            set: { viewModel.setSetting($0, for: key) }
        )
    }

    private func toggleCategory(_ category: String) {
        if let index = viewModel.draft.categories.firstIndex(of: category) {
            viewModel.draft.categories.remove(at: index)
        } else if viewModel.draft.categories.count < 10 {
            viewModel.draft.categories.append(category)
        }
    }
}

private struct RecipeSettingEditorRow: View {
    let capability: CameraCapabilityTransport
    @Binding var value: JSONValue

    var body: some View {
        switch capability.valueType {
        case "enum":
            enumEditor
        case "integer":
            integerEditor
        case "decimal":
            decimalEditor
        case "boolean":
            Toggle(capability.displayName, isOn: booleanBinding)
        case "object":
            objectEditor
        default:
            TextField(capability.displayName, text: stringBinding)
        }
    }

    private var enumEditor: some View {
        let options = allowedStringValues
        return Group {
            if options.isEmpty {
                TextField(capability.displayName, text: stringBinding)
            } else {
                Picker(capability.displayName, selection: stringBinding) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
        }
    }

    private var integerEditor: some View {
        let lower = Int(capability.minimum ?? -100)
        let upper = Int(capability.maximum ?? 100)
        let step = max(1, Int(capability.step ?? 1))
        return Stepper(
            "\(capability.displayName): \(Int(value.numberValue ?? Double(lower)))",
            value: integerBinding,
            in: lower...upper,
            step: step
        )
    }

    private var decimalEditor: some View {
        TextField(capability.displayName, value: decimalBinding, format: .number)
            .keyboardType(.decimalPad)
    }

    private var objectEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(capability.displayName)
                .font(.headline)
            if case let .object(fields) = capability.allowedValues {
                let keys = objectFieldKeys(from: fields)
                ForEach(keys, id: \.self) { key in
                    objectField(key: key, allowed: fields[key])
                }
            } else {
                Text("This setting is managed by the camera capability model.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func objectField(key: String, allowed: JSONValue?) -> some View {
        if case let .array(options) = allowed {
            let strings = options.compactMap(\.stringValue)
            if !strings.isEmpty {
                Picker(key.replacingOccurrences(of: "_", with: " ").capitalized, selection: objectStringBinding(for: key, fallback: strings[0])) {
                    ForEach(strings, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            } else {
                numericObjectField(key: key)
            }
        } else {
            numericObjectField(key: key)
        }
    }

    private func numericObjectField(key: String) -> some View {
        Stepper(
            "\(key.replacingOccurrences(of: "_", with: " ").capitalized): \(Int(objectNumberValue(for: key)))",
            value: objectNumberBinding(for: key),
            in: Int(capability.minimum ?? -9)...Int(capability.maximum ?? 9)
        )
    }

    private var allowedStringValues: [String] {
        guard case let .array(values) = capability.allowedValues else { return [] }
        return values.compactMap(\.stringValue)
    }

    private func objectFieldKeys(from fields: [String: JSONValue]) -> [String] {
        if case let .array(axes) = fields["axes"] {
            return axes.compactMap(\.stringValue).sorted()
        }
        return fields.keys.sorted()
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { value.stringValue ?? "" },
            set: { value = .string($0) }
        )
    }

    private var booleanBinding: Binding<Bool> {
        Binding(
            get: { if case let .boolean(value) = value { return value }; return false },
            set: { value = .boolean($0) }
        )
    }

    private var integerBinding: Binding<Int> {
        Binding(
            get: { Int(value.numberValue ?? capability.minimum ?? 0) },
            set: { value = .number(Double($0)) }
        )
    }

    private var decimalBinding: Binding<Double> {
        Binding(
            get: { value.numberValue ?? capability.minimum ?? 0 },
            set: { value = .number($0) }
        )
    }

    private func objectValue(for key: String) -> JSONValue {
        guard case let .object(values) = value else { return .null }
        return values[key] ?? .null
    }

    private func objectStringBinding(for key: String, fallback: String) -> Binding<String> {
        Binding(
            get: { objectValue(for: key).stringValue ?? fallback },
            set: { setObjectValue(.string($0), for: key) }
        )
    }

    private func objectNumberValue(for key: String) -> Double {
        objectValue(for: key).numberValue ?? capability.minimum ?? 0
    }

    private func objectNumberBinding(for key: String) -> Binding<Int> {
        Binding(
            get: { Int(objectNumberValue(for: key)) },
            set: { setObjectValue(.number(Double($0)), for: key) }
        )
    }

    private func setObjectValue(_ newValue: JSONValue, for key: String) {
        var values: [String: JSONValue]
        if case let .object(existing) = value {
            values = existing
        } else {
            values = [:]
        }
        values[key] = newValue
        value = .object(values)
    }
}
