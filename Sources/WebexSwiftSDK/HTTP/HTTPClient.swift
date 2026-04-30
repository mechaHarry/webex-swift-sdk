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
                throw WebexSDKError.network("Received non-HTTP URL response")
            }

            return HTTPResponse(data: data, response: httpResponse)
        } catch let error as CancellationError {
            throw error
        } catch let error as WebexSDKError {
            throw error
        } catch {
            if Self.isCancellation(error) {
                throw CancellationError()
            }

            throw WebexSDKError.network("URLSession request failed: \(Redactor.redactSecrets(error.localizedDescription))")
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == "Swift.CancellationError"
    }
}
