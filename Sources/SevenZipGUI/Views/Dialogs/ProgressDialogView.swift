import SwiftUI

public struct ProgressDialogView: View {
    @ObservedObject var progress: OperationProgressState
    let onClose: () -> Void

    public init(progress: OperationProgressState, onClose: @escaping () -> Void) {
        self.progress = progress
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: progress.isCompleted
                      ? (progress.errorMessage == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                      : (progress.title == "Compressing" ? "archivebox.fill" : "arrow.down.doc.fill"))
                    .font(.title2)
                    .foregroundColor(progress.isCompleted
                                     ? (progress.errorMessage == nil ? .green : .red)
                                     : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(progress.percentage))% \(progress.title) \(progress.archiveName)")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        if progress.isPaused {
                            Text("PAUSED")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(3)
                        }
                        if progress.isBackgroundPriority {
                            Text("BACKGROUND")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.2))
                                .foregroundColor(.secondary)
                                .cornerRadius(3)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                // Two-column Windows 7-Zip style stats grid
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        statRow(label: "Elapsed time:", value: progress.formattedElapsed)
                        statRow(label: "Remaining time:", value: progress.formattedRemaining)
                        statRow(label: "Files:", value: "\(progress.filesProcessed)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        statRow(label: "Total size:", value: progress.formattedTotalSize)
                        statRow(label: "Processed:", value: progress.formattedProcessedSize)
                        statRow(label: "Speed:", value: progress.formattedSpeed)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                // Current file
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.currentFile)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ProgressView(value: progress.percentage, total: 100.0)
                        .progressViewStyle(.linear)
                }

                if let err = progress.errorMessage {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(3)
                }
            }
            .padding()

            Divider()

            // Footer controls matching Windows 7-Zip (Background, Pause, Cancel)
            HStack(spacing: 10) {
                Button(progress.isBackgroundPriority ? "Foreground" : "Background") {
                    progress.toggleBackground()
                }
                .disabled(progress.isCompleted)

                Button(progress.isPaused ? "Continue" : "Pause") {
                    progress.togglePause()
                }
                .disabled(progress.isCompleted)

                Spacer()

                if progress.isCompleted {
                    Button("Close") {
                        onClose()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        progress.cancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }
}
