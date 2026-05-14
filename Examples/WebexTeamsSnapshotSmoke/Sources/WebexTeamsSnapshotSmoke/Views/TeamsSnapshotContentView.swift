import SwiftUI

struct TeamsSnapshotContentView: View {
    @ObservedObject var model: TeamsSnapshotWindowModel

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
                Text("Teams")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    statusLabel
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
                Label("Refresh Teams", systemImage: "arrow.clockwise")
            }
            .disabled(!model.canRefresh)

            Button {
                Task {
                    await model.loadNextPage()
                }
            } label: {
                Label("Load More", systemImage: "arrow.down.circle")
            }
            .disabled(!model.canLoadMore)
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
            PlaceholderView(
                title: "Unable to Load Teams",
                message: message,
                systemImage: "exclamationmark.triangle"
            )
            .textSelection(.enabled)
        case .ready:
            if model.rows.isEmpty, model.isRefreshing {
                ProgressView("Loading teams")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rows.isEmpty {
                PlaceholderView(
                    title: "No Teams",
                    message: "Refresh teams to load a snapshot.",
                    systemImage: "person.3.sequence"
                )
            } else {
                NavigationSplitView {
                    List(selection: selection) {
                        ForEach(model.rows) { row in
                            TeamSnapshotRowView(row: row)
                                .tag(row.id as String?)
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("Teams")
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
                } detail: {
                    TeamSnapshotDetailView(detail: model.selectedDetail)
                }
                .overlay(alignment: .bottomLeading) {
                    if let error = model.lastErrorText {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedTeamID },
            set: { model.select(teamID: $0) }
        )
    }

    private var statusLabel: some View {
        Group {
            if model.isRefreshing {
                Label("Refreshing teams", systemImage: "arrow.triangle.2.circlepath")
            } else if model.isLoadingNextPage {
                Label("Loading page", systemImage: "arrow.down")
            } else {
                Label("Ready", systemImage: "checkmark.circle")
            }
        }
    }
}

private struct TeamSnapshotRowView: View {
    let row: TeamSnapshotRowModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 5) {
                Text(row.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(row.shortID, systemImage: "number")
                    Label(row.createdText, systemImage: "calendar")
                    Label(row.additionalFieldsText, systemImage: "curlybraces")
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PlaceholderView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
