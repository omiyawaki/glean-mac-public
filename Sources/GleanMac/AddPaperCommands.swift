import SwiftUI

private struct OpenAddPaperKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openAddPaper: (() -> Void)? {
        get { self[OpenAddPaperKey.self] }
        set { self[OpenAddPaperKey.self] = newValue }
    }
}

struct AddPaperCommands: Commands {
    @FocusedValue(\.openAddPaper) private var openAddPaper

    var body: some Commands {
        CommandMenu("Paper") {
            Button("Add Paper...") {
                openAddPaper?()
            }
            .disabled(openAddPaper == nil)
        }
    }
}
