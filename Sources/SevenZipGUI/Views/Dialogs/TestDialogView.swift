import SwiftUI

public struct TestDialogView: View {
    @ObservedObject var state: FileManagerState
    @Environment(\.dismiss) var dismiss

    public init(state: FileManagerState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: state.testSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(state.testSuccess ? .green : .red)
                    .font(.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.testSuccess ? "Archive Test Passed" : "Archive Test Failed")
                        .font(.headline)
                    Text(state.testSuccess ? "Everything is Ok. No errors found." : "Errors detected in archive.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Console output
            ScrollView {
                Text(state.testOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 520, height: 380)
    }
}
