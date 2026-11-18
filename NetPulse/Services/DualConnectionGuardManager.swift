import Foundation
import Network

@MainActor
final class DualConnectionGuardManager: ObservableObject {
    static let shared = DualConnectionGuardManager()

    @Published var settings: DualConnectionGuardSettings
    @Published var events: [DualGuardEventRecord] = []

    // الحالة الحية للمراقبَين المنفصلين + واجهة pdp_ip0
    @Published var isWifiPathSatisfied: Bool = false
    @Published var isCellularPathSatisfied: Bool = false
    @Published var hasPdp0IPAddress: Bool = false
    @Published var pdp0IPString: String? = nil
    @Published var isDualActiveNow: Bool = false
    @Published var currentSessionLeakedBytes: Int64 = 0

    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let cellularMonitor = NWPathMonitor(requiredInterfaceType: .cellular)
    private let monitorQueue = DispatchQueue(label: "com.netpulse.dualguard.monitors", qos: .utility)

    private var wasDualActivePreviously: Bool = false
    private var lastDualNotificationTime: TimeInterval = 0
    private var lastWifiAssistMilestoneBytes: Int64 = 0
    private var lastEvaluatedWifiId: String = ""
    private var lastEvaluatedWifiName: String = "واي فاي"

    private init() {
        self.settings = AppGroupStorage.loadDualGuardSettings()
        self.events = DatabaseManager.shared.fetchDualGuardEvents()
        startDedicatedMonitors()
    }

    private func startDedicatedMonitors() {
        wifiMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = (path.status == .satisfied)
            Task { @MainActor in
                guard let self else { return }
                self.isWifiPathSatisfied = satisfied
                if !satisfied {
                    self.resetWifiSessionLeakTracking()
                }
                self.evaluateDualStatus(wifiId: self.lastEvaluatedWifiId, wifiName: self.lastEvaluatedWifiName)
            }
        }

        cellularMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = (path.status == .satisfied)
            Task { @MainActor in
                guard let self else { return }
                self.isCellularPathSatisfied = satisfied
                self.evaluateDualStatus(wifiId: self.lastEvaluatedWifiId, wifiName: self.lastEvaluatedWifiName)
            }
        }

        wifiMonitor.start(queue: monitorQueue)
        cellularMonitor.start(queue: monitorQueue)
    }

    func updateSettings(_ newSettings: DualConnectionGuardSettings) {
        self.settings = newSettings
        AppGroupStorage.saveDualGuardSettings(newSettings)
        evaluateDualStatus(wifiId: lastEvaluatedWifiId, wifiName: lastEvaluatedWifiName)
    }

    func reloadEvents() {
        self.events = DatabaseManager.shared.fetchDualGuardEvents()
    }

    func clearEvents() {
        DatabaseManager.shared.clearDualGuardEvents()
        self.events = []
    }

    func resetSessionCounterManually() {
        currentSessionLeakedBytes = 0
        lastWifiAssistMilestoneBytes = 0
    }

    /// يُستدعى دورياً من محرك القياس الرئيسي لتزويد قراءة getifaddrs() على pdp_ip0 والدلتا الخلوية
    func processSystemReading(
        reading: SystemInterfaceReading,
        wifiNetworkId: String,
        wifiNetworkName: String,
        cellularDeltaWhilePolling: Int64
    ) {
        self.hasPdp0IPAddress = reading.hasActiveCellularIP
        self.pdp0IPString = reading.cellularIPAddress
        self.lastEvaluatedWifiId = wifiNetworkId
        self.lastEvaluatedWifiName = wifiNetworkName

        let wifiActive = isWifiPathSatisfied || reading.isWifiInterfaceUp
        if !wifiActive {
            resetWifiSessionLeakTracking()
        }

        evaluateDualStatus(wifiId: wifiNetworkId, wifiName: wifiNetworkName, readingWifiUp: reading.isWifiInterfaceUp)

        // رصد سحب Wi-Fi Assist الخفي على واجهات pdp_ip أثناء اتصال الواي فاي الفعلي
        if wifiActive && cellularDeltaWhilePolling > 0 {
            currentSessionLeakedBytes += cellularDeltaWhilePolling
            checkWifiAssistLeakAlert(wifiId: wifiNetworkId, wifiName: wifiNetworkName)
        }
    }

    private func evaluateDualStatus(wifiId: String, wifiName: String, readingWifiUp: Bool = false) {
        let wifiConnected = isWifiPathSatisfied || readingWifiUp
        let cellularOpen = isCellularPathSatisfied || hasPdp0IPAddress
        let dualNow = wifiConnected && cellularOpen
        self.isDualActiveNow = dualNow

        guard dualNow else {
            wasDualActivePreviously = false
            return
        }

        guard settings.isDualAlertEnabled, shouldMonitorWifiNetwork(networkId: wifiId) else {
            wasDualActivePreviously = true
            return
        }

        let now = Date().timeIntervalSince1970
        let cooldownSec = Double(max(1, settings.reminderCooldownMinutes) * 60)

        // إطلاق الإشعار فوراً لحظة اتصال الواي فاي مع بقاء الداتا مفتوحة، أو بعد انتهاء فترة التذكير
        if !wasDualActivePreviously || (now - lastDualNotificationTime) >= cooldownSec {
            // منع التكرار المزعج إذا كان المستخدم قد تلقى تنبيهاً قبل ثوانٍ معدودة بسبب تذبذب الإشارة
            if (now - lastDualNotificationTime) >= 45 {
                lastDualNotificationTime = now
                NotificationService.shared.notifyDualWifiAndCellularActive(wifiName: wifiName)

                let record = DualGuardEventRecord(
                    id: UUID().uuidString,
                    timestamp: now,
                    wifiNetworkName: wifiName,
                    eventType: .dualActive,
                    leakedBytes: 0
                )
                DatabaseManager.shared.insertDualGuardEvent(record)
                events.insert(record, at: 0)
            }
        }

        wasDualActivePreviously = true
    }

    private func checkWifiAssistLeakAlert(wifiId: String, wifiName: String) {
        guard settings.isWifiAssistGuardEnabled, shouldMonitorWifiNetwork(networkId: wifiId) else {
            return
        }

        let stepBytes = Int64(max(0.1, settings.wifiAssistThresholdMB) * 1024.0 * 1024.0)
        guard stepBytes > 0 else { return }

        if currentSessionLeakedBytes - lastWifiAssistMilestoneBytes >= stepBytes {
            lastWifiAssistMilestoneBytes = currentSessionLeakedBytes
            NotificationService.shared.notifyWifiAssistLeak(
                wifiName: wifiName,
                leakedBytes: currentSessionLeakedBytes
            )

            let record = DualGuardEventRecord(
                id: UUID().uuidString,
                timestamp: Date().timeIntervalSince1970,
                wifiNetworkName: wifiName,
                eventType: .wifiAssistLeak,
                leakedBytes: currentSessionLeakedBytes
            )
            DatabaseManager.shared.insertDualGuardEvent(record)
            events.insert(record, at: 0)
        }
    }

    private func shouldMonitorWifiNetwork(networkId: String) -> Bool {
        switch settings.ruleMode {
        case .allNetworks:
            return true
        case .selectedOnly:
            guard !networkId.isEmpty else { return false }
            return settings.targetNetworkIds.contains(networkId)
        case .excludeSelected:
            guard !networkId.isEmpty else { return true }
            return !settings.targetNetworkIds.contains(networkId)
        }
    }

    private func resetWifiSessionLeakTracking() {
        wasDualActivePreviously = false
        currentSessionLeakedBytes = 0
        lastWifiAssistMilestoneBytes = 0
    }
}
