import Foundation

public struct TeamsAPI: Sendable {
    private let transport: WebexTransport

    public init(transport: WebexTransport) {
        self.transport = transport
    }

    public func get(teamID: String) async throws -> WebexTeam {
        let data = try await transport.send(WebexRequest(
            path: try teamPath(teamID),
            isPathPercentEncoded: true
        ))
        return try JSONDecoder().decode(WebexTeam.self, from: data)
    }

    private func teamPath(_ teamID: String) throws -> String {
        let trimmedID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex team ID")
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: allowed),
              !encodedID.isEmpty else {
            throw WebexSDKError.network("Invalid Webex team ID")
        }

        return "/v1/teams/\(encodedID)"
    }
}
