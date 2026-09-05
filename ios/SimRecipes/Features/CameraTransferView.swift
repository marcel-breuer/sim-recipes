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
}

@MainActor
final class CameraTransferViewModel: ObservableObject {
    let recipe: RecipeTransport

    @Published private(set) var phase: CameraTransferPhase = .idle
    @Published private(set) var cameras: [CameraDescriptor] = []
    @Published private(set) var slots: [CameraSlotStatus] = []
    @Published private(set) var currentSlot: CameraSlot?
    @Published private(set) var resultMessage: String?
    @Published private(set) var errorMessage: String?
    @Published var selectedSlot: CameraSlot?
    @Published var showingOverwriteConfirmation = false

    private let cameraService: any CameraService
    private var activeCameraID: String?
    private var currentSnapshot: CameraSlotSnapshot?

    init(recipe: RecipeTransport, cameraService: any CameraService) {
        self.recipe = recipe
        self.cameraService = cameraService
    }

    var connectedCamera: CameraDescriptor? {
        guard let activeCameraID else { return nil }
        return cameras.first { $0.id == activeCameraID }
    }

    var canTransfer: Bool {
        phase == .ready && selectedSlot != nil
    }

    func start() async {
        guard phase == .idle || isFailed else { return }
        phase = .requestingAccess
        errorMessage = nil
        resultMessage = nil

        do {
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
        guard camera.isX20Candidate, !phase.isBusy else { return }
        phase = .connecting
        errorMessage = nil
        resultMessage = nil

        do {
            try await cameraService.openSession(for: camera.id)
            activeCameraID = camera.id
            phase = .loadingSlots

            let availableSlots = try await cameraService.availableSlots()
            currentSnapshot = try? await cameraService.readCurrentSlotSnapshot(propertyCodes: [])
            currentSlot = currentSnapshot?.slot
            slots = availableSlots.map { slot in
                CameraSlotStatus(
                    slot: slot,
                    isCurrent: slot == currentSnapshot?.slot,
                    propertyCount: slot == currentSnapshot?.slot ? currentSnapshot?.properties.count : nil
                )
            }
            selectedSlot = currentSnapshot?.slot ?? availableSlots.first
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

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        phase = .failed(error.localizedDescription)
    }
}

struct CameraTransferView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CameraTransferViewModel

    init(recipe: RecipeTransport, cameraService: any CameraService) {
        _viewModel = StateObject(wrappedValue: CameraTransferViewModel(
            recipe: recipe,
            cameraService: cameraService
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
            connectionSection
            slotSection
            actionSection
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
