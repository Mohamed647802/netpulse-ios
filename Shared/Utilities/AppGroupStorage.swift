import Foundation

enum AppGroupStorage {
    static let appGroupIdentifier = "group.com.netpulse.shared"

    private static let widgetSummaryKey = "netpulse.widget.summary.v1"
    private static let snapshotKey = "netpulse.interface.snapshot.v1"
    private static let customAlarmKey = "netpulse.custom.alarm.v1"
    private static let spikeSettingsKey = "netpulse.spike.settings.v1"
    private static let dualGuardSettingsKey = "netpulse.dualguard.settings.v1"
    private static let appearanceModeKey = "netpulse.appearance.mode.v1"

    /// يعيد مجلد App Group المشترك إذا كان متاحاً، أو يعود تلقائياً لمجلد Documents لضمان عدم تعطل التوقيع المجاني.
    static var sharedDirectoryURL: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return groupURL
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    static var isAppGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil
    }

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var databaseFileURL: URL {
        sharedDirectoryURL.appendingPathComponent("netpulse_storage.sqlite3")
    }

    static var widgetSummaryFileURL: URL {
        sharedDirectoryURL.appendingPathComponent("widget_summary.json")
    }

    // MARK: - حفظ وقراءة الكائنات القابلة للترميز (Codable)
    static func saveCodable<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        userDefaults.set(data, forKey: key)
    }

    static func loadCodable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - ملخص الويدجت المشترك
    static func saveWidgetSummary(_ summary: WidgetSharedSummary) {
        saveCodable(summary, forKey: widgetSummaryKey)
        if let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: widgetSummaryFileURL, options: .atomic)
        }
    }

    static func loadWidgetSummary() -> WidgetSharedSummary? {
        if let data = try? Data(contentsOf: widgetSummaryFileURL),
           let decoded = try? JSONDecoder().decode(WidgetSharedSummary.self, from: data) {
            return decoded
        }
        return loadCodable(WidgetSharedSummary.self, forKey: widgetSummaryKey)
    }

    // MARK: - لقطة عدادات النظام (Reboot-Safe Delta)
    static func saveInterfaceSnapshot(_ snapshot: InterfaceCountersSnapshot) {
        saveCodable(snapshot, forKey: snapshotKey)
    }

    static func loadInterfaceSnapshot() -> InterfaceCountersSnapshot? {
        loadCodable(InterfaceCountersSnapshot.self, forKey: snapshotKey)
    }

    // MARK: - حالة منبّه الاستهلاك المخصص
    static func saveCustomAlarmState(_ state: CustomUsageAlarmState) {
        saveCodable(state, forKey: customAlarmKey)
    }

    static func loadCustomAlarmState() -> CustomUsageAlarmState {
        loadCodable(CustomUsageAlarmState.self, forKey: customAlarmKey) ?? CustomUsageAlarmState()
    }

    // MARK: - إعدادات السحب المفاجئ
    static func saveSpikeSettings(_ settings: SpikeAlertSettings) {
        saveCodable(settings, forKey: spikeSettingsKey)
    }

    static func loadSpikeSettings() -> SpikeAlertSettings {
        loadCodable(SpikeAlertSettings.self, forKey: spikeSettingsKey) ?? SpikeAlertSettings()
    }

    // MARK: - إعدادات حارس الداتا مع الواي فاي
    static func saveDualGuardSettings(_ settings: DualConnectionGuardSettings) {
        saveCodable(settings, forKey: dualGuardSettingsKey)
    }

    static func loadDualGuardSettings() -> DualConnectionGuardSettings {
        loadCodable(DualConnectionGuardSettings.self, forKey: dualGuardSettingsKey) ?? DualConnectionGuardSettings()
    }

    // MARK: - وضع المظهر (ليلي / نهاري / تلقائي)
    static func saveAppearanceMode(_ mode: AppAppearanceMode) {
        userDefaults.set(mode.rawValue, forKey: appearanceModeKey)
    }

    static func loadAppearanceMode() -> AppAppearanceMode {
        guard let raw = userDefaults.string(forKey: appearanceModeKey),
              let mode = AppAppearanceMode(rawValue: raw) else {
            return .system
        }
        return mode
    }
}
