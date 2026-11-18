import SwiftUI

enum AppTabSection: String, CaseIterable, Identifiable {
    case counterAndHistory
    case customAlarm
    case routerUsage
    case quotaManager
    case spikeAlert
    case dualGuard
    case permissions
    case backupSettings

    var id: String { rawValue }

    var shortArabicTitle: String {
        switch self {
        case .counterAndHistory: return "العداد والسجل"
        case .customAlarm: return "منبّه الكمية"
        case .routerUsage: return "الراوتر"
        case .quotaManager: return "الباقات"
        case .spikeAlert: return "السحب المفاجئ"
        case .dualGuard: return "حارس الداتا"
        case .permissions: return "الصلاحيات"
        case .backupSettings: return "النسخ الاحتياطي"
        }
    }

    var iconName: String {
        switch self {
        case .counterAndHistory: return "chart.xyaxis.line"
        case .customAlarm: return "bell.and.waves.left.and.right.fill"
        case .routerUsage: return "wifi.router.fill"
        case .quotaManager: return "chart.bar.doc.horizontal.fill"
        case .spikeAlert: return "bolt.trianglebadge.exclamationmark.fill"
        case .dualGuard: return "shield.lefthalf.filled.badge.checkmark"
        case .permissions: return "checkmark.shield.fill"
        case .backupSettings: return "externaldrive.fill.badge.checkmark"
        }
    }
}

struct MainContainerView: View {
    @Binding var appearanceMode: AppAppearanceMode

    @EnvironmentObject var monitor: NetworkMonitorService
    @EnvironmentObject var alarmManager: CustomUsageAlarmManager
    @EnvironmentObject var routerService: RouterUPnPService
    @EnvironmentObject var quotaManager: QuotaManager
    @EnvironmentObject var spikeManager: SpikeAlertManager
    @EnvironmentObject var guardManager: DualConnectionGuardManager
    @EnvironmentObject var permissions: PermissionsManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab: AppTabSection = .counterAndHistory

    var body: some View {
        VStack(spacing: 0) {
            // عرض القسم المستقل المختار
            ZStack {
                switch selectedTab {
                case .counterAndHistory:
                    CounterAndHistoryView()
                case .customAlarm:
                    CustomUsageAlarmView()
                case .routerUsage:
                    RouterUsageView()
                case .quotaManager:
                    QuotaManagerView()
                case .spikeAlert:
                    SpikeAlertView()
                case .dualGuard:
                    DualConnectionGuardView()
                case .permissions:
                    PermissionsView()
                case .backupSettings:
                    BackupAndSettingsView(appearanceMode: $appearanceMode)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // شريط التبويبات السفلي العصري المستقل للأقسام الثمانية
            modernBottomTabBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var modernBottomTabBar: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.4)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AppTabSection.allCases) { tab in
                            tabBarButton(for: tab) {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    selectedTab = tab
                                    proxy.scrollTo(tab.id, anchor: .center)
                                }
                            }
                            .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                }
            }
        }
        .background(AppTheme.cardBackground(colorScheme).ignoresSafeArea(edges: .bottom))
    }

    private func tabBarButton(for tab: AppTabSection, action: @escaping () -> Void) -> some View {
        let isSelected = (selectedTab == tab)
        let indicatorColor = statusDotColor(for: tab)

        return Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    Image(systemName: tab.iconName)
                        .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .frame(width: 38, height: 30)
                        .background(
                            Capsule()
                                .fill(isSelected ? AppTheme.wifiAccent : Color.clear)
                        )

                    if let dotColor = indicatorColor {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(AppTheme.cardBackground(colorScheme), lineWidth: 1.5))
                            .offset(x: 2, y: 1)
                    }
                }

                Text(tab.shortArabicTitle)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? AppTheme.wifiAccent : .secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 68)
            .padding(.vertical, 2)
        }
    }

    private func statusDotColor(for tab: AppTabSection) -> Color? {
        switch tab {
        case .customAlarm:
            if alarmManager.state.isRunning && !alarmManager.state.isPaused {
                return alarmManager.state.progressRatio >= 1.0 ? AppTheme.dangerColor : AppTheme.downloadColor
            }
            return nil
        case .dualGuard:
            return guardManager.isDualActiveNow ? AppTheme.dangerColor : nil
        case .permissions:
            return !permissions.allEssentialPermissionsGranted ? AppTheme.warningColor : nil
        case .spikeAlert:
            return !spikeManager.incidents.isEmpty ? AppTheme.warningColor : nil
        default:
            return nil
        }
    }
}
