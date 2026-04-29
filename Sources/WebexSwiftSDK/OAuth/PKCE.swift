import CryptoKit
import Foundation
import Security

public enum PKCE {
    public static let minimumVerifierByteCount = 32
    public static let maximumVerifierByteCount = 96

    public static func generateVerifier(byteCount: Int = 32) throws -> String {
        guard byteCount >= minimumVerifierByteCount, byteCount <= maximumVerifierByteCount else {
            throw PKCEError.invalidVerifierByteCount(
                minimum: minimumVerifierByteCount,
                maximum: maximumVerifierByteCount,
                actual: byteCount
            )
        }

        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }

            return SecRandomCopyBytes(kSecRandomDefault, byteCount, baseAddress)
        }

        guard status == errSecSuccess else {
            throw PKCEError.randomGenerationFailed(status: status)
        }

        return base64URLEncoded(Data(bytes))
    }

    public static func s256Challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncoded(Data(digest))
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum PKCEError: Error, Equatable, Sendable {
    case invalidVerifierByteCount(minimum: Int, maximum: Int, actual: Int)
    case randomGenerationFailed(status: OSStatus)
}

extension PKCEError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidVerifierByteCount(let minimum, let maximum, let actual):
            return "Invalid PKCE verifier byte count: valid range \(minimum)...\(maximum), actual \(actual)"
        case .randomGenerationFailed(let status):
            return "Failed to generate secure PKCE verifier bytes with status \(status)"
        }
    }
}
