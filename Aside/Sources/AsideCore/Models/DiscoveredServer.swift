import Foundation

public struct DiscoveredServer: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let username: String
    public let password: String
    public init(host: String, port: Int, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    public var attachTarget: String { "http://\(host):\(port)" }
    public var baseURL: URL { URL(string: "http://\(host):\(port)")! }

    /// Build a URLRequest with optional Basic auth for the given API path.
    public func authenticatedRequest(path: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        if !username.isEmpty && !password.isEmpty {
            let credentials = "\(username):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
