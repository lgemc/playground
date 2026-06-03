import Foundation
import SwiftUI
import Combine

/// Helper to manage model download permissions and prompts
@MainActor
class MLXModelDownloadHelper: ObservableObject {
    static let shared = MLXModelDownloadHelper()

    @Published var showingPermissionAlert = false
    @Published var pendingModelId: String = ""
    @Published var pendingModelType: String = ""
    @Published var pendingModelSize: String = ""
    @Published var onApproved: (() -> Void)? = nil
    @Published var onDenied: (() -> Void)? = nil

    private let permissionService = ModelPermissionService.shared

    private init() {}

    /// Check if model download is approved, or prompt user
    /// Returns true if approved, false if denied/pending
    func checkPermission(
        modelId: String,
        modelType: String,
        estimatedSizeMB: Int,
        onApproved: @escaping () -> Void,
        onDenied: @escaping () -> Void
    ) -> Bool {
        // Check if already approved
        if permissionService.isApproved(modelId: modelId) {
            print("✅ Model \(modelId) already approved")
            return true
        }

        // Check if recently denied (within last hour)
        if let permission = try? permissionService.getPermission(modelId: modelId).get(),
           let deniedAt = permission.deniedAt,
           Date().timeIntervalSince(deniedAt) < 3600 {
            print("❌ Model \(modelId) was recently denied")
            onDenied()
            return false
        }

        // Need to prompt user
        print("❓ Prompting user for permission to download \(modelId)")
        promptForPermission(
            modelId: modelId,
            modelType: modelType,
            estimatedSizeMB: estimatedSizeMB,
            onApproved: onApproved,
            onDenied: onDenied
        )

        return false
    }

    private func promptForPermission(
        modelId: String,
        modelType: String,
        estimatedSizeMB: Int,
        onApproved: @escaping () -> Void,
        onDenied: @escaping () -> Void
    ) {
        // Record that we prompted
        let _ = permissionService.recordPrompt(modelId: modelId, modelType: modelType)

        // Set up alert
        self.pendingModelId = modelId
        self.pendingModelType = modelType
        self.pendingModelSize = formatSize(estimatedSizeMB)
        self.onApproved = onApproved
        self.onDenied = onDenied
        self.showingPermissionAlert = true
    }

    func approve() {
        guard !pendingModelId.isEmpty else { return }

        // Save approval
        let _ = permissionService.approve(modelId: pendingModelId, modelType: pendingModelType)

        // Call callback
        onApproved?()

        // Reset
        reset()
    }

    func deny() {
        guard !pendingModelId.isEmpty else { return }

        // Save denial
        let _ = permissionService.deny(modelId: pendingModelId, modelType: pendingModelType)

        // Call callback
        onDenied?()

        // Reset
        reset()
    }

    private func reset() {
        pendingModelId = ""
        pendingModelType = ""
        pendingModelSize = ""
        onApproved = nil
        onDenied = nil
        showingPermissionAlert = false
    }

    private func formatSize(_ mb: Int) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        } else {
            return "\(mb) MB"
        }
    }
}

/// View modifier to show model download permission alert
struct ModelDownloadPermissionAlert: ViewModifier {
    @ObservedObject var helper = MLXModelDownloadHelper.shared

    func body(content: Content) -> some View {
        content
            .alert("Download AI Model?", isPresented: $helper.showingPermissionAlert) {
                Button("Cancel", role: .cancel) {
                    helper.deny()
                }
                Button("Download") {
                    helper.approve()
                }
            } message: {
                Text("This feature requires downloading \(helper.pendingModelType) model (\(helper.pendingModelSize)). Download now?\n\nThe model will be stored locally on your device.")
            }
    }
}

extension View {
    func modelDownloadPermissionAlert() -> some View {
        modifier(ModelDownloadPermissionAlert())
    }
}
