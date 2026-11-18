import Foundation

// MARK: - نوع الاتصال
enum ConnectionKind: String, Codable, CaseIterable, Identifiable {
    case wifi = "wifi"
    case cellular = "cellular"
    case none = "none"

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .wifi: return "واي فاي"
        case .cellular: return "بيانات الهاتف"
        case .none: return "غير متصل"
        }
    }

    var systemImage: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .none: return "wifi.slash"
        }
    }
}

// MARK: - خيارات الفلترة في القسم الأول
enum HistoryFilterOption: String, CaseIterable, Identifiable {
    case currentNetwork = "current"
    case allWifi = "wifi"
    case cellular = "cellular"
    case all = "all"

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .currentNetwork: return "الشبكة الحالية"
        case .allWifi: return "كل الواي فاي"
        case .cellular: return "داتا الهاتف"
        case .all: return "الكل"
        }
    }

    var iconName: String {
        switch self {
        case .currentNetwork: return "dot.radiowaves.left.and.right"
        case .allWifi: return "wifi"
        case .cellular: return "cellularbars"
        case .all: return "square.stack.3d.up.fill"
        }
    }
}

// MARK: - وحدة القياس المفضلة
enum DataUnitPreference: String, Codable, CaseIterable, Identifiable {
    case auto = "auto"
    case megabytes = "MB"
    case gigabytes = "GB"

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .auto: return "تلقائي"
        case .megabytes: return "ميجابايت (MB)"
        case .gigabytes: return "جيجابايت (GB)"
        }
    }
}

// MARK: - وحدة الإدخال للعداد والباقات
enum ExplicitDataUnit: String, Codable, CaseIterable, Identifiable {
    case megabytes = "MB"
    case gigabytes = "GB"

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .megabytes: return "ميجابايت (MB)"
        case .gigabytes: return "جيجابايت (GB)"
        }
    }

    var shortLabel: String {
        switch self {
        case .megabytes: return "م.ب"
        case .gigabytes: return "ج.ب"
        }
    }

    func toBytes(_ value: Double) -> Int64 {
        switch self {
        case .megabytes:
            return Int64(max(0, value) * 1024.0 * 1024.0)
        case .gigabytes:
            return Int64(max(0, value) * 1024.0 * 1024.0 * 1024.0)
        }
    }

    func fromBytes(_ bytes: Int64) -> Double {
        switch self {
        case .megabytes:
            return Double(bytes) / (1024.0 * 1024.0)
        case .gigabytes:
            return Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        }
    }
}

// MARK: - سجل الاستهلاك اليومي التفصيلي (SQLite)
struct DailyUsageRecord: Identifiable, Codable, Equatable, Hashable {
    var id: String // "\(dateKey)_\(networkId)"
    var dateKey: String // "yyyy-MM-dd"
    var networkId: String
    var networkName: String
    var connectionType: ConnectionKind
    var downloadBytes: Int64
    var uploadBytes: Int64
    var updatedAt: TimeInterval

    var totalBytes: Int64 {
        downloadBytes + uploadBytes
    }
}

// MARK: - تجميع اليوم الواحد (قد يشمل أكثر من شبكة في نفس التاريخ)
struct AggregatedDayGroup: Identifiable, Equatable {
    var dateKey: String
    var date: Date
    var records: [DailyUsageRecord]

    var id: String { dateKey }

    var downloadBytes: Int64 {
        records.reduce(0) { $0 + $1.downloadBytes }
    }

    var uploadBytes: Int64 {
        records.reduce(0) { $0 + $1.uploadBytes }
    }

    var totalBytes: Int64 {
        downloadBytes + uploadBytes
    }

    var networksSummary: String {
        let names = Array(Set(records.map { $0.networkName })).sorted()
        return names.joined(separator: " • ")
    }
}

// MARK: - ملف تعريف الشبكة المحفوظة (بصمة الشبكة المحلية + التسمية المخصصة)
struct SavedNetworkProfile: Identifiable, Codable, Equatable, Hashable {
    var networkId: String
    var customName: String
    var connectionType: ConnectionKind
    var gatewayIP: String
    var subnet: String
    var upnpUDN: String
    var routerModelName: String
    var lastSeenAt: TimeInterval

    var id: String { networkId }
}

// MARK: - لقطة عدادات الواجهات لمعالجة إعادة التشغيل (Reboot-Safe Delta)
struct InterfaceCountersSnapshot: Codable, Equatable {
    struct RawCounter: Codable, Equatable {
        var ibytes: UInt32
        var obytes: UInt32
    }

    var bootTime: Int64
    var timestamp: TimeInterval
    var interfaces: [String: RawCounter]
}

// MARK: - القسم الثاني: إعدادات وحالة عدّاد ومنبّه الاستهلاك المخصص
enum MonitoredConnectionScope: String, Codable, CaseIterable, Identifiable {
    case wifiOnly = "wifi_only"
    case cellularOnly = "cellular_only"
    case both = "both"

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .wifiOnly: return "الواي فاي فقط"
        case .cellularOnly: return "داتا الهاتف فقط"
        case .both: return "الاثنان معاً (واي فاي + داتا)"
        }
    }

    var shortArabicTitle: String {
        switch self {
        case .wifiOnly: return "واي فاي فقط"
        case .cellularOnly: return "داتا الهاتف فقط"
        case .both: return "الاثنان معاً"
        }
    }

    var iconName: String {
        switch self {
        case .wifiOnly: return "wifi"
        case .cellularOnly: return "antenna.radiowaves.left.and.right"
        case .both: return "arrow.triangle.merge"
        }
    }
}

struct CustomUsageAlarmState: Codable, Equatable {
    var targetAmountInput: Double = 500.0
    var unit: ExplicitDataUnit = .megabytes
    var scope: MonitoredConnectionScope = .cellularOnly
    var warningPercentage: Double = 80.0
    var isRunning: Bool = false
    var isPaused: Bool = false
    var consumedDownloadBytes: Int64 = 0
    var consumedUploadBytes: Int64 = 0
    var startedAt: TimeInterval? = nil
    var warningNotificationSent: Bool = false
    var fullLimitNotificationSent: Bool = false
    var repeatAlertAfterFull: Bool = true
    var repeatEveryMB: Double = 50.0
    var lastRepeatMilestoneBytes: Int64 = 0

    var targetBytes: Int64 {
        max(1, unit.toBytes(targetAmountInput))
    }

    var consumedTotalBytes: Int64 {
        consumedDownloadBytes + consumedUploadBytes
    }

    var remainingBytes: Int64 {
        max(0, targetBytes - consumedTotalBytes)
    }

    var exceededBytes: Int64 {
        max(0, consumedTotalBytes - targetBytes)
    }

    var progressRatio: Double {
        guard targetBytes > 0 else { return 0 }
        return Double(consumedTotalBytes) / Double(targetBytes)
    }

    var progressPercentage: Double {
        progressRatio * 100.0
    }
}

// MARK: - القسم الثالث: سجل ولقطة استهلاك الراوتر بالكامل
enum RouterFetchMethod: String, Codable {
    case upnp = "UPnP (WANCommonInterfaceConfig)"
    case hilink = "واجهة إحصائيات الراوتر (HiLink/HTTP)"
    case manual = "مزامنة يدوية مساندة"
    case none = "غير متصل بالراوتر"
}

struct RouterDailySnapshot: Identifiable, Codable, Equatable {
    var dateKey: String
    var gatewayIP: String
    var routerName: String
    var baselineRx: Int64
    var baselineTx: Int64
    var latestRx: Int64
    var latestTx: Int64
    var accumulatedRx: Int64
    var accumulatedTx: Int64
    var isManual: Bool
    var updatedAt: TimeInterval

    var id: String { "\(dateKey)_\(gatewayIP)" }

    var todayTotalBytes: Int64 {
        accumulatedRx + accumulatedTx
    }

    var rawSessionTotalBytes: Int64 {
        latestRx + latestTx
    }
}

// MARK: - القسم الرابع: باقة مستقلة لكل شبكة
struct NetworkQuotaPlan: Identifiable, Codable, Equatable {
    var id: String
    var networkId: String
    var networkName: String
    var connectionType: ConnectionKind
    var quotaBytes: Int64
    var renewalDay: Int // 1...31
    var usedOffsetBytes: Int64 // استهلاك مسبق في الدورة الحالية قبل التثبيت
    var dailyOverageAlertEnabled: Bool
    var warningPercent: Double
    var lastAlertCycleKey: String?
    var lastDailyAlertDate: String?
    var isEnabled: Bool
}

struct EvaluatedQuotaStatus: Identifiable, Equatable {
    var plan: NetworkQuotaPlan
    var cycleStartDate: Date
    var cycleEndDate: Date
    var cycleKey: String
    var trackedBytesInCycle: Int64
    var todayBytesOnNetwork: Int64
    var remainingDays: Int

    var id: String { plan.id }

    var totalConsumedBytes: Int64 {
        trackedBytesInCycle + plan.usedOffsetBytes
    }

    var remainingQuotaBytes: Int64 {
        max(0, plan.quotaBytes - totalConsumedBytes)
    }

    var allowedDailyBytes: Int64 {
        let days = max(1, remainingDays)
        return remainingQuotaBytes / Int64(days)
    }

    var usageRatio: Double {
        guard plan.quotaBytes > 0 else { return 0 }
        return Double(totalConsumedBytes) / Double(plan.quotaBytes)
    }

    var isDailyLimitExceeded: Bool {
        allowedDailyBytes > 0 && todayBytesOnNetwork > allowedDailyBytes
    }
}

// MARK: - القسم الخامس: إعدادات وحوادث السحب المفاجئ (Spike Alert)
struct SpikeAlertSettings: Codable, Equatable {
    var isWifiSpikeEnabled: Bool = true
    var wifiThresholdMB: Double = 500.0
    var wifiWindowMinutes: Int = 15

    var isCellularSpikeEnabled: Bool = true
    var cellularThresholdMB: Double = 100.0
    var cellularWindowMinutes: Int = 10
}

struct SpikeIncidentRecord: Identifiable, Codable, Equatable {
    var id: String
    var timestamp: TimeInterval
    var networkId: String
    var networkName: String
    var connectionType: ConnectionKind
    var bytesDelta: Int64
    var windowMinutes: Int
    var downloadBytes: Int64
    var uploadBytes: Int64
}

// MARK: - القسم السادس: إعدادات وسجل حارس الداتا المفتوحة مع الواي فاي و Wi-Fi Assist
enum DualGuardNetworkRuleMode: String, Codable, CaseIterable, Identifiable {
    case allNetworks = "all"
    case selectedOnly = "selected_only"
    case excludeSelected = "exclude_selected"

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .allNetworks: return "جميع شبكات الواي فاي"
        case .selectedOnly: return "شبكات محددة فقط"
        case .excludeSelected: return "كل الشبكات ما عدا المستثناة"
        }
    }
}

struct DualConnectionGuardSettings: Codable, Equatable {
    var isDualAlertEnabled: Bool = true
    var isWifiAssistGuardEnabled: Bool = true
    var wifiAssistThresholdMB: Double = 1.0
    var reminderCooldownMinutes: Int = 30
    var ruleMode: DualGuardNetworkRuleMode = .allNetworks
    var targetNetworkIds: [String] = []
}

enum DualGuardEventKind: String, Codable {
    case dualActive = "dual_active"
    case wifiAssistLeak = "wifi_assist_leak"

    var arabicTitle: String {
        switch self {
        case .dualActive: return "بقاء الداتا مفتوحة مع الواي فاي"
        case .wifiAssistLeak: return "سحب خفي عبر Wi-Fi Assist"
        }
    }
}

struct DualGuardEventRecord: Identifiable, Codable, Equatable {
    var id: String
    var timestamp: TimeInterval
    var wifiNetworkName: String
    var eventType: DualGuardEventKind
    var leakedBytes: Int64
}

// MARK: - المظهر (الوضع الليلي / النهاري / التلقائي)
enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var arabicTitle: String {
        switch self {
        case .system: return "تلقائي حسب النظام"
        case .light: return "الوضع النهاري"
        case .dark: return "الوضع الليلي"
        }
    }
}

// MARK: - ملخص مشاركة البيانات مع WidgetKit عبر App Group
struct WidgetSharedSummary: Codable, Equatable {
    var updatedAt: TimeInterval
    var activeNetworkName: String
    var activeConnectionKind: ConnectionKind
    var todayWifiDownload: Int64
    var todayWifiUpload: Int64
    var todayCellularDownload: Int64
    var todayCellularUpload: Int64
    var customAlarmActive: Bool
    var customAlarmConsumedBytes: Int64
    var customAlarmTargetBytes: Int64
    var primaryQuotaName: String?
    var primaryQuotaRemainingBytes: Int64?
    var primaryQuotaTotalBytes: Int64?
    var isDualWifiCellularActive: Bool

    var todayWifiTotal: Int64 { todayWifiDownload + todayWifiUpload }
    var todayCellularTotal: Int64 { todayCellularDownload + todayCellularUpload }
    var todayGrandTotal: Int64 { todayWifiTotal + todayCellularTotal }

    static let placeholder = WidgetSharedSummary(
        updatedAt: Date().timeIntervalSince1970,
        activeNetworkName: "واي فاي المنزل",
        activeConnectionKind: .wifi,
        todayWifiDownload: 1_450_000_000,
        todayWifiUpload: 210_000_000,
        todayCellularDownload: 185_000_000,
        todayCellularUpload: 32_000_000,
        customAlarmActive: true,
        customAlarmConsumedBytes: 380_000_000,
        customAlarmTargetBytes: 524_288_000,
        primaryQuotaName: "واي فاي المنزل",
        primaryQuotaRemainingBytes: 142_000_000_000,
        primaryQuotaTotalBytes: 214_748_364_800,
        isDualWifiCellularActive: false
    )
}

// MARK: - نموذج النسخة الاحتياطية الكاملة (JSON)
struct NetPulseFullBackup: Codable {
    var schemaVersion: Int = 1
    var exportedAt: TimeInterval
    var appVersion: String
    var dailyRecords: [DailyUsageRecord]
    var networkProfiles: [SavedNetworkProfile]
    var quotaPlans: [NetworkQuotaPlan]
    var spikeIncidents: [SpikeIncidentRecord]
    var dualGuardEvents: [DualGuardEventRecord]
    var routerSnapshots: [RouterDailySnapshot]
    var customAlarmState: CustomUsageAlarmState
    var spikeSettings: SpikeAlertSettings
    var dualGuardSettings: DualConnectionGuardSettings
}
