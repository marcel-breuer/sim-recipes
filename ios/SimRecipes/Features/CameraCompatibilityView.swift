import SwiftUI

@MainActor
final class CameraCompatibilityViewModel: ObservableObject {
    @Published private(set) var cameras: [SupportedCameraTransport] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let capabilityService: CameraCapabilityService

    init(capabilityService: CameraCapabilityService) {
        self.capabilityService = capabilityService
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            cameras = try await capabilityService.supportedCameras()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CameraCompatibilityView: View {
    @StateObject private var viewModel: CameraCompatibilityViewModel

    init(capabilityService: CameraCapabilityService) {
        _viewModel = StateObject(wrappedValue: CameraCompatibilityViewModel(
            capabilityService: capabilityService
        ))
    }

    var body: some View {
        Group {
            if let errorMessage = viewModel.errorMessage, viewModel.cameras.isEmpty {
                ContentUnavailableView {
                    Label("Unable to load cameras", systemImage: "camera.badge.ellipsis")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") {
                        Task { await viewModel.load() }
                    }
                }
            } else if viewModel.cameras.isEmpty, viewModel.isLoading {
                ProgressView("Loading camera compatibility…")
            } else {
                List(viewModel.cameras) { camera in
                    NavigationLink {
                        CameraCapabilityDetailView(camera: camera)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(camera.name)
                                .font(.headline)
                            Text("\(camera.capabilities.count) supported settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .refreshable {
                    await viewModel.load()
                }
            }
        }
        .navigationTitle("Camera compatibility")
        .task {
            await viewModel.load()
        }
    }
}

private struct CameraCapabilityDetailView: View {
    let camera: SupportedCameraTransport

    var body: some View {
        List {
            Section {
                Text("Only settings listed here can be safely checked before a transfer. The app will never claim a successful camera write without verified adapter evidence.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Supported settings") {
                ForEach(camera.capabilities) { capability in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(capability.displayName)
                            .font(.headline)
                        Text(capability.key)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(summary(for: capability))
                            .font(.subheadline)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle(camera.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(for capability: CameraCapabilityTransport) -> String {
        var values = [capability.valueType]
        if let minimum = capability.minimum, let maximum = capability.maximum {
            values.append("range \(minimum.formatted())–\(maximum.formatted())")
        } else if let minimum = capability.minimum {
            values.append("from \(minimum.formatted())")
        } else if let maximum = capability.maximum {
            values.append("up to \(maximum.formatted())")
        }
        if case let .array(allowedValues) = capability.allowedValues {
            values.append(allowedValues.compactMap(\.stringValue).joined(separator: ", "))
        }
        return values.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
