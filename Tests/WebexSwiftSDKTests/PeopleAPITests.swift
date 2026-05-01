import XCTest
@testable import WebexSwiftSDK

final class PeopleAPITests: XCTestCase {
    func testPersonDecodesExpandedReadFields() throws {
        let json = Data("""
        {
          "id": "person-id",
          "emails": ["primary@example.com", "secondary@example.com"],
          "phoneNumbers": [
            {
              "type": "work",
              "value": "+15551234567",
              "primary": true
            },
            {
              "type": "work_extension",
              "value": "1234",
              "primary": false
            },
            {
              "type": "mobile",
              "value": "+15557654321",
              "primary": false
            },
            {
              "type": "fax",
              "value": "+15550000000",
              "primary": false
            }
          ],
          "extension": "1234",
          "locationId": "location-id",
          "displayName": "Ada Lovelace",
          "nickName": "Ada",
          "firstName": "Augusta",
          "lastName": "Lovelace",
          "avatar": "https://example.com/avatar.png",
          "orgId": "org-id",
          "roles": ["role-1", "role-2"],
          "licenses": ["license-1", "license-2"],
          "department": "Engineering",
          "manager": "Grace Hopper",
          "managerId": "manager-id",
          "title": "Principal Engineer",
          "addresses": [
            {
              "type": "work",
              "country": "US",
              "locality": "San Jose",
              "region": "CA",
              "streetAddress": "170 W Tasman Dr",
              "postalCode": "95134"
            }
          ],
          "created": "2026-04-29T10:11:12Z",
          "lastModified": "2026-04-30T11:12:13.123Z",
          "timezone": "America/Los_Angeles",
          "lastActivity": "2026-05-01T12:13:14Z",
          "siteUrls": ["https://example.webex.com"],
          "sipAddresses": [
            {
              "type": "personal-room",
              "value": "ada@example.webex.com",
              "primary": true
            },
            {
              "type": "enterprise",
              "value": "ada@example.com",
              "primary": false
            },
            {
              "type": "cloud-calling",
              "value": "ada-calling@example.com",
              "primary": false
            }
          ],
          "xmppFederationJid": "ada@example.com",
          "status": "active",
          "invitePending": "false",
          "loginEnabled": "true",
          "type": "person"
        }
        """.utf8)

        let person = try JSONDecoder().decode(WebexPerson.self, from: json)

        XCTAssertEqual(person.id, "person-id")
        XCTAssertEqual(person.emails, ["primary@example.com", "secondary@example.com"])
        XCTAssertEqual(person.phoneNumbers, [
            WebexPersonPhoneNumber(type: .work, value: "+15551234567", primary: true),
            WebexPersonPhoneNumber(type: .workExtension, value: "1234", primary: false),
            WebexPersonPhoneNumber(type: .mobile, value: "+15557654321", primary: false),
            WebexPersonPhoneNumber(type: .fax, value: "+15550000000", primary: false)
        ])
        XCTAssertEqual(person.extension, "1234")
        XCTAssertEqual(person.locationID, "location-id")
        XCTAssertEqual(person.displayName, "Ada Lovelace")
        XCTAssertEqual(person.nickName, "Ada")
        XCTAssertEqual(person.firstName, "Augusta")
        XCTAssertEqual(person.lastName, "Lovelace")
        XCTAssertEqual(person.avatar, "https://example.com/avatar.png")
        XCTAssertEqual(person.orgID, "org-id")
        XCTAssertEqual(person.roles, ["role-1", "role-2"])
        XCTAssertEqual(person.licenses, ["license-1", "license-2"])
        XCTAssertEqual(person.department, "Engineering")
        XCTAssertEqual(person.manager, "Grace Hopper")
        XCTAssertEqual(person.managerID, "manager-id")
        XCTAssertEqual(person.title, "Principal Engineer")
        XCTAssertEqual(person.addresses, [
            WebexPersonAddress(
                type: "work",
                country: "US",
                locality: "San Jose",
                region: "CA",
                streetAddress: "170 W Tasman Dr",
                postalCode: "95134"
            )
        ])
        XCTAssertEqual(iso8601(person.created), "2026-04-29T10:11:12Z")
        XCTAssertEqual(iso8601(person.lastModified), "2026-04-30T11:12:13Z")
        XCTAssertEqual(person.timezone, "America/Los_Angeles")
        XCTAssertEqual(iso8601(person.lastActivity), "2026-05-01T12:13:14Z")
        XCTAssertEqual(person.siteUrls, ["https://example.webex.com"])
        XCTAssertEqual(person.sipAddresses, [
            WebexPersonSIPAddress(type: .personalRoom, value: "ada@example.webex.com", primary: true),
            WebexPersonSIPAddress(type: .enterprise, value: "ada@example.com", primary: false),
            WebexPersonSIPAddress(type: .cloudCalling, value: "ada-calling@example.com", primary: false)
        ])
        XCTAssertEqual(person.xmppFederationJid, "ada@example.com")
        XCTAssertEqual(person.status, .active)
        XCTAssertEqual(person.invitePending, "false")
        XCTAssertEqual(person.loginEnabled, "true")
        XCTAssertEqual(person.type, .person)
    }

    func testPersonStatusPreservesUnknownValues() throws {
        let json = Data(#"{"id":"person-id","emails":["user@example.com"],"status":"future-status"}"#.utf8)

        let person = try JSONDecoder().decode(WebexPerson.self, from: json)

        XCTAssertEqual(person.status, .unknown("future-status"))
    }

    func testPersonTypePreservesUnknownValues() throws {
        let json = Data(#"{"id":"person-id","emails":["user@example.com"],"type":"future-type"}"#.utf8)

        let person = try JSONDecoder().decode(WebexPerson.self, from: json)

        XCTAssertEqual(person.type, .unknown("future-type"))
    }

    func testPersonRequiresEmails() throws {
        let json = Data(#"{"id":"person-id"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(WebexPerson.self, from: json)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                return XCTFail("Expected keyNotFound error, got \(error)")
            }

            XCTAssertEqual(key.stringValue, "emails")
        }
    }

    func testPersonPhoneNumberTypePreservesUnknownValues() throws {
        let json = Data("""
        {
          "id": "person-id",
          "emails": ["user@example.com"],
          "phoneNumbers": [
            {
              "type": "satellite",
              "value": "+15551234567",
              "primary": true
            }
          ]
        }
        """.utf8)

        let person = try JSONDecoder().decode(WebexPerson.self, from: json)

        XCTAssertEqual(person.phoneNumbers?.first?.type, .unknown("satellite"))
    }

    func testPersonSIPAddressTypePreservesUnknownValues() throws {
        let json = Data("""
        {
          "id": "person-id",
          "emails": ["user@example.com"],
          "sipAddresses": [
            {
              "type": "future-sip",
              "value": "user@example.com",
              "primary": true
            }
          ]
        }
        """.utf8)

        let person = try JSONDecoder().decode(WebexPerson.self, from: json)

        XCTAssertEqual(person.sipAddresses?.first?.type, .unknown("future-sip"))
    }

    func testMeWithCallingDataSendsQueryAndDecodesPerson() async throws {
        let httpClient = MockPeopleHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"person-id","emails":["user@example.com"],"displayName":"Ada Lovelace"}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let person = try await api.me(callingData: true)

        XCTAssertEqual(person.id, "person-id")
        XCTAssertEqual(person.emails, ["user@example.com"])
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://webexapis.com/v1/people/me?callingData=true")
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer people-token")
    }

    func testGetPersonPercentEncodesPathAndSendsCallingData() async throws {
        let httpClient = MockPeopleHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"person/id with spaces","emails":["user@example.com"]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let person = try await api.get(personID: "person/id with spaces", callingData: false)

        XCTAssertEqual(person.id, "person/id with spaces")
        let requests = await httpClient.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://webexapis.com/v1/people/person%2Fid%20with%20spaces?callingData=false"
        )
    }

    func testListPeopleSendsOfficialParamsAndDecodesPage() async throws {
        let httpClient = MockPeopleHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/people?cursor=next>; rel="next""#],
            body: #"{"items":[{"id":"person-1","emails":["one@example.com"]}],"notFoundIds":["missing-1","missing-2"]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let page = try await api.list(params: ListPeopleParams(
            email: "user@example.com",
            displayName: "Ada",
            id: "person-1,person-2",
            orgID: "org-id",
            roles: "role-1,role-2",
            callingData: true,
            locationID: "location-id",
            max: 50,
            excludeStatus: true
        ))

        XCTAssertEqual(page.items.map(\.id), ["person-1"])
        XCTAssertEqual(page.notFoundIDs, ["missing-1", "missing-2"])
        XCTAssertEqual(page.nextPage?.url.absoluteString, "https://webexapis.com/v1/people?cursor=next")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].url?.absoluteString,
            "https://webexapis.com/v1/people?email=user@example.com&displayName=Ada&id=person-1,person-2&orgId=org-id&roles=role-1,role-2&callingData=true&locationId=location-id&max=50&excludeStatus=true"
        )
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer people-token")
    }

    func testListPeopleNextPageUsesParsedWebexPageLink() async throws {
        let httpClient = MockPeopleHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            headers: ["Link": #"<https://webexapis.com/v1/people?cursor=second>; rel="next""#],
            body: #"{"items":[{"id":"person-1","emails":["one@example.com"]}]}"#
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"items":[{"id":"person-2","emails":["two@example.com"]}]}"#
        ))
        let api = makeAPI(httpClient: httpClient)

        let firstPage = try await api.list(params: .init(max: 10))
        let nextPage = try XCTUnwrap(firstPage.nextPage)
        let secondPage = try await api.list(nextPage: nextPage)

        XCTAssertEqual(firstPage.items.map(\.id), ["person-1"])
        XCTAssertNil(firstPage.notFoundIDs)
        XCTAssertEqual(secondPage.items.map(\.id), ["person-2"])
        XCTAssertNil(secondPage.notFoundIDs)
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/people?max=10",
            "https://webexapis.com/v1/people?cursor=second"
        ])
    }

    func testInvalidPersonIDValidationFailsBeforeHTTPWithoutLeakingRawID() async throws {
        let httpClient = MockPeopleHTTPClient()
        let api = makeAPI(httpClient: httpClient)

        do {
            _ = try await api.get(personID: "   ")
            XCTFail("Expected invalid person ID")
        } catch WebexSDKError.network(let message) {
            XCTAssertEqual(message, "Invalid Webex person ID")
            XCTAssertFalse(message.contains("   "))
        } catch {
            XCTFail("Expected network error, got \(error)")
        }

        let requests = await httpClient.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testMalformedPeopleJSONDoesNotLeakAccessToken() async throws {
        let httpClient = MockPeopleHTTPClient()
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"person-id","emails":"not-an-array","displayName":"secret-access-token"}"#
        ))
        let transport = WebexTransport(httpClient: httpClient) {
            AccessTokenState(
                value: "secret-access-token",
                expiresAt: Date(timeIntervalSince1970: 1_000),
                tokenType: "Bearer"
            )
        }
        let api = PeopleAPI(transport: transport)

        do {
            _ = try await api.me()
            XCTFail("Expected malformed people JSON to throw")
        } catch {
            XCTAssertFalse(String(describing: error).contains("secret-access-token"))
        }
    }

    func testClientPeopleMeRefreshesStoredTokenAndFetchesPerson() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let httpClient = MockPeopleHTTPClient()
        let now = Date(timeIntervalSince1970: 100)
        try await store.saveTokenRecord(
            WebexTokenRecord(
                refreshToken: "stored-refresh",
                refreshTokenExpiresAt: .distantFuture,
                lastAccessTokenExpiresAt: now.addingTimeInterval(10),
                grantedScopes: ["openid", "spark:people_read"],
                tokenType: "Bearer",
                lastRefreshAt: now
            ),
            for: accountID
        )
        await httpClient.enqueue(response: tokenHTTPResponse(
            accessToken: "refreshed-access",
            refreshToken: "refreshed-refresh"
        ))
        await httpClient.enqueue(response: httpResponse(
            statusCode: 200,
            body: #"{"id":"person-id","emails":["user@example.com"],"displayName":"Ada Lovelace","orgId":"org-id","created":"2026-04-29T10:11:12Z"}"#
        ))
        let client = WebexClient(
            accountID: accountID,
            configuration: configuration,
            tokenStore: store,
            httpClient: httpClient
        )

        let person = try await client.people.me()

        XCTAssertEqual(person.id, "person-id")
        XCTAssertEqual(person.emails, ["user@example.com"])
        XCTAssertEqual(person.displayName, "Ada Lovelace")
        XCTAssertEqual(person.orgID, "org-id")
        XCTAssertEqual(iso8601(person.created), "2026-04-29T10:11:12Z")
        let requests = await httpClient.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://webexapis.com/v1/access_token",
            "https://webexapis.com/v1/people/me"
        ])
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-access")
    }

    private var configuration: WebexIntegrationConfiguration {
        WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "client-secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid", "spark:people_read"]
        )
    }

    private func tokenHTTPResponse(
        accessToken: String,
        refreshToken: String
    ) -> HTTPResponse {
        httpResponse(
            statusCode: 200,
            body: """
            {"access_token":"\(accessToken)","expires_in":600,"refresh_token":"\(refreshToken)","refresh_token_expires_in":3600,"token_type":"Bearer","scope":"openid spark:people_read"}
            """
        )
    }

    private func iso8601(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private func makeAPI(httpClient: HTTPClient) -> PeopleAPI {
    PeopleAPI(transport: WebexTransport(httpClient: httpClient) {
        AccessTokenState(
            value: "people-token",
            expiresAt: Date(timeIntervalSince1970: 1_000),
            tokenType: "Bearer"
        )
    })
}

private func httpResponse(
    statusCode: Int,
    headers: [String: String] = [:],
    body: String
) -> HTTPResponse {
    HTTPResponse(
        data: Data(body.utf8),
        response: HTTPURLResponse(
            url: URL(string: "https://webexapis.com/v1/people")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    )
}

private actor MockPeopleHTTPClient: HTTPClient {
    private var responses: [HTTPResponse] = []
    private var requests: [URLRequest] = []

    func enqueue(response: HTTPResponse) {
        responses.append(response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw WebexSDKError.network("Unexpected people request")
        }

        return responses.removeFirst()
    }
}
