import Foundation

/// Developer app credentials, read from ~/.tesla-widget/credentials.env (never stored in the App Group).
struct Credentials {
    var clientID: String
    var clientSecret: String
    /// Website hosting the public key, e.g. "yourname.github.io" (TESLA_WEBSITE).
    var website: String

    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tesla-widget")
    static let file = directory.appendingPathComponent("credentials.env")

    static func load() -> Credentials? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { values[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        }
        guard let id = values["TESLA_CLIENT_ID"], !id.isEmpty,
              let secret = values["TESLA_CLIENT_SECRET"], !secret.isEmpty else { return nil }
        let site = (values["TESLA_WEBSITE"] ?? "")
            .replacingOccurrences(of: "https://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return Credentials(clientID: id, clientSecret: secret, website: site)
    }
}

enum TeslaAuth {
    static func authorizeURL(_ creds: Credentials, state: String) -> URL {
        var c = URLComponents(url: Shared.authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: creds.clientID),
            .init(name: "redirect_uri", value: Shared.redirectURI(creds.website)),
            .init(name: "scope", value: Shared.userScopes),
            .init(name: "state", value: state),
            .init(name: "prompt_missing_scopes", value: "true"),
        ]
        return c.url!
    }

    static func exchange(code: String, creds: Credentials, audience: URL) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "authorization_code",
            "client_id": creds.clientID,
            "client_secret": creds.clientSecret,
            "code": code,
            "audience": audience.absoluteString,
            "redirect_uri": Shared.redirectURI(creds.website),
        ])
    }

    static func refresh(_ tokens: Tokens, clientID: String) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": tokens.refreshToken,
        ], fallbackRefresh: tokens.refreshToken)
    }

    static func partnerToken(_ creds: Credentials, audience: URL) async throws -> String {
        try await tokenRequest([
            "grant_type": "client_credentials",
            "client_id": creds.clientID,
            "client_secret": creds.clientSecret,
            "scope": Shared.partnerScopes,
            "audience": audience.absoluteString,
        ], fallbackRefresh: "").accessToken
    }

    private static func tokenRequest(_ form: [String: String], fallbackRefresh: String? = nil) async throws -> Tokens {
        var req = URLRequest(url: Shared.tokenURL, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var c = URLComponents()
        c.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, which form decoding would read as a space.
        req.httpBody = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status), let access = json["access_token"] as? String else {
            let message = [json["error_description"], json["error"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? "HTTP \(status)"
            throw FleetError(status: status, message: message)
        }
        guard let refresh = json["refresh_token"] as? String ?? fallbackRefresh else {
            throw FleetError(status: status, message: "Tesla didn't return a refresh token")
        }
        let expiresIn = json["expires_in"] as? Double ?? 8 * 3600
        return Tokens(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn))
    }
}
