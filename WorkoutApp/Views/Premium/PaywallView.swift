import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProduct: Product?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.89, green: 0.96, blue: 0.90))
                                .frame(width: 110, height: 110)
                            Image(systemName: "crown.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Color(red: 0.12, green: 0.44, blue: 0.26))
                        }

                        Text("Workout App Premium")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)

                        Text("Cloud-basierte Trainingshistorie, tiefere Analysen und ein sauberer Premium-Flow fuer den App Store.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 12) {
                        PremiumFeatureLine(icon: "externaldrive.badge.icloud", text: "Cloud-Sync fuer dein Workout-Profil und Fortschrittskennzahlen")
                        PremiumFeatureLine(icon: "chart.xyaxis.line", text: "Premium Analytics fuer Charts und persoenliche Rekorde")
                        PremiumFeatureLine(icon: "sparkles", text: "Verkaufsfaehiger Abo-Flow mit Restore, Status und rechtlichen Links")
                    }

                    VStack(spacing: 12) {
                        if !storeManager.products.isEmpty {
                            if let monthlyProduct = storeManager.monthlyProduct {
                                ProductCard(
                                    title: "\(monthlyProduct.displayPrice) / Monat",
                                    badge: nil,
                                    isSelected: selectedProduct?.id == monthlyProduct.id
                                ) {
                                    selectedProduct = monthlyProduct
                                }
                            }

                            if let yearlyProduct = storeManager.yearlyProduct {
                                ProductCard(
                                    title: "\(yearlyProduct.displayPrice) / Jahr",
                                    badge: storeManager.yearlySavingsPercent > 0 ? "\(storeManager.yearlySavingsPercent)% sparen" : nil,
                                    isSelected: selectedProduct?.id == yearlyProduct.id
                                ) {
                                    selectedProduct = yearlyProduct
                                }
                            }
                        } else {
                            ProductCard(title: "4,99 EUR / Monat", badge: nil, isSelected: true) { }
                            ProductCard(title: "29,99 EUR / Jahr", badge: "Bester Preis", isSelected: false) { }
                        }
                    }

                    Button {
                        guard let selectedProduct else { return }
                        Task {
                            await storeManager.purchase(selectedProduct)
                        }
                    } label: {
                        HStack {
                            if storeManager.purchaseInProgress {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(storeManager.purchaseInProgress ? "Wird verarbeitet ..." : "Premium freischalten")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundStyle(.white)
                        .background(Color(red: 0.12, green: 0.44, blue: 0.26), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedProduct == nil && !storeManager.products.isEmpty)

                    Button("Kaeufe wiederherstellen") {
                        Task {
                            await storeManager.restorePurchases()
                        }
                    }
                    .font(.subheadline.weight(.semibold))

                    VStack(spacing: 8) {
                        Text("Das Abo verlaengert sich automatisch, sofern es nicht rechtzeitig in deinem Apple-ID-Account gekuendigt wird.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 16) {
                            Link("Datenschutz", destination: AppConfig.privacyURL)
                            Link("Nutzungsbedingungen", destination: AppConfig.termsURL)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedProduct = storeManager.yearlyProduct ?? storeManager.monthlyProduct
            }
            .onChange(of: storeManager.showSuccess) { _, success in
                if success {
                    dismiss()
                }
            }
        }
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

private struct PremiumFeatureLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(red: 0.12, green: 0.44, blue: 0.26))
                .frame(width: 34, height: 34)
                .background(Color(red: 0.89, green: 0.96, blue: 0.90), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(text)
                .font(.body)
            Spacer()
        }
    }
}

private struct ProductCard: View {
    let title: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.12, green: 0.44, blue: 0.26), in: Capsule())
                        .foregroundStyle(.white)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color(red: 0.12, green: 0.44, blue: 0.26) : .secondary)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? Color(red: 0.12, green: 0.44, blue: 0.26) : Color.black.opacity(0.06), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

