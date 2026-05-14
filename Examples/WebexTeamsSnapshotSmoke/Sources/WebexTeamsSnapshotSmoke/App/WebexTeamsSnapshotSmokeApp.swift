import SwiftUI
import WebexSwiftSDK

@main
struct WebexTeamsSnapshotSmokeApp: App {
    @StateObject private var model: TeamsSnapshotWindowModel

    init() {
        do {
            let configuration = try TeamsSnapshotSmokeConfiguration(environment: ProcessInfo.processInfo.environment)
            _model = StateObject(wrappedValue: TeamsSnapshotWindowModel(
                runtimeFactory: {
                    try await TeamsSnapshotBootstrap.makeRuntime(configuration: configuration)
                }
            ))
        } catch {
            let startupFailure = String(describing: error)
            _model = StateObject(wrappedValue: TeamsSnapshotWindowModel(
                runtimeFactory: {
                    throw WebexSDKError.network(startupFailure)
                }
            ))
        }
    }

    var body: some Scene {
        WindowGroup("Webex Teams Snapshot Smoke") {
            TeamsSnapshotContentView(model: model)
                .frame(minWidth: 920, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Teams") {
                    Task {
                        await model.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.canRefresh)

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
