import Foundation
import Security

// MARK: - API Error

enum VRChatAPIError: LocalizedError {
    case invalidURL
    case invalidCredentials
    case requiresTwoFactorAuth(methods: [TwoFactorMethod])
    case twoFactorCodeInvalid
    case twoFactorEmailCodeInvalid
    case notAuthenticated
    case sessionExpired
    case rateLimited(retryAfter: TimeInterval?)
    case cloudflareBlock
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)
    case networkError(Error)
    case keychainError(OSStatus)
    case cookiePersistenceError(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .invalidCredentials:
            return "用户名或密码错误"
        case .requiresTwoFactorAuth(let methods):
            let names = methods.map { $0.displayName }.joined(separator: " / ")
            return "需要两步验证：\(names)"
        case .twoFactorCodeInvalid:
            return "两步验证码无效"
        case .twoFactorEmailCodeInvalid:
            return "邮箱验证码无效"
        case .notAuthenticated:
            return "未登录，请先登录"
        case .sessionExpired:
            return "会话已过期，请重新登录"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "请求过于频繁，请在 \(Int(seconds)) 秒后重试"
            }
            return "请求过于频繁，请稍后重试"
        case .cloudflareBlock:
            return "请求被拦截，请稍后重试"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .decodingError(let error):
            return "数据解析失败: \(error.localizedDescription)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .keychainError(let status):
            return "钥匙串访问失败 (OSStatus: \(status))"
        case .cookiePersistenceError(let error):
            return "Cookie 持久化失败: \(error.localizedDescription)"
        case .unknown:
            return "发生未知错误"
        }
    }
}

enum TwoFactorMethod: String, Codable, Sendable {
    case totp
    case otp // email code

    var displayName: String {
        switch self {
        case .totp: return "验证器应用 (TOTP)"
        case .otp:  return "邮箱验证码"
        }
    }
}

// MARK: - Cookie Persistence Helper

private let vrchatCookieDomain = "api.vrchat.cloud"
private let persistedCookieKey = "vrchat_persisted_cookies"

private extension HTTPCookieStorage {

    /// Serialize auth-related cookies to UserDefaults for cold-launch survival.
    func persistVRChatCookies() {
        guard let cookieURL = URL(string: "https://\(vrchatCookieDomain)") else {
            return
        }
        guard let cookies = cookies(for: cookieURL), !cookies.isEmpty else {
            return
        }
        let archivable = cookies.filter { cookie in
            cookie.name == "auth" || cookie.name == "twoFactorAuth" || cookie.name == "apiKey"
        }
        guard !archivable.isEmpty else { return }

        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: archivable,
                requiringSecureCoding: false
            )
            UserDefaults.standard.set(data, forKey: persistedCookieKey)
        } catch {
            // Cookie persistence failure is non-fatal; the session simply
            // won't survive a cold launch, but in-flight requests continue.
            print("[VRChatAPIClient] Warning: failed to persist cookies: \(error.localizedDescription)")
        }
    }

    /// Restore previously persisted cookies after a cold launch.
    func restoreVRChatCookies() {
        guard let data = UserDefaults.standard.data(forKey: persistedCookieKey) else {
            return
        }
        do {
            let cookies = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSArray.self, HTTPCookie.self],
                from: data
            )
            guard let restored = cookies as? [HTTPCookie] else { return }
            for cookie in restored {
                setCookie(cookie)
            }
        } catch {
            // Best-effort restoration; stale data is silently discarded.
            UserDefaults.standard.removeObject(forKey: persistedCookieKey)
        }
    }

    /// Remove all VRChat cookies from storage and UserDefaults.
    func clearVRChatCookies() {
        guard let cookieURL = URL(string: "https://\(vrchatCookieDomain)") else {
            return
        }
        guard let cookies = cookies(for: cookieURL) else {
            UserDefaults.standard.removeObject(forKey: persistedCookieKey)
            return
        }
        for cookie in cookies {
            deleteCookie(cookie)
        }
        UserDefaults.standard.removeObject(forKey: persistedCookieKey)
    }
}

// MARK: - API Client

/// Thread-safe actor wrapping all VRChat API communication.
///
/// - All methods are isolated to the actor for compile-time data-race safety.
/// - Cookie persistence uses `HTTPCookieStorage` + `UserDefaults` for
///   cold-launch session survival.
/// - Keychain stores username/password for optional auto-fill.
/// - Every error path produces a typed `VRChatAPIError`; no error is silently
///   swallowed.
actor VRChatAPIClient {

    // MARK: Singleton

    static let shared = VRChatAPIClient()

    // MARK: Constants

    private let baseURL = "https://api.vrchat.cloud/api/1"
    private let userAgent = "VRCX-Lite-iOS/1.0.0 (Contact: vrcxlite@future.dev)"

    // MARK: State

    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private var currentUser: CurrentUser?
    private var isAuthenticated = false

    // MARK: Init

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "Accept-Encoding": "gzip, deflate, br",
            "Accept": "application/json",
        ]

        self.session = URLSession(configuration: config)

        // Restore any cookies from a previous session
        HTTPCookieStorage.shared.restoreVRChatCookies()
    }

    // MARK: - Public Read-Only State

    var isLoggedIn: Bool { isAuthenticated }
    var authenticatedUser: CurrentUser? { currentUser }

    // MARK: Session Restoration (cold-launch auto-login)

    /// Attempt to restore a session from persisted cookies without user
    /// interaction. Returns the current user on success, throws on failure.
    func restoreSession() async throws -> CurrentUser {
        let cookieURL = URL(string: "https://\(vrchatCookieDomain)")!
        let existingCookies = HTTPCookieStorage.shared.cookies(for: cookieURL) ?? []
        let hasAuthCookie = existingCookies.contains { $0.name == "auth" }

        guard hasAuthCookie else {
            throw VRChatAPIError.notAuthenticated
        }

        return try await fetchCurrentUser()
    }

    // MARK: Login Flow

    /// Step 1 — attempt login with username + password.
    /// May throw `.requiresTwoFactorAuth` when 2FA is active on the account.
    func login(username: String, password: String) async throws -> CurrentUser {
        isAuthenticated = false
        currentUser = nil

        // Clean cookie jar for a fresh login session
        HTTPCookieStorage.shared.clearVRChatCookies()

        let basicAuth = "\(username):\(password)"
        guard let encoded = basicAuth.data(using: .utf8)?.base64EncodedString() else {
            throw VRChatAPIError.invalidCredentials
        }

        let url = try buildURL(path: "/auth/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)

        // Check whether the server demands a 2FA code.
        // The API returns either the CurrentUser object OR a Pending2FAResponse.
        do {
            let pending = try decoder.decode(Pending2FAResponse.self, from: data)
            if let methods = pending.requiresTwoFactorAuth, !methods.isEmpty {
                // Persist the preliminary session cookie so the 2FA verify
                // call can reference the same server-side session.
                HTTPCookieStorage.shared.persistVRChatCookies()
                throw VRChatAPIError.requiresTwoFactorAuth(methods: methods)
            }
        } catch let error as VRChatAPIError {
            // Re-throw our own typed errors immediately
            throw error
        } catch {
            // Decoding as Pending2FAResponse failed → data is not a 2FA
            // challenge; fall through to try decoding as CurrentUser.
        }

        // Not a 2FA challenge — treat the body as the current user.
        let user: CurrentUser
        do {
            user = try decoder.decode(CurrentUser.self, from: data)
        } catch {
            throw VRChatAPIError.decodingError(error)
        }

        currentUser = user
        isAuthenticated = true
        HTTPCookieStorage.shared.persistVRChatCookies()

        // Persist credentials in Keychain for convenience (non-fatal on failure)
        do {
            try KeychainHelper.storeCredentials(username: username, password: password)
        } catch {
            // Logged but not re-thrown: auth succeeded, Keychain is auxiliary
            print("[VRChatAPIClient] Warning: Keychain write failed: \(error.localizedDescription)")
        }

        return user
    }

    /// Step 2a — verify a TOTP code (authenticator app).
    func verifyTOTP(code: String) async throws -> CurrentUser {
        let url = try buildURL(path: "/auth/twofactorauth/totp/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(TwoFactorCodeBody(code: code))

        let (data, _) = try await performRequest(request)

        let result: Verify2FAResult
        do {
            result = try decoder.decode(Verify2FAResult.self, from: data)
        } catch {
            throw VRChatAPIError.decodingError(error)
        }

        guard result.verified == true else {
            throw VRChatAPIError.twoFactorCodeInvalid
        }

        return try await fetchCurrentUser()
    }

    /// Step 2b — verify an email OTP code.
    func verifyEmailCode(code: String) async throws -> CurrentUser {
        let url = try buildURL(path: "/auth/twofactorauth/email/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(TwoFactorCodeBody(code: code))

        let (data, _) = try await performRequest(request)

        let result: Verify2FAResult
        do {
            result = try decoder.decode(Verify2FAResult.self, from: data)
        } catch {
            throw VRChatAPIError.decodingError(error)
        }

        guard result.verified == true else {
            throw VRChatAPIError.twoFactorEmailCodeInvalid
        }

        return try await fetchCurrentUser()
    }

    /// Fetch the currently authenticated user profile.
    func fetchCurrentUser() async throws -> CurrentUser {
        let url = try buildURL(path: "/auth/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await performRequest(request)
        let user: CurrentUser
        do {
            user = try decoder.decode(CurrentUser.self, from: data)
        } catch {
            throw VRChatAPIError.decodingError(error)
        }

        currentUser = user
        isAuthenticated = true
        HTTPCookieStorage.shared.persistVRChatCookies()
        return user
    }

    /// Logout — clear cookies and stored credentials.
    func logout() async {
        // Attempt server-side logout (best-effort, do not throw)
        do {
            let url = try buildURL(path: "/logout")
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            let (_, _) = try await performRequest(request)
        } catch {
            // Server logout is advisory; local cleanup still proceeds.
        }

        HTTPCookieStorage.shared.clearVRChatCookies()
        KeychainHelper.deleteCredentials()
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: Friends

    /// Fetch the authenticated user's friends list.
    func fetchFriends(offline: Bool = false) async throws -> [Friend] {
        try await authenticatedGET(
            path: "/auth/user/friends",
            queryItems: [URLQueryItem(name: "offline", value: String(offline))]
        )
    }

    /// Unfriend a user by their ID.
    func unfriend(userID: String) async throws {
        let url = try buildURL(path: "/auth/user/friends/\(userID)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await performRequest(request)
    }

    // MARK: Notifications

    /// Fetch pending notifications (friend requests, invites, etc.).
    func fetchNotifications() async throws -> [VRCNotification] {
        try await authenticatedGET(path: "/auth/user/notifications")
    }

    /// Accept a friend request by notification ID.
    func acceptFriendRequest(notificationID: String) async throws {
        let url = try buildURL(path: "/auth/user/notifications/\(notificationID)/accept")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        _ = try await performRequest(request)
    }

    /// Decline a friend request by notification ID.
    func declineFriendRequest(notificationID: String) async throws {
        let url = try buildURL(path: "/auth/user/notifications/\(notificationID)/decline")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        _ = try await performRequest(request)
    }

    /// Respond to an invite notification.
    func respondToInvite(notificationID: String, accept: Bool) async throws {
        let url = try buildURL(path: "/auth/user/notifications/\(notificationID)/respond")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["response": accept ? "accept" : "decline"]
        request.httpBody = try encoder.encode(body)
        _ = try await performRequest(request)
    }

    /// Mark a notification as seen.
    func markNotificationSeen(notificationID: String) async throws {
        let url = try buildURL(path: "/auth/user/notifications/\(notificationID)/see")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        _ = try await performRequest(request)
    }

    // MARK: Worlds & Instances

    /// Fetch world details by world ID.
    func fetchWorld(worldID: String) async throws -> World {
        try await authenticatedGET(path: "/worlds/\(worldID)")
    }

    /// Fetch active/public worlds (with optional search/filter).
    func fetchActiveWorlds(search: String? = nil) async throws -> [World] {
        var items: [URLQueryItem] = []
        if let search { items.append(URLQueryItem(name: "search", value: search)) }
        return try await authenticatedGET(
            path: "/worlds/active",
            queryItems: items.isEmpty ? nil : items
        )
    }

    /// Fetch instance details by world ID + instance ID.
    func fetchInstance(worldID: String, instanceID: String) async throws -> Instance {
        try await authenticatedGET(path: "/worlds/\(worldID)/instances/\(instanceID)")
    }

    /// Generate the VRChat official app/website launch URL for a given world + instance.
    nonisolated func buildWorldLaunchURL(worldID: String, instanceID: String?) -> URL? {
        if let inst = instanceID {
            return URL(string: "https://vrchat.com/home/launch?worldId=\(worldID)&instanceId=\(inst)")
        }
        return URL(string: "https://vrchat.com/home/world/\(worldID)")
    }

    // MARK: User Profile

    /// Fetch another user's public profile.
    func fetchUser(userID: String) async throws -> User {
        try await authenticatedGET(path: "/users/\(userID)")
    }

    /// Send a friend request to a user.
    func sendFriendRequest(userID: String) async throws {
        let url = try buildURL(path: "/user/\(userID)/friendRequest")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await performRequest(request)
    }

    // MARK: User Notes

    /// Fetch the note for a specific user.
    func fetchUserNote(userID: String) async throws -> UserNote {
        try await authenticatedGET(path: "/user/\(userID)/note")
    }

    /// Update the note for a specific user.
    func updateUserNote(userID: String, note: String) async throws {
        let url = try buildURL(path: "/user/\(userID)/note")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["note": note])
        _ = try await performRequest(request)
    }

    // MARK: Favorites

    /// Fetch all favorites (friends, worlds, avatars).
    func fetchFavorites() async throws -> [Favorite] {
        try await authenticatedGET(path: "/favorites")
    }

    /// Fetch favorite friends only.
    func fetchFavoriteFriends() async throws -> [FavoriteFriend] {
        try await authenticatedGET(path: "/favorites/friends")
    }

    /// Fetch favorite worlds only.
    func fetchFavoriteWorlds() async throws -> [FavoriteWorld] {
        try await authenticatedGET(path: "/favorites/worlds")
    }

    /// Add a friend to favorites.
    func addFavoriteFriend(userID: String) async throws {
        let url = try buildURL(path: "/favorites/friend/\(userID)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await performRequest(request)
    }

    /// Remove a friend from favorites.
    func removeFavoriteFriend(userID: String) async throws {
        let url = try buildURL(path: "/favorites/friend/\(userID)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await performRequest(request)
    }

    // MARK: - Private Helpers

    /// Perform a GET request requiring authentication.
    private func authenticatedGET<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        let url = try buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, _) = try await performRequest(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw VRChatAPIError.decodingError(error)
        }
    }

    /// Build a full URL from a path relative to the API base.
    private func buildURL(path: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw VRChatAPIError.invalidURL
        }
        if let items = queryItems, !items.isEmpty {
            components.queryItems = items
        }
        guard let url = components.url else {
            throw VRChatAPIError.invalidURL
        }
        return url
    }

    /// Execute a URLRequest and map HTTP-level errors to typed errors.
    @discardableResult
    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var req = request
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            throw VRChatAPIError.networkError(error)
        } catch {
            throw VRChatAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VRChatAPIError.unknown
        }

        // Persist cookies on every response that includes a Set-Cookie header
        if let headerFields = httpResponse.allHeaderFields as? [String: String],
           headerFields.keys.contains(where: { $0.lowercased() == "set-cookie" }) {
            HTTPCookieStorage.shared.persistVRChatCookies()
        }

        switch httpResponse.statusCode {
        case 200...299:
            return (data, httpResponse)

        case 401:
            isAuthenticated = false
            currentUser = nil
            throw VRChatAPIError.sessionExpired

        case 403:
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.contains("cloudflare") || body.contains("Cloudflare") {
                throw VRChatAPIError.cloudflareBlock
            }
            throw VRChatAPIError.httpError(statusCode: 403, message: "访问被拒绝")

        case 429:
            let retryAfter: TimeInterval? = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw VRChatAPIError.rateLimited(retryAfter: retryAfter)

        default:
            let bodyMessage = String(data: data, encoding: .utf8) ?? "无错误信息"
            throw VRChatAPIError.httpError(
                statusCode: httpResponse.statusCode,
                message: bodyMessage
            )
        }
    }
}

// MARK: - Keychain Helper

private enum KeychainHelper {

    private static let service = "com.vrcx-lite.auth"

    static func storeCredentials(username: String, password: String) throws {
        deleteCredentials()

        let account = username
        guard let passwordData = password.data(using: .utf8) else {
            throw VRChatAPIError.invalidCredentials
        }

        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData   as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VRChatAPIError.keychainError(status)
        }
    }

    static func retrieveCredentials() -> (username: String, password: String)? {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData  as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let dict = item as? [String: Any],
              let account = dict[kSecAttrAccount as String] as? String,
              let passwordData = dict[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }

        return (account, password)
    }

    static func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Response Models

struct Pending2FAResponse: Codable, Sendable {
    let requiresTwoFactorAuth: [TwoFactorMethod]?
    let error: APIErrorBody?
}

struct APIErrorBody: Codable, Sendable {
    let message: String
    let statusCode: Int?
}

struct TwoFactorCodeBody: Codable, Sendable {
    let code: String
}

struct Verify2FAResult: Codable, Sendable {
    let verified: Bool
}

struct CurrentUser: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let username: String?
    let displayName: String?
    let userIcon: String?
    let bio: String?
    let status: String?
    let statusDescription: String?
    let state: String?
    let tags: [String]?
    let developerType: String?
    let lastLogin: String?
    let dateJoined: String?
    let friends: [String]?
    let worldId: String?
    let instanceId: String?
    let location: String?
    let travelingToLocation: String?
    let onlineFriends: [String]?
    let activeFriends: [String]?
    let offlineFriends: [String]?
}

struct Friend: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let username: String?
    let displayName: String?
    let userIcon: String?
    let bio: String?
    let status: String?
    let statusDescription: String?
    let state: String?
    let lastLogin: String?
    let location: String?
    let worldId: String?
    let instanceId: String?
    let travelingToLocation: String?
    let isFavorite: Bool?
    let tags: [String]?
}

struct VRCNotification: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    let senderUserId: String?
    let senderUsername: String?
    let receiverUserId: String?
    let message: String?
    let details: String?
    let jobName: String?
    let jobColor: String?
    let createdAt: String?
    let seen: Bool?
}

struct World: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let description: String?
    let authorId: String?
    let authorName: String?
    let imageUrl: String?
    let thumbnailImageUrl: String?
    let capacity: Int?
    let visits: Int?
    let favorites: Int?
    let popularity: Int?
    let heat: Int?
    let occupants: Int?
    let organization: String?
    let previewYoutubeId: String?
    let favoritesGroup: String?
    let publicationDate: String?
    let updatedAt: String?
    let releaseStatus: String?
    let version: Int?
    let tags: [String]?
    let featured: Bool?
    let instances: [[String: String]]?
}

struct Instance: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let worldId: String?
    let ownerId: String?
    let region: String?
    let type: String?
    let active: Bool?
    let full: Bool?
    let nUsers: Int?
    let capacity: Int?
    let platforms: [String]?
    let permanent: Bool?
    let photonRegion: String?
    let canRequestInvite: Bool?
    let createdAt: String?
    let location: String?
}

struct User: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let username: String?
    let displayName: String?
    let userIcon: String?
    let bio: String?
    let bioLinks: [String]?
    let status: String?
    let statusDescription: String?
    let state: String?
    let lastLogin: String?
    let lastActivity: String?
    let dateJoined: String?
    let tags: [String]?
    let developerType: String?
    let worldId: String?
    let instanceId: String?
    let location: String?
    let friendKey: String?
    let isFriend: Bool?
    let lastPlatform: String?
}

struct UserNote: Codable, Hashable, Sendable {
    let note: String?
    let userId: String?
}

struct Favorite: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: String?
    let favoriteId: String?
    let tags: [String]?
}

struct FavoriteFriend: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let userId: String?
    let friend: Friend?
    let tags: [String]?
}

struct FavoriteWorld: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let worldId: String?
    let world: World?
    let tags: [String]?
}
