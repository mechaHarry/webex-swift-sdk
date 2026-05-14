import SwiftUI

struct EnrichedSpacesContentView: View {
    @ObservedObject var model: EnrichedSpacesWindowModel

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
                Text("Enriched Spaces")
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
                Label("Refresh Spaces", systemImage: "arrow.clockwise")
            }
            .disabled(!model.canRefresh)

            Button {
                Task {
                    await model.refreshEnrichment()
                }
            } label: {
                Label("Refresh Enrichment", systemImage: "sparkles")
            }
            .disabled(!model.canRefreshEnrichment)

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
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if model.rows.isEmpty, model.isRefreshing {
                ProgressView("Loading spaces")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rows.isEmpty {
                PlaceholderView(
                    title: "No Spaces",
                    message: "Refresh spaces to load a snapshot.",
                    systemImage: "rectangle.3.group"
                )
            } else {
                NavigationSplitView {
                    List(selection: selection) {
                        ForEach(model.rows) { row in
                            EnrichedSpaceRowView(row: row)
                                .tag(row.id as String?)
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("Spaces")
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
                } detail: {
                    EnrichedSpaceDetailView(detail: model.selectedDetail)
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
            get: { model.selectedSpaceID },
            set: { model.select(spaceID: $0) }
        )
    }

    private var statusLabel: some View {
        Group {
            if model.isRefreshing {
                Label("Refreshing spaces", systemImage: "arrow.triangle.2.circlepath")
            } else if model.isLoadingNextPage {
                Label("Loading page", systemImage: "arrow.down")
            } else {
                Label("Ready", systemImage: "checkmark.circle")
            }
        }
    }
}

private struct EnrichedSpaceRowView: View {
    let row: EnrichedSpaceRowModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.systemImageName)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(row.typeText)
                    Text(row.enrichmentStatusText)
                    Text(row.enrichmentSummary)
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
