import Foundation

struct WebexRealtimeTriggerAdapter: Sendable {
    static func trigger(for event: WebexRealtimeEvent) -> WebexStreamTrigger {
        event.streamTrigger()
    }
}
