import SwiftUI
import WebexSwiftSDK

@main
struct WebexMessagesThreadedStreamWindowSmokeApp: App {
    @StateObject private var model: ThreadedMessagesStreamWindowModel

    init() {
        do {
            let configuration = try ThreadedStreamSmokeConfiguration(environment: ProcessInfo.processInfo.environment)
            _model = StateObject(wrappedValue: ThreadedMessagesStreamWindowModel(
                runtimeFactory: {
                    try await ThreadedMessageStreamBootstrap.makeRuntime(configuration: configuration)
                }
            ))
        } catch {
            let startupFailure = String(describing: error)
            _model = StateObject(wrappedValue: ThreadedMessagesStreamWindowModel(
                runtimeFactory: {
                    throw WebexSDKError.network(startupFailure)
                }
            ))
        }
    }

    var body: some Scene {
        WindowGroup {
            ThreadedMessagesStreamContentView(model: model)
                .frame(minWidth: 820, minHeight: 560)
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

                Button("Load Next Page") {
                    Task {
                        await model.loadNextPage()
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                .disabled(!model.canLoadNextPage)
            }
        }
    }
}
