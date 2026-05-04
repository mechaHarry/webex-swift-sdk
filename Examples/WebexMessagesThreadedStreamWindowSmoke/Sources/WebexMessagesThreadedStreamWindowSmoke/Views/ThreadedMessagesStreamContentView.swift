import SwiftUI

struct ThreadedMessagesStreamContentView: View {
    @ObservedObject var model: ThreadedMessagesStreamWindowModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task {
            await model.start()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Message Structure")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    statusLabel
                    Label(model.realtimeStatusText, systemImage: "bolt.horizontal.circle")
                        .lineLimit(1)
                    Text("Revision \(model.revision)")
                    Text("Updated \(model.lastUpdatedText)")
                    if model.hasMore {
                        Text(model.capReached ? "More pages capped" : "More pages available")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await model.loadNextPage()
                }
            } label: {
                Label("Next Page", systemImage: "arrow.down.doc")
            }
            .disabled(!model.canLoadNextPage)

            Button {
                Task {
                    await model.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(!model.canRefresh)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .authorizing:
            ProgressView("Opening Webex")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(message)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if model.rows.isEmpty, model.isRefreshing {
                ProgressView("Loading messages")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rows.isEmpty {
                Text("No messages")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.rows) { row in
                    ThreadedMessageRowView(row: row)
                }
                .listStyle(.inset)
                .overlay(alignment: .bottomLeading) {
                    if let error = model.lastErrorText {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
        }
    }

    private var statusLabel: some View {
        Group {
            if model.isRefreshing {
                Label("Refreshing", systemImage: "arrow.triangle.2.circlepath")
            } else if model.isLoadingNextPage {
                Label("Loading", systemImage: "arrow.down")
            } else {
                Label("Ready", systemImage: "checkmark.circle")
            }
        }
    }
}

private struct ThreadedMessageRowView: View {
    let row: ThreadedMessageRowModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear
                .frame(width: CGFloat(row.depth) * 22)

            Image(systemName: iconName)
                .foregroundStyle(row.isPlaceholderParent ? .secondary : .primary)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(row.sender)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(row.contentSource)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    Text(row.createdText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(row.body)
                    .font(.body)
                    .lineLimit(4)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Text("id \(row.id)")
                    Text("parent \(row.parentText)")
                    Text(row.childCountText)
                    Text("depth \(row.depth)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
    }

    private var iconName: String {
        if row.isPlaceholderParent {
            return "questionmark.square.dashed"
        }
        return row.depth == 0 ? "bubble.left" : "arrow.turn.down.right"
    }
}
