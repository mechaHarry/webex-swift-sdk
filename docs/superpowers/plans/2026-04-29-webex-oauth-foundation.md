# Webex OAuth Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the SwiftPM foundation for Webex OAuth 2.0 with PKCE, local Keychain-backed account storage, token refresh lifecycle, and a minimal authenticated `people.me()` REST endpoint.

**Architecture:** The package exposes `WebexClient` for one account and `WebexClientRegistry` for persisted multi-account construction. OAuth, storage, token refresh, retry/backoff, and REST transport are isolated behind small protocols so tests can run without Webex credentials or browser automation.

**Tech Stack:** SwiftPM, Swift concurrency, Foundation, AuthenticationServices, Security Keychain Services, CryptoKit, XCTest.

---

## Scope Check

This plan implements the OAuth and authenticated REST foundation from `docs/superpowers/specs/2026-04-29-webex-oauth-design.md`. It deliberately includes only one typed Webex API group, `PeopleAPI.me()`, because that endpoint is enough to validate authenticated transport and discover account metadata. Messaging, rooms, pagination helpers, webhooks, and UI screens are separate follow-up plans.

Relevant docs:

- Webex OAuth: https://developer.webex.com/messaging/docs/api/guides/integrations-and-authorization
- Webex Login with Webex: https://developer.webex.com/create/docs/login-with-webex
- Webex Get My Own Details: https://developer.webex.com/messaging/docs/api/v1/people/get-my-own-details
- Webex REST basics and pagination: https://developer.webex.com/messaging/docs/basics
- Apple ASWebAuthenticationSession: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession
- Apple WebAuthenticationSession: https://developer.apple.com/documentation/authenticationservices/webauthenticationsession
- Apple Keychain Services: https://developer.apple.com/documentation/security/keychain-services

## File Structure

- Create `Package.swift`: SwiftPM package definition for the SDK and tests.
- Create `Sources/WebexSwiftSDK/WebexSwiftSDK.swift`: public exports and package marker.
- Create `Sources/WebexSwiftSDK/Core/WebexAccountID.swift`: stable local account UUID.
- Create `Sources/WebexSwiftSDK/Core/WebexIntegrationConfiguration.swift`: user-provided Webex OAuth config.
- Create `Sources/WebexSwiftSDK/Core/WebexAccountMetadata.swift`: mutable account display and Webex identity metadata.
- Create `Sources/WebexSwiftSDK/Core/WebexSDKError.swift`: typed public errors with redaction-safe descriptions.
- Create `Sources/WebexSwiftSDK/Security/Redactor.swift`: shared sensitive-value redaction.
- Create `Sources/WebexSwiftSDK/OAuth/PKCE.swift`: verifier and S256 challenge generation.
- Create `Sources/WebexSwiftSDK/OAuth/WebexAuthorizationRequest.swift`: authorization URL builder.
- Create `Sources/WebexSwiftSDK/OAuth/OAuthBrowserSession.swift`: browser auth protocol.
- Create `Sources/WebexSwiftSDK/OAuth/ASWebAuthenticationSessionAdapter.swift`: default Apple-native browser auth implementation.
- Create `Sources/WebexSwiftSDK/OAuth/OAuthCallbackParser.swift`: redirect URL parsing and state validation.
- Create `Sources/WebexSwiftSDK/OAuth/WebexTokenEndpoint.swift`: token exchange and refresh request construction plus token response models.
- Create `Sources/WebexSwiftSDK/Storage/WebexCredentialStore.swift`: credential store protocol and records.
- Create `Sources/WebexSwiftSDK/Storage/WebexTokenStore.swift`: token store protocol and records.
- Create `Sources/WebexSwiftSDK/Storage/WebexAccountMetadataStore.swift`: metadata store protocol.
- Create `Sources/WebexSwiftSDK/Storage/WebexAccountIndexStore.swift`: persisted local account ID index.
- Create `Sources/WebexSwiftSDK/Storage/InMemoryStores.swift`: test and lightweight runtime stores.
- Create `Sources/WebexSwiftSDK/Storage/KeychainStore.swift`: Keychain-backed store implementation.
- Create `Sources/WebexSwiftSDK/HTTP/HTTPClient.swift`: transport protocol and `URLSession` implementation.
- Create `Sources/WebexSwiftSDK/HTTP/RetryPolicy.swift`: exponential backoff, jitter, and `Retry-After` handling.
- Create `Sources/WebexSwiftSDK/Auth/TokenManager.swift`: actor-isolated access-token cache and refresh coalescing.
- Create `Sources/WebexSwiftSDK/Auth/WebexClientRegistry.swift`: persisted account registry and client construction.
- Create `Sources/WebexSwiftSDK/WebexClient.swift`: one-account SDK facade.
- Create `Sources/WebexSwiftSDK/API/PeopleAPI.swift`: first typed API group for `GET /v1/people/me`.
- Create `Tests/WebexSwiftSDKTests/*Tests.swift`: focused XCTest files matching the source responsibilities.
- Modify `README.md`: add a short Swift usage example after the package compiles.

## Task 1: Bootstrap SwiftPM Package

**Files:**
- Create: `Package.swift`
- Create: `Sources/WebexSwiftSDK/WebexSwiftSDK.swift`
- Create: `Tests/WebexSwiftSDKTests/BootstrapTests.swift`

- [ ] **Step 1: Write the package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-swift-sdk",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WebexSwiftSDK",
            targets: ["WebexSwiftSDK"]
        )
    ],
    targets: [
        .target(
            name: "WebexSwiftSDK"
        ),
        .testTarget(
            name: "WebexSwiftSDKTests",
            dependencies: ["WebexSwiftSDK"]
        )
    ]
)
```

- [ ] **Step 2: Add a package marker**

Create `Sources/WebexSwiftSDK/WebexSwiftSDK.swift`:

```swift
import Foundation

public enum WebexSwiftSDK {
    public static let name = "WebexSwiftSDK"
}
```

- [ ] **Step 3: Write the bootstrap test**

Create `Tests/WebexSwiftSDKTests/BootstrapTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class BootstrapTests: XCTestCase {
    func testPackageMarkerIsAvailable() {
        XCTAssertEqual(WebexSwiftSDK.name, "WebexSwiftSDK")
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test`

Expected: PASS with one executed test.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/WebexSwiftSDK/WebexSwiftSDK.swift Tests/WebexSwiftSDKTests/BootstrapTests.swift
git commit -m "chore: bootstrap Swift package"
```

## Task 2: Core Models And Redaction-Safe Errors

**Files:**
- Create: `Sources/WebexSwiftSDK/Core/WebexAccountID.swift`
- Create: `Sources/WebexSwiftSDK/Core/WebexIntegrationConfiguration.swift`
- Create: `Sources/WebexSwiftSDK/Core/WebexAccountMetadata.swift`
- Create: `Sources/WebexSwiftSDK/Core/WebexSDKError.swift`
- Create: `Sources/WebexSwiftSDK/Security/Redactor.swift`
- Create: `Tests/WebexSwiftSDKTests/CoreModelTests.swift`
- Modify: `Sources/WebexSwiftSDK/WebexSwiftSDK.swift`

- [ ] **Step 1: Write failing core model tests**

Create `Tests/WebexSwiftSDKTests/CoreModelTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class CoreModelTests: XCTestCase {
    func testAccountIDRoundTripsStableUUIDString() throws {
        let raw = "A4B0F5D9-6F9B-4B98-92A3-85B32B722001"
        let accountID = try WebexAccountID(rawValue: raw)

        XCTAssertEqual(accountID.rawValue, raw.lowercased())
        XCTAssertEqual(WebexAccountID(rawValue: accountID.rawValue), accountID)
    }

    func testAccountIDGeneratesUniqueValues() {
        let first = WebexAccountID()
        let second = WebexAccountID()

        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.rawValue.isEmpty)
    }

    func testIntegrationConfigurationNormalizesScopes() {
        let config = WebexIntegrationConfiguration(
            clientID: "client-1",
            clientSecret: "secret-1",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:people_read", "openid", "spark:people_read"]
        )

        XCTAssertEqual(config.scopeString, "openid spark:people_read")
    }

    func testErrorDescriptionRedactsSensitiveValues() {
        let error = WebexSDKError.tokenExchangeFailed(
            statusCode: 400,
            message: "client_secret=secret-1 access_token=token-1 refresh_token=refresh-1 code=auth-code",
            trackingID: "API_123"
        )

        let description = String(describing: error)
        XCTAssertFalse(description.contains("secret-1"))
        XCTAssertFalse(description.contains("token-1"))
        XCTAssertFalse(description.contains("refresh-1"))
        XCTAssertFalse(description.contains("auth-code"))
        XCTAssertTrue(description.contains("[redacted]"))
        XCTAssertTrue(description.contains("API_123"))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter CoreModelTests`

Expected: FAIL because `WebexAccountID`, `WebexIntegrationConfiguration`, `WebexSDKError`, and `Redactor` are not defined.

- [ ] **Step 3: Implement core models**

Create `Sources/WebexSwiftSDK/Core/WebexAccountID.swift`:

```swift
import Foundation

public struct WebexAccountID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init() {
        self.rawValue = UUID().uuidString.lowercased()
    }

    public init(rawValue: String) throws {
        guard let uuid = UUID(uuidString: rawValue) else {
            throw WebexSDKError.invalidAccountID(rawValue)
        }
        self.rawValue = uuid.uuidString.lowercased()
    }

    public var description: String {
        rawValue
    }
}
```

Create `Sources/WebexSwiftSDK/Core/WebexIntegrationConfiguration.swift`:

```swift
import Foundation

public struct WebexIntegrationConfiguration: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String
    public let redirectURI: URL
    public let scopes: [String]
    public let prefersEphemeralWebBrowserSession: Bool

    public init(
        clientID: String,
        clientSecret: String,
        redirectURI: URL,
        scopes: [String],
        prefersEphemeralWebBrowserSession: Bool = false
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = Array(Set(scopes)).sorted()
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
    }

    public var scopeString: String {
        scopes.joined(separator: " ")
    }
}
```

Create `Sources/WebexSwiftSDK/Core/WebexAccountMetadata.swift`:

```swift
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
```

Create `Sources/WebexSwiftSDK/Security/Redactor.swift`:

```swift
import Foundation

enum Redactor {
    private static let sensitiveKeys = [
        "access_token",
        "refresh_token",
        "client_secret",
        "code",
        "code_verifier",
        "Authorization"
    ]

    static func redact(_ value: String) -> String {
        var redacted = value
        for key in sensitiveKeys {
            redacted = redactAssignments(named: key, in: redacted)
        }
        return redacted
    }

    private static func redactAssignments(named key: String, in value: String) -> String {
        let patterns = [
            "\(key)=",
            "\(key): ",
            "\"\(key)\":\"",
            "\"\(key)\": \""
        ]

        var result = value
        for pattern in patterns {
            while let range = result.range(of: pattern) {
                let valueStart = range.upperBound
                let valueEnd = result[valueStart...].firstIndex { character in
                    character == " " || character == "&" || character == "\"" || character == "," || character == "\n"
                } ?? result.endIndex
                result.replaceSubrange(valueStart..<valueEnd, with: "[redacted]")
            }
        }
        return result
    }
}
```

Create `Sources/WebexSwiftSDK/Core/WebexSDKError.swift`:

```swift
import Foundation

public enum WebexSDKError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidAccountID(String)
    case invalidAuthorizationCallback(String)
    case authorizationStateMismatch(expected: String, actual: String?)
    case userCancelledAuthorization
    case missingCredential(WebexAccountID)
    case missingRefreshToken(WebexAccountID)
    case reauthenticationRequired(WebexAccountID)
    case duplicateAccount(existing: WebexAccountID, reason: String)
    case tokenExchangeFailed(statusCode: Int, message: String, trackingID: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case webexAPI(statusCode: Int, trackingID: String?, message: String)
    case network(String)

    public var description: String {
        switch self {
        case .invalidAccountID(let value):
            return "Invalid Webex account ID: \(value)"
        case .invalidAuthorizationCallback(let value):
            return "Invalid authorization callback: \(Redactor.redact(value))"
        case .authorizationStateMismatch(let expected, let actual):
            return "Authorization state mismatch. expected=\(expected) actual=\(actual ?? "nil")"
        case .userCancelledAuthorization:
            return "User cancelled Webex authorization"
        case .missingCredential(let accountID):
            return "Missing credential for account \(accountID.rawValue)"
        case .missingRefreshToken(let accountID):
            return "Missing refresh token for account \(accountID.rawValue)"
        case .reauthenticationRequired(let accountID):
            return "Reauthentication required for account \(accountID.rawValue)"
        case .duplicateAccount(let existing, let reason):
            return "Duplicate Webex account candidate existing=\(existing.rawValue) reason=\(reason)"
        case .tokenExchangeFailed(let statusCode, let message, let trackingID):
            return "Token exchange failed status=\(statusCode) trackingID=\(trackingID ?? "none") message=\(Redactor.redact(message))"
        case .rateLimited(let retryAfter):
            return "Rate limited retryAfter=\(retryAfter.map(String.init) ?? "none")"
        case .webexAPI(let statusCode, let trackingID, let message):
            return "Webex API error status=\(statusCode) trackingID=\(trackingID ?? "none") message=\(Redactor.redact(message))"
        case .network(let message):
            return "Network error: \(Redactor.redact(message))"
        }
    }
}
```

- [ ] **Step 4: Keep package marker minimal**

Modify `Sources/WebexSwiftSDK/WebexSwiftSDK.swift` if needed so it still contains:

```swift
import Foundation

public enum WebexSwiftSDK {
    public static let name = "WebexSwiftSDK"
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter CoreModelTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/WebexSwiftSDK/Core Sources/WebexSwiftSDK/Security Sources/WebexSwiftSDK/WebexSwiftSDK.swift Tests/WebexSwiftSDKTests/CoreModelTests.swift
git commit -m "feat: add core Webex account models"
```

## Task 3: PKCE And Authorization URL Builder

**Files:**
- Create: `Sources/WebexSwiftSDK/OAuth/PKCE.swift`
- Create: `Sources/WebexSwiftSDK/OAuth/WebexAuthorizationRequest.swift`
- Create: `Tests/WebexSwiftSDKTests/PKCETests.swift`
- Create: `Tests/WebexSwiftSDKTests/AuthorizationRequestTests.swift`

- [ ] **Step 1: Write failing PKCE tests**

Create `Tests/WebexSwiftSDKTests/PKCETests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class PKCETests: XCTestCase {
    func testKnownVerifierProducesS256Challenge() throws {
        let challenge = PKCE.s256Challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testGeneratedVerifierUsesAllowedCharactersAndLength() throws {
        let verifier = try PKCE.generateVerifier(byteCount: 32)

        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
        XCTAssertTrue(verifier.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "." || character == "_" || character == "~"
        })
    }
}
```

- [ ] **Step 2: Write failing authorization URL tests**

Create `Tests/WebexSwiftSDKTests/AuthorizationRequestTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class AuthorizationRequestTests: XCTestCase {
    func testAuthorizationURLContainsRequiredWebexParameters() throws {
        let config = WebexIntegrationConfiguration(
            clientID: "client-123",
            clientSecret: "secret-123",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["spark:people_read", "openid"]
        )

        let request = WebexAuthorizationRequest(
            configuration: config,
            state: "state-123",
            codeChallenge: "challenge-123",
            loginHint: "user@example.com",
            prompt: "select_account"
        )

        let url = try request.url()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: components!.queryItems!.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "webexapis.com")
        XCTAssertEqual(url.path, "/v1/authorize")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["client_id"], "client-123")
        XCTAssertEqual(query["redirect_uri"], "myapp://oauth/webex")
        XCTAssertEqual(query["scope"], "openid spark:people_read")
        XCTAssertEqual(query["state"], "state-123")
        XCTAssertEqual(query["code_challenge"], "challenge-123")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["login_hint"], "user@example.com")
        XCTAssertEqual(query["prompt"], "select_account")
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

Run: `swift test --filter PKCETests && swift test --filter AuthorizationRequestTests`

Expected: FAIL because PKCE and authorization request types are missing.

- [ ] **Step 4: Implement PKCE**

Create `Sources/WebexSwiftSDK/OAuth/PKCE.swift`:

```swift
import CryptoKit
import Foundation
import Security

public enum PKCE {
    public static func generateVerifier(byteCount: Int = 32) throws -> String {
        precondition(byteCount >= 32)
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw WebexSDKError.network("Unable to generate secure random PKCE verifier")
        }
        return base64URLEncoded(Data(bytes))
    }

    public static func s256Challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncoded(Data(digest))
    }

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

- [ ] **Step 5: Implement authorization request builder**

Create `Sources/WebexSwiftSDK/OAuth/WebexAuthorizationRequest.swift`:

```swift
import Foundation

public struct WebexAuthorizationRequest: Equatable, Sendable {
    public var authorizationEndpoint: URL
    public var configuration: WebexIntegrationConfiguration
    public var state: String
    public var codeChallenge: String
    public var loginHint: String?
    public var prompt: String?

    public init(
        authorizationEndpoint: URL = URL(string: "https://webexapis.com/v1/authorize")!,
        configuration: WebexIntegrationConfiguration,
        state: String,
        codeChallenge: String,
        loginHint: String? = nil,
        prompt: String? = nil
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.configuration = configuration
        self.state = state
        self.codeChallenge = codeChallenge
        self.loginHint = loginHint
        self.prompt = prompt
    }

    public func url() throws -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: configuration.scopeString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        if let loginHint {
            components?.queryItems?.append(URLQueryItem(name: "login_hint", value: loginHint))
        }

        if let prompt {
            components?.queryItems?.append(URLQueryItem(name: "prompt", value: prompt))
        }

        guard let url = components?.url else {
            throw WebexSDKError.invalidAuthorizationCallback("Unable to build Webex authorization URL")
        }
        return url
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter PKCETests && swift test --filter AuthorizationRequestTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/WebexSwiftSDK/OAuth/PKCE.swift Sources/WebexSwiftSDK/OAuth/WebexAuthorizationRequest.swift Tests/WebexSwiftSDKTests/PKCETests.swift Tests/WebexSwiftSDKTests/AuthorizationRequestTests.swift
git commit -m "feat: build Webex authorization requests with PKCE"
```

## Task 4: Browser Session Abstraction And Callback Parsing

**Files:**
- Create: `Sources/WebexSwiftSDK/OAuth/OAuthBrowserSession.swift`
- Create: `Sources/WebexSwiftSDK/OAuth/ASWebAuthenticationSessionAdapter.swift`
- Create: `Sources/WebexSwiftSDK/OAuth/OAuthCallbackParser.swift`
- Create: `Tests/WebexSwiftSDKTests/OAuthCallbackParserTests.swift`

- [ ] **Step 1: Write failing callback parser tests**

Create `Tests/WebexSwiftSDKTests/OAuthCallbackParserTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class OAuthCallbackParserTests: XCTestCase {
    func testParsesAuthorizationCodeWhenStateMatches() throws {
        let callback = URL(string: "myapp://oauth/webex?code=abc123&state=state123")!

        let result = try OAuthCallbackParser.parse(callbackURL: callback, expectedState: "state123")

        XCTAssertEqual(result.code, "abc123")
        XCTAssertEqual(result.state, "state123")
    }

    func testThrowsWhenStateDoesNotMatch() {
        let callback = URL(string: "myapp://oauth/webex?code=abc123&state=wrong")!

        XCTAssertThrowsError(try OAuthCallbackParser.parse(callbackURL: callback, expectedState: "expected")) { error in
            XCTAssertEqual(error as? WebexSDKError, .authorizationStateMismatch(expected: "expected", actual: "wrong"))
        }
    }

    func testThrowsWhenCodeIsMissing() {
        let callback = URL(string: "myapp://oauth/webex?state=state123")!

        XCTAssertThrowsError(try OAuthCallbackParser.parse(callbackURL: callback, expectedState: "state123"))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter OAuthCallbackParserTests`

Expected: FAIL because callback parser types are missing.

- [ ] **Step 3: Implement browser session protocol**

Create `Sources/WebexSwiftSDK/OAuth/OAuthBrowserSession.swift`:

```swift
import Foundation

public protocol OAuthBrowserSession: AnyObject, Sendable {
    func authenticate(
        authorizationURL: URL,
        callbackURLScheme: String,
        prefersEphemeralWebBrowserSession: Bool
    ) async throws -> URL
}
```

- [ ] **Step 4: Implement ASWebAuthenticationSession adapter**

Create `Sources/WebexSwiftSDK/OAuth/ASWebAuthenticationSessionAdapter.swift`:

```swift
import AuthenticationServices
import Foundation

public final class ASWebAuthenticationSessionAdapter: NSObject, OAuthBrowserSession, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private var anchorProvider: @MainActor () -> ASPresentationAnchor
    @MainActor private var currentSession: ASWebAuthenticationSession?

    public init(anchorProvider: @escaping @MainActor () -> ASPresentationAnchor) {
        self.anchorProvider = anchorProvider
    }

    public func authenticate(
        authorizationURL: URL,
        callbackURLScheme: String,
        prefersEphemeralWebBrowserSession: Bool
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: authorizationURL,
                    callbackURLScheme: callbackURLScheme
                ) { [weak self] callbackURL, error in
                    Task { @MainActor in
                        self?.currentSession = nil
                    }
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let error = error as? ASWebAuthenticationSessionError,
                              error.code == .canceledLogin {
                        continuation.resume(throwing: WebexSDKError.userCancelledAuthorization)
                    } else {
                        continuation.resume(throwing: WebexSDKError.network(error?.localizedDescription ?? "Web authentication failed"))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
                currentSession = session
                if session.start() == false {
                    currentSession = nil
                    continuation.resume(throwing: WebexSDKError.network("Unable to start ASWebAuthenticationSession"))
                }
            }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchorProvider()
        }
    }
}
```

- [ ] **Step 5: Implement callback parser**

Create `Sources/WebexSwiftSDK/OAuth/OAuthCallbackParser.swift`:

```swift
import Foundation

public struct OAuthAuthorizationCode: Equatable, Sendable {
    public let code: String
    public let state: String
}

public enum OAuthCallbackParser {
    public static func parse(callbackURL: URL, expectedState: String) throws -> OAuthAuthorizationCode {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw WebexSDKError.invalidAuthorizationCallback(callbackURL.absoluteString)
        }

        let items = components.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value
        let state = items.first { $0.name == "state" }?.value

        guard state == expectedState else {
            throw WebexSDKError.authorizationStateMismatch(expected: expectedState, actual: state)
        }

        guard let code, code.isEmpty == false else {
            throw WebexSDKError.invalidAuthorizationCallback(callbackURL.absoluteString)
        }

        return OAuthAuthorizationCode(code: code, state: expectedState)
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter OAuthCallbackParserTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/WebexSwiftSDK/OAuth/OAuthBrowserSession.swift Sources/WebexSwiftSDK/OAuth/ASWebAuthenticationSessionAdapter.swift Sources/WebexSwiftSDK/OAuth/OAuthCallbackParser.swift Tests/WebexSwiftSDKTests/OAuthCallbackParserTests.swift
git commit -m "feat: add native OAuth browser session boundary"
```

## Task 5: Storage Protocols And In-Memory Stores

**Files:**
- Create: `Sources/WebexSwiftSDK/Storage/WebexCredentialStore.swift`
- Create: `Sources/WebexSwiftSDK/Storage/WebexTokenStore.swift`
- Create: `Sources/WebexSwiftSDK/Storage/WebexAccountMetadataStore.swift`
- Create: `Sources/WebexSwiftSDK/Storage/WebexAccountIndexStore.swift`
- Create: `Sources/WebexSwiftSDK/Storage/InMemoryStores.swift`
- Create: `Tests/WebexSwiftSDKTests/InMemoryStoreTests.swift`

- [ ] **Step 1: Write failing storage tests**

Create `Tests/WebexSwiftSDKTests/InMemoryStoreTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class InMemoryStoreTests: XCTestCase {
    func testCredentialRecordRoundTripsByAccountID() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let credential = WebexCredentialRecord(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        try await store.saveCredential(credential, for: accountID)

        XCTAssertEqual(try await store.loadCredential(for: accountID), credential)
    }

    func testTokenRecordDoesNotRequirePersistedAccessToken() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()
        let token = WebexTokenRecord(
            refreshToken: "refresh",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 100),
            lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 10),
            grantedScopes: ["openid"],
            tokenType: "Bearer",
            lastRefreshAt: Date(timeIntervalSince1970: 5)
        )

        try await store.saveTokenRecord(token, for: accountID)

        XCTAssertEqual(try await store.loadTokenRecord(for: accountID), token)
    }

    func testDeleteRemovesAllRecordsForAccount() async throws {
        let accountID = WebexAccountID()
        let store = InMemoryWebexStore()

        try await store.saveMetadata(WebexAccountMetadata(email: "user@example.com"), for: accountID)
        try await store.deleteMetadata(for: accountID)

        XCTAssertNil(try await store.loadMetadata(for: accountID))
    }

    func testAccountIndexRoundTripsPersistedIDs() async throws {
        let first = WebexAccountID()
        let second = WebexAccountID()
        let store = InMemoryWebexStore()

        try await store.saveAccountIDs([first, second])

        XCTAssertEqual(try await store.loadAccountIDs(), [first, second])
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter InMemoryStoreTests`

Expected: FAIL because storage protocols and records are missing.

- [ ] **Step 3: Implement storage records and protocols**

Create `Sources/WebexSwiftSDK/Storage/WebexCredentialStore.swift`:

```swift
import Foundation

public struct WebexCredentialRecord: Equatable, Codable, Sendable {
    public var clientID: String
    public var clientSecret: String
    public var redirectURI: URL
    public var scopes: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(clientID: String, clientSecret: String, redirectURI: URL, scopes: [String], createdAt: Date, updatedAt: Date) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scopes = scopes.sorted()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var configuration: WebexIntegrationConfiguration {
        WebexIntegrationConfiguration(clientID: clientID, clientSecret: clientSecret, redirectURI: redirectURI, scopes: scopes)
    }
}

public protocol WebexCredentialStore: Sendable {
    func loadCredential(for accountID: WebexAccountID) async throws -> WebexCredentialRecord?
    func saveCredential(_ record: WebexCredentialRecord, for accountID: WebexAccountID) async throws
    func deleteCredential(for accountID: WebexAccountID) async throws
}
```

Create `Sources/WebexSwiftSDK/Storage/WebexTokenStore.swift`:

```swift
import Foundation

public struct WebexTokenRecord: Equatable, Codable, Sendable {
    public var refreshToken: String
    public var refreshTokenExpiresAt: Date
    public var lastAccessTokenExpiresAt: Date
    public var grantedScopes: [String]
    public var tokenType: String
    public var lastRefreshAt: Date

    public init(
        refreshToken: String,
        refreshTokenExpiresAt: Date,
        lastAccessTokenExpiresAt: Date,
        grantedScopes: [String],
        tokenType: String,
        lastRefreshAt: Date
    ) {
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.lastAccessTokenExpiresAt = lastAccessTokenExpiresAt
        self.grantedScopes = grantedScopes.sorted()
        self.tokenType = tokenType
        self.lastRefreshAt = lastRefreshAt
    }
}

public protocol WebexTokenStore: Sendable {
    func loadTokenRecord(for accountID: WebexAccountID) async throws -> WebexTokenRecord?
    func saveTokenRecord(_ record: WebexTokenRecord, for accountID: WebexAccountID) async throws
    func deleteTokenRecord(for accountID: WebexAccountID) async throws
}
```

Create `Sources/WebexSwiftSDK/Storage/WebexAccountMetadataStore.swift`:

```swift
import Foundation

public protocol WebexAccountMetadataStore: Sendable {
    func loadMetadata(for accountID: WebexAccountID) async throws -> WebexAccountMetadata?
    func saveMetadata(_ metadata: WebexAccountMetadata, for accountID: WebexAccountID) async throws
    func deleteMetadata(for accountID: WebexAccountID) async throws
}
```

- [ ] **Step 4: Implement account index store protocol**

Create `Sources/WebexSwiftSDK/Storage/WebexAccountIndexStore.swift`:

```swift
import Foundation

public protocol WebexAccountIndexStore: Sendable {
    func loadAccountIDs() async throws -> [WebexAccountID]
    func saveAccountIDs(_ accountIDs: [WebexAccountID]) async throws
}
```

- [ ] **Step 5: Implement in-memory store**

Create `Sources/WebexSwiftSDK/Storage/InMemoryStores.swift`:

```swift
import Foundation

public actor InMemoryWebexStore: WebexCredentialStore, WebexTokenStore, WebexAccountMetadataStore, WebexAccountIndexStore {
    private var credentials: [WebexAccountID: WebexCredentialRecord] = [:]
    private var tokens: [WebexAccountID: WebexTokenRecord] = [:]
    private var metadata: [WebexAccountID: WebexAccountMetadata] = [:]
    private var accountIDs: [WebexAccountID] = []

    public init() {}

    public func loadCredential(for accountID: WebexAccountID) async throws -> WebexCredentialRecord? {
        credentials[accountID]
    }

    public func saveCredential(_ record: WebexCredentialRecord, for accountID: WebexAccountID) async throws {
        credentials[accountID] = record
    }

    public func deleteCredential(for accountID: WebexAccountID) async throws {
        credentials.removeValue(forKey: accountID)
    }

    public func loadTokenRecord(for accountID: WebexAccountID) async throws -> WebexTokenRecord? {
        tokens[accountID]
    }

    public func saveTokenRecord(_ record: WebexTokenRecord, for accountID: WebexAccountID) async throws {
        tokens[accountID] = record
    }

    public func deleteTokenRecord(for accountID: WebexAccountID) async throws {
        tokens.removeValue(forKey: accountID)
    }

    public func loadMetadata(for accountID: WebexAccountID) async throws -> WebexAccountMetadata? {
        metadata[accountID]
    }

    public func saveMetadata(_ metadata: WebexAccountMetadata, for accountID: WebexAccountID) async throws {
        self.metadata[accountID] = metadata
    }

    public func deleteMetadata(for accountID: WebexAccountID) async throws {
        metadata.removeValue(forKey: accountID)
    }

    public func loadAccountIDs() async throws -> [WebexAccountID] {
        accountIDs
    }

    public func saveAccountIDs(_ accountIDs: [WebexAccountID]) async throws {
        self.accountIDs = accountIDs
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter InMemoryStoreTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/WebexSwiftSDK/Storage Tests/WebexSwiftSDKTests/InMemoryStoreTests.swift
git commit -m "feat: add Webex account storage protocols"
```

## Task 6: Token Endpoint Models And HTTP Test Client

**Files:**
- Create: `Sources/WebexSwiftSDK/HTTP/HTTPClient.swift`
- Create: `Sources/WebexSwiftSDK/OAuth/WebexTokenEndpoint.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexTokenEndpointTests.swift`

- [ ] **Step 1: Write failing token endpoint tests**

Create `Tests/WebexSwiftSDKTests/WebexTokenEndpointTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class WebexTokenEndpointTests: XCTestCase {
    func testAuthorizationCodeRequestUsesFormBody() throws {
        let config = WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"]
        )

        let request = try WebexTokenEndpoint.authorizationCodeRequest(
            configuration: config,
            code: "code-1",
            codeVerifier: "verifier-1"
        )

        let body = String(data: request.httpBody!, encoding: .utf8)!
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/access_token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("client_id=client"))
        XCTAssertTrue(body.contains("client_secret=secret"))
        XCTAssertTrue(body.contains("code=code-1"))
        XCTAssertTrue(body.contains("code_verifier=verifier-1"))
    }

    func testTokenResponseBuildsRecordAndMemoryToken() throws {
        let now = Date(timeIntervalSince1970: 100)
        let response = WebexTokenResponse(
            accessToken: "access",
            expiresIn: 10,
            refreshToken: "refresh",
            refreshTokenExpiresIn: 100,
            tokenType: "Bearer",
            scope: "openid spark:people_read",
            idToken: nil
        )

        let record = response.tokenRecord(receivedAt: now)
        let memoryToken = response.accessTokenState(receivedAt: now)

        XCTAssertEqual(record.refreshToken, "refresh")
        XCTAssertEqual(record.refreshTokenExpiresAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(record.lastAccessTokenExpiresAt, Date(timeIntervalSince1970: 110))
        XCTAssertEqual(record.grantedScopes, ["openid", "spark:people_read"])
        XCTAssertEqual(memoryToken.value, "access")
        XCTAssertEqual(memoryToken.expiresAt, Date(timeIntervalSince1970: 110))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter WebexTokenEndpointTests`

Expected: FAIL because HTTP client and token endpoint types are missing.

- [ ] **Step 3: Implement HTTP client protocol**

Create `Sources/WebexSwiftSDK/HTTP/HTTPClient.swift`:

```swift
import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let response: HTTPURLResponse

    public init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebexSDKError.network("Response was not HTTPURLResponse")
            }
            return HTTPResponse(data: data, response: httpResponse)
        } catch let error as WebexSDKError {
            throw error
        } catch {
            throw WebexSDKError.network(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Implement token endpoint**

Create `Sources/WebexSwiftSDK/OAuth/WebexTokenEndpoint.swift`:

```swift
import Foundation

public struct AccessTokenState: Equatable, Sendable {
    public let value: String
    public let expiresAt: Date
    public let tokenType: String

    public init(value: String, expiresAt: Date, tokenType: String) {
        self.value = value
        self.expiresAt = expiresAt
        self.tokenType = tokenType
    }
}

public struct WebexTokenResponse: Codable, Equatable, Sendable {
    public let accessToken: String
    public let expiresIn: TimeInterval
    public let refreshToken: String
    public let refreshTokenExpiresIn: TimeInterval
    public let tokenType: String
    public let scope: String?
    public let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case tokenType = "token_type"
        case scope
        case idToken = "id_token"
    }

    public init(
        accessToken: String,
        expiresIn: TimeInterval,
        refreshToken: String,
        refreshTokenExpiresIn: TimeInterval,
        tokenType: String,
        scope: String?,
        idToken: String?
    ) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.refreshTokenExpiresIn = refreshTokenExpiresIn
        self.tokenType = tokenType
        self.scope = scope
        self.idToken = idToken
    }

    public func tokenRecord(receivedAt: Date) -> WebexTokenRecord {
        WebexTokenRecord(
            refreshToken: refreshToken,
            refreshTokenExpiresAt: receivedAt.addingTimeInterval(refreshTokenExpiresIn),
            lastAccessTokenExpiresAt: receivedAt.addingTimeInterval(expiresIn),
            grantedScopes: scope?.split(separator: " ").map(String.init) ?? [],
            tokenType: tokenType,
            lastRefreshAt: receivedAt
        )
    }

    public func accessTokenState(receivedAt: Date) -> AccessTokenState {
        AccessTokenState(
            value: accessToken,
            expiresAt: receivedAt.addingTimeInterval(expiresIn),
            tokenType: tokenType
        )
    }
}

public enum WebexTokenEndpoint {
    public static var accessTokenURL = URL(string: "https://webexapis.com/v1/access_token")!

    public static func authorizationCodeRequest(
        configuration: WebexIntegrationConfiguration,
        code: String,
        codeVerifier: String
    ) throws -> URLRequest {
        try formRequest(parameters: [
            "grant_type": "authorization_code",
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "code": code,
            "redirect_uri": configuration.redirectURI.absoluteString,
            "code_verifier": codeVerifier
        ])
    }

    public static func refreshTokenRequest(
        configuration: WebexIntegrationConfiguration,
        refreshToken: String
    ) throws -> URLRequest {
        try formRequest(parameters: [
            "grant_type": "refresh_token",
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "refresh_token": refreshToken
        ])
    }

    private static func formRequest(parameters: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: accessTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(parameters).data(using: .utf8)
        return request
    }

    private static func formEncode(_ parameters: [String: String]) -> String {
        parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter WebexTokenEndpointTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/WebexSwiftSDK/HTTP/HTTPClient.swift Sources/WebexSwiftSDK/OAuth/WebexTokenEndpoint.swift Tests/WebexSwiftSDKTests/WebexTokenEndpointTests.swift
git commit -m "feat: add Webex token endpoint models"
```

## Task 7: Token Manager With Refresh Coalescing

**Files:**
- Create: `Sources/WebexSwiftSDK/HTTP/RetryPolicy.swift`
- Create: `Sources/WebexSwiftSDK/Auth/TokenManager.swift`
- Create: `Tests/WebexSwiftSDKTests/TokenManagerTests.swift`

- [ ] **Step 1: Write failing token manager tests**

Create `Tests/WebexSwiftSDKTests/TokenManagerTests.swift`:

```swift
import Foundation
import XCTest
@testable import WebexSwiftSDK

final class TokenManagerTests: XCTestCase {
    func testUsesFreshMemoryTokenWithoutRefresh() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 100))
        let http = MockHTTPClient()
        let store = InMemoryWebexStore()
        let accountID = WebexAccountID()
        let manager = TokenManager(
            accountID: accountID,
            configuration: sampleConfiguration(),
            tokenStore: store,
            httpClient: http,
            clock: clock.now,
            refreshLeeway: 30
        )

        await manager.setAccessTokenForTesting(AccessTokenState(value: "access", expiresAt: Date(timeIntervalSince1970: 200), tokenType: "Bearer"))

        let token = try await manager.validAccessToken()

        XCTAssertEqual(token.value, "access")
        XCTAssertEqual(await http.requestCount, 0)
    }

    func testRefreshesNearExpiredTokenAndPersistsRefreshTokenOnly() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 100))
        let http = MockHTTPClient()
        let store = InMemoryWebexStore()
        let accountID = WebexAccountID()
        try await store.saveTokenRecord(
            WebexTokenRecord(
                refreshToken: "old-refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 500),
                lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 110),
                grantedScopes: ["openid"],
                tokenType: "Bearer",
                lastRefreshAt: Date(timeIntervalSince1970: 50)
            ),
            for: accountID
        )
        await http.enqueue(statusCode: 200, json: """
        {
          "access_token": "new-access",
          "expires_in": 100,
          "refresh_token": "new-refresh",
          "refresh_token_expires_in": 500,
          "token_type": "Bearer",
          "scope": "openid"
        }
        """)

        let manager = TokenManager(
            accountID: accountID,
            configuration: sampleConfiguration(),
            tokenStore: store,
            httpClient: http,
            clock: clock.now,
            refreshLeeway: 30
        )

        let token = try await manager.validAccessToken()
        let record = try await store.loadTokenRecord(for: accountID)

        XCTAssertEqual(token.value, "new-access")
        XCTAssertEqual(record?.refreshToken, "new-refresh")
        XCTAssertEqual(await http.requestCount, 1)
    }

    func testConcurrentCallsShareOneRefreshRequest() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 100))
        let http = MockHTTPClient()
        let store = InMemoryWebexStore()
        let accountID = WebexAccountID()
        try await store.saveTokenRecord(
            WebexTokenRecord(
                refreshToken: "refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 500),
                lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 101),
                grantedScopes: ["openid"],
                tokenType: "Bearer",
                lastRefreshAt: Date(timeIntervalSince1970: 50)
            ),
            for: accountID
        )
        await http.enqueue(statusCode: 200, json: """
        {
          "access_token": "shared-access",
          "expires_in": 100,
          "refresh_token": "shared-refresh",
          "refresh_token_expires_in": 500,
          "token_type": "Bearer",
          "scope": "openid"
        }
        """)
        let manager = TokenManager(
            accountID: accountID,
            configuration: sampleConfiguration(),
            tokenStore: store,
            httpClient: http,
            clock: clock.now,
            refreshLeeway: 30
        )

        async let first = manager.validAccessToken()
        async let second = manager.validAccessToken()
        async let third = manager.validAccessToken()

        let values = try await [first.value, second.value, third.value]
        XCTAssertEqual(values, ["shared-access", "shared-access", "shared-access"])
        XCTAssertEqual(await http.requestCount, 1)
    }

    func testRefreshRetriesTransientServerErrorWithBackoff() async throws {
        let clock = TestClock(now: Date(timeIntervalSince1970: 100))
        let http = MockHTTPClient()
        let sleeps = SleepRecorder()
        let store = InMemoryWebexStore()
        let accountID = WebexAccountID()
        try await store.saveTokenRecord(
            WebexTokenRecord(
                refreshToken: "refresh",
                refreshTokenExpiresAt: Date(timeIntervalSince1970: 500),
                lastAccessTokenExpiresAt: Date(timeIntervalSince1970: 101),
                grantedScopes: ["openid"],
                tokenType: "Bearer",
                lastRefreshAt: Date(timeIntervalSince1970: 50)
            ),
            for: accountID
        )
        await http.enqueue(statusCode: 500, json: "{\"message\":\"temporary\"}")
        await http.enqueue(statusCode: 200, json: """
        {
          "access_token": "retried-access",
          "expires_in": 100,
          "refresh_token": "retried-refresh",
          "refresh_token_expires_in": 500,
          "token_type": "Bearer",
          "scope": "openid"
        }
        """)
        let manager = TokenManager(
            accountID: accountID,
            configuration: sampleConfiguration(),
            tokenStore: store,
            httpClient: http,
            clock: clock.now,
            refreshLeeway: 30,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 1, jitter: 0),
            sleeper: sleeps.sleep
        )

        let token = try await manager.validAccessToken()

        XCTAssertEqual(token.value, "retried-access")
        XCTAssertEqual(await http.requestCount, 2)
        XCTAssertEqual(await sleeps.values, [1])
    }

    private func sampleConfiguration() -> WebexIntegrationConfiguration {
        WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"]
        )
    }
}

private struct TestClock: Sendable {
    var nowValue: Date

    init(now: Date) {
        self.nowValue = now
    }

    func now() -> Date {
        nowValue
    }
}

private actor MockHTTPClient: HTTPClient {
    private var responses: [(Int, String)] = []
    private(set) var requestCount = 0

    func enqueue(statusCode: Int, json: String) {
        responses.append((statusCode, json))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requestCount += 1
        let response = responses.removeFirst()
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.0,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return HTTPResponse(data: Data(response.1.utf8), response: http)
    }
}

private actor SleepRecorder {
    private(set) var values: [TimeInterval] = []

    func sleep(_ interval: TimeInterval) async {
        values.append(interval)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter TokenManagerTests`

Expected: FAIL because `TokenManager` is missing.

- [ ] **Step 3: Implement token manager**

Create `Sources/WebexSwiftSDK/HTTP/RetryPolicy.swift`:

```swift
import Foundation

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let jitter: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5, jitter: TimeInterval = 0.25) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.jitter = jitter
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(max(0, attempt - 1)))
        return exponential + Double.random(in: 0...jitter)
    }

    public static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return seconds
        }
        return nil
    }
}
```

Create `Sources/WebexSwiftSDK/Auth/TokenManager.swift`:

```swift
import Foundation

public actor TokenManager {
    private let accountID: WebexAccountID
    private let configuration: WebexIntegrationConfiguration
    private let tokenStore: WebexTokenStore
    private let httpClient: HTTPClient
    private let clock: @Sendable () -> Date
    private let refreshLeeway: TimeInterval
    private let retryPolicy: RetryPolicy
    private let sleeper: @Sendable (TimeInterval) async -> Void
    private var accessToken: AccessTokenState?
    private var refreshTask: Task<AccessTokenState, Error>?

    public init(
        accountID: WebexAccountID,
        configuration: WebexIntegrationConfiguration,
        tokenStore: WebexTokenStore,
        httpClient: HTTPClient,
        clock: @escaping @Sendable () -> Date = Date.init,
        refreshLeeway: TimeInterval = 300,
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            let nanoseconds = UInt64(interval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.accountID = accountID
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.httpClient = httpClient
        self.clock = clock
        self.refreshLeeway = refreshLeeway
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
    }

    public func validAccessToken() async throws -> AccessTokenState {
        if let accessToken, isFresh(accessToken) {
            return accessToken
        }

        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task<AccessTokenState, Error> {
            try await refreshAccessToken()
        }
        refreshTask = task

        do {
            let token = try await task.value
            accessToken = token
            refreshTask = nil
            return token
        } catch {
            refreshTask = nil
            throw error
        }
    }

    public func invalidateAccessToken() {
        accessToken = nil
    }

    func setAccessTokenForTesting(_ token: AccessTokenState) {
        accessToken = token
    }

    private func isFresh(_ token: AccessTokenState) -> Bool {
        token.expiresAt.timeIntervalSince(clock()) > refreshLeeway
    }

    private func refreshAccessToken() async throws -> AccessTokenState {
        guard let record = try await tokenStore.loadTokenRecord(for: accountID) else {
            throw WebexSDKError.missingRefreshToken(accountID)
        }

        guard record.refreshTokenExpiresAt > clock() else {
            throw WebexSDKError.reauthenticationRequired(accountID)
        }

        var attempt = 1
        while true {
            let request = try WebexTokenEndpoint.refreshTokenRequest(
                configuration: configuration,
                refreshToken: record.refreshToken
            )
            let response = try await httpClient.send(request)

            if (200..<300).contains(response.response.statusCode) {
                let tokenResponse = try JSONDecoder().decode(WebexTokenResponse.self, from: response.data)
                let receivedAt = clock()
                let tokenRecord = tokenResponse.tokenRecord(receivedAt: receivedAt)
                try await tokenStore.saveTokenRecord(tokenRecord, for: accountID)
                return tokenResponse.accessTokenState(receivedAt: receivedAt)
            }

            let body = String(data: response.data, encoding: .utf8) ?? ""
            if response.response.statusCode == 400 && body.localizedCaseInsensitiveContains("refresh token") {
                throw WebexSDKError.reauthenticationRequired(accountID)
            }

            if (500..<600).contains(response.response.statusCode), attempt < retryPolicy.maxAttempts {
                await sleeper(retryPolicy.delay(forAttempt: attempt))
                attempt += 1
                continue
            }

            throw WebexSDKError.tokenExchangeFailed(
                statusCode: response.response.statusCode,
                message: body,
                trackingID: response.response.value(forHTTPHeaderField: "trackingId")
            )
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter TokenManagerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WebexSwiftSDK/HTTP/RetryPolicy.swift Sources/WebexSwiftSDK/Auth/TokenManager.swift Tests/WebexSwiftSDKTests/TokenManagerTests.swift
git commit -m "feat: refresh Webex tokens with coalescing"
```

## Task 8: Retry Policy And Authenticated REST Transport

**Files:**
- Create: `Sources/WebexSwiftSDK/HTTP/WebexTransport.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexTransportTests.swift`

- [ ] **Step 1: Write failing transport tests**

Create `Tests/WebexSwiftSDKTests/WebexTransportTests.swift`:

```swift
import Foundation
import XCTest
@testable import WebexSwiftSDK

final class WebexTransportTests: XCTestCase {
    func testAddsBearerTokenToRequest() async throws {
        let http = CapturingHTTPClient()
        await http.enqueue(statusCode: 200, json: "{}")
        let tokenManager = StaticTokenManager(value: "access")
        let transport = WebexTransport(httpClient: http, tokenProvider: tokenManager.token)

        _ = try await transport.send(WebexRequest(path: "/v1/people/me"))

        let authorization = await http.lastRequest?.value(forHTTPHeaderField: "Authorization")
        XCTAssertEqual(authorization, "Bearer access")
    }

    func testRetriesOnceAfterUnauthorizedByInvalidatingToken() async throws {
        let http = CapturingHTTPClient()
        await http.enqueue(statusCode: 401, json: "{\"message\":\"invalid token\"}")
        await http.enqueue(statusCode: 200, json: "{}")
        let tokenManager = StaticTokenManager(value: "access")
        let transport = WebexTransport(
            httpClient: http,
            tokenProvider: tokenManager.token,
            tokenInvalidator: tokenManager.invalidate
        )

        _ = try await transport.send(WebexRequest(path: "/v1/people/me"))

        XCTAssertEqual(await http.requestCount, 2)
        XCTAssertEqual(await tokenManager.invalidateCount, 1)
    }

    func testRateLimitSurfacesRetryAfter() async {
        let http = CapturingHTTPClient()
        await http.enqueue(statusCode: 429, json: "{\"message\":\"rate limited\"}", headers: ["Retry-After": "7"])
        let tokenManager = StaticTokenManager(value: "access")
        let transport = WebexTransport(httpClient: http, tokenProvider: tokenManager.token)

        do {
            _ = try await transport.send(WebexRequest(path: "/v1/people/me"))
            XCTFail("Expected rate limit error")
        } catch WebexSDKError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 7)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testRetriesServerErrorsWithBackoff() async throws {
        let http = CapturingHTTPClient()
        let sleeps = SleepRecorder()
        await http.enqueue(statusCode: 500, json: "{\"message\":\"temporary\"}")
        await http.enqueue(statusCode: 200, json: "{}")
        let tokenManager = StaticTokenManager(value: "access")
        let transport = WebexTransport(
            httpClient: http,
            tokenProvider: tokenManager.token,
            retryPolicy: RetryPolicy(maxAttempts: 2, baseDelay: 1, jitter: 0),
            sleeper: sleeps.sleep
        )

        _ = try await transport.send(WebexRequest(path: "/v1/people/me"))

        XCTAssertEqual(await http.requestCount, 2)
        XCTAssertEqual(await sleeps.values, [1])
    }
}

private actor CapturingHTTPClient: HTTPClient {
    private var responses: [(Int, String, [String: String])] = []
    private(set) var requestCount = 0
    private(set) var lastRequest: URLRequest?

    func enqueue(statusCode: Int, json: String, headers: [String: String] = [:]) {
        responses.append((statusCode, json, headers))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requestCount += 1
        lastRequest = request
        let response = responses.removeFirst()
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.0,
            httpVersion: nil,
            headerFields: response.2
        )!
        return HTTPResponse(data: Data(response.1.utf8), response: http)
    }
}

private actor StaticTokenManager {
    private let value: String
    private(set) var invalidateCount = 0

    init(value: String) {
        self.value = value
    }

    func token() async throws -> AccessTokenState {
        AccessTokenState(value: value, expiresAt: Date(timeIntervalSinceNow: 100), tokenType: "Bearer")
    }

    func invalidate() async {
        invalidateCount += 1
    }
}

private actor SleepRecorder {
    private(set) var values: [TimeInterval] = []

    func sleep(_ interval: TimeInterval) async {
        values.append(interval)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter WebexTransportTests`

Expected: FAIL because `WebexTransport` and `WebexRequest` are missing.

- [ ] **Step 3: Implement transport**

Create `Sources/WebexSwiftSDK/HTTP/WebexTransport.swift`:

```swift
import Foundation

public struct WebexRequest: Sendable {
    public var method: String
    public var path: String
    public var queryItems: [URLQueryItem]
    public var body: Data?

    public init(method: String = "GET", path: String, queryItems: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
    }
}

public struct WebexTransport: Sendable {
    private let baseURL: URL
    private let httpClient: HTTPClient
    private let tokenProvider: @Sendable () async throws -> AccessTokenState
    private let tokenInvalidator: @Sendable () async -> Void
    private let retryPolicy: RetryPolicy
    private let sleeper: @Sendable (TimeInterval) async -> Void

    public init(
        baseURL: URL = URL(string: "https://webexapis.com")!,
        httpClient: HTTPClient,
        tokenProvider: @escaping @Sendable () async throws -> AccessTokenState,
        tokenInvalidator: @escaping @Sendable () async -> Void = {},
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            let nanoseconds = UInt64(interval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient
        self.tokenProvider = tokenProvider
        self.tokenInvalidator = tokenInvalidator
        self.retryPolicy = retryPolicy
        self.sleeper = sleeper
    }

    public func send(_ request: WebexRequest) async throws -> Data {
        var attempt = 1
        var allowUnauthorizedRetry = true

        while true {
            do {
                return try await sendOnce(request, allowUnauthorizedRetry: allowUnauthorizedRetry)
            } catch WebexSDKError.webexAPI(let statusCode, _, _)
                where (500..<600).contains(statusCode) && attempt < retryPolicy.maxAttempts {
                await sleeper(retryPolicy.delay(forAttempt: attempt))
                attempt += 1
            }
        }
    }

    private func sendOnce(_ request: WebexRequest, allowUnauthorizedRetry: Bool) async throws -> Data {
        let token = try await tokenProvider()
        let urlRequest = try buildURLRequest(request, accessToken: token.value)
        let response = try await httpClient.send(urlRequest)

        switch response.response.statusCode {
        case 200..<300:
            return response.data
        case 401 where allowUnauthorizedRetry:
            await tokenInvalidator()
            return try await sendOnce(request, allowUnauthorizedRetry: false)
        case 429:
            throw WebexSDKError.rateLimited(RetryPolicy.retryAfter(from: response.response))
        default:
            let message = String(data: response.data, encoding: .utf8) ?? ""
            throw WebexSDKError.webexAPI(
                statusCode: response.response.statusCode,
                trackingID: response.response.value(forHTTPHeaderField: "trackingId"),
                message: message
            )
        }
    }

    private func buildURLRequest(_ request: WebexRequest, accessToken: String) throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = request.path.hasPrefix("/") ? request.path : "/\(request.path)"
        components?.queryItems = request.queryItems.isEmpty ? nil : request.queryItems

        guard let url = components?.url else {
            throw WebexSDKError.network("Unable to build Webex request URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        return urlRequest
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter WebexTransportTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WebexSwiftSDK/HTTP/WebexTransport.swift Tests/WebexSwiftSDKTests/WebexTransportTests.swift
git commit -m "feat: add authenticated Webex REST transport"
```

## Task 9: WebexClient Facade And People API

**Files:**
- Create: `Sources/WebexSwiftSDK/WebexClient.swift`
- Create: `Sources/WebexSwiftSDK/API/PeopleAPI.swift`
- Create: `Tests/WebexSwiftSDKTests/PeopleAPITests.swift`

- [ ] **Step 1: Write failing People API tests**

Create `Tests/WebexSwiftSDKTests/PeopleAPITests.swift`:

```swift
import Foundation
import XCTest
@testable import WebexSwiftSDK

final class PeopleAPITests: XCTestCase {
    func testMeDecodesCurrentPersonAndMetadata() async throws {
        let http = PeopleHTTPClient()
        await http.enqueue(statusCode: 200, json: """
        {
          "id": "person-1",
          "emails": ["user@example.com"],
          "displayName": "Example User",
          "orgId": "org-1",
          "created": "2024-01-01T00:00:00.000Z"
        }
        """)
        let transport = WebexTransport(httpClient: http) {
            AccessTokenState(value: "access", expiresAt: Date(timeIntervalSinceNow: 100), tokenType: "Bearer")
        }
        let api = PeopleAPI(transport: transport)

        let person = try await api.me()

        XCTAssertEqual(person.id, "person-1")
        XCTAssertEqual(person.emails, ["user@example.com"])
        XCTAssertEqual(person.displayName, "Example User")
        XCTAssertEqual(person.orgID, "org-1")
    }
}

private actor PeopleHTTPClient: HTTPClient {
    private var responses: [(Int, String)] = []

    func enqueue(statusCode: Int, json: String) {
        responses.append((statusCode, json))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        XCTAssertEqual(request.url?.absoluteString, "https://webexapis.com/v1/people/me")
        let response = responses.removeFirst()
        let http = HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(response.1.utf8), response: http)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter PeopleAPITests`

Expected: FAIL because `PeopleAPI` is missing.

- [ ] **Step 3: Implement People API**

Create `Sources/WebexSwiftSDK/API/PeopleAPI.swift`:

```swift
import Foundation

public struct WebexPerson: Equatable, Decodable, Sendable {
    public let id: String
    public let emails: [String]
    public let displayName: String?
    public let orgID: String?
    public let created: String?

    enum CodingKeys: String, CodingKey {
        case id
        case emails
        case displayName
        case orgID = "orgId"
        case created
    }

    public var metadata: WebexAccountMetadata {
        WebexAccountMetadata(
            webexUserID: id,
            email: emails.first,
            displayName: displayName,
            organizationID: orgID,
            lastVerifiedAt: Date()
        )
    }
}

public struct PeopleAPI: Sendable {
    private let transport: WebexTransport
    private let decoder: JSONDecoder

    public init(transport: WebexTransport, decoder: JSONDecoder = JSONDecoder()) {
        self.transport = transport
        self.decoder = decoder
    }

    public func me() async throws -> WebexPerson {
        let data = try await transport.send(WebexRequest(path: "/v1/people/me"))
        return try decoder.decode(WebexPerson.self, from: data)
    }
}
```

- [ ] **Step 4: Implement WebexClient facade**

Create `Sources/WebexSwiftSDK/WebexClient.swift`:

```swift
import Foundation

public final class WebexClient: Sendable {
    public let accountID: WebexAccountID
    public let people: PeopleAPI
    private let tokenManager: TokenManager

    public init(
        accountID: WebexAccountID,
        configuration: WebexIntegrationConfiguration,
        tokenStore: WebexTokenStore,
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) {
        self.accountID = accountID
        let tokenManager = TokenManager(
            accountID: accountID,
            configuration: configuration,
            tokenStore: tokenStore,
            httpClient: httpClient
        )
        self.tokenManager = tokenManager
        let transport = WebexTransport(
            httpClient: httpClient,
            tokenProvider: {
                try await tokenManager.validAccessToken()
            },
            tokenInvalidator: {
                await tokenManager.invalidateAccessToken()
            }
        )
        self.people = PeopleAPI(transport: transport)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter PeopleAPITests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/WebexSwiftSDK/WebexClient.swift Sources/WebexSwiftSDK/API/PeopleAPI.swift Tests/WebexSwiftSDKTests/PeopleAPITests.swift
git commit -m "feat: expose Webex client with people API"
```

## Task 10: Keychain Store

**Files:**
- Create: `Sources/WebexSwiftSDK/Storage/KeychainStore.swift`
- Create: `Tests/WebexSwiftSDKTests/KeychainStoreTests.swift`

- [ ] **Step 1: Write opt-in Keychain tests**

Create `Tests/WebexSwiftSDKTests/KeychainStoreTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class KeychainStoreTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WEBEX_SDK_RUN_KEYCHAIN_TESTS"] == "1")
    }

    func testCredentialRoundTripInKeychain() async throws {
        let accountID = WebexAccountID()
        let secondID = WebexAccountID()
        let store = KeychainWebexStore(service: "WebexSwiftSDKTests")
        let credential = WebexCredentialRecord(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        defer {
            Task {
                try? await store.deleteCredential(for: accountID)
                try? await store.deleteTokenRecord(for: accountID)
                try? await store.deleteMetadata(for: accountID)
                try? await store.saveAccountIDs([])
            }
        }

        try await store.saveCredential(credential, for: accountID)
        try await store.saveAccountIDs([accountID, secondID])

        XCTAssertEqual(try await store.loadCredential(for: accountID), credential)
        XCTAssertEqual(try await store.loadAccountIDs(), [accountID, secondID])
    }
}
```

- [ ] **Step 2: Run skipped test**

Run: `swift test --filter KeychainStoreTests`

Expected: PASS with the test skipped unless `WEBEX_SDK_RUN_KEYCHAIN_TESTS=1` is set.

- [ ] **Step 3: Implement Keychain store**

Create `Sources/WebexSwiftSDK/Storage/KeychainStore.swift`:

```swift
import Foundation
import Security

public actor KeychainWebexStore: WebexCredentialStore, WebexTokenStore, WebexAccountMetadataStore, WebexAccountIndexStore {
    private let service: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(service: String = "WebexSwiftSDK") {
        self.service = service
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadCredential(for accountID: WebexAccountID) async throws -> WebexCredentialRecord? {
        try load(WebexCredentialRecord.self, accountID: accountID, kind: "credential")
    }

    public func saveCredential(_ record: WebexCredentialRecord, for accountID: WebexAccountID) async throws {
        try save(record, accountID: accountID, kind: "credential")
    }

    public func deleteCredential(for accountID: WebexAccountID) async throws {
        try delete(accountID: accountID, kind: "credential")
    }

    public func loadTokenRecord(for accountID: WebexAccountID) async throws -> WebexTokenRecord? {
        try load(WebexTokenRecord.self, accountID: accountID, kind: "token")
    }

    public func saveTokenRecord(_ record: WebexTokenRecord, for accountID: WebexAccountID) async throws {
        try save(record, accountID: accountID, kind: "token")
    }

    public func deleteTokenRecord(for accountID: WebexAccountID) async throws {
        try delete(accountID: accountID, kind: "token")
    }

    public func loadMetadata(for accountID: WebexAccountID) async throws -> WebexAccountMetadata? {
        try load(WebexAccountMetadata.self, accountID: accountID, kind: "metadata")
    }

    public func saveMetadata(_ metadata: WebexAccountMetadata, for accountID: WebexAccountID) async throws {
        try save(metadata, accountID: accountID, kind: "metadata")
    }

    public func deleteMetadata(for accountID: WebexAccountID) async throws {
        try delete(accountID: accountID, kind: "metadata")
    }

    public func loadAccountIDs() async throws -> [WebexAccountID] {
        try load([WebexAccountID].self, accountKey: "__webex_account_index__", kind: "account-index") ?? []
    }

    public func saveAccountIDs(_ accountIDs: [WebexAccountID]) async throws {
        try save(accountIDs, accountKey: "__webex_account_index__", kind: "account-index")
    }

    private func load<T: Decodable>(_ type: T.Type, accountID: WebexAccountID, kind: String) throws -> T? {
        try load(type, accountKey: accountID.rawValue, kind: kind)
    }

    private func load<T: Decodable>(_ type: T.Type, accountKey: String, kind: String) throws -> T? {
        var query = baseQuery(accountKey: accountKey, kind: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw WebexSDKError.network("Keychain load failed status=\(status)")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, accountID: WebexAccountID, kind: String) throws {
        try save(value, accountKey: accountID.rawValue, kind: kind)
    }

    private func save<T: Encodable>(_ value: T, accountKey: String, kind: String) throws {
        let data = try encoder.encode(value)
        let query = baseQuery(accountKey: accountKey, kind: kind)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw WebexSDKError.network("Keychain update failed status=\(updateStatus)")
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw WebexSDKError.network("Keychain add failed status=\(addStatus)")
        }
    }

    private func delete(accountID: WebexAccountID, kind: String) throws {
        let status = SecItemDelete(baseQuery(accountKey: accountID.rawValue, kind: kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WebexSDKError.network("Keychain delete failed status=\(status)")
        }
    }

    private func baseQuery(accountKey: String, kind: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(accountKey).\(kind)"
        ]
    }
}
```

- [ ] **Step 4: Run skipped Keychain test and full tests**

Run: `swift test --filter KeychainStoreTests && swift test`

Expected: PASS, with Keychain test skipped by default and all normal tests passing.

- [ ] **Step 5: Optionally run real Keychain test locally**

Run: `WEBEX_SDK_RUN_KEYCHAIN_TESTS=1 swift test --filter KeychainStoreTests`

Expected: PASS on a local macOS user session with Keychain access.

- [ ] **Step 6: Commit**

```bash
git add Sources/WebexSwiftSDK/Storage/KeychainStore.swift Tests/WebexSwiftSDKTests/KeychainStoreTests.swift
git commit -m "feat: add Keychain-backed Webex storage"
```

## Task 11: WebexClientRegistry

**Files:**
- Create: `Sources/WebexSwiftSDK/Auth/WebexClientRegistry.swift`
- Create: `Tests/WebexSwiftSDKTests/WebexClientRegistryTests.swift`

- [ ] **Step 1: Write failing registry tests**

Create `Tests/WebexSwiftSDKTests/WebexClientRegistryTests.swift`:

```swift
import XCTest
@testable import WebexSwiftSDK

final class WebexClientRegistryTests: XCTestCase {
    func testAddsAccountWithGeneratedStableID() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: URLSessionHTTPClient())

        let account = try await registry.addAccount(configuration: sampleConfiguration(), metadata: WebexAccountMetadata(email: "user@example.com"))

        XCTAssertFalse(account.id.rawValue.isEmpty)
        XCTAssertEqual(account.metadata.email, "user@example.com")
        XCTAssertNotNil(try await store.loadCredential(for: account.id))
        XCTAssertEqual(try await store.loadAccountIDs(), [account.id])
    }

    func testListAccountsReturnsSavedMetadataAcrossRegistryInstances() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: URLSessionHTTPClient())
        let account = try await registry.addAccount(configuration: sampleConfiguration(), metadata: WebexAccountMetadata(email: "user@example.com"))
        let reloadedRegistry = WebexClientRegistry(store: store, httpClient: URLSessionHTTPClient())

        let accounts = try await reloadedRegistry.listAccounts()

        XCTAssertEqual(accounts.map(\.id), [account.id])
        XCTAssertEqual(accounts.first?.metadata.email, "user@example.com")
    }

    func testRemoveAccountDeletesAllStoredRecords() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: URLSessionHTTPClient())
        let account = try await registry.addAccount(configuration: sampleConfiguration(), metadata: WebexAccountMetadata(email: "user@example.com"))

        try await registry.removeAccount(account.id)

        XCTAssertNil(try await store.loadCredential(for: account.id))
        XCTAssertNil(try await store.loadMetadata(for: account.id))
        XCTAssertEqual(try await store.loadAccountIDs(), [])
    }

    func testLikelyDuplicateByClientIDAndWebexUserIDThrowsGracefully() async throws {
        let store = InMemoryWebexStore()
        let registry = WebexClientRegistry(store: store, httpClient: URLSessionHTTPClient())
        let original = try await registry.addAccount(
            configuration: sampleConfiguration(),
            metadata: WebexAccountMetadata(webexUserID: "person-1", email: "first@example.com")
        )

        do {
            _ = try await registry.addAccount(
                configuration: sampleConfiguration(),
                metadata: WebexAccountMetadata(webexUserID: "person-1", email: "changed@example.com")
            )
            XCTFail("Expected duplicate error")
        } catch WebexSDKError.duplicateAccount(let existing, let reason) {
            XCTAssertEqual(existing, original.id)
            XCTAssertTrue(reason.contains("clientID"))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    private func sampleConfiguration() -> WebexIntegrationConfiguration {
        WebexIntegrationConfiguration(
            clientID: "client",
            clientSecret: "secret",
            redirectURI: URL(string: "myapp://oauth/webex")!,
            scopes: ["openid"]
        )
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter WebexClientRegistryTests`

Expected: FAIL because registry types are missing.

- [ ] **Step 3: Implement registry**

Create `Sources/WebexSwiftSDK/Auth/WebexClientRegistry.swift`:

```swift
import Foundation

public struct WebexAccountRecord: Equatable, Sendable {
    public let id: WebexAccountID
    public let metadata: WebexAccountMetadata

    public init(id: WebexAccountID, metadata: WebexAccountMetadata) {
        self.id = id
        self.metadata = metadata
    }
}

public actor WebexClientRegistry {
    private let store: WebexCredentialStore & WebexTokenStore & WebexAccountMetadataStore & WebexAccountIndexStore
    private let httpClient: HTTPClient

    public init(
        store: WebexCredentialStore & WebexTokenStore & WebexAccountMetadataStore & WebexAccountIndexStore = KeychainWebexStore(),
        httpClient: HTTPClient = URLSessionHTTPClient()
    ) {
        self.store = store
        self.httpClient = httpClient
    }

    public func addAccount(
        configuration: WebexIntegrationConfiguration,
        metadata: WebexAccountMetadata = WebexAccountMetadata(),
        now: Date = Date()
    ) async throws -> WebexAccountRecord {
        if let duplicate = try await likelyDuplicate(configuration: configuration, metadata: metadata) {
            throw WebexSDKError.duplicateAccount(existing: duplicate.id, reason: duplicate.reason)
        }

        let accountID = WebexAccountID()
        let credential = WebexCredentialRecord(
            clientID: configuration.clientID,
            clientSecret: configuration.clientSecret,
            redirectURI: configuration.redirectURI,
            scopes: configuration.scopes,
            createdAt: now,
            updatedAt: now
        )
        try await store.saveCredential(credential, for: accountID)
        try await store.saveMetadata(metadata, for: accountID)
        var accountIDs = try await store.loadAccountIDs()
        accountIDs.append(accountID)
        try await store.saveAccountIDs(accountIDs)
        return WebexAccountRecord(id: accountID, metadata: metadata)
    }

    public func listAccounts() async throws -> [WebexAccountRecord] {
        var records: [WebexAccountRecord] = []
        for accountID in try await store.loadAccountIDs() {
            let metadata = try await store.loadMetadata(for: accountID) ?? WebexAccountMetadata()
            records.append(WebexAccountRecord(id: accountID, metadata: metadata))
        }
        return records
    }

    public func client(for accountID: WebexAccountID) async throws -> WebexClient {
        guard let credential = try await store.loadCredential(for: accountID) else {
            throw WebexSDKError.missingCredential(accountID)
        }
        return WebexClient(
            accountID: accountID,
            configuration: credential.configuration,
            tokenStore: store,
            httpClient: httpClient
        )
    }

    public func removeAccount(_ accountID: WebexAccountID) async throws {
        try await store.deleteCredential(for: accountID)
        try await store.deleteTokenRecord(for: accountID)
        try await store.deleteMetadata(for: accountID)
        var accountIDs = try await store.loadAccountIDs()
        accountIDs.removeAll { $0 == accountID }
        try await store.saveAccountIDs(accountIDs)
    }

    private func likelyDuplicate(
        configuration: WebexIntegrationConfiguration,
        metadata: WebexAccountMetadata
    ) async throws -> (id: WebexAccountID, reason: String)? {
        let accountIDs = try await store.loadAccountIDs()
        for accountID in accountIDs {
            guard let existingCredential = try await store.loadCredential(for: accountID),
                  let existingMetadata = try await store.loadMetadata(for: accountID) else {
                continue
            }

            if existingCredential.clientID == configuration.clientID,
               let existingUserID = existingMetadata.webexUserID,
               let incomingUserID = metadata.webexUserID,
               existingUserID == incomingUserID {
                return (accountID, "matching clientID and Webex user ID")
            }

            if existingCredential.clientID == configuration.clientID,
               let existingSubject = existingMetadata.oidcSubject,
               let incomingSubject = metadata.oidcSubject,
               existingSubject == incomingSubject {
                return (accountID, "matching clientID and OIDC subject")
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter WebexClientRegistryTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/WebexSwiftSDK/Auth/WebexClientRegistry.swift Tests/WebexSwiftSDKTests/WebexClientRegistryTests.swift
git commit -m "feat: add Webex client registry"
```

## Task 12: README Usage And Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README**

Replace `README.md` with:

````markdown
# webex-swift-sdk

Swift-first macOS SDK for Webex Developer APIs.

## Current Scope

This package provides the OAuth and authenticated REST foundation:

- user-provided Webex integration credentials
- PKCE authorization request support
- Apple-native browser auth boundary
- Keychain-backed credential and refresh-token storage
- memory-only access-token cache by default
- coordinated token refresh
- authenticated REST transport
- `people.me()` as the first typed Webex endpoint

## Example

```swift
import WebexSwiftSDK

let registry = WebexClientRegistry()
let accounts = try await registry.listAccounts()

for account in accounts {
    let client = try await registry.client(for: account.id)
    let person = try await client.people.me()
    print(person.displayName ?? person.id)
}
```

The host macOS app owns UI, account selection, and window-to-account routing. The SDK owns OAuth, token lifecycle, local secure storage, and authenticated Webex REST execution.
````

- [ ] **Step 2: Run full tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 3: Confirm no generated companion files are tracked**

Run: `git status --short`

Expected: only `README.md` is modified for this task.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: describe OAuth foundation usage"
```

## Plan Self-Review

- Spec coverage: Tasks cover SwiftPM setup, core account IDs, mutable metadata, duplicate detection, PKCE, native OAuth browser boundary, callback parsing, token exchange models, refresh-token persistence, memory-only access-token cache, refresh coalescing, authenticated REST transport, `people.me()`, Keychain storage, persisted account index, registry construction, and README usage.
- Intentional gaps: Full Webex OAuth end-to-end browser login, SwiftUI `WebAuthenticationSession`, messages, rooms, and pagination should be follow-up plans after this foundation compiles and passes tests.
- Placeholder scan: No deferred implementation markers are used in code steps.
- Type consistency: `WebexAccountID`, `WebexIntegrationConfiguration`, `WebexTokenRecord`, `AccessTokenState`, `TokenManager`, `WebexTransport`, `PeopleAPI`, `WebexClient`, and `WebexClientRegistry` names are consistent across tasks.
