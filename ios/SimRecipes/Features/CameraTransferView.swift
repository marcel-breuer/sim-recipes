import Combine
import SwiftUI

enum CameraTransferPhase: Equatable {
    case idle
    case requestingAccess
    case discovering
    case connecting
    case loadingSlots
    case ready
    case transferring
    case succeeded
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .requestingAccess, .discovering, .connecting, .loadingSlots, .transferring:
            true
        case .idle, .ready, .succeeded, .failed:
            false
        }
    }
}

struct CameraSlotStatus: Equatable, Identifiable, Sendable {
    let slot: CameraSlot
    let isCurrent: Bool
    let propertyCount: Int?

    var id: UInt8 { slot.rawValue }

    var title: String {
        "C\(slot.rawValue)"
    }

    var detail: String {
        if isCurrent, let propertyCount {
            return propertyCount == 0
                ? "Currently selected · no readable settings"
                : "Currently selected · \(propertyCount) readable settings"
        }
        if isCurrent {
            return "Currently selected · contents not read"
        }
        return "Available on camera"
    }

    init(descriptor: CameraSlotDescriptor) {
        slot = descriptor.slot
        switch descriptor.readState {
        case let .readable(propertyCount):
            isCurrent = true
            self.propertyCount = propertyCount
        case .notSelected:
            isCurrent = false
            propertyCount = nil
        }
    }
}

@MainActor
final class CameraTransferViewModel: ObservableObject {
    let recipe: RecipeTransport

    @Published private(set) var phase: CameraTransferPhase = .idle
    @Published private(set) var cameras: [CameraDescriptor] = []
    @Published private(set) var slots: [CameraSlotStatus] = []
    @Published private(set) var currentSlot: CameraSlot?
    @Published private(set) var preflight: CameraPreflightResult?
    @Published private(set) var preflightError: String?
    @Published private(set) var resultMessage: String?
    @Published private(set) var errorMessage: String?
    @Published var selectedSlot: CameraSlot?
    @Published var showingOverwriteConfirmation = false

    private let cameraService: any CameraService
    private let capabilityService: CameraCapabilityService?
    private var activeCameraID: String?

    init(
        recipe: RecipeTransport,
        cameraService: any CameraService,
        capabilityService: CameraCapabilityService? = nil
    ) {
        self.recipe = recipe
        self.cameraService = cameraService
        self.capabilityService = capabilityService
    }

    var connectedCamera: CameraDescriptor? {
        guard let activeCameraID else { return nil }
        return cameras.first { $0.id == activeCameraID }
    }

    var canTransfer: Bool {
        phase == .ready && selectedSlot != nil && (capabilityService == nil || preflight?.isTransferSafe == true)
    }

    func start() async {
        guard phase == .idle || isFailed else { return }
        phase = .requestingAccess
        errorMessage = nil
        preflightError = nil
        resultMessage = nil

        do {
            await loadPreflight()
            try await cameraService.requestControlAuthorization()
            cameraService.startDiscovery()
            phase = .discovering
            await refreshDiscovery()
        } catch {
            fail(error)
        }
    }

    func refreshDiscovery() async {
        guard phase == .discovering || phase == .idle || isFailed else { return }
        phase = .discovering
        cameraService.startDiscovery()
        try? await Task.sleep(nanoseconds: 300_000_000)
        cameras = cameraService.discoveredCameras.filter(\.isX20Candidate)
    }

    func connect(to camera: CameraDescriptor) async {
        guard camera.isX20Candidate, canOpenCameraSession else { return }
        phase = .connecting
        errorMessage = nil
        resultMessage = nil

        do {
            try await cameraService.openSession(for: camera.id)
            activeCameraID = camera.id
            phase = .loadingSlots

            let slotDescriptors = try await cameraService.readSlotDescriptors(propertyCodes: [])
            currentSlot = slotDescriptors.first(where: { descriptor in
                if case .readable = descriptor.readState {
                    return true
                }
                return false
            })?.slot
            slots = slotDescriptors.map(CameraSlotStatus.init(descriptor:))
            selectedSlot = currentSlot ?? slotDescriptors.first?.slot
            phase = .ready
        } catch {
            fail(error)
            try? await cameraService.closeSession()
            activeCameraID = nil
        }
    }

    func requestTransfer() {
        guard canTransfer else { return }
        // Confirmation is required even when the adapter cannot currently read
        // the target contents. The camera must never be overwritten implicitly.
        showingOverwriteConfirmation = true
    }

    func confirmTransfer() async {
        guard let selectedSlot, canTransfer else { return }
        showingOverwriteConfirmation = false
        phase = .transferring
        errorMessage = nil
        resultMessage = nil

        do {
            let confirmation = CameraSlotOverwriteConfirmation(slot: selectedSlot)
            _ = try await cameraService.transferRecipe(
                recipe,
                to: selectedSlot,
                confirmation: confirmation
            )
            phase = .succeeded
            resultMessage = "\(recipe.name) was verified in C\(selectedSlot.rawValue)."
        } catch {
            // Only a verified adapter result can reach the success state.
            fail(error)
        }
    }

    func retry() async {
        guard !phase.isBusy else { return }
        if activeCameraID != nil {
            await loadPreflight()
            phase = .ready
            errorMessage = nil
            resultMessage = nil
        } else {
            phase = .idle
            await start()
        }
    }

    func close() async {
        guard activeCameraID != nil else { return }
        try? await cameraService.closeSession()
        activeCameraID = nil
        phase = .idle
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private var canOpenCameraSession: Bool {
        switch phase {
        case .discovering, .ready, .succeeded, .failed:
            true
        case .idle, .requestingAccess, .connecting, .loadingSlots, .transferring:
            false
        }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        phase = .failed(error.localizedDescription)
    }

    private func loadPreflight() async {
        guard let capabilityService else { return }

        do {
            let cameras = try await capabilityService.supportedCameras()
            guard let camera = cameras.first(where: {
                $0.id == recipe.cameraModelID || $0.slug == recipe.cameraModelID
            }) else {
                preflight = nil
                preflightError = "No capability catalog is available for \(recipe.cameraModelName ?? recipe.cameraModelID)."
                return
            }
            preflight = CameraCompatibilityEvaluator.evaluate(recipe: recipe, camera: camera)
            preflightError = nil
        } catch {
            preflight = nil
            preflightError = "Compatibility could not be verified: \(error.localizedDescription)"
        }
    }
}

struct CameraTransferView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CameraTransferViewModel

    init(
        recipe: RecipeTransport,
        cameraService: any CameraService,
        capabilityService: CameraCapabilityService? = nil
    ) {
        _viewModel = StateObject(wrappedValue: CameraTransferViewModel(
            recipe: recipe,
            cameraService: cameraService,
            capabilityService: capabilityService
        ))
    }

    var body: some View {
        transferList
        .navigationTitle("Transfer to Camera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    Task {
                        await viewModel.close()
                        dismiss()
                    }
                }
                .disabled(viewModel.phase.isBusy)
            }
        }
        .confirmationDialog(
            "Overwrite C\(viewModel.selectedSlot?.rawValue ?? 0)?",
            isPresented: $viewModel.showingOverwriteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Transfer and overwrite", role: .destructive) {
                Task { await viewModel.confirmTransfer() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected custom-setting slot may contain camera settings. Continue only if you want to replace them with this recipe.")
        }
        .task {
            await viewModel.start()
        }
        .onDisappear {
            Task { await viewModel.close() }
        }
    }

    private var transferList: some View {
        List {
            recipeSection
            preflightSection
            connectionSection
            slotSection
            actionSection
        }
    }

    @ViewBuilder
    private var preflightSection: some View {
        Section("Transfer preflight") {
            if let preflight = viewModel.preflight {
                if preflight.isTransferSafe {
                    Label(
                        "All recipe settings are supported by \(preflight.cameraName).",
                        systemImage: "checkmark.shield.fill"
                    )
                    .foregroundStyle(.green)
                } else {
                    Label(
                        "Transfer blocked until incompatible settings are removed.",
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .foregroundStyle(.red)
                    ForEach(preflight.issues) { issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(issue.displayName)
                                .font(.headline)
                            Text(issue.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let preflightError = viewModel.preflightError {
                Label(preflightError, systemImage: "questionmark.diamond")
                    .foregroundStyle(.orange)
                Text("The transfer stays disabled until the capability catalog can be verified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Checking recipe compatibility…")
            }
        }
    }

    private var recipeSection: some View {
        Section("Recipe") {
            LabeledContent("Name", value: viewModel.recipe.name)
            LabeledContent("Camera", value: viewModel.recipe.cameraModelName ?? viewModel.recipe.cameraModelID)
            Text("The recipe is read from this iPhone, so transfer does not require an internet connection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var slotSection: some View {
        if !viewModel.slots.isEmpty {
            Section("Target slot") {
                ForEach(viewModel.slots) { status in
                    CameraSlotRow(
                        status: status,
                        isSelected: viewModel.selectedSlot == status.slot
                    ) {
                        viewModel.selectedSlot = status.slot
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        Section("Camera connection") {
            switch viewModel.phase {
            case .requestingAccess:
                ProgressView("Requesting camera access…")
            case .discovering, .idle:
                Label("Connect a Fujifilm X-S20 with a data-capable USB-C cable.", systemImage: "cable.connector")
                Button {
                    Task { await viewModel.refreshDiscovery() }
                } label: {
                    Label("Scan for camera", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("Scan for Fujifilm X-S20 camera")
            case .connecting:
                ProgressView("Opening camera session…")
            case .loadingSlots:
                ProgressView("Reading custom-setting slots…")
            default:
                if let connectedCamera = viewModel.connectedCamera {
                    Label(connectedCamera.name, systemImage: "camera.fill")
                    Text("Connected over USB and identified as a Fujifilm X-S20.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.cameras.isEmpty, viewModel.connectedCamera == nil {
                ForEach(viewModel.cameras) { camera in
                    Button {
                        Task { await viewModel.connect(to: camera) }
                    } label: {
                        Label(camera.name, systemImage: "camera")
                    }
                    .accessibilityLabel("Connect to \(camera.name)")
                }
            } else if viewModel.phase == .discovering, viewModel.cameras.isEmpty {
                Text("No compatible camera detected yet. Keep the camera unlocked and tap Scan for camera again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            if let resultMessage = viewModel.resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if viewModel.errorMessage != nil {
                Button {
                    Task { await viewModel.retry() }
                } label: {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
            }

            Button {
                viewModel.requestTransfer()
            } label: {
                if viewModel.phase == .transferring {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Transfer recipe", systemImage: "arrow.down.to.line.compact")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canTransfer || viewModel.phase.isBusy)
            .accessibilityLabel("Transfer recipe to selected camera slot")
        }
    }
}

private struct CameraSlotRow: View {
    let status: CameraSlotStatus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
                        .font(.headline)
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select camera slot \(status.title)")
        .accessibilityValue(status.detail)
    }
}
