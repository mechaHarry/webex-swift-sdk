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

    func testGeneratedVerifierRejectsSmallByteCountWithoutCrashing() {
        XCTAssertThrowsError(try PKCE.generateVerifier(byteCount: 31)) { error in
            XCTAssertEqual(error as? PKCEError, .invalidVerifierByteCount(minimum: 32, maximum: 96, actual: 31))
            XCTAssertTrue(String(describing: error).contains("32...96"))
        }
    }

    func testGeneratedVerifierAcceptsMaximumByteCount() throws {
        let verifier = try PKCE.generateVerifier(byteCount: 96)

        XCTAssertEqual(verifier.count, 128)
    }

    func testGeneratedVerifierRejectsTooLargeByteCountWithoutAllocating() {
        XCTAssertThrowsError(try PKCE.generateVerifier(byteCount: 97)) { error in
            XCTAssertEqual(error as? PKCEError, .invalidVerifierByteCount(minimum: 32, maximum: 96, actual: 97))
            XCTAssertTrue(String(describing: error).contains("32...96"))
        }
    }

    func testGeneratedVerifierRejectsHugeByteCountWithoutAllocating() {
        XCTAssertThrowsError(try PKCE.generateVerifier(byteCount: Int.max)) { error in
            XCTAssertEqual(error as? PKCEError, .invalidVerifierByteCount(minimum: 32, maximum: 96, actual: Int.max))
            XCTAssertTrue(String(describing: error).contains("32...96"))
        }
    }
}
