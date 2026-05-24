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
    case home
    case friends
    case worlds
    case memories
    case profile

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home:      return "首页"
        case .friends:   return "好友"
        case .worlds:    return "世界"
        case .memories:  return "回忆"
        case .profile:   return "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .home:      return "house"
        case .friends:   return "person.2"
        case .worlds:    return "globe.americas"
        case .memories:  return "clock.arrow.2.circlepath"
        case .profile:   return "person.crop.circle"
        }
    }
}

// MARK: - Activity Feed Item

enum ActivityItem: Identifiable, Hashable {
    case friendOnline(Friend)
    case friendActive(Friend)
    case friendInWorld(Friend, String)
    case friendRequest(VRCNotification)
    case invite(VRCNotification)
    case worldPopular(World)

    var id: String {
        switch self {
        case .friendOnline(let f):    return "online-\(f.id)"
        case .friendActive(let f):    return "active-\(f.id)"
        case .friendInWorld(let f, _): return "inworld-\(f.id)"
        case .friendRequest(let n):   return "fr-\(n.id)"
        case .invite(let n):          return "inv-\(n.id)"
        case .worldPopular(let w):   return "popw-\(w.id)"
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

    @State private var selectedSection: AppSection = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Computed binding because @Environment Observable doesn't support $ prefix.
    private var showLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.showLoginSheet },
            set: { appState.showLoginSheet = $0 }
        )
    }

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
                .badge(section == .home ? appState.unreadNotificationCount : 0)
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
                            if section == .home, appState.unreadNotificationCount > 0 {
                                Text("\(appState.unreadNotificationCount)")
                                    .font(.caption2).fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.red, in: Capsule())
                            } else if section == .friends, appState.isLoggedIn {
                                Text("\(appState.friends.count)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else if selectedSection == section {
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.secondary)
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
        case .home:
            HomeView(isCompact: isCompact)
        case .friends:
            FriendsListView(isCompact: isCompact)
        case .worlds:
            WorldsView(isCompact: isCompact)
        case .memories:
            MemoriesView(isCompact: isCompact)
        case .profile:
            ProfileView()
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

    // MARK: Feed

    var feedItems: [ActivityItem] = []

    /// Refresh the home feed from current friends, notifications, and worlds data.
    func refreshFeed() {
        var items: [ActivityItem] = []

        // Online friends
        for friend in onlineFriends {
            let status = friend.status ?? friend.state ?? "online"
            if status == "join me" || status == "active" {
                items.append(.friendActive(friend))
            } else if let loc = friend.location, !loc.isEmpty, loc != "offline", loc != "private" {
                items.append(.friendInWorld(friend, loc))
            } else {
                items.append(.friendOnline(friend))
            }
        }

        // Recent notifications as activity
        for notif in notifications.prefix(10) {
            if notif.type == "friendRequest" {
                items.append(.friendRequest(notif))
            } else if notif.type == "invite" {
                items.append(.invite(notif))
            }
        }

        // World recommendations
        let popular = worlds.sorted { ($0.occupants ?? 0) > ($1.occupants ?? 0) }.prefix(3)
        for world in popular where (world.occupants ?? 0) > 0 {
            items.append(.worldPopular(world))
        }

        // Sort: most recent/active first
        feedItems = Array(items.prefix(30))
    }

    // MARK: Computed Properties

    var unreadNotificationCount: Int {
        notifications.filter { $0.seen == false }.count
    }

    var onlineFriends: [Friend] {
        friends.filter { ($0.state ?? "offline") != "offline" }
    }

    var offlineFriends: [Friend] {
        friends.filter { ($0.state ?? "offline") == "offline" }
    }

    var activeFriends: [Friend] {
        friends.filter {
            let s = ($0.status ?? $0.state ?? "").lowercased()
            return s == "active" || s == "join me"
        }
    }

    var friendRequests: [VRCNotification] {
        notifications.filter { $0.type == "friendRequest" }
    }

    var invites: [VRCNotification] {
        notifications.filter { $0.type == "invite" || $0.type == "requestInvite" }
    }

    var favoriteFriends: [Friend] {
        friends.filter { $0.isFavorite == true }
    }

    // MARK: Session Restoration

    func restoreSessionIfPossible() async {
        isRestoringSession = true
        defer { isRestoringSession = false }

        do {
            let user = try await api.restoreSession()
            currentUser = user
            isLoggedIn = true
        } catch VRChatAPIError.notAuthenticated {
            return
        } catch VRChatAPIError.sessionExpired {
            await api.logout()
            return
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Preload data for feed (best-effort parallel)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do { friends = try await api.fetchFriends() }
                catch { /* preload failure is non-critical */ }
            }
            group.addTask {
                do { notifications = try await api.fetchNotifications() }
                catch { /* preload failure is non-critical */ }
            }
            group.addTask {
                do { worlds = try await api.fetchActiveWorlds() }
                catch { /* preload failure is non-critical */ }
            }
        }
        refreshFeed()
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

    func markAllNotificationsRead() async {
        let unreadIDs = notifications.filter { $0.seen == false }.map(\.id)
        guard !unreadIDs.isEmpty else { return }

        for id in unreadIDs {
            do {
                try await api.markNotificationSeen(notificationID: id)
            } catch {
                // Individual mark may fail; continue with remaining
            }
        }
        // Re-fetch to sync state
        do {
            notifications = try await api.fetchNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                _ = try await appState.login(username: username, password: password)
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

enum FriendFilter: String, CaseIterable {
    case all
    case online
    case active
    case offline

    var label: String {
        switch self {
        case .all:     return "全部"
        case .online:  return "在线"
        case .active:  return "活跃"
        case .offline: return "离线"
        }
    }
}

struct FriendsListView: View {
    @Environment(AppState.self) private var appState
    let isCompact: Bool
    @State private var filter: FriendFilter = .all

    private var filteredFriends: [Friend] {
        switch filter {
        case .all:     return appState.friends
        case .online:  return appState.onlineFriends
        case .active:  return appState.activeFriends
        case .offline: return appState.offlineFriends
        }
    }

    var body: some View {
        Group {
            if appState.isRestoringSession {
                ProgressView("恢复登录…")
            } else if !appState.isLoggedIn {
                ContentUnavailableView(
                    "未登录", systemImage: "person.2.slash",
                    description: Text("请先登录 VRChat 账户以查看好友列表")
                )
            } else {
                VStack(spacing: 0) {
                    // ── Filter + Count ──
                    HStack {
                        Picker("筛选", selection: $filter) {
                            ForEach(FriendFilter.allCases, id: \.self) { f in
                                Text(f.label).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                        Text("共 \(filteredFriends.count) 人")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .background(.ultraThinMaterial)

                    if appState.isLoadingFriends && appState.friends.isEmpty {
                        List(0..<8) { _ in
                            HStack(spacing: 12) {
                                Circle().fill(.quaternary).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 120, height: 14)
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 60, height: 10)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .redacted(reason: .placeholder)
                    } else if filteredFriends.isEmpty {
                        ContentUnavailableView(
                            filter == .all ? "暂无好友" : "无匹配好友",
                            systemImage: "person.2.slash"
                        )
                    } else {
                        List(filteredFriends) { friend in
                            SelectableRow(detail: .friend(friend), isCompact: isCompact) {
                                FriendRow(friend: friend)
                            }
                        }
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

    private var locationHint: String? {
        guard let loc = friend.location, !loc.isEmpty, loc != "offline", loc != "private" else {
            return nil
        }
        if loc.hasPrefix("wrld_") { return "世界中" }
        if loc.contains(":") { return "实例中" }
        return loc
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarImage(url: friend.userIcon, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(friend.displayName ?? friend.username ?? "未知用户")
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if friend.isFavorite == true {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 4) {
                    // Online indicator dot
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let hint = locationHint {
                        Text("· \(hint)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Notifications List

enum NotificationFilter: String, CaseIterable {
    case all
    case friendRequests
    case invites

    var label: String {
        switch self {
        case .all:            return "全部"
        case .friendRequests: return "好友请求"
        case .invites:        return "邀请"
        }
    }
}

struct NotificationsView: View {
    @Environment(AppState.self) private var appState
    let isCompact: Bool
    @State private var filter: NotificationFilter = .all

    private var filteredNotifications: [VRCNotification] {
        switch filter {
        case .all:            return appState.notifications
        case .friendRequests: return appState.friendRequests
        case .invites:        return appState.invites
        }
    }

    var body: some View {
        Group {
            if appState.isRestoringSession {
                ProgressView("恢复登录…")
            } else if !appState.isLoggedIn {
                ContentUnavailableView(
                    "未登录", systemImage: "bell.slash",
                    description: Text("请先登录以查看通知")
                )
            } else {
                VStack(spacing: 0) {
                    Picker("筛选", selection: $filter) {
                        ForEach(NotificationFilter.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    if appState.isLoadingNotifications && appState.notifications.isEmpty {
                        List(0..<6) { _ in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 100, height: 14)
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 60, height: 10)
                                }
                            }
                        }
                        .redacted(reason: .placeholder)
                    } else if filteredNotifications.isEmpty {
                        ContentUnavailableView(
                            filter == .all ? "暂无通知" : "无匹配通知",
                            systemImage: filter == .all ? "bell.slash" : "bell"
                        )
                    } else {
                        List(filteredNotifications) { notif in
                            SelectableRow(detail: .notification(notif), isCompact: isCompact) {
                                NotificationRow(notification: notif)
                            }
                        }
                    }
                }
                .refreshable { await refreshNotifications() }
                .toolbar {
                    if appState.unreadNotificationCount > 0 {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                HapticManager.light()
                                Task { await appState.markAllNotificationsRead() }
                            } label: {
                                Text("全部已读")
                                    .font(.caption)
                            }
                        }
                    }
                }
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

enum WorldCategory: String, CaseIterable {
    case trending
    case popular
    case recent
    case search

    var label: String {
        switch self {
        case .trending: return "热门"
        case .popular:  return "最多人"
        case .recent:   return "最新"
        case .search:   return "搜索"
        }
    }

    var icon: String {
        switch self {
        case .trending: return "flame"
        case .popular:  return "person.3"
        case .recent:   return "clock"
        case .search:   return "magnifyingglass"
        }
    }
}

struct WorldsView: View {
    @Environment(AppState.self) private var appState
    let isCompact: Bool
    @State private var selectedCategory: WorldCategory = .trending
    @State private var searchText = ""

    var body: some View {
        Group {
            if appState.isRestoringSession {
                ProgressView("恢复登录…")
            } else if !appState.isLoggedIn {
                ContentUnavailableView(
                    "未登录", systemImage: "globe.americas",
                    description: Text("请先登录以浏览世界")
                )
            } else {
                VStack(spacing: 0) {
                    // ── Category Picker ──
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(WorldCategory.allCases, id: \.self) { cat in
                                Button {
                                    HapticManager.selection()
                                    selectedCategory = cat
                                    if cat == .search { return }
                                    Task { await refreshWorlds() }
                                } label: {
                                    Label(cat.label, systemImage: cat.icon)
                                        .font(.caption).fontWeight(.medium)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(
                                            selectedCategory == cat
                                            ? AnyShapeStyle(.tint)
                                            : AnyShapeStyle(.quaternary),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(
                                            selectedCategory == cat
                                            ? .white
                                            : .secondary
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(.ultraThinMaterial)

                    // ── Search Bar (when search category) ──
                    if selectedCategory == .search {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("搜索世界…", text: $searchText)
                                .textFieldStyle(.plain)
                                .onSubmit { Task { await refreshWorlds() } }
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    Task { await refreshWorlds() }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }

                    // ── World List ──
                    if appState.isLoadingWorlds && appState.worlds.isEmpty {
                        List(0..<6) { _ in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(width: 48, height: 48)
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 140, height: 14)
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 80, height: 10)
                                }
                            }
                        }
                        .redacted(reason: .placeholder)
                    } else if appState.worlds.isEmpty {
                        ContentUnavailableView("未找到世界", systemImage: "globe.americas")
                    } else {
                        List(appState.worlds) { world in
                            SelectableRow(detail: .world(world), isCompact: isCompact) {
                                WorldRow(world: world)
                            }
                        }
                    }
                }
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
    }

    private func refreshWorlds() async {
        appState.isLoadingWorlds = true
        defer { appState.isLoadingWorlds = false }

        var search: String? = nil
        switch selectedCategory {
        case .search: search = searchText.isEmpty ? nil : searchText
        case .trending, .popular, .recent: search = nil
        }

        do {
            appState.worlds = try await VRChatAPIClient.shared.fetchActiveWorlds(search: search)
            // Client-side sorting for categories
            switch selectedCategory {
            case .popular:
                appState.worlds.sort { ($0.occupants ?? 0) > ($1.occupants ?? 0) }
            case .recent:
                appState.worlds.sort { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
            default: break
            }
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
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Thumbnail
                AsyncImage(url: world.imageUrl.flatMap(URL.init)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.quaternary)
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: "globe.americas")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            )
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Name & Author
                VStack(spacing: 4) {
                    Text(world.name ?? "未知世界")
                        .font(.title2.bold())
                    if let author = world.authorName {
                        Label(author, systemImage: "person.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Stats grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
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

                // Tags
                if let tags = world.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                let label = tag
                                    .replacingOccurrences(of: "content_", with: "")
                                    .replacingOccurrences(of: "language_", with: "")
                                    .replacingOccurrences(of: "_", with: " ")
                                Text("#\(label)")
                                    .font(.caption2)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        .padding(.horizontal)
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
                    .padding(.horizontal)
                }

                // Instances
                if let instances = world.instances, !instances.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("活跃实例 (\(instances.count))").font(.headline).padding(.horizontal)
                        ForEach(instances.prefix(5), id: \.self) { dict in
                            let name = dict["name"] ?? dict["id"] ?? "Unknown"
                            let count = dict["n_users"] ?? dict["count"] ?? "?"
                            HStack {
                                Label(name, systemImage: "circle.grid.3x3")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(count) 人")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                        }
                    }
                }

                // Launch
                Button {
                    HapticManager.medium()
                    if let url = VRChatAPIClient.shared.buildWorldLaunchURL(
                        worldID: world.id, instanceID: nil
                    ) {
                        openURL(url)
                    }
                } label: {
                    Label("在 VRChat 中查看", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.horizontal)
            }
            .padding(.vertical)
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

// MARK: - Home View

struct HomeView: View {
    @Environment(AppState.self) private var appState
    let isCompact: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !appState.isLoggedIn {
                    // ── Not Logged In ──
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("欢迎使用 VRCX-Lite").font(.title2.bold())
                        Text("登录 VRChat 以查看好友动态、世界推荐和社交回忆")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            HapticManager.medium()
                            appState.showLoginSheet = true
                        } label: {
                            Label("登录 VRChat", systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: 200)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
                } else {
                    // ── My Status Card ──
                    if let user = appState.currentUser {
                        statusCard(user: user)
                    }

                    // ── Quick Actions ──
                    quickActions

                    // ── Online Friends Snapshot ──
                    if !appState.onlineFriends.isEmpty {
                        onlineFriendsStrip
                    }

                    // ── Activity Feed ──
                    if !appState.feedItems.isEmpty {
                        feedSection
                    } else {
                        ProgressView("加载动态…")
                            .padding()
                    }

                    // ── Popular Worlds ──
                    if !appState.worlds.isEmpty {
                        worldRecommendations
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable {
            await refreshAll()
        }
        .task {
            if appState.isLoggedIn && appState.feedItems.isEmpty {
                await refreshAll()
            }
        }
        .if(isCompact) { view in
            view.navigationDestination(for: DetailContent.self) { detail in
                DetailResolver(detail: detail)
            }
        }
    }

    // MARK: Status Card

    private func statusCard(user: CurrentUser) -> some View {
        HStack(spacing: 12) {
            AvatarImage(url: user.userIcon, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName ?? user.username ?? "VRChat 用户")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(FriendStatusColor.color(state: user.state, status: user.status))
                        .frame(width: 8, height: 8)
                    Text(FriendStatusColor.label(state: user.state, status: user.status))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Text("\(appState.friends.count)").font(.title3.bold())
                Text("好友").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: Quick Actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickActionCard(
                icon: "person.fill.badge.plus", label: "好友请求",
                count: appState.friendRequests.count, color: .orange
            ) {
                HapticManager.light()
                // filtered to friend requests view
            }
            QuickActionCard(
                icon: "envelope.fill", label: "邀请",
                count: appState.invites.count, color: .blue
            ) {
                HapticManager.light()
            }
            QuickActionCard(
                icon: "star.fill", label: "收藏好友",
                count: appState.favoriteFriends.count, color: .yellow
            ) {
                HapticManager.light()
            }
            QuickActionCard(
                icon: "clock.arrow.2.circlepath", label: "回忆", count: 0, color: .purple
            ) {
                HapticManager.light()
            }
        }
        .padding(.horizontal)
    }

    // MARK: Online Friends Strip

    private var onlineFriendsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("在线好友").font(.subheadline.bold())
                Spacer()
                Text("\(appState.onlineFriends.count) 人在线")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(appState.onlineFriends.prefix(20)) { friend in
                        VStack(spacing: 4) {
                            AvatarImage(url: friend.userIcon, size: 48)

                            Text(friend.displayName ?? friend.username ?? "?")
                                .font(.caption2).lineLimit(1)
                                .frame(width: 54)

                            Circle()
                                .fill(FriendStatusColor.color(state: friend.state, status: friend.status))
                                .frame(width: 6, height: 6)
                        }
                        .onTapGesture {
                            HapticManager.light()
                            appState.selectedDetail = .friend(friend)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: Feed

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("动态").font(.subheadline.bold())
                Spacer()
            }
            .padding(.horizontal)

            LazyVStack(spacing: 2) {
                ForEach(appState.feedItems) { item in
                    ActivityRow(item: item)
                    if item.id != appState.feedItems.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        }
    }

    // MARK: World Recommendations

    private var worldRecommendations: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("推荐世界").font(.subheadline.bold())
                Spacer()
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.worlds.prefix(8)) { world in
                        VStack(alignment: .leading, spacing: 6) {
                            AsyncImage(url: world.thumbnailImageUrl.flatMap(URL.init)) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                                        .overlay(Image(systemName: "globe.americas").foregroundStyle(.tertiary))
                                }
                            }
                            .frame(width: 140, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            Text(world.name ?? "未知世界")
                                .font(.caption).fontWeight(.medium).lineLimit(1)

                            if let n = world.occupants {
                                Label("\(n)", systemImage: "person.fill")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 140)
                        .onTapGesture {
                            HapticManager.light()
                            appState.selectedDetail = .world(world)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func refreshAll() async {
        let api = VRChatAPIClient.shared
        do { appState.friends = try await api.fetchFriends() }
        catch { appState.errorMessage = error.localizedDescription }
        do { appState.notifications = try await api.fetchNotifications() }
        catch { /* non-critical: feed items will skip notification entries */ }
        do { appState.worlds = try await api.fetchActiveWorlds() }
        catch { /* non-critical: feed items will skip world entries */ }
        appState.refreshFeed()
    }
}

// MARK: - Quick Action Card

struct QuickActionCard: View {
    let icon: String
    let label: String
    let count: Int
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.title3).foregroundStyle(color)
                        .frame(height: 28)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.red, in: Circle())
                            .offset(x: 8, y: -4)
                    }
                }
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let item: ActivityItem
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title3).foregroundStyle(iconColor)
                .frame(width: 30)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Time marker
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.light()
            switch item {
            case .friendOnline(let f), .friendActive(let f), .friendInWorld(let f, _):
                appState.selectedDetail = .friend(f)
            case .friendRequest(let n), .invite(let n):
                appState.selectedDetail = .notification(n)
            case .worldPopular(let w):
                appState.selectedDetail = .world(w)
            }
        }
    }

    private var iconName: String {
        switch item {
        case .friendOnline:          return "circle.fill"
        case .friendActive:          return "sparkles"
        case .friendInWorld:         return "globe.americas.fill"
        case .friendRequest:         return "person.badge.plus"
        case .invite:                return "envelope.fill"
        case .worldPopular:          return "flame.fill"
        }
    }

    private var iconColor: Color {
        switch item {
        case .friendOnline:          return .green
        case .friendActive:          return .orange
        case .friendInWorld:         return .blue
        case .friendRequest:         return .orange
        case .invite:                return .cyan
        case .worldPopular:          return .red
        }
    }

    private var title: String {
        switch item {
        case .friendOnline(let f):
            return "\(f.displayName ?? f.username ?? "好友") 上线了"
        case .friendActive(let f):
            return "\(f.displayName ?? f.username ?? "好友") 正在活跃"
        case .friendInWorld(let f, _):
            return "\(f.displayName ?? f.username ?? "好友") 在探索世界"
        case .friendRequest:
            return "新的好友请求"
        case .invite:
            return "收到世界邀请"
        case .worldPopular(let w):
            return "热门世界: \(w.name ?? "未知")"
        }
    }

    private var subtitle: String? {
        switch item {
        case .friendOnline(let f):
            return f.statusDescription
        case .friendActive(let f):
            return f.statusDescription
        case .friendInWorld(_, let loc):
            return loc.hasPrefix("wrld_") ? "正在世界中" : loc
        case .friendRequest(let n):
            return "来自 \(n.senderUsername ?? "未知")"
        case .invite(let n):
            return "来自 \(n.senderUsername ?? "未知")"
        case .worldPopular(let w):
            return "\(w.occupants ?? 0) 人在线"
        }
    }
}

// MARK: - Memories View

struct MemoriesView: View {
    @Environment(AppState.self) private var appState
    let isCompact: Bool
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if !appState.isLoggedIn {
                ContentUnavailableView(
                    "需要登录", systemImage: "clock.arrow.2.circlepath",
                    description: Text("登录后记录你的 VR 社交回忆")
                )
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // ── Summary Stats ──
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2)) {
                            MemoryStatCard(
                                icon: "person.2.fill", label: "好友",
                                value: "\(appState.friends.count)", color: .blue
                            )
                            MemoryStatCard(
                                icon: "globe.americas.fill", label: "常去世界",
                                value: "\(appState.worlds.count)+", color: .green
                            )
                            MemoryStatCard(
                                icon: "bell.fill", label: "未读通知",
                                value: "\(appState.unreadNotificationCount)", color: .orange
                            )
                            MemoryStatCard(
                                icon: "star.fill", label: "收藏好友",
                                value: "\(appState.favoriteFriends.count)", color: .yellow
                            )
                        }
                        .padding(.horizontal)

                        // ── Coming Soon Banner ──
                        VStack(spacing: 12) {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 40)).foregroundStyle(.purple)
                            Text("回忆时间线 即将推出")
                                .font(.headline)
                            Text("记录每次相遇、每个世界、每张照片\n生成你的 VR 社交年度报告")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 8) {
                                ForEach(["时间线", "照片", "年度总结", "社交统计"], id: \.self) { feature in
                                    Text(feature)
                                        .font(.caption2)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)

                        // ── Recent Activity ──
                        VStack(alignment: .leading, spacing: 8) {
                            Text("近期动态").font(.subheadline.bold()).padding(.horizontal)
                            ForEach(appState.feedItems.prefix(10)) { item in
                                ActivityRow(item: item)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .refreshable {
            do { appState.notifications = try await VRChatAPIClient.shared.fetchNotifications() }
            catch { /* non-critical */ }
            appState.refreshFeed()
        }
    }
}

// MARK: - Memory Stat Card

struct MemoryStatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2).foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3.bold())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            // ── User Info ──
            if appState.isLoggedIn, let user = appState.currentUser {
                Section {
                    HStack(spacing: 14) {
                        AvatarImage(url: user.userIcon, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName ?? user.username ?? "VRChat 用户")
                                .font(.title3.bold())
                            Text("@\(user.username ?? user.id)")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(FriendStatusColor.color(state: user.state, status: user.status))
                                    .frame(width: 7, height: 7)
                                Text(FriendStatusColor.label(state: user.state, status: user.status))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Button {
                        HapticManager.light()
                        appState.showLoginSheet = true
                    } label: {
                        Label("登录 VRChat", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }

            // ── My Stats ──
            if appState.isLoggedIn {
                Section("我的数据") {
                    LabeledContent("好友数", value: "\(appState.friends.count)")
                    LabeledContent("在线好友", value: "\(appState.onlineFriends.count)")
                    LabeledContent("未读通知", value: "\(appState.unreadNotificationCount)")
                    LabeledContent("收藏好友", value: "\(appState.favoriteFriends.count)")
                }
            }

            // ── Favorites ──
            if appState.isLoggedIn && !appState.favoriteFriends.isEmpty {
                Section("收藏好友") {
                    ForEach(appState.favoriteFriends.prefix(5)) { friend in
                        HStack {
                            AvatarImage(url: friend.userIcon, size: 30)
                            Text(friend.displayName ?? friend.username ?? "?")
                                .font(.subheadline)
                        }
                    }
                    if appState.favoriteFriends.count > 5 {
                        Text("...还有 \(appState.favoriteFriends.count - 5) 位")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // ── Actions ──
            if appState.isLoggedIn {
                Section {
                    Button(role: .destructive) {
                        HapticManager.heavy()
                        Task { await appState.logout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }

            // ── About ──
            Section {
                LabeledContent("版本", value: "1.0.0")
                LabeledContent("项目", value: "VRCX-Lite")
                LabeledContent("平台", value: "iOS / iPadOS")
            } header: {
                Text("关于")
            }
        }
        .navigationTitle("我的")
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
