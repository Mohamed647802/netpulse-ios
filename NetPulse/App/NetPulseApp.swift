import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // فرض الاتجاه العربي من اليمين إلى اليسار على كامل مكونات النظام والواجهة
        UIView.appearance().semanticContentAttribute = .forceRightToLeft
        UINavigationBar.appearance().semanticContentAttribute = .forceRightToLeft

        NotificationService.shared.configure()
        BackgroundTaskService.shared.registerBackgroundTasks()
        BackgroundTaskService.shared.scheduleBackgroundTasks()
        return true
    }
}

@MainActor
@main
struct NetPulseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var monitor = NetworkMonitorService.shared
    @StateObject private var alarmManager = CustomUsageAlarmManager.shared
    @StateObject private var routerService = RouterUPnPService.shared
    @StateObject private var quotaManager = QuotaManager.shared
    @StateObject private var spikeManager = SpikeAlertManager.shared
    @StateObject private var guardManager = DualConnectionGuardManager.shared
    @StateObject private var permissions = PermissionsManager.shared

    @State private var appearanceMode: AppAppearanceMode = AppGroupStorage.loadAppearanceMode()

    private var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            MainContainerView(appearanceMode: $appearanceMode)
                .environmentObject(monitor)
                .environmentObject(alarmManager)
                .environmentObject(routerService)
                .environmentObject(quotaManager)
                .environmentObject(spikeManager)
                .environmentObject(guardManager)
                .environmentObject(permissions)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, ByteFormatterUtil.arabicLocale)
                .preferredColorScheme(resolvedColorScheme)
                .onChange(of: appearanceMode) { newMode in
                    AppGroupStorage.saveAppearanceMode(newMode)
                }
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        monitor.startForegroundTimer()
                        monitor.pollOnce(forceWidgetReload: true)
                        Task { await permissions.refreshAllStatuses() }
                    case .background:
                        monitor.stopForegroundTimer()
                        BackgroundTaskService.shared.scheduleBackgroundTasks()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
