import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var storeManager: StoreManager
    @EnvironmentObject private var localization: LocalizationService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let planSummary: OnboardingPlanSummary?
    let allowsSkip: Bool
    let showsCloseButton: Bool
    let onSkip: (() -> Void)?
    let onPurchaseSuccess: (() -> Void)?

    @State private var selectedTier: PremiumTier = .yearly
    @State private var handledCompletion = false

    init(
        planSummary: OnboardingPlanSummary? = nil,
        allowsSkip: Bool = false,
        showsCloseButton: Bool = true,
        onSkip: (() -> Void)? = nil,
        onPurchaseSuccess: (() -> Void)? = nil
    ) {
        self.planSummary = planSummary
        self.allowsSkip = allowsSkip
        self.showsCloseButton = showsCloseButton
        self.onSkip = onSkip
        self.onPurchaseSuccess = onPurchaseSuccess
    }

    private var personalizedPlanLine: String? {
        guard let planSummary else { return nil }
        return localization.localized(
            "plan.ready.plan.line",
            planSummary.trainingDaysPerWeek,
            localization.localized(planSummary.planStyle.titleKey)
        )
    }

    private var headerTitle: String {
        guard let planSummary else { return localization.localized("paywall.header.default") }
        return localization.localized(
            "paywall.header.plan",
            localization.localized(planSummary.goalFocus.planTitleKey)
        )
    }

    private var headerSubtitle: String {
        if let personalizedPlanLine {
            return localization.localized("paywall.subtitle.plan", personalizedPlanLine)
        }
        return localization.localized("paywall.subtitle.default")
    }

    private var offers: [PaywallOfferCardModel] {
        [
            yearlyOffer,
            monthlyOffer,
            lifetimeOffer,
        ]
    }

    private var selectedProduct: Product? {
        offers.first(where: { $0.tier == selectedTier })?.product
    }

    private var yearlyOffer: PaywallOfferCardModel {
        let product = storeManager.yearlyProduct
        let price = product?.displayPrice
            ?? AppConfig.fallbackDisplayPrice(for: AppConfig.premiumYearlyProductID, locale: localization.locale)
            ?? "--"
        let monthlyEquivalent = product.map(storeManager.formattedMonthlyEquivalent(for:))
            ?? fallbackMonthlyEquivalent()
        let detail: String? = storeManager.yearlySavingsPercent > 0
            ? localization.localized("paywall.plan.yearly.save", storeManager.yearlySavingsPercent)
            : nil

        return PaywallOfferCardModel(
            tier: .yearly,
            product: product,
            title: localization.localized("paywall.plan.yearly.title"),
            price: price,
            subtitle: monthlyEquivalent.map {
                localization.localized("paywall.plan.yearly.caption", $0)
            } ?? localization.localized("paywall.plan.yearly.caption.fallback"),
            detail: detail,
            badges: [
                localization.localized("paywall.plan.yearly.badge"),
                localization.localized("paywall.plan.yearly.trial", AppConfig.yearlyTrialDays),
            ],
            isRecommended: true
        )
    }

    private var monthlyOffer: PaywallOfferCardModel {
        let product = storeManager.monthlyProduct
        let price = product?.displayPrice
            ?? AppConfig.fallbackDisplayPrice(for: AppConfig.premiumMonthlyProductID, locale: localization.locale)
            ?? "--"

        return PaywallOfferCardModel(
            tier: .monthly,
            product: product,
            title: localization.localized("paywall.plan.monthly.title"),
            price: price,
            subtitle: localization.localized("paywall.plan.monthly.caption"),
            detail: nil,
            badges: [],
            isRecommended: false
        )
    }

    private var lifetimeOffer: PaywallOfferCardModel {
        let product = storeManager.lifetimeProduct
        let price = product?.displayPrice
            ?? AppConfig.fallbackDisplayPrice(for: AppConfig.premiumLifetimeProductID, locale: localization.locale)
            ?? "--"

        return PaywallOfferCardModel(
            tier: .lifetime,
            product: product,
            title: localization.localized("paywall.plan.lifetime.title"),
            price: price,
            subtitle: localization.localized("paywall.plan.lifetime.caption"),
            detail: localization.localized("paywall.plan.lifetime.detail"),
            badges: [localization.localized("paywall.plan.lifetime.badge")],
            isRecommended: false
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(OnboardingPalette.accentSoft(for: colorScheme))
                                .frame(width: 110, height: 110)

                            Image(systemName: "crown.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(OnboardingPalette.accent)
                        }

                        Text(headerTitle)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))

                        Text(headerSubtitle)
                            .font(.body)
                            .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 12) {
                        PaywallFeatureLine(
                            icon: "doc.text",
                            text: localization.localized("paywall.feature.templates")
                        )
                        PaywallFeatureLine(
                            icon: "chart.xyaxis.line",
                            text: localization.localized("paywall.feature.analytics")
                        )
                        PaywallFeatureLine(
                            icon: "trophy.fill",
                            text: localization.localized("paywall.feature.prs")
                        )
                        PaywallFeatureLine(
                            icon: "camera.metering.matrix",
                            text: localization.localized("paywall.feature.progress")
                        )
                    }
                    .padding(20)
                    .background(OnboardingPalette.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(OnboardingPalette.border(for: colorScheme), lineWidth: 1)
                    )

                    VStack(spacing: 12) {
                        ForEach(offers) { offer in
                            PaywallProductCard(
                                offer: offer,
                                isSelected: selectedTier == offer.tier,
                                colorScheme: colorScheme
                            ) {
                                selectedTier = offer.tier
                            }
                        }
                    }

                    if let errorMessage = storeManager.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        guard let selectedProduct else { return }
                        Task {
                            await storeManager.purchase(selectedProduct)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if storeManager.purchaseInProgress {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(
                                storeManager.purchaseInProgress
                                    ? localization.localized("paywall.cta.processing")
                                    : localization.localized("paywall.cta.unlock")
                            )
                            .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(.white)
                        .background(OnboardingPalette.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedProduct == nil)

                    Button(localization.localized("profile.premium.restore")) {
                        Task {
                            await storeManager.restorePurchases()
                        }
                    }
                    .font(.subheadline.weight(.semibold))

                    if allowsSkip {
                        Text(localization.localized("paywall.free.access"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button(localization.localized("paywall.skip")) {
                            onSkip?()
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 8) {
                        Text(localization.localized("paywall.disclaimer"))
                            .font(.caption)
                            .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 16) {
                            Link(localization.localized("auth.privacy"), destination: AppConfig.privacyURL)
                            Link(localization.localized("auth.terms"), destination: AppConfig.termsURL)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(24)
            }
            .background(OnboardingPalette.background(for: colorScheme))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(localization.localized("common.close")) {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                selectedTier = .yearly
                handledCompletion = false
                storeManager.consumeSuccess()
            }
            .onChange(of: storeManager.isPremium) { _, isPremium in
                guard isPremium else { return }
                handleSuccessfulUnlock()
            }
            .onChange(of: storeManager.showSuccess) { _, success in
                guard success else { return }
                handleSuccessfulUnlock()
            }
        }
    }

    private func handleSuccessfulUnlock() {
        guard !handledCompletion else { return }
        handledCompletion = true
        storeManager.consumeSuccess()

        if let onPurchaseSuccess {
            onPurchaseSuccess()
        } else {
            dismiss()
        }
    }

    private func fallbackMonthlyEquivalent() -> String? {
        guard let fallback = AppConfig.premiumProductFallbacks[AppConfig.premiumYearlyProductID] else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = localization.locale
        formatter.currencyCode = localization.locale.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        let monthlyEquivalent = fallback.usdPrice / 12
        return formatter.string(from: NSDecimalNumber(decimal: monthlyEquivalent))
    }
}

struct PremiumLockedView: View {
    let title: String
    let subtitle: String
    let ctaTitle: String
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "crown.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color(red: 0.12, green: 0.44, blue: 0.26))

            Text(title)
                .font(.title3.weight(.bold))

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(ctaTitle, action: onTap)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.12, green: 0.44, blue: 0.26))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding()
    }
}

private struct PaywallFeatureLine: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(OnboardingPalette.accent)
                .frame(width: 34, height: 34)
                .background(OnboardingPalette.accentSoft(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(text)
                .font(.body)
                .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))

            Spacer()
        }
    }
}

private struct PaywallProductCard: View {
    let offer: PaywallOfferCardModel
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(offer.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))

                        Text(offer.price)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(OnboardingPalette.primaryText(for: colorScheme))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        ForEach(offer.badges, id: \.self) { badge in
                            Text(badge)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    offer.isRecommended
                                        ? OnboardingPalette.accent
                                        : OnboardingPalette.elevatedSurface(for: colorScheme),
                                    in: Capsule()
                                )
                                .foregroundStyle(offer.isRecommended ? .white : OnboardingPalette.primaryText(for: colorScheme))
                        }
                    }
                }

                Text(offer.subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OnboardingPalette.secondaryText(for: colorScheme))

                if let detail = offer.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OnboardingPalette.accent)
                }

                HStack {
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? OnboardingPalette.accent : OnboardingPalette.secondaryText(for: colorScheme))
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(OnboardingPalette.surface(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                isSelected || offer.isRecommended
                                    ? OnboardingPalette.accent
                                    : OnboardingPalette.border(for: colorScheme),
                                lineWidth: isSelected || offer.isRecommended ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PaywallOfferCardModel: Identifiable {
    let tier: PremiumTier
    let product: Product?
    let title: String
    let price: String
    let subtitle: String
    let detail: String?
    let badges: [String]
    let isRecommended: Bool

    var id: PremiumTier { tier }
}
