import SwiftUI

struct AddPaperToolbarButton: View {
    @Bindable var controller: AddPaperController
    let offlineCoordinator: OfflineIntakeCoordinator
    let syncPendingOperations: () async -> Void

    var body: some View {
        Button {
            controller.present()
        } label: {
            Label("Add Paper", systemImage: "plus")
                .labelStyle(.iconOnly)
        }
        .help("Add Paper")
        .popover(isPresented: $controller.isPresented, arrowEdge: .bottom) {
            AddPaperPopover(
                controller: controller,
                offlineCoordinator: offlineCoordinator,
                syncPendingOperations: syncPendingOperations
            )
        }
    }
}

private struct AddPaperPopover: View {
    @Bindable var controller: AddPaperController
    let offlineCoordinator: OfflineIntakeCoordinator
    let syncPendingOperations: () async -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Add Paper", systemImage: "doc.badge.plus")
                .font(.headline)

            TextField("DOI", text: $controller.input)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .disabled(controller.isSubmitting)
                .onSubmit(submitIfPossible)
                .onChange(of: controller.input) { _, _ in
                    controller.normalizeInputForEditing()
                }

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    controller.isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(controller.isSubmitting)

                Button {
                    submitIfPossible()
                } label: {
                    HStack(spacing: 6) {
                        if controller.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus")
                        }
                        Text("Add")
                    }
                    .frame(minWidth: 64)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(!controller.canSubmit)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            inputFocused = true
        }
    }

    private func submitIfPossible() {
        guard controller.canSubmit else { return }
        Task {
            await controller.submit(
                offlineCoordinator: offlineCoordinator,
                syncPendingOperations: syncPendingOperations
            )
        }
    }
}
