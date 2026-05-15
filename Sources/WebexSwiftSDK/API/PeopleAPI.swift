import Foundation

public enum WebexPersonPhoneNumberType: Equatable, Sendable {
    case work
    case workExtension
    case mobile
    case fax
    case unknown(String)
}

extension WebexPersonPhoneNumberType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "work":
            self = .work
        case "work_extension":
            self = .workExtension
        case "mobile":
            self = .mobile
        case "fax":
            self = .fax
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .work:
            return "work"
        case .workExtension:
            return "work_extension"
        case .mobile:
            return "mobile"
        case .fax:
            return "fax"
        case .unknown(let value):
            return value
        }
    }
}

public enum WebexPersonSIPAddressType: Equatable, Sendable {
    case personalRoom
    case enterprise
    case cloudCalling
    case unknown(String)
}

extension WebexPersonSIPAddressType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "personal-room":
            self = .personalRoom
        case "enterprise":
            self = .enterprise
        case "cloud-calling":
            self = .cloudCalling
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .personalRoom:
            return "personal-room"
        case .enterprise:
            return "enterprise"
        case .cloudCalling:
            return "cloud-calling"
        case .unknown(let value):
            return value
        }
    }
}

public enum WebexPersonStatus: Equatable, Sendable {
    case active
    case call
    case doNotDisturb
    case inactive
    case meeting
    case outOfOffice
    case pending
    case presenting
    case unknownStatus
    case unknown(String)
}

extension WebexPersonStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "active":
            self = .active
        case "call":
            self = .call
        case "DoNotDisturb":
            self = .doNotDisturb
        case "inactive":
            self = .inactive
        case "meeting":
            self = .meeting
        case "OutOfOffice":
            self = .outOfOffice
        case "pending":
            self = .pending
        case "presenting":
            self = .presenting
        case "unknown":
            self = .unknownStatus
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .active:
            return "active"
        case .call:
            return "call"
        case .doNotDisturb:
            return "DoNotDisturb"
        case .inactive:
            return "inactive"
        case .meeting:
            return "meeting"
        case .outOfOffice:
            return "OutOfOffice"
        case .pending:
            return "pending"
        case .presenting:
            return "presenting"
        case .unknownStatus:
            return "unknown"
        case .unknown(let value):
            return value
        }
    }
}

public enum WebexPersonType: Equatable, Sendable {
    case person
    case bot
    case appuser
    case unknown(String)
}

extension WebexPersonType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "person":
            self = .person
        case "bot":
            self = .bot
        case "appuser":
            self = .appuser
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .person:
            return "person"
        case .bot:
            return "bot"
        case .appuser:
            return "appuser"
        case .unknown(let value):
            return value
        }
    }
}

public struct WebexPersonPhoneNumber: Codable, Equatable, Sendable {
    public let type: WebexPersonPhoneNumberType?
    public let value: String?
    public let primary: Bool?

    public init(
        type: WebexPersonPhoneNumberType? = nil,
        value: String? = nil,
        primary: Bool? = nil
    ) {
        self.type = type
        self.value = value
        self.primary = primary
    }
}

public struct WebexPersonAddress: Codable, Equatable, Sendable {
    public let type: String?
    public let country: String?
    public let locality: String?
    public let region: String?
    public let streetAddress: String?
    public let postalCode: String?

    public init(
        type: String? = nil,
        country: String? = nil,
        locality: String? = nil,
        region: String? = nil,
        streetAddress: String? = nil,
        postalCode: String? = nil
    ) {
        self.type = type
        self.country = country
        self.locality = locality
        self.region = region
        self.streetAddress = streetAddress
        self.postalCode = postalCode
    }
}

public struct WebexPersonSIPAddress: Codable, Equatable, Sendable {
    public let type: WebexPersonSIPAddressType?
    public let value: String?
    public let primary: Bool?

    public init(
        type: WebexPersonSIPAddressType? = nil,
        value: String? = nil,
        primary: Bool? = nil
    ) {
        self.type = type
        self.value = value
        self.primary = primary
    }
}

public struct WebexPerson: Equatable, Decodable, Sendable {
    public let id: String
    public let emails: [String]
    public let phoneNumbers: [WebexPersonPhoneNumber]?
    public let `extension`: String?
    public let locationID: String?
    public let displayName: String?
    public let nickName: String?
    public let firstName: String?
    public let lastName: String?
    public let avatar: String?
    public let orgID: String?
    public let roles: [String]?
    public let licenses: [String]?
    public let department: String?
    public let manager: String?
    public let managerID: String?
    public let title: String?
    public let addresses: [WebexPersonAddress]?
    public let created: Date?
    public let lastModified: Date?
    public let timezone: String?
    public let lastActivity: Date?
    public let siteUrls: [String]?
    public let sipAddresses: [WebexPersonSIPAddress]?
    public let xmppFederationJid: String?
    public let status: WebexPersonStatus?
    public let invitePending: String?
    public let loginEnabled: String?
    public let type: WebexPersonType?
    public let additionalFields: [String: WebexJSONValue]

    public init(
        id: String,
        emails: [String],
        phoneNumbers: [WebexPersonPhoneNumber]? = nil,
        extension: String? = nil,
        locationID: String? = nil,
        displayName: String? = nil,
        nickName: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        avatar: String? = nil,
        orgID: String? = nil,
        roles: [String]? = nil,
        licenses: [String]? = nil,
        department: String? = nil,
        manager: String? = nil,
        managerID: String? = nil,
        title: String? = nil,
        addresses: [WebexPersonAddress]? = nil,
        created: Date? = nil,
        lastModified: Date? = nil,
        timezone: String? = nil,
        lastActivity: Date? = nil,
        siteUrls: [String]? = nil,
        sipAddresses: [WebexPersonSIPAddress]? = nil,
        xmppFederationJid: String? = nil,
        status: WebexPersonStatus? = nil,
        invitePending: String? = nil,
        loginEnabled: String? = nil,
        type: WebexPersonType? = nil,
        additionalFields: [String: WebexJSONValue] = [:]
    ) {
        self.id = id
        self.emails = emails
        self.phoneNumbers = phoneNumbers
        self.extension = `extension`
        self.locationID = locationID
        self.displayName = displayName
        self.nickName = nickName
        self.firstName = firstName
        self.lastName = lastName
        self.avatar = avatar
        self.orgID = orgID
        self.roles = roles
        self.licenses = licenses
        self.department = department
        self.manager = manager
        self.managerID = managerID
        self.title = title
        self.addresses = addresses
        self.created = created
        self.lastModified = lastModified
        self.timezone = timezone
        self.lastActivity = lastActivity
        self.siteUrls = siteUrls
        self.sipAddresses = sipAddresses
        self.xmppFederationJid = xmppFederationJid
        self.status = status
        self.invitePending = invitePending
        self.loginEnabled = loginEnabled
        self.type = type
        self.additionalFields = additionalFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case emails
        case phoneNumbers
        case `extension`
        case locationID = "locationId"
        case displayName
        case nickName
        case firstName
        case lastName
        case avatar
        case orgID = "orgId"
        case roles
        case licenses
        case department
        case manager
        case managerID = "managerId"
        case title
        case addresses
        case created
        case lastModified
        case timezone
        case lastActivity
        case siteUrls
        case sipAddresses
        case xmppFederationJid
        case status
        case invitePending
        case loginEnabled
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.emails = try container.decode([String].self, forKey: .emails)
        self.phoneNumbers = try container.decodeIfPresent([WebexPersonPhoneNumber].self, forKey: .phoneNumbers)
        self.extension = try container.decodeIfPresent(String.self, forKey: .extension)
        self.locationID = try container.decodeIfPresent(String.self, forKey: .locationID)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.nickName = try container.decodeIfPresent(String.self, forKey: .nickName)
        self.firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        self.lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        self.avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        self.orgID = try container.decodeIfPresent(String.self, forKey: .orgID)
        self.roles = try container.decodeIfPresent([String].self, forKey: .roles)
        self.licenses = try container.decodeIfPresent([String].self, forKey: .licenses)
        self.department = try container.decodeIfPresent(String.self, forKey: .department)
        self.manager = try container.decodeIfPresent(String.self, forKey: .manager)
        self.managerID = try container.decodeIfPresent(String.self, forKey: .managerID)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.addresses = try container.decodeIfPresent([WebexPersonAddress].self, forKey: .addresses)
        self.created = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .created)
        self.lastModified = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .lastModified)
        self.timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        self.lastActivity = try WebexDateDecoding.decodeIfPresent(from: container, forKey: .lastActivity)
        self.siteUrls = try container.decodeIfPresent([String].self, forKey: .siteUrls)
        self.sipAddresses = try container.decodeIfPresent([WebexPersonSIPAddress].self, forKey: .sipAddresses)
        self.xmppFederationJid = try container.decodeIfPresent(String.self, forKey: .xmppFederationJid)
        self.status = try container.decodeIfPresent(WebexPersonStatus.self, forKey: .status)
        self.invitePending = try container.decodeIfPresent(String.self, forKey: .invitePending)
        self.loginEnabled = try container.decodeIfPresent(String.self, forKey: .loginEnabled)
        self.type = try container.decodeIfPresent(WebexPersonType.self, forKey: .type)
        self.additionalFields = try WebexAdditionalFields.decode(
            from: decoder,
            excluding: Set(CodingKeys.allCases.map(\.rawValue))
        )
    }
}

public struct ListPeopleParams: Equatable, Sendable {
    public let email: String?
    public let displayName: String?
    public let id: String?
    public let orgID: String?
    public let roles: String?
    public let callingData: Bool?
    public let locationID: String?
    public let max: Int?
    public let excludeStatus: Bool?

    public init(
        email: String? = nil,
        displayName: String? = nil,
        id: String? = nil,
        orgID: String? = nil,
        roles: String? = nil,
        callingData: Bool? = nil,
        locationID: String? = nil,
        max: Int? = nil,
        excludeStatus: Bool? = nil
    ) {
        self.email = email
        self.displayName = displayName
        self.id = id
        self.orgID = orgID
        self.roles = roles
        self.callingData = callingData
        self.locationID = locationID
        self.max = max
        self.excludeStatus = excludeStatus
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let email {
            items.append(URLQueryItem(name: "email", value: email))
        }
        if let displayName {
            items.append(URLQueryItem(name: "displayName", value: displayName))
        }
        if let id {
            items.append(URLQueryItem(name: "id", value: id))
        }
        if let orgID {
            items.append(URLQueryItem(name: "orgId", value: orgID))
        }
        if let roles {
            items.append(URLQueryItem(name: "roles", value: roles))
        }
        if let callingData {
            items.append(URLQueryItem(name: "callingData", value: String(callingData)))
        }
        if let locationID {
            items.append(URLQueryItem(name: "locationId", value: locationID))
        }
        if let max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }
        if let excludeStatus {
            items.append(URLQueryItem(name: "excludeStatus", value: String(excludeStatus)))
        }
        return items
    }
}

public struct WebexPersonListPage: Equatable, Sendable {
    public let items: [WebexPerson]
    public let notFoundIDs: [String]?
    public let nextPage: WebexPageLink?

    public init(
        items: [WebexPerson],
        notFoundIDs: [String]? = nil,
        nextPage: WebexPageLink?
    ) {
        self.items = items
        self.notFoundIDs = notFoundIDs
        self.nextPage = nextPage
    }
}

public struct PeopleAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func me(callingData: Bool? = nil) async throws -> WebexPerson {
        let data = try await transport.send(WebexRequest(
            path: "/v1/people/me",
            queryItems: callingDataQueryItems(callingData)
        ))
        return try JSONDecoder().decode(WebexPerson.self, from: data)
    }

    public func get(personID: String, callingData: Bool? = nil) async throws -> WebexPerson {
        let data = try await transport.send(WebexRequest(
            path: try personPath(personID),
            isPathPercentEncoded: true,
            queryItems: callingDataQueryItems(callingData)
        ))
        return try JSONDecoder().decode(WebexPerson.self, from: data)
    }

    public func list(params: ListPeopleParams = ListPeopleParams()) async throws -> WebexPersonListPage {
        try await list(request: WebexRequest(
            path: "/v1/people",
            queryItems: params.queryItems
        ))
    }

    public func list(nextPage: WebexPageLink) async throws -> WebexPersonListPage {
        try await list(request: nextPage.request)
    }

    private func list(request: WebexRequest) async throws -> WebexPersonListPage {
        let response = try await transport.sendResponse(request)
        let envelope = try JSONDecoder().decode(WebexPersonListEnvelope.self, from: response.data)
        return WebexPersonListPage(
            items: envelope.items,
            notFoundIDs: envelope.notFoundIDs,
            nextPage: WebexPageLink.next(from: response.response)
        )
    }

    private func callingDataQueryItems(_ callingData: Bool?) -> [URLQueryItem] {
        guard let callingData else {
            return []
        }

        return [URLQueryItem(name: "callingData", value: String(callingData))]
    }

    private func personPath(_ personID: String) throws -> String {
        let trimmedID = personID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex person ID")
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
              !encodedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex person ID")
        }

        return "/v1/people/\(encodedID)"
    }
}

private struct WebexPersonListEnvelope: Decodable {
    let items: [WebexPerson]
    let notFoundIDs: [String]?

    private enum CodingKeys: String, CodingKey {
        case items
        case notFoundIDs = "notFoundIds"
    }
}
