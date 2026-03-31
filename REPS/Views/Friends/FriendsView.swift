import SwiftUI

struct FriendsView: View {
    @StateObject private var viewModel = FriendsViewModel()
    @EnvironmentObject private var sessionViewModel: AppSessionViewModel
    @EnvironmentObject private var localization: LocalizationService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingPalette.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        inviteCard

                        if let errorMessage = viewModel.errorMessage {
                            FriendsStatusBanner(
                                icon: "exclamationmark.triangle.fill",
                                title: localization.localized("common.error"),
                                message: errorMessage,
                                tint: .red
                            )
                        }

                        if let successMessage = viewModel.successMessage {
                            FriendsStatusBanner(
                                icon: "checkmark.circle.fill",
                                title: localization.localized("common.success"),
                                message: successMessage,
                                tint: OnboardingPalette.accent
                            )
                        }

                        if !viewModel.payload.incomingRequests.isEmpty || !viewModel.payload.outgoingRequests.isEmpty {
                            requestsSection
                        }

                        leaderboardSection

                        if !viewModel.payload.friends.isEmpty {
                            friendsSection
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(localization.localized("friends.title"))
            .task {
                await refreshFriendsState()
                await handlePendingInvite()
            }
            .task(id: sessionViewModel.pendingInviteCode) {
                await handlePendingInvite()
            }
            .refreshable {
                await refreshFriendsState()
            }
        }
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localization.localized("friends.invite.title"))
                .font(.title3.weight(.bold))
                .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))

            Text(localization.localized("friends.invite.subtitle"))
                .font(.subheadline)
                .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))

            HStack(spacing: 12) {
                TextField(localization.localized("friends.invite.placeholder"), text: $viewModel.inviteCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                    .background(OnboardingPalette.elevatedSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    Task {
                        await viewModel.sendInviteRequest()
                    }
                } label: {
                    Text(localization.localized("friends.invite.add"))
                        .font(.headline)
                        .frame(height: 52)
                        .padding(.horizontal, 18)
                        .background(OnboardingPalette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .disabled(viewModel.isProcessing)
            }

            if !viewModel.payload.friendCode.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.localized("friends.invite.your_code"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))
                        Text(viewModel.payload.friendCode)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                    }

                    Spacer()

                    if let inviteURL = URL(string: viewModel.payload.inviteLink), !viewModel.payload.inviteLink.isEmpty {
                        ShareLink(item: inviteURL) {
                            Label(localization.localized("friends.invite.share"), systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                                .background(OnboardingPalette.surface(for: colorScheme), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(OnboardingPalette.elevatedSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(18)
        .background(OnboardingPalette.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(OnboardingPalette.border(for: colorScheme), lineWidth: 1)
        )
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.localized("friends.requests.title"))
                .font(.title3.weight(.bold))
                .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))

            ForEach(viewModel.payload.incomingRequests) { request in
                requestRow(request, isIncoming: true)
            }

            ForEach(viewModel.payload.outgoingRequests) { request in
                requestRow(request, isIncoming: false)
            }
        }
    }

    private func requestRow(_ request: WorkoutFriendRequestSummary, isIncoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                friendBadge(for: request.user)
                Spacer()
                Text(request.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))
            }

            HStack(spacing: 12) {
                if isIncoming {
                    Button {
                        Task {
                            await viewModel.acceptRequest(id: request.id)
                        }
                    } label: {
                        Text(localization.localized("friends.requests.accept"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(OnboardingPalette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text(localization.localized("friends.requests.pending"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))
                        .background(OnboardingPalette.elevatedSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(OnboardingPalette.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(OnboardingPalette.border(for: colorScheme), lineWidth: 1)
        )
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localization.localized("friends.leaderboard.title"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                }
            }

            if viewModel.leaderboard.isEmpty {
                ContentUnavailableView(
                    localization.localized("friends.empty.title"),
                    systemImage: "person.3.sequence.fill",
                    description: Text(localization.localized("friends.empty.subtitle"))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(viewModel.leaderboard, id: \.user.id) { entry in
                    HStack(spacing: 14) {
                        Text("#\(entry.rank)")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                            .frame(width: 40, alignment: .leading)

                        friendBadge(for: entry.user)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(localization.localized("friends.metric.sessions_minutes", entry.user.weeklySessions, entry.user.weeklyMinutes))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                            Text(localization.localized("friends.metric.streak_days", entry.user.currentStreak))
                                .font(.caption)
                                .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))
                        }
                    }
                    .padding(16)
                    .background(
                        entry.isCurrentUser ? OnboardingPalette.accentSoft(for: colorScheme) : OnboardingPalette.surface(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(OnboardingPalette.border(for: colorScheme), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.localized("friends.list.title"))
                .font(.title3.weight(.bold))
                .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))

            ForEach(viewModel.payload.friends) { friend in
                HStack(spacing: 14) {
                    friendBadge(for: friend)
                    Spacer()
                    Button(role: .destructive) {
                        Task {
                            await viewModel.removeFriend(id: friend.id)
                        }
                    } label: {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.title3)
                    }
                }
                .padding(16)
                .background(OnboardingPalette.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(OnboardingPalette.border(for: colorScheme), lineWidth: 1)
                )
            }
        }
    }

    private func friendBadge(for friend: WorkoutFriendSummary) -> some View {
        HStack(spacing: 12) {
            Text(friend.initials)
                .font(.headline.weight(.bold))
                .frame(width: 46, height: 46)
                .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                .background(OnboardingPalette.accentSoft(for: colorScheme), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                Text(friendSummary(friend))
                    .font(.caption)
                    .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))
                    .lineLimit(2)
            }
        }
    }

    private func friendSummary(_ friend: WorkoutFriendSummary) -> String {
        if let lastWorkoutAt = friend.lastWorkoutAt, !friend.lastWorkoutTemplate.isEmpty {
            return "\(friend.lastWorkoutTemplate) · \(lastWorkoutAt.formatted(.relative(presentation: .named)))"
        }
        if !friend.lastWorkoutTemplate.isEmpty {
            return friend.lastWorkoutTemplate
        }
        return localization.localized("friends.summary.no_workout")
    }

    private func handlePendingInvite() async {
        guard let inviteCode = sessionViewModel.consumePendingInviteCode() else { return }
        await viewModel.sendInviteRequest(using: inviteCode)
    }

    private func refreshFriendsState() async {
        await sessionViewModel.syncSnapshot()
        await viewModel.load()
    }
}

private struct FriendsStatusBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(OnboardingPalette.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(OnboardingPalette.border(for: colorScheme), lineWidth: 1)
        )
    }
}
