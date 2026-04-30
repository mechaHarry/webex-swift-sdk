import Foundation

public struct WebexPageLink: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var request: WebexRequest {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return WebexRequest(
            path: url.path,
            queryItems: components?.queryItems ?? []
        )
    }

    public static func next(from response: HTTPURLResponse) -> WebexPageLink? {
        guard let header = linkHeader(from: response) else {
            return nil
        }

        for segment in splitLinkHeader(header) {
            guard let parsed = parse(segment),
                  parsed.relation == "next",
                  parsed.url.scheme == "https",
                  parsed.url.host == "webexapis.com" else {
                continue
            }

            return WebexPageLink(url: parsed.url)
        }

        return nil
    }

    private static func linkHeader(from response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            guard String(describing: key).caseInsensitiveCompare("Link") == .orderedSame else {
                continue
            }

            return String(describing: value)
        }

        return nil
    }

    private static func splitLinkHeader(_ header: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var isInsideQuotes = false

        for character in header {
            if character == "\"" {
                isInsideQuotes.toggle()
            }

            if character == ",", !isInsideQuotes {
                segments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                continue
            }

            current.append(character)
        }

        let finalSegment = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalSegment.isEmpty {
            segments.append(finalSegment)
        }

        return segments
    }

    private static func parse(_ segment: String) -> (url: URL, relation: String)? {
        guard let urlStart = segment.firstIndex(of: "<"),
              let urlEnd = segment[urlStart...].firstIndex(of: ">") else {
            return nil
        }

        let rawURL = String(segment[segment.index(after: urlStart)..<urlEnd])
        guard let url = URL(string: rawURL) else {
            return nil
        }

        let parameters = segment[segment.index(after: urlEnd)...]
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for parameter in parameters {
            let parts = parameter.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].caseInsensitiveCompare("rel") == .orderedSame else {
                continue
            }

            let relation = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (url, relation)
        }

        return nil
    }
}
