import SwiftUI

enum AppTheme {
    static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.05, green: 0.52, blue: 0.95), Color(red: 0.00, green: 0.72, blue: 0.68)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let alarmGradient = LinearGradient(
        colors: [Color(red: 0.96, green: 0.42, blue: 0.15), Color(red: 0.90, green: 0.18, blue: 0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let routerGradient = LinearGradient(
        colors: [Color(red: 0.36, green: 0.28, blue: 0.92), Color(red: 0.14, green: 0.58, blue: 0.96)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let wifiAccent = Color(red: 0.04, green: 0.58, blue: 0.96)
    static let cellularAccent = Color(red: 0.08, green: 0.72, blue: 0.48)
    static let downloadColor = Color(red: 0.05, green: 0.65, blue: 0.52)
    static let uploadColor = Color(red: 0.45, green: 0.36, blue: 0.95)
    static let warningColor = Color(red: 0.95, green: 0.58, blue: 0.08)
    static let dangerColor = Color(red: 0.90, green: 0.20, blue: 0.26)

    static func screenBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.07, blue: 0.11)
            : Color(red: 0.95, green: 0.96, blue: 0.98)
    }

    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.10, green: 0.13, blue: 0.19)
            : Color.white
    }

    static func secondaryCardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.17, blue: 0.24)
            : Color(red: 0.93, green: 0.95, blue: 0.98)
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }
}

struct ModernCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var paddingAmount: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(paddingAmount)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppTheme.cardBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.cardBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .clear : Color.black.opacity(0.04),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

extension View {
    func modernCard(padding: CGFloat = 16) -> some View {
        modifier(ModernCardModifier(paddingAmount: padding))
    }
}

// MARK: - ترويسة عصرية لكل قسم مستقل
struct SectionHeroBanner: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var gradient: LinearGradient = AppTheme.primaryGradient
    var badgeText: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 52, height: 52)
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    if let badgeText {
                        Text(badgeText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.25)))
                    }
                }

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(gradient)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
    }
}

// MARK: - عداد دائري بصري متحرك (Circular Gauge)
struct CircularUsageGaugeView: View {
    let progress: Double // 0.0 ... 1.0+
    let warningRatio: Double // مثال 0.80
    let centerPrimaryText: String
    let centerSecondaryText: String
    let statusLabel: String
    var lineWidth: CGFloat = 18

    private var clampedTrim: CGFloat {
        CGFloat(min(max(progress, 0.0), 1.0))
    }

    private var activeGradient: AngularGradient {
        if progress >= 1.0 {
            return AngularGradient(
                colors: [AppTheme.dangerColor, Color.pink, AppTheme.dangerColor],
                center: .center
            )
        } else if progress >= warningRatio {
            return AngularGradient(
                colors: [AppTheme.warningColor, Color.orange, AppTheme.dangerColor],
                center: .center
            )
        } else {
            return AngularGradient(
                colors: [AppTheme.wifiAccent, AppTheme.downloadColor, AppTheme.wifiAccent],
                center: .center
            )
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: lineWidth)

            // علامة نسبة التحذير على القوس
            Circle()
                .trim(from: max(0, CGFloat(warningRatio) - 0.006), to: min(1, CGFloat(warningRatio) + 0.006))
                .stroke(AppTheme.warningColor, style: StrokeStyle(lineWidth: lineWidth + 6, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0, to: clampedTrim)
                .stroke(activeGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: clampedTrim)

            VStack(spacing: 6) {
                Text(statusLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(centerPrimaryText)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(progress >= 1.0 ? AppTheme.dangerColor : .primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(centerSecondaryText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(progress >= warningRatio ? AppTheme.warningColor : AppTheme.downloadColor)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - بطاقة مصغرة للتحميل والرفع
struct DirectionMetricBadge: View {
    let label: String
    let valueText: String
    let isDownload: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isDownload ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isDownload ? AppTheme.downloadColor : AppTheme.uploadColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(valueText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((isDownload ? AppTheme.downloadColor : AppTheme.uploadColor).opacity(0.10))
        )
    }
}

// MARK: - بطاقة الحالة الفارغة المتوافقة مع iOS 16+
struct EmptyStateCardView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)

            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .modernCard()
    }
}
