import SwiftUI
import WebexSwiftSDK

@main
struct WebexMessagesStreamWindowSmokeApp: App {
    @StateObject private var model: MessagesStreamWindowModel

    init() {
        do {
            let configuration = try StreamSmokeConfiguration(environment: ProcessInfo.processInfo.environment)
            _model = StateObject(wrappedValue: MessagesStreamWindowModel(
                runtimeFactory: {
                    try await MessageStreamBootstrap.makeRuntime(configuration: configuration)
                }
            ))
        } catch {
            let startupFailure = String(describing: error)
            _model = StateObject(wrappedValue: MessagesStreamWindowModel(
                runtimeFactory: {
                    throw WebexSDKError.network(startupFailure)
                }
            ))
        }
    }

    var body: some Scene {
        WindowGroup {
            MessagesStreamContentView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Messages") {
                    Task {
                        await model.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.canRefresh)
            }
        }
    }
}
