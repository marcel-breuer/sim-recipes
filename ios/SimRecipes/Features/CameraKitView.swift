import Combine
import SwiftUI

enum CameraKitSlotResult: Equatable {
    case waiting
    case writing
    case verified
    case failed(String)
    case unknown(String)
    case stopped
}

struct CameraKitItem: Equatable, Identifiable {
    let recipe: RecipeTransport
    var slot: CameraSlot?
    var preflight: CameraPreflightResult?
    var result: CameraKitSlotResult = .waiting

    var id: String { recipe.id }
}

enum CameraKitMappingValidator {
    static func hasUniqueSlots(_ assignments: [String: CameraSlot]) -> Bool {
        Set(assignments.values).count == assignments.count
    }
}

@MainActor
final class CameraKitViewModel: ObservableObject {
    @Published private(set) var items: [CameraKitItem] = []
    @Published private(set) var cameras: [CameraDescriptor] = []
    @Published private(set) var connectedCameraName: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?
    @Published private(set) var hasStopped = false
    @Published private(set) var unverifiedSlotContents: Set<CameraSlot> = []

    let collectionName: String
    private let collection: RecipeCollectionTransport
    private let localStore: LocalRecipeStore
    private let cameraService: any CameraService
    private let capabilityService: CameraCapabilityService
    private var activeCameraID: String?

    init(
        collection: RecipeCollectionTransport,
        localStore: LocalRecipeStore,
        cameraService: any CameraService,
        capabilityService: CameraCapabilityService
    ) {
        self.collection = collection
        self.collectionName = collection.name
        self.localStore = localStore
        self.cameraService = cameraService
        self.capabilityService = capabilityService
    }

    var canInstallNext: Bool {
        guard !hasStopped, connectedCameraName != nil,
              let next = items.first(where: { $0.result == .waiting }) else { return false }
        let assignments = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.slot.map { (item.id, $0) }
        })
        return next.slot != nil && next.preflight?.isTransferSafe == true
            && CameraKitMappingValidator.hasUniqueSlots(assignments)
    }

    var hasDuplicateSlots: Bool {
        let assignments = items.compactMap(\.slot)
        return Set(assignments).count != assignments.count
    }

    var nextItem: CameraKitItem? {
        items.first(where: { $0.result == .waiting })
    }

    func load() async {
        do {
            items = try collection.recipes.compactMap { member in
                guard let recipe = try localStore.recipe(id: member.id) else { return nil }
                return CameraKitItem(recipe: recipe)
            }
            guard !items.isEmpty else {
                errorMessage = "No recipes from this collection are available offline. Save them to your library first."
                return
            }
            let supported = try await capabilityService.supportedCameras()
            for index in items.indices {
                guard let camera = supported.first(where: {
                    $0.id == items[index].recipe.cameraModelID || $0.slug == items[index].recipe.cameraModelID
                }) else { continue }
                items[index].preflight = CameraCompatibilityEvaluator.evaluate(
                    recipe: items[index].recipe,
                    camera: camera
                )
            }
        } catch {
            errorMessage = "Camera compatibility could not be checked: \(error.localizedDescription)"
        }
    }

    func assign(_ slot: CameraSlot?, to recipeID: String) {
        guard let index = items.firstIndex(where: { $0.id == recipeID }),
              items[index].result == .waiting else { return }
        items[index].slot = slot
    }

    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            try await cameraService.requestControlAuthorization()
            cameraService.startDiscovery()
            try await Task.sleep(for: .seconds(1))
            cameras = cameraService.discoveredCameras.filter(\.isX20Candidate)
            guard !cameras.isEmpty else {
                errorMessage = "No supported X-S20 was found. Connect it by USB-C, unlock it, and check its USB mode."
                return
            }
            try await open(cameras[0])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ camera: CameraDescriptor) async throws {
        try await cameraService.openSession(for: camera.id)
        activeCameraID = camera.id
        connectedCameraName = camera.name
        let slots = try await cameraService.availableSlots()
        unverifiedSlotContents = Set(slots)
        notice = "Slot contents are not verified. Confirm each overwrite and select the mapped C-slot on the camera before continuing."
    }

    func writeNextAfterConfirmation() async {
        guard let next = nextItem, let slot = next.slot,
              next.preflight?.isTransferSafe == true else { return }
        guard items.filter({ $0.slot == slot }).count == 1 else {
            errorMessage = "Each recipe must be mapped to a different camera slot."
            return
        }

        guard activeCameraID != nil else {
            errorMessage = "Connect the camera before installing the kit."
            return
        }

        do {
            let selected = try await cameraService.readCurrentSlotSnapshot(propertyCodes: [])
            guard selected.slot == slot else {
                errorMessage = "Select C\(slot.rawValue) on the camera, then retry. The app will not change the camera slot automatically."
                return
            }
        } catch {
            errorMessage = "The selected camera slot could not be verified: \(error.localizedDescription)"
            return
        }

        guard let index = items.firstIndex(where: { $0.id == next.id }) else { return }
        items[index].result = .writing
        errorMessage = nil
        do {
            let snapshot = try await cameraService.transferRecipe(
                next.recipe,
                to: slot,
                confirmation: CameraSlotOverwriteConfirmation(slot: slot)
            )
            guard snapshot.slot == slot else {
                items[index].result = .unknown("The camera response reported a different slot.")
                return
            }
            items[index].result = .verified
            unverifiedSlotContents.remove(slot)
        } catch CameraServiceError.recipeTransferEncodingUnavailable {
            items[index].result = .failed("Recipe transfer encoding is not verified for this camera. No write was attempted.")
        } catch {
            // A protocol error after sending a mutation may not prove whether the camera applied it.
            items[index].result = .unknown(error.localizedDescription)
        }
    }

    func stopBeforeNextSlot() {
        hasStopped = true
        for index in items.indices where items[index].result == .waiting {
            items[index].result = .stopped
        }
        notice = "Stopped. No additional slot was written."
    }

    func close() async {
        guard activeCameraID != nil else { return }
        try? await cameraService.closeSession()
        activeCameraID = nil
        connectedCameraName = nil
    }
}

struct CameraKitCollectionPickerView: View {
    let collections: [RecipeCollectionTransport]
    let localStore: LocalRecipeStore
    let cameraService: any CameraService
    let capabilityService: CameraCapabilityService

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if collections.isEmpty {
                ContentUnavailableView(
                    "No collections",
                    systemImage: "folder",
                    description: Text("Create a collection or save a public collection before building a camera kit.")
                )
            }
            ForEach(collections) { collection in
                NavigationLink {
                    CameraKitInstallView(
                        collection: collection,
                        localStore: localStore,
                        cameraService: cameraService,
                        capabilityService: capabilityService
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(collection.name).font(.headline)
                        Text("\(collection.recipes.count) recipes · saved locally for offline use")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Choose a camera kit")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}

struct CameraKitInstallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: CameraKitViewModel
    @State private var confirmingItem: CameraKitItem?

    init(
        collection: RecipeCollectionTransport,
        localStore: LocalRecipeStore,
        cameraService: any CameraService,
        capabilityService: CameraCapabilityService
    ) {
        _model = StateObject(wrappedValue: CameraKitViewModel(
            collection: collection,
            localStore: localStore,
            cameraService: cameraService,
            capabilityService: capabilityService
        ))
    }

    var body: some View {
        List {
            Section("Connection") {
                if let connectedCameraName = model.connectedCameraName {
                    Label("Connected: \(connectedCameraName)", systemImage: "camera.fill")
                } else {
                    Button {
                        Task { await model.connect() }
                    } label: {
                        if model.isConnecting { ProgressView("Finding camera…") }
                        else { Label("Connect X-S20 over USB-C", systemImage: "cable.connector") }
                    }
                    .disabled(model.isConnecting)
                }
            }

            if let notice = model.notice {
                Section("Before installing") { Label(notice, systemImage: "exclamationmark.triangle") }
            }

            Section("Map recipes to camera slots") {
                if model.items.isEmpty {
                    ProgressView("Loading saved recipes…")
                }
                ForEach(model.items) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(item.recipe.name).font(.headline)
                            Spacer()
                            statusLabel(item.result)
                        }
                        HStack {
                            Text("Target slot")
                            Spacer()
                            Picker("Target slot", selection: Binding(
                                get: { item.slot },
                                set: { model.assign($0, to: item.id) }
                            )) {
                                Text("Choose…").tag(CameraSlot?.none)
                                ForEach(CameraSlot.allCases, id: \.rawValue) { slot in
                                    Text("C\(slot.rawValue)").tag(CameraSlot?.some(slot))
                                }
                            }
                            .labelsHidden()
                            .disabled(item.result != .waiting)
                        }
                        if let preflight = item.preflight, !preflight.isTransferSafe {
                            ForEach(preflight.issues) { issue in
                                Label("\(issue.displayName): \(issue.detail)", systemImage: "xmark.octagon")
                                    .font(.caption).foregroundStyle(.red)
                            }
                        } else if item.preflight == nil {
                            Label("Compatibility is not available offline for this recipe.", systemImage: "questionmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let slot = item.slot {
                            Label("C\(slot.rawValue) contents: unknown; overwrite confirmation required", systemImage: "questionmark.folder")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if model.hasDuplicateSlots {
                    Label("Assign each recipe to a different camera slot.", systemImage: "arrow.triangle.branch")
                        .foregroundStyle(.orange)
                }
            }

            if let next = model.nextItem, let slot = next.slot, model.canInstallNext {
                Section {
                    Button(role: .destructive) { confirmingItem = next } label: {
                        Label("Review overwrite for C\(slot.rawValue)", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.items.filter { $0.slot == slot }.count != 1)
                    Button("Stop before next slot", role: .cancel) { model.stopBeforeNextSlot() }
                } footer: {
                    Text("Only the next mapped recipe can be transferred. Review and confirm every slot individually.")
                }
            }

            if let errorMessage = model.errorMessage {
                Section("Status") { Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
        }
        .navigationTitle("Install camera kit")
        .task { await model.load() }
        .confirmationDialog(
            "Overwrite C\(confirmingItem?.slot?.rawValue ?? 0)?",
            isPresented: Binding(get: { confirmingItem != nil }, set: { if !$0 { confirmingItem = nil } }),
            titleVisibility: .visible
        ) {
            Button("Confirm overwrite and transfer", role: .destructive) {
                confirmingItem = nil
                Task { await model.writeNextAfterConfirmation() }
            }
            Button("Cancel", role: .cancel) { confirmingItem = nil }
        } message: {
            Text("The current contents of this slot may be replaced. Back them up first. The app will report unknown or failed results without claiming success.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    Task { await model.close(); dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ result: CameraKitSlotResult) -> some View {
        switch result {
        case .waiting: Text("Not started").foregroundStyle(.secondary)
        case .writing: ProgressView()
        case .verified: Label("Verified", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case let .failed(message): Label("Failed: \(message)", systemImage: "xmark.circle").foregroundStyle(.red)
        case let .unknown(message): Label("Unknown: \(message)", systemImage: "questionmark.circle").foregroundStyle(.orange)
        case .stopped: Text("Not attempted").foregroundStyle(.secondary)
        }
    }
}
