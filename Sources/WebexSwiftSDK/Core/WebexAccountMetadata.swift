import Foundation

public struct WebexAccountMetadata: Equatable, Codable, Sendable {
    public var webexUserID: String?
    public var oidcSubject: String?
    public var email: String?
    public var displayName: String?
    public var organizationID: String?
    public var lastVerifiedAt: Date?

    public init(
        webexUserID: String? = nil,
        oidcSubject: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
        organizationID: String? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.webexUserID = webexUserID
        self.oidcSubject = oidcSubject
        self.email = email
        self.displayName = displayName
        self.organizationID = organizationID
        self.lastVerifiedAt = lastVerifiedAt
    }
}
