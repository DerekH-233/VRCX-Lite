import SwiftUI
import UIKit

// MARK: - Friend Status

/// VRChat friend state/status → color mapping.
enum FriendStatusColor {
    static func color(state: String?, status: String?) -> Color {
        let s = (status ?? state ?? "").lowercased()
        switch s {
        case "active":       return .orange
        case "join me":      return .cyan
        case "ask me":       return .yellow
        case "busy":         return .red
        case "do not disturb": return .red
        case "online":       return .green
        // Treat nil/"offline"/unknown as offline
        default:             return .gray.opacity(0.4)
        }
    }

    static func label(state: String?, status: String?) -> String {
        let s = (status ?? state ?? "").lowercased()
        switch s {
        case "active":            return "在线 · 活跃"
        case "join me":           return "Join Me"
        case "ask me":            return "Ask Me"
        case "busy":              return "勿打扰"
        case "do not disturb":    return "勿打扰"
        case "online":            return "在线"
        case "offline":           return "离线"
        default:                  return "离线"
        }
    }
}

// MARK: - App Navigation Items

enum AppSection: String, CaseIterable, Identifiable {
    case friends
    case notifications
    case worlds
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .friends:       return "好友"
        case .notifications: return "通知"
        case .worlds:        return "世界"
        case .settings:      return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .friends:       return "person.2"
        case .notifications: return "bell.badge"
        case .worlds:        return "globe.americas"
        case .settings:      return "gearshape"
        }
    }
}

// MARK: - Detail Content

enum DetailContent: Identifiable, Hashable {
    case friend(Friend)
    case notification(VRCNotification)
    case world(World)
    case instance(Instance)

    var id: String {
        switch self {
        case .friend(let f):       return "friend.\(f.id)"
        case .notification(let n): return "notif.\(n.id)"
        case .world(let w):        return "world.\(w.id)"
        case .instance(let i):     return "instance.\(i.id)"
        }
    }
}

// MARK: - Root Container

struct MainContainerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedSection: AppSection = .friends
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            Group {
                if horizontalSizeClass == .regular {
                    threeColumnLayout
                } else {
                    compactLayout
                }
            }
            .background(.ultraThinMaterial)

            // ── Error Banner ──
            if let error = appState.errorMessage {
                VStack {
                    ErrorBanner(message: error) {
                        appState.errorMessage = nil
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .animation(.spring(response: 0.4), value: appState.errorMessage != nil)
                .padding(.top, 8)
                .padding(.horizontal)
                .zIndex(100)
            }
        }
        // ── Auto-restore session on launch ──
        .task {
            await appState.restoreSessionIfPossible()
        }
        // ── Login sheet ──
        .sheet(isPresented: showLoginBinding) {
            LoginView()
        }

    /// Computed binding because @Environment Observable doesn't support $ prefix.
    private var showLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.showLoginSheet },
            set: { appState.showLoginSheet = $0 }
        )
    }
    }

    // MARK: - Three-Column (iPad)

    private var threeColumnLayout: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            sidebar: {
                sidebarContent
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            },
            content: {
                contentColumn
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: .infinity)
            },
            detail: {
                detailColumn
            }
        )
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedSection) { _, _ in
            HapticManager.selection()
        }
    }

    // MARK: - Compact (iPhone)

    private var compactLayout: some View {
        TabView(selection: $selectedSection) {
            ForEach(AppSection.allCases) { section in
                NavigationStack {
                    sectionView(for: section, isCompact: true)
                        .navigationTitle(section.label)
                        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                if !appState.isLoggedIn {
                                    Button {
                                        HapticManager.light()
                                        appState.showLoginSheet = true
                                    } label: {
                                        Text("登录").fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                }
                .tabItem {
                    Label(section.label, systemImage: section.systemImage)
                }
                .tag(section)
            }
        }
        .onChange(of: selectedSection) { _, _ in
            HapticManager.selection()
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List {
            // ── User Header ──
            Section {
                if let user = appState.currentUser {
                    VStack(alignment: .leading, spacing: 8) {
                        AvatarImage(url: user.userIcon, size: 44)
                        Text(user.displayName ?? user.username ?? "VRChat 用户")
                            .font(.headline)
                        if let statusDesc = user.statusDescription {
                            Text(statusDesc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // Mini status indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(FriendStatusColor.color(
                                    state: user.state,
                                    status: user.status
                                ))
                                .frame(width: 8, height: 8)
                            Text(FriendStatusColor.label(
                                state: user.state,
                                status: user.status
                            ))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        HapticManager.light()
                        appState.showLoginSheet = true
                    } label: {
                        Label("登录 VRChat", systemImage: "person.crop.circle.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // ── Navigation Items ──
            Section("导航") {
                ForEach(AppSection.allCases) { section in
                    Button {
                        HapticManager.selection()
                        selectedSection = section
                    } label: {
                        HStack {
                            Label(section.label, systemImage: section.systemImage)
                                .foregroundStyle(selectedSection == section ? .primary : .secondary)
                            Spacer()
                            if selectedSection == section {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("VRCX-Lite")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                if appState.isLoggedIn {
                    Button(role: .destructive) {
                        HapticManager.heavy()
                        Task { await appState.logout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Content Column (iPad)

    private var contentColumn: some View {
        sectionView(for: selectedSection, isCompact: false)
            .navigationTitle(selectedSection.label)
    }

    // MARK: - Detail Column (iPad)

    @ViewBuilder
    private var detailColumn: some View {
        if let detail = appState.selectedDetail {
            detailView(for: detail)
        } else {
            ContentUnavailableView(
                "选择一项查看详情",
                systemImage: "sidebar.trailing",
                description: Text("从中间列表选择一个项目以在此处查看详细信息")
            )
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: AppSection, isCompact: Bool) -> some View {
        switch section {
        case .friends:
            FriendsListView(isCompact: isCompact)
        case .notifications:
            NotificationsView(isCompact: isCompact)
        case .worlds:
            WorldsView(isCompact: isCompact)
        case .settings:
            SettingsView()
        }
    }

    // MARK: - Detail Router

    @ViewBuilder
    private func detailView(for content: DetailContent) -> some View {
        switch content {
        case .friend(let friend):
            FriendDetailView(friend: friend)
        case .notification(let notification):
            NotificationDetailView(notification: notification)
        case .world(let world):
            WorldDetailView(world: world)
        case .instance(let instance):
            InstanceDetailView(instance: instance)
        }
    }
}

// MARK: - App State

@MainActor
@Observable
final class AppState {
    var isLoggedIn = false
    var currentUser: CurrentUser?
    var showLoginSheet = false
    var selectedDetail: DetailContent?

    var friends: [Friend] = []
    var notifications: [VRCNotification] = []
    var worlds: [World] = []

    var isLoadingFriends = false
    var isLoadingNotifications = false
    var isLoadingWorlds = false
    var isRestoringSession = false

    var errorMessage: String?

    private let api = VRChatAPIClient.shared

    // MARK: Session Restoration

    func restoreSessionIfPossible() async {
        isRestoringSession = true
        defer { isRestoringSession = false }

        do {
            let user = try await api.restoreSession()
            currentUser = user
            isLoggedIn = true
        } catch VRChatAPIError.notAuthenticated {
            // No saved session — user must log in manually; not an error.
        } catch VRChatAPIError.sessionExpired {
            // Session expired — clear and show login.
            await api.logout()
        } catch {
            // Network or other transient error — user can retry.
            errorMessage = error.localizedDescription
        }
    }

    func login(username: String, password: String) async throws -> CurrentUser {
        let user = try await api.login(username: username, password: password)
        currentUser = user
        isLoggedIn = true
        HapticManager.success()
        return user
    }

    func verifyTOTP(code: String) async throws -> CurrentUser {
        let user = try await api.verifyTOTP(code: code)
        currentUser = user
        isLoggedIn = true
        HapticManager.success()
        return user
    }

    func verifyEmailCode(code: String) async throws -> CurrentUser {
        let user = try await api.verifyEmailCode(code: code)
        currentUser = user
        isLoggedIn = true
        HapticManager.success()
        return user
    }

    func logout() async {
        HapticManager.heavy()
        await api.logout()
        isLoggedIn = false
        currentUser = nil
        friends = []
        notifications = []
        worlds = []
        selectedDetail = nil
        errorMessage = nil
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.red.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Avatar Image Component

struct AvatarImage: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url.flatMap { URL(string: $0) }) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            case .empty:
                ProgressView().scaleEffect(0.6)
            @unknown default:
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Login View

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var twoFactorCode = ""
    @State private var isLoggingIn = false
    @State private var pending2FAMethods: [TwoFactorMethod] = []
    @State private var localError: String?

    // Auto-fill from Keychain
    @State private var didAttemptKeychainFill = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("用户名/邮箱", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("VRChat 账户")
                }

                if !pending2FAMethods.isEmpty {
                    Section {
                        TextField("验证码", text: $twoFactorCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    } header: {
                        Text("两步验证")
                    } footer: {
                        Text("请输入通过 \(pending2FAMethods.map(\.displayName).joined(separator: " 或 ")) 收到的验证码")
                    }
                }

                if let error = localError {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button {
                        HapticManager.light()
                        Task { await performLogin() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoggingIn {
                                ProgressView()
                            } else {
                                Text(pending2FAMethods.isEmpty ? "登录" : "验证")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty
                              || password.isEmpty
                              || isLoggingIn)
                }
            }
            .navigationTitle("登录 VRChat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        HapticManager.light()
                        dismiss()
                    }
                }
            }
            .onAppear {
                fillFromKeychain()
            }
        }
    }

    private func fillFromKeychain() {
        guard !didAttemptKeychainFill else { return }
        didAttemptKeychainFill = true

        if let creds = KeychainHelper_Access.retrieve() {
            username = creds.username
            password = creds.password
        }
    }

    private func performLogin() async {
        isLoggingIn = true
        localError = nil
        defer { isLoggingIn = false }

        if pending2FAMethods.isEmpty {
            // Step 1: Login
            do {
                let user = try await appState.login(username: username, password: password)
                dismiss()
            } catch VRChatAPIError.requiresTwoFactorAuth(let methods) {
                HapticManager.warning()
                pending2FAMethods = methods
            } catch {
                HapticManager.error()
                localError = error.localizedDescription
            }
        } else {
            // Step 2: 2FA verification
            let trimmed = twoFactorCode.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                localError = "请输入验证码"
                return
            }

            do {
                if pending2FAMethods.contains(.totp) {
                    let _ = try await appState.verifyTOTP(code: trimmed)
                } else {
                    let _ = try await appState.verifyEmailCode(code: trimmed)
                }
                pending2FAMethods = []
                dismiss()
            } catch {
                HapticManager.error()
                localError = error.localizedDescription
            }
        }
    }
}

// MARK: - Keychain Access (for LoginView auto-fill)

private enum KeychainHelper_Access {
    static func retrieve() -> (username: String, password: String)? {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.vrcx-lite.auth",
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
}

// MARK: - Selectable Row Tap Helper

private struct SelectableRow<Content: View>: View {
    let detail: DetailContent
    let isCompact: Bool
    let content: Content
    @Environment(AppState.self) private var appState

    init(detail: DetailContent, isCompact: Bool, @ViewBuilder content: () -> Content) {
        self.detail = detail
        self.isCompact = isCompact
        self.content = content()
    }

    var body: some View {
        if isCompact {
            NavigationLink(value: detail) {
                content
            }
        } else {
            Button {
                HapticManager.light()
                appState.selectedDetail = detail
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Friends List

struct FriendsListView: View {
    @Environment(AppState.self) private var appState
    let isCompact: Bool

    var body: some View {
        Group {
            if appState.isRestoringSession {
                ProgressView("恢复登录…")
            } else if appState.isLoadingFriends && appState.friends.isEmpty {
                ProgressView("加载好友列表…")
            } else if !appState.isLoggedIn {
                ContentUnavailableView(
                    "未登录",
                    systemImage: "person.2.slash",
                    description: Text("请先登录 VRChat 账户以查看好友列表")
                )
            } else if appState.friends.isEmpty {
                ContentUnavailableView("暂无好友", systemImage: "person.2.slash")
            } else {
                List(appState.friends) { friend in
                    SelectableRow(detail: .friend(friend), isCompact: isCompact) {
                        FriendRow(friend: friend)
                    }
                }
                .refreshable { await refreshFriends() }
            }
        }
        .if(isCompact) { view in
            view.navigationDestination(for: DetailContent.self) { detail in
                DetailResolver(detail: detail)
            }
        }
        .task {
            if appState.isLoggedIn && appState.friends.isEmpty {
                await refreshFriends()
            }
        }
    }

    private func refreshFriends() async {
        appState.isLoadingFriends = true
        defer { appState.isLoadingFriends = false }

        do {
            appState.friends = try await VRChatAPIClient.shared.fetchFriends()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Friend Row

struct FriendRow: View {
    let friend: Friend

    private var statusColor: Color {
        FriendStatusColor.color(state: friend.state, status: friend.status)
    }

    private var statusText: String {
        FriendStatusColor.label(state: friend.state, status: friend.status)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with 1pt semi-transparent white border
            AvatarImage(url: friend.userIcon, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName ?? friend.username ?? "未知用户")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Notifications List

struct NotificationsView: View {
    @Environment(AppState.self) private var appState
    let isCompact: Bool

    var body: some View {
        Group {
            if appState.isRestoringSession {
                ProgressView("恢复登录…")
            } else if appState.isLoadingNotifications && appState.notifications.isEmpty {
                ProgressView("加载通知…")
            } else if !appState.isLoggedIn {
                ContentUnavailableView(
                    "未登录",
                    systemImage: "bell.slash",
                    description: Text("请先登录以查看通知")
                )
            } else if appState.notifications.isEmpty {
                ContentUnavailableView("暂无通知", systemImage: "bell.slash")
            } else {
                List(appState.notifications) { notif in
                    SelectableRow(detail: .notification(notif), isCompact: isCompact) {
                        NotificationRow(notification: notif)
                    }
                }
                .refreshable { await refreshNotifications() }
            }
        }
        .if(isCompact) { view in
            view.navigationDestination(for: DetailContent.self) { detail in
                DetailResolver(detail: detail)
            }
        }
        .task {
            if appState.isLoggedIn && appState.notifications.isEmpty {
                await refreshNotifications()
            }
        }
    }

    private func refreshNotifications() async {
        appState.isLoadingNotifications = true
        defer { appState.isLoadingNotifications = false }

        do {
            appState.notifications = try await VRChatAPIClient.shared.fetchNotifications()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Notification Row

struct NotificationRow: View {
    let notification: VRCNotification

    var typeLabel: String {
        switch notification.type {
        case "friendRequest": return "好友请求"
        case "invite":        return "世界邀请"
        case "requestInvite": return "请求邀请"
        case "voteToKick":    return "投票踢出"
        default:              return notification.type
        }
    }

    var icon: String {
        switch notification.type {
        case "friendRequest": return "person.badge.plus"
        case "invite":        return "envelope.open"
        case "requestInvite": return "paperplane"
        case "voteToKick":    return "exclamationmark.bubble"
        default:              return "bell"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 36, height: 36)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.senderUsername ?? "系统")
                    .fontWeight(.medium)
                Text(typeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if notification.seen == false {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Worlds List

struct WorldsView: View {
    @Environment(AppState.self) private var appState
    let isCompact: Bool
    @State private var searchText = ""

    var body: some View {
        Group {
            if appState.isRestoringSession {
                ProgressView("恢复登录…")
            } else if appState.isLoadingWorlds && appState.worlds.isEmpty {
                ProgressView("加载世界列表…")
            } else if !appState.isLoggedIn {
                ContentUnavailableView(
                    "未登录",
                    systemImage: "globe.americas",
                    description: Text("请先登录以浏览世界")
                )
            } else {
                List(appState.worlds) { world in
                    SelectableRow(detail: .world(world), isCompact: isCompact) {
                        WorldRow(world: world)
                    }
                }
                .searchable(text: $searchText, prompt: "搜索世界…")
                .refreshable { await refreshWorlds() }
            }
        }
        .if(isCompact) { view in
            view.navigationDestination(for: DetailContent.self) { detail in
                DetailResolver(detail: detail)
            }
        }
        .task {
            if appState.isLoggedIn && appState.worlds.isEmpty {
                await refreshWorlds()
            }
        }
        .onChange(of: searchText) { _, newValue in
            Task { await refreshWorlds(search: newValue) }
        }
    }

    private func refreshWorlds(search: String? = nil) async {
        appState.isLoadingWorlds = true
        defer { appState.isLoadingWorlds = false }

        do {
            let q = (search?.isEmpty ?? true) ? nil : search
            appState.worlds = try await VRChatAPIClient.shared.fetchActiveWorlds(search: q)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - World Row

struct WorldRow: View {
    let world: World

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: world.thumbnailImageUrl.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "globe.americas")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .frame(width: 48, height: 48)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                case .empty:
                    ProgressView().frame(width: 48, height: 48)
                @unknown default:
                    Image(systemName: "globe.americas").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(world.name ?? "未知世界")
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let author = world.authorName {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let occupants = world.occupants {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill").font(.caption2)
                    Text("\(occupants)").font(.caption).fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }
        }
    }
}

// MARK: - Detail Resolver (Compact push navigation)

struct DetailResolver: View {
    let detail: DetailContent

    var body: some View {
        switch detail {
        case .friend(let friend):
            FriendDetailView(friend: friend)
        case .notification(let notification):
            NotificationDetailView(notification: notification)
        case .world(let world):
            WorldDetailView(world: world)
        case .instance(let instance):
            InstanceDetailView(instance: instance)
        }
    }
}

// MARK: - Friend Detail View

struct FriendDetailView: View {
    let friend: Friend
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    private var statusColor: Color {
        FriendStatusColor.color(state: friend.state, status: friend.status)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AvatarImage(url: friend.userIcon, size: 120)

                VStack(spacing: 4) {
                    Text(friend.displayName ?? friend.username ?? "未知")
                        .font(.title2.bold())

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                        Text(FriendStatusColor.label(
                            state: friend.state,
                            status: friend.status
                        ))
                        .foregroundStyle(.secondary)
                    }

                    if let statusDesc = friend.statusDescription {
                        Text(statusDesc)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Location info
                if let location = friend.location, !location.isEmpty, location != "offline" {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Action: launch VRChat world URL if friend is in a world
                if let worldID = friend.worldId, !worldID.isEmpty,
                   let url = VRChatAPIClient.shared.buildWorldLaunchURL(
                    worldID: worldID,
                    instanceID: friend.instanceId
                   ) {
                    Button {
                        HapticManager.medium()
                        openURL(url)
                    } label: {
                        Label("在 VRChat 中打开", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                // Bio
                if let bio = friend.bio, !bio.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("简介")
                            .font(.headline)
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(friend.displayName ?? "好友详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notification Detail View

struct NotificationDetailView: View {
    let notification: VRCNotification
    @Environment(AppState.self) private var appState
    @State private var isActing = false
    @State private var actionError: String?

    private var isFriendRequest: Bool { notification.type == "friendRequest" }
    private var isInvite: Bool {
        notification.type == "invite" || notification.type == "requestInvite"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Icon
                Image(systemName: isFriendRequest ? "person.badge.plus" : "envelope.open")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                // Title
                Text(notification.senderUsername ?? "系统")
                    .font(.title2.bold())

                Text(typeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let message = notification.message, !message.isEmpty {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Actions
                if isFriendRequest || isInvite {
                    VStack(spacing: 12) {
                        if isActing {
                            ProgressView("处理中…")
                        } else {
                            // Accept
                            Button {
                                Task { await act(accept: true) }
                            } label: {
                                Label(
                                    isFriendRequest ? "接受好友请求" : "接受邀请",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            // Decline
                            Button(role: .destructive) {
                                Task { await act(accept: false) }
                            } label: {
                                Label(
                                    isFriendRequest ? "拒绝好友请求" : "拒绝邀请",
                                    systemImage: "xmark.circle.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 32)
                }

                if let error = actionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("通知详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var typeLabel: String {
        switch notification.type {
        case "friendRequest": return "好友请求"
        case "invite":        return "世界邀请"
        case "requestInvite": return "请求邀请"
        case "voteToKick":    return "投票踢出"
        default:              return notification.type
        }
    }

    private func act(accept: Bool) async {
        isActing = true
        actionError = nil
        HapticManager.medium()

        let api = VRChatAPIClient.shared

        do {
            if isFriendRequest {
                if accept {
                    try await api.acceptFriendRequest(notificationID: notification.id)
                } else {
                    try await api.declineFriendRequest(notificationID: notification.id)
                }
            } else if isInvite {
                try await api.respondToInvite(notificationID: notification.id, accept: accept)
            }

            // Refresh notifications
            appState.notifications = try await api.fetchNotifications()
            HapticManager.success()
        } catch {
            actionError = error.localizedDescription
            HapticManager.error()
        }

        isActing = false
    }
}

// MARK: - World Detail View

struct WorldDetailView: View {
    let world: World
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Thumbnail
                AsyncImage(url: world.imageUrl.flatMap(URL.init)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.quaternary)
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: "globe.americas")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            )
                    case .empty:
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.quaternary)
                            .frame(height: 200)
                            .overlay(ProgressView())
                    @unknown default:
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.quaternary)
                            .frame(height: 200)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Name & Author
                VStack(spacing: 4) {
                    Text(world.name ?? "未知世界")
                        .font(.title2.bold())
                    if let author = world.authorName {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Stats
                HStack(spacing: 24) {
                    if let occupants = world.occupants {
                        statView(icon: "person.2.fill", label: "在线", value: "\(occupants)")
                    }
                    if let favorites = world.favorites {
                        statView(icon: "star.fill", label: "收藏", value: "\(favorites)")
                    }
                    if let visits = world.visits {
                        statView(icon: "eye.fill", label: "访问", value: "\(visits)")
                    }
                    if let capacity = world.capacity {
                        statView(icon: "person.3.fill", label: "容量", value: "\(capacity)")
                    }
                }

                // Description
                if let desc = world.description, !desc.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("简介").font(.headline)
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Launch in VRChat
                if let url = URL(string: "https://vrchat.com/home/world/\(world.id)") {
                    Button {
                        HapticManager.medium()
                        openURL(url)
                    } label: {
                        Label("在 VRChat 中查看", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(world.name ?? "世界详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statView(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.title3)
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Instance Detail View

struct InstanceDetailView: View {
    let instance: Instance
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(instance.name ?? instance.id)
                    .font(.title2.bold())

                if let nUsers = instance.nUsers {
                    Label("\(nUsers) 人", systemImage: "person.2.fill")
                }

                if let region = instance.region {
                    Label(region, systemImage: "location.fill")
                }

                if let platforms = instance.platforms, !platforms.isEmpty {
                    Label(platforms.joined(separator: ", "), systemImage: "rectangle.on.rectangle")
                }

                // Launch
                if let worldID = instance.worldId,
                   let url = VRChatAPIClient.shared.buildWorldLaunchURL(
                    worldID: worldID,
                    instanceID: instance.id
                   ) {
                    Button {
                        HapticManager.medium()
                        openURL(url)
                    } label: {
                        Label("在 VRChat 中打开", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("实例详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                if appState.isLoggedIn {
                    if let user = appState.currentUser {
                        HStack {
                            AvatarImage(url: user.userIcon, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName ?? user.username ?? "VRChat 用户")
                                    .fontWeight(.medium)
                                Text(user.id)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(role: .destructive) {
                        HapticManager.heavy()
                        Task { await appState.logout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        HapticManager.light()
                        appState.showLoginSheet = true
                    } label: {
                        Label("登录 VRChat", systemImage: "person.crop.circle")
                    }
                }
            } header: {
                Text("账户")
            }

            Section {
                LabeledContent("版本", value: "1.0.0")
                LabeledContent("项目", value: "VRCX-Lite")
                LabeledContent("平台", value: "iOS / iPadOS")
            } header: {
                Text("关于")
            }
        }
        .navigationTitle("设置")
    }
}

// MARK: - Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - App Entry Point

@main
struct VRCX_LiteApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainContainerView()
                .environment(appState)
                .background(.ultraThinMaterial)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Previews

#Preview("iPad Landscape — 3 Column") {
    MainContainerView()
        .environment(AppState())
        .previewDevice("iPad Pro (11-inch) (6th generation)")
}

#Preview("iPhone Portrait — Tab") {
    MainContainerView()
        .environment(AppState())
        .previewDevice("iPhone 16 Pro")
}
