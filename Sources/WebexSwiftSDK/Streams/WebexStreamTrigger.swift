import Foundation

public struct WebexStreamTrigger: Equatable, Sendable {
    public let resource: String
    public let event: String
    public let resourceID: String?
    public let roomID: String?
    public let actorID: String?

    public init(
        resource: String,
        event: String,
        resourceID: String? = nil,
        roomID: String? = nil,
        actorID: String? = nil
    ) {
        self.resource = resource
        self.event = event
        self.resourceID = resourceID
        self.roomID = roomID
        self.actorID = actorID
    }
}
