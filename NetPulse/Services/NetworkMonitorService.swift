import Foundation
import Network
import WidgetKit

@MainActor
final class NetworkMonitorService: ObservableObject {
    static let shared = NetworkMonitorService()

    // حالة الاتصال الحالية
    @Published var activeConnectionKind: ConnectionKind = .none
    @Published var currentWifiNetworkId: String = "wifi_default"
    @Published var currentWifiNetworkName: String = "شبكة واي فاي"
    @Published var localIPAddress: String = "—"
    @Published var gatewayIPAddress: String = "192.168.1.1"
    @Published var subnetCIDR: String = "—"
    @Published var lastRebootDetectedAt: TimeInterval? = nil

    // السرعة اللحظية الحية
    @Published var liveDownloadSpeedBps: Double = 0
    @Published var liveUploadSpeedBps: Double = 0

    // إحصائيات اليوم السريعة
    @Published var todayCurrentNetworkDownload: Int64 = 0
    @Published var todayCurrentNetworkUpload: Int64 = 0
    @Published var todayAllWifiDownload: Int64 = 0
    @Published var todayAllWifiUpload: Int64 = 0
    @Published var todayCellularDownload: Int64 = 0
    @Published var todayCellularUpload: Int64 = 0

    // جميع السجلات اليومية والشبكات المحفوظة
    @Published var allDailyRecords: [DailyUsageRecord] = []
    @Published var savedNetworkProfiles: [SavedNetworkProfile] = []

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.netpulse.main.pathmonitor", qos: .utility)
    private var pollingTimer: Timer?
    private var lastPollTimestamp: TimeInterval = Date().timeIntervalSince1970
    private var lastWidgetReloadTime: TimeInterval = 0
    private var quotaEvalCounter: Int = 0

    // السماح للمستخدم بتثبيت ملف تعريف شبكة معينة يدوياً عند تشابه عنوان البوابة 192.168.1.1 بين مكانين
    private let manualPinnedProfilePrefix = "netpulse.pinned.subnet."

    static let cellularNetworkId = "cellular_mobile"
    static let cellularDefaultName = "بيانات الهاتف"

    private init() {
        ensureDefaultCellularProfileExists()
        reloadFromDatabase()
        startMonitoring()

        PermissionsManager.shared.setLocationWakeupHandler { [weak self] in
            self?.pollOnce(forceWidgetReload: true)
        }
    }

    private func ensureDefaultCellularProfileExists() {
        if DatabaseManager.shared.fetchNetworkProfile(networkId: Self.cellularNetworkId) == nil {
            let cellProfile = SavedNetworkProfile(
                networkId: Self.cellularNetworkId,
                customName: Self.cellularDefaultName,
                connectionType: .cellular,
                gatewayIP: "",
                subnet: "",
                upnpUDN: "",
                routerModelName: "",
                lastSeenAt: Date().timeIntervalSince1970
            )
            DatabaseManager.shared.upsertNetworkProfile(cellProfile)
        }
    }

    func startMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let kind: ConnectionKind
            if path.status != .satisfied {
                kind = .none
            } else if path.usesInterfaceType(.wifi) {
                kind = .wifi
            } else if path.usesInterfaceType(.cellular) {
                kind = .cellular
            } else {
                kind = .wifi
            }

            Task { @MainActor in
                guard let self else { return }
                self.activeConnectionKind = kind
                self.pollOnce(forceWidgetReload: true)
            }
        }
        pathMonitor.start(queue: pathQueue)

        startForegroundTimer()
        pollOnce(forceWidgetReload: true)
    }

    func startForegroundTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollOnce(forceWidgetReload: false)
            }
        }
    }

    func stopForegroundTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        liveDownloadSpeedBps = 0
        liveUploadSpeedBps = 0
        pollOnce(forceWidgetReload: true)
    }

    /// تنفيذ دورة قياس كاملة (تعمل في المقدمة وفي مهام الخلفية BGTaskScheduler)
    func pollOnce(forceWidgetReload: Bool = false) {
        let reading = SystemNetworkReader.readCurrentState()
        let now = reading.timestamp
        let elapsed = max(0.3, now - lastPollTimestamp)
        lastPollTimestamp = now

        // تحديث حالة الاتصال وبصمة الشبكة المحلية
        updateActiveNetworkIdentity(from: reading)

        // قراءة اللقطة السابقة وحساب الدلتا الآمنة ضد إعادة التشغيل (Reboot-Safe Delta)
        let prevSnapshot = AppGroupStorage.loadInterfaceSnapshot()
        let deltaResult = SystemNetworkReader.computeSafeDelta(
            previous: prevSnapshot,
            currentReading: reading
        )
        AppGroupStorage.saveInterfaceSnapshot(deltaResult.newSnapshot)

        if deltaResult.didRebootOccur {
            lastRebootDetectedAt = now
        }

        let wifiDown = deltaResult.wifiDownloadDelta
        let wifiUp = deltaResult.wifiUploadDelta
        let cellDown = deltaResult.cellularDownloadDelta
        let cellUp = deltaResult.cellularUploadDelta

        // تحديث مؤشر السرعة الحية
        let totalDownNow = wifiDown + cellDown
        let totalUpNow = wifiUp + cellUp
        if elapsed < 10.0 {
            liveDownloadSpeedBps = Double(totalDownNow) / elapsed
            liveUploadSpeedBps = Double(totalUpNow) / elapsed
        } else {
            liveDownloadSpeedBps = 0
            liveUploadSpeedBps = 0
        }

        let todayKey = ByteFormatterUtil.todayDateKey()
        var didRecordNewBytes = false

        // حفظ استهلاك الواي فاي على الشبكة الحالية
        if wifiDown > 0 || wifiUp > 0 {
            DatabaseManager.shared.addUsageDelta(
                dateKey: todayKey,
                networkId: currentWifiNetworkId,
                networkName: currentWifiNetworkName,
                connectionType: .wifi,
                downloadDelta: wifiDown,
                uploadDelta: wifiUp
            )
            didRecordNewBytes = true
        }

        // حفظ استهلاك بيانات الهاتف
        let cellName = DatabaseManager.shared.fetchNetworkProfile(networkId: Self.cellularNetworkId)?.customName ?? Self.cellularDefaultName
        if cellDown > 0 || cellUp > 0 {
            DatabaseManager.shared.addUsageDelta(
                dateKey: todayKey,
                networkId: Self.cellularNetworkId,
                networkName: cellName,
                connectionType: .cellular,
                downloadDelta: cellDown,
                uploadDelta: cellUp
            )
            didRecordNewBytes = true
        }

        // تغذية القسم الثاني: منبّه وعداد الاستهلاك المخصص
        CustomUsageAlarmManager.shared.processNetworkDelta(
            wifiDownload: wifiDown,
            wifiUpload: wifiUp,
            cellularDownload: cellDown,
            cellularUpload: cellUp
        )

        // تغذية القسم الخامس: جرس إنذار السحب المفاجئ
        SpikeAlertManager.shared.recordTraffic(
            wifiNetworkId: currentWifiNetworkId,
            wifiNetworkName: currentWifiNetworkName,
            wifiDownload: wifiDown,
            wifiUpload: wifiUp,
            cellularDownload: cellDown,
            cellularUpload: cellUp
        )

        // تغذية القسم السادس: منبّه بقاء الداتا مفتوحة مع الواي فاي وحارس Wi-Fi Assist
        DualConnectionGuardManager.shared.processSystemReading(
            reading: reading,
            wifiNetworkId: currentWifiNetworkId,
            wifiNetworkName: currentWifiNetworkName,
            cellularDeltaWhilePolling: cellDown + cellUp
        )

        if didRecordNewBytes || allDailyRecords.isEmpty {
            reloadFromDatabase()
            quotaEvalCounter += 1
            if quotaEvalCounter >= 4 || forceWidgetReload {
                quotaEvalCounter = 0
                QuotaManager.shared.reloadPlansAndEvaluate(triggerAlerts: true)
            }
        }

        syncWidgetSummary(forceReload: forceWidgetReload)
    }

    private func updateActiveNetworkIdentity(from reading: SystemInterfaceReading) {
        if reading.isWifiInterfaceUp, let ipv4 = reading.wifiIPv4 {
            localIPAddress = ipv4
            let gw = reading.probableGatewayIP ?? "192.168.1.1"
            let subnet = reading.wifiSubnetCIDR ?? "192.168.1.0/24"
            gatewayIPAddress = gw
            subnetCIDR = subnet
            RouterUPnPService.shared.updateDetectedGateway(gw)

            let sanitizedSubnet = subnet.replacingOccurrences(of: "/", with: "_")
            let defaultFingerprintId = "wifi_\(sanitizedSubnet)_\(gw)"

            // التحقق مما إذا كان المستخدم قد اختار ملف شبكة محدد لهذا النطاق المحلي
            let pinnedKey = manualPinnedProfilePrefix + sanitizedSubnet
            let chosenId: String
            if let pinnedId = AppGroupStorage.userDefaults.string(forKey: pinnedKey),
               DatabaseManager.shared.fetchNetworkProfile(networkId: pinnedId) != nil {
                chosenId = pinnedId
            } else {
                chosenId = defaultFingerprintId
            }

            currentWifiNetworkId = chosenId

            if let existing = DatabaseManager.shared.fetchNetworkProfile(networkId: chosenId) {
                currentWifiNetworkName = existing.customName
                var updated = existing
                updated.gatewayIP = gw
                updated.subnet = subnet
                updated.lastSeenAt = reading.timestamp
                DatabaseManager.shared.upsertNetworkProfile(updated)
            } else {
                let defaultArabicName = "واي فاي (\(gw))"
                currentWifiNetworkName = defaultArabicName
                let newProfile = SavedNetworkProfile(
                    networkId: chosenId,
                    customName: defaultArabicName,
                    connectionType: .wifi,
                    gatewayIP: gw,
                    subnet: subnet,
                    upnpUDN: RouterUPnPService.shared.routerUDN,
                    routerModelName: RouterUPnPService.shared.routerFriendlyName,
                    lastSeenAt: reading.timestamp
                )
                DatabaseManager.shared.upsertNetworkProfile(newProfile)
                savedNetworkProfiles = DatabaseManager.shared.fetchAllNetworkProfiles()
            }

            if activeConnectionKind == .none {
                activeConnectionKind = .wifi
            }
        } else if reading.hasActiveCellularIP {
            localIPAddress = reading.cellularIPAddress ?? "—"
            subnetCIDR = "شبكة الجوال"
            if activeConnectionKind == .none {
                activeConnectionKind = .cellular
            }
        } else {
            localIPAddress = "—"
        }
    }

    // MARK: - تسمية الشبكة الحالية أو إنشاء شبكة واي فاي جديدة والتبديل إليها
    func renameNetwork(networkId: String, newName: String) {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        DatabaseManager.shared.renameNetwork(networkId: networkId, newName: clean)
        if networkId == currentWifiNetworkId {
            currentWifiNetworkName = clean
        }
        reloadFromDatabase()
        QuotaManager.shared.reloadPlansAndEvaluate(triggerAlerts: false)
        syncWidgetSummary(forceReload: true)
    }

    func createAndActivateWifiProfile(customName: String) {
        let clean = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let newId = "wifi_custom_\(UUID().uuidString.prefix(8))"
        let profile = SavedNetworkProfile(
            networkId: newId,
            customName: clean,
            connectionType: .wifi,
            gatewayIP: gatewayIPAddress,
            subnet: subnetCIDR,
            upnpUDN: "",
            routerModelName: "",
            lastSeenAt: Date().timeIntervalSince1970
        )
        DatabaseManager.shared.upsertNetworkProfile(profile)
        switchActiveWifiProfile(to: newId)
    }

    func switchActiveWifiProfile(to networkId: String) {
        guard let profile = DatabaseManager.shared.fetchNetworkProfile(networkId: networkId),
              profile.connectionType == .wifi else { return }
        let sanitizedSubnet = subnetCIDR.replacingOccurrences(of: "/", with: "_")
        AppGroupStorage.userDefaults.set(networkId, forKey: manualPinnedProfilePrefix + sanitizedSubnet)
        currentWifiNetworkId = profile.networkId
        currentWifiNetworkName = profile.customName
        reloadFromDatabase()
        syncWidgetSummary(forceReload: true)
    }

    // MARK: - قراءة السجلات وتحديث الملخصات اليومية
    func reloadFromDatabase() {
        let records = DatabaseManager.shared.fetchAllDailyRecords()
        self.allDailyRecords = records
        self.savedNetworkProfiles = DatabaseManager.shared.fetchAllNetworkProfiles()

        let todayKey = ByteFormatterUtil.todayDateKey()
        let todayRecords = records.filter { $0.dateKey == todayKey }

        todayAllWifiDownload = todayRecords
            .filter { $0.connectionType == .wifi }
            .reduce(0) { $0 + $1.downloadBytes }
        todayAllWifiUpload = todayRecords
            .filter { $0.connectionType == .wifi }
            .reduce(0) { $0 + $1.uploadBytes }

        todayCellularDownload = todayRecords
            .filter { $0.connectionType == .cellular }
            .reduce(0) { $0 + $1.downloadBytes }
        todayCellularUpload = todayRecords
            .filter { $0.connectionType == .cellular }
            .reduce(0) { $0 + $1.uploadBytes }

        let activeId = activeConnectionKind == .cellular ? Self.cellularNetworkId : currentWifiNetworkId
        todayCurrentNetworkDownload = todayRecords
            .filter { $0.networkId == activeId }
            .reduce(0) { $0 + $1.downloadBytes }
        todayCurrentNetworkUpload = todayRecords
            .filter { $0.networkId == activeId }
            .reduce(0) { $0 + $1.uploadBytes }
    }

    var currentActiveDisplayName: String {
        switch activeConnectionKind {
        case .wifi:
            return currentWifiNetworkName
        case .cellular:
            return DatabaseManager.shared.fetchNetworkProfile(networkId: Self.cellularNetworkId)?.customName ?? Self.cellularDefaultName
        case .none:
            return "غير متصل بالإنترنت"
        }
    }

    var currentActiveNetworkIdForFilter: String {
        activeConnectionKind == .cellular ? Self.cellularNetworkId : currentWifiNetworkId
    }

    // MARK: - مزامنة الويدجت عبر App Group
    func syncWidgetSummary(forceReload: Bool) {
        let now = Date().timeIntervalSince1970
        let alarm = CustomUsageAlarmManager.shared.state
        let activeQuota = QuotaManager.shared.evaluatedStatuses.first {
            $0.plan.networkId == currentActiveNetworkIdForFilter && $0.plan.isEnabled
        } ?? QuotaManager.shared.evaluatedStatuses.first { $0.plan.isEnabled }

        let summary = WidgetSharedSummary(
            updatedAt: now,
            activeNetworkName: currentActiveDisplayName,
            activeConnectionKind: activeConnectionKind,
            todayWifiDownload: todayAllWifiDownload,
            todayWifiUpload: todayAllWifiUpload,
            todayCellularDownload: todayCellularDownload,
            todayCellularUpload: todayCellularUpload,
            customAlarmActive: alarm.isRunning && !alarm.isPaused,
            customAlarmConsumedBytes: alarm.consumedTotalBytes,
            customAlarmTargetBytes: alarm.targetBytes,
            primaryQuotaName: activeQuota?.plan.networkName,
            primaryQuotaRemainingBytes: activeQuota?.remainingQuotaBytes,
            primaryQuotaTotalBytes: activeQuota?.plan.quotaBytes,
            isDualWifiCellularActive: DualConnectionGuardManager.shared.isDualActiveNow
        )

        AppGroupStorage.saveWidgetSummary(summary)

        if forceReload || (now - lastWidgetReloadTime) >= 60 {
            lastWidgetReloadTime = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
