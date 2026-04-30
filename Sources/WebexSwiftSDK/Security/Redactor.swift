import Foundation

internal enum Redactor {
    private static let replacement = "[redacted]"
    private static let sensitiveSecretKeys = "access_token|refresh_token|id_token|client_secret|code_verifier"
    private static let authorizationCodeKey = "code"

    internal static func redactSecrets(_ value: String) -> String {
        var redacted = value
        redacted = replacingValueMatches(
            in: redacted,
            pattern: #"("(?:\#(sensitiveSecretKeys)|Authorization)"\s*:\s*")([^"\\]*(?:\\.[^"\\]*)*)(")"#,
            valueCaptureGroup: 2
        )
        redacted = replacingValueMatches(
            in: redacted,
            pattern: #"\b(?:\#(sensitiveSecretKeys))\b(\s*=\s*)([^&\s,;]+)"#,
            valueCaptureGroup: 2
        )
        redacted = replacingValueMatches(
            in: redacted,
            pattern: #"\b(?:\#(sensitiveSecretKeys))\b(\s*:\s*)([^\r\n\s,;]+)"#,
            valueCaptureGroup: 2
        )
        redacted = replacingValueMatches(
            in: redacted,
            pattern: #"\bAuthorization\b(\s*[:=]\s*)([^\r\n,;]+)"#,
            valueCaptureGroup: 2
        )
        return redacted
    }

    internal static func redactOAuthCallback(_ value: String) -> String {
        var redacted = redactSecrets(value)
        redacted = replacingValueMatches(
            in: redacted,
            pattern: #"\b\#(authorizationCodeKey)\b(\s*=\s*)([^&\s,;]+)"#,
            valueCaptureGroup: 2
        )
        redacted = replacingValueMatches(
            in: redacted,
            pattern: #"\b\#(authorizationCodeKey)\b(\s*:\s*)([^\r\n\s,;]+)"#,
            valueCaptureGroup: 2
        )
        return redacted
    }

    private static func replacingValueMatches(
        in value: String,
        pattern: String,
        valueCaptureGroup: Int
    ) -> String {
        let expression = try! NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        )
        let mutableValue = NSMutableString(string: value)
        let range = NSRange(location: 0, length: mutableValue.length)
        let matches = expression.matches(in: value, range: range)

        for match in matches.reversed() {
            let valueRange = match.range(at: valueCaptureGroup)
            guard valueRange.location != NSNotFound else {
                continue
            }

            mutableValue.replaceCharacters(in: valueRange, with: replacement)
        }

        return mutableValue as String
    }
}
