import Foundation
import UIKit
import UserNotifications
import CoreLocation
import Network

enum PermissionState: String {
    case granted = "granted"
    case partial = "partial"
    case denied = "denied"
    case notDetermined = "not_determined"

    var arabicLabel: String {
        switch self {
        case .granted: return "مفعّلة بالكامل"
        case .partial: return "مفعّلة أثناء الاستخدام"
        case .denied: return "غير مفعّلة (مرفوضة)"
        case .notDetermined: return "بانتظار التفعيل"
        }
    }
}

@MainActor
final class PermissionsManager: NSObject, ObservableObject {
    static let shared = PermissionsManager()

    @Published var notificationsState: PermissionState = .notDetermined
    @Published var localNetworkState: PermissionState = .notDetermined
    @Published var locationState: PermissionState = .notDetermined
    @Published var backgroundRefreshState: PermissionState = .notDetermined
    @Published var isCheckingLocalNetwork: Bool = false

    private let locationManager = CLLocationManager()
    private var nwBrowser: NWBrowser?
    private var onLocationNetworkWakeup: (@MainActor () -> Void)?

    private let localNetGrantedCacheKey = "netpulse.permission.localnetwork.state"

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers

        if let cached = AppGroupStorage.userDefaults.string(forKey: localNetGrantedCacheKey),
           let parsed = PermissionState(rawValue: cached) {
            localNetworkState = parsed
        }

        Task {
            await refreshAllStatuses()
        }
    }

    func setLocationWakeupHandler(_ handler: @escaping @MainActor () -> Void) {
        self.onLocationNetworkWakeup = handler
    }

    var allEssentialPermissionsGranted: Bool {
        notificationsState == .granted && backgroundRefreshState == .granted
    }

    var missingPermissionsCount: Int {
        var count = 0
        if notificationsState != .granted { count += 1 }
        if localNetworkState != .granted { count += 1 }
        if backgroundRefreshState != .granted { count += 1 }
        if locationState == .notDetermined || locationState == .denied { count += 1 }
        return count
    }

    // MARK: - تحديث جميع الحالات
    func refreshAllStatuses() async {
        await refreshNotificationStatus()
        refreshLocationStatus()
        refreshBackgroundStatus()
    }

    // MARK: - 1. صلاحية الإشعارات الفورية والعاجلة
    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral:
            notificationsState = .granted
        case .provisional:
            notificationsState = .partial
        case .denied:
            notificationsState = .denied
        case .notDetermined:
            notificationsState = .notDetermined
        @unknown default:
            notificationsState = .notDetermined
        }
    }

    func requestNotificationsPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await refreshNotificationStatus()
            return granted
        } catch {
            await refreshNotificationStatus()
            return false
        }
    }

    // MARK: - 2. صلاحية الشبكة المحلية والاتصال بالراوتر (Bonjour + UDP UPnP)
    func requestAndCheckLocalNetworkPermission() {
        isCheckingLocalNetwork = true
        nwBrowser?.cancel()

        let params = NWParameters()
        params.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_upnp._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: params)
        self.nwBrowser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.localNetworkState = .granted
                    AppGroupStorage.userDefaults.set(PermissionState.granted.rawValue, forKey: self.localNetGrantedCacheKey)
                    self.isCheckingLocalNetwork = false
                    browser.cancel()
                case .waiting(let error):
                    let desc = String(describing: error)
                    if desc.contains("-65570") || desc.lowercased().contains("policydenied") {
                        self.localNetworkState = .denied
                        AppGroupStorage.userDefaults.set(PermissionState.denied.rawValue, forKey: self.localNetGrantedCacheKey)
                    }
                    self.isCheckingLocalNetwork = false
                    browser.cancel()
                case .failed:
                    self.isCheckingLocalNetwork = false
                    browser.cancel()
                default:
                    break
                }
            }
        }

        browser.start(queue: DispatchQueue.global(qos: .userInitiated))

        // إرسال نبضة SSDP محلية بالتوازي لتحفيز نافذة إذن الشبكة المحلية فوراً على iOS
        triggerLocalUDPProbe()

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self else { return }
            if self.isCheckingLocalNetwork {
                self.isCheckingLocalNetwork = false
                self.nwBrowser?.cancel()
            }
        }
    }

    private func triggerLocalUDPProbe() {
        let host = NWEndpoint.Host("239.255.255.250")
        let port = NWEndpoint.Port(rawValue: 1900)!
        let conn = NWConnection(host: host, port: port, using: .udp)
        conn.start(queue: DispatchQueue.global(qos: .utility))
        let payload = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 1\r
        ST: urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1\r
        \r

        """
        conn.send(content: payload.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    // MARK: - 3. صلاحية الموقع لرصد انتقالات الواي فاي والداتا بالخلفية
    func refreshLocationStatus() {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways:
            locationState = .granted
            startSignificantLocationMonitoringIfAuthorized()
        case .authorizedWhenInUse:
            locationState = .partial
            startSignificantLocationMonitoringIfAuthorized()
        case .denied, .restricted:
            locationState = .denied
        case .notDetermined:
            locationState = .notDetermined
        @unknown default:
            locationState = .notDetermined
        }
    }

    func requestLocationPermission(always: Bool = false) {
        let current = locationManager.authorizationStatus
        if current == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if current == .authorizedWhenInUse && always {
            locationManager.requestAlwaysAuthorization()
        } else if always {
            locationManager.requestAlwaysAuthorization()
        }
    }

    private func startSignificantLocationMonitoringIfAuthorized() {
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    // MARK: - 4. حالة التحديث في الخلفية (Background App Refresh)
    func refreshBackgroundStatus() {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            backgroundRefreshState = .granted
        case .denied, .restricted:
            backgroundRefreshState = .denied
        @unknown default:
            backgroundRefreshState = .notDetermined
        }
    }

    // MARK: - طلب جميع الصلاحيات الأساسية بخطوة واحدة
    func requestAllPermissions() async {
        _ = await requestNotificationsPermission()
        requestAndCheckLocalNetworkPermission()
        requestLocationPermission(always: false)
        refreshBackgroundStatus()
    }

    // MARK: - فتح شاشة إعدادات التطبيق في النظام
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension PermissionsManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refreshLocationStatus()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.onLocationNetworkWakeup?()
        }
    }
}
