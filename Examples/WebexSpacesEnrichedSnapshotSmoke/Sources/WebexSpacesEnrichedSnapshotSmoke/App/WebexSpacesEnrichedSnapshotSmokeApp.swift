import SwiftUI
import WebexSwiftSDK

@main
struct WebexSpacesEnrichedSnapshotSmokeApp: App {
    @StateObject private var model: EnrichedSpacesWindowModel

    init() {
        do {
            let configuration = try EnrichedSpacesSmokeConfiguration(environment: ProcessInfo.processInfo.environment)
            _model = StateObject(wrappedValue: EnrichedSpacesWindowModel(
                runtimeFactory: {
                    try await EnrichedSpacesBootstrap.makeRuntime(configuration: configuration)
                }
            ))
        } catch {
            let startupFailure = String(describing: error)
            _model = StateObject(wrappedValue: EnrichedSpacesWindowModel(
                runtimeFactory: {
                    throw WebexSDKError.network(startupFailure)
                }
            ))
        }
    }

    var body: some Scene {
        WindowGroup {
            EnrichedSpacesContentView(model: model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Spaces") {
                    Task {
                        await model.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.canRefresh)

                Button("Refresh Enrichment") {
                    Task {
                        await model.refreshEnrichment()
                    }
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(!model.canRefreshEnrichment)

                Button("Load More") {
                    Task {
                        await model.loadNextPage()
                    }
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(!model.canLoadMore)
            }
        }
    }
}
