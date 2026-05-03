import SwiftUI

struct MessagesStreamContentView: View {
    @ObservedObject var model: MessagesStreamWindowModel

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
                Text("Messages")
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
                    MessageRowView(row: row)
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

private struct MessageRowView: View {
    let row: MessageRowModel

    var body: some View {
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

            if row.mentionedPeopleText != "(none)" || row.mentionedGroupsText != "(none)" {
                HStack(spacing: 10) {
                    if row.mentionedPeopleText != "(none)" {
                        Label(row.mentionedPeopleText, systemImage: "person.2")
                    }
                    if row.mentionedGroupsText != "(none)" {
                        Label(row.mentionedGroupsText, systemImage: "at")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}
