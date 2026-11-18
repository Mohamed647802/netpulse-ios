import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    enum Category: String {
        case customAlarmWarning = "CUSTOM_ALARM_WARNING"
        case customAlarmFull = "CUSTOM_ALARM_FULL"
        case spikeAlert = "SPIKE_ALERT"
        case dualDataActive = "DUAL_DATA_ACTIVE"
        case wifiAssistLeak = "WIFI_ASSIST_LEAK"
        case quotaAlert = "QUOTA_ALERT"
        case testAlert = "TEST_ALERT"
    }

    private override init() {
        super.init()
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Category.customAlarmWarning.rawValue, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.customAlarmFull.rawValue, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.spikeAlert.rawValue, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.dualDataActive.rawValue, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.wifiAssistLeak.rawValue, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.quotaAlert.rawValue, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.testAlert.rawValue, actions: [], intentIdentifiers: [], options: [])
        ]
        center.setNotificationCategories(categories)
    }

    func sendNotification(
        title: String,
        body: String,
        category: Category,
        isTimeSensitive: Bool = false,
        identifier: String = UUID().uuidString
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.sound = .default

        if isTimeSensitive {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        } else {
            content.interruptionLevel = .active
            content.relevanceScore = 0.8
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - إشعارات مخصصة جاهزة لكل قسم

    func notifyCustomAlarmWarning(percentage: Double, remainingBytes: Int64, scopeTitle: String) {
        let pctText = String(format: "%.0f%%", percentage)
        let remText = ByteFormatterUtil.formatBytes(remainingBytes)
        sendNotification(
            title: "⚠️ اقتربت من حد الاستهلاك (\(pctText))",
            body: "وصل عداد (\(scopeTitle)) إلى \(pctText) من الكمية المحددة. المتبقي لك الآن: \(remText).",
            category: .customAlarmWarning,
            isTimeSensitive: true,
            identifier: "custom_alarm_warning_\(Int(Date().timeIntervalSince1970))"
        )
    }

    func notifyCustomAlarmCompleted(targetBytes: Int64, exceededBytes: Int64, scopeTitle: String, isRepeat: Bool) {
        let targetText = ByteFormatterUtil.formatBytes(targetBytes)
        let title = isRepeat
            ? "🚨 تحذير متكرر: السحب مستمر بعد انتهاء الكمية!"
            : "🛑 انتهت الكمية المحددة بالكامل (100%)!"
        let body = isRepeat
            ? "تم تجاوز كمية (\(targetText)) على (\(scopeTitle)) بمقدار إضافي قدره \(ByteFormatterUtil.formatBytes(exceededBytes))!"
            : "تم استهلاك كامل الكمية المحددة (\(targetText)) على (\(scopeTitle)). أوقف الاتصال إذا أردت تجنب الاستهلاك الإضافي."

        sendNotification(
            title: title,
            body: body,
            category: .customAlarmFull,
            isTimeSensitive: true,
            identifier: "custom_alarm_full_\(Int(Date().timeIntervalSince1970))"
        )
    }

    func notifySpikeDetected(networkName: String, bytesDelta: Int64, windowMinutes: Int, connectionKind: ConnectionKind) {
        let amount = ByteFormatterUtil.formatBytes(bytesDelta)
        sendNotification(
            title: "🚨 جرس إنذار: سحب مفاجئ للبيانات!",
            body: "تم رصد استهلاك \(amount) خلال \(windowMinutes) دقيقة على (\(networkName) - \(connectionKind.arabicTitle)). تحقق من التحديثات التلقائية أو الفيديوهات عالية الجودة!",
            category: .spikeAlert,
            isTimeSensitive: true,
            identifier: "spike_\(Int(Date().timeIntervalSince1970))"
        )
    }

    func notifyDualWifiAndCellularActive(wifiName: String) {
        sendNotification(
            title: "📶 نسيت داتا الهاتف مفتوحة مع الواي فاي!",
            body: "أنت متصل الآن بشبكة (\(wifiName)) لكن زر بيانات الهاتف لا يزال مفعّلاً. أغلق الداتا من مركز التحكم لحماية باقتك من السحب الخفي.",
            category: .dualDataActive,
            isTimeSensitive: true,
            identifier: "dual_active_\(Int(Date().timeIntervalSince1970))"
        )
    }

    func notifyWifiAssistLeak(wifiName: String, leakedBytes: Int64) {
        let amount = ByteFormatterUtil.formatBytes(leakedBytes)
        sendNotification(
            title: "⚠️ حارس Wi-Fi Assist: سحب خفي من الداتا!",
            body: "رغم اتصالك بالواي فاي (\(wifiName))، تم سحب \(amount) من باقة الموبايل بالخلفية عبر pdp_ip0!",
            category: .wifiAssistLeak,
            isTimeSensitive: true,
            identifier: "wifi_assist_\(Int(Date().timeIntervalSince1970))"
        )
    }

    func notifyQuotaDailyExceeded(networkName: String, todayBytes: Int64, allowedDailyBytes: Int64) {
        sendNotification(
            title: "📊 تجاوزت المعدل اليومي لباقة (\(networkName))",
            body: "استهلكت اليوم \(ByteFormatterUtil.formatBytes(todayBytes)) بينما المعدل اليومي المسموح لتكفي الباقة هو \(ByteFormatterUtil.formatBytes(allowedDailyBytes)).",
            category: .quotaAlert,
            isTimeSensitive: false,
            identifier: "quota_daily_\(networkName)_\(ByteFormatterUtil.todayDateKey())"
        )
    }

    func notifyQuotaThresholdReached(networkName: String, usedPercent: Double, remainingBytes: Int64) {
        let pct = String(format: "%.0f%%", usedPercent)
        sendNotification(
            title: "⚠️ تنبيه باقة (\(networkName)): استُهلك \(pct)",
            body: "المتبقي في باقة (\(networkName)) حتى موعد التجديد هو \(ByteFormatterUtil.formatBytes(remainingBytes)).",
            category: .quotaAlert,
            isTimeSensitive: true,
            identifier: "quota_threshold_\(networkName)_\(ByteFormatterUtil.todayDateKey())"
        )
    }

    func sendTestNotification() {
        sendNotification(
            title: "✅ الإشعارات والتنبيهات تعمل بنجاح",
            body: "نظام التنبيهات الفورية في تطبيق نبض البيانات جاهز لحماية باقاتك على مدار الساعة.",
            category: .testAlert,
            isTimeSensitive: true
        )
    }

    // MARK: - UNUserNotificationCenterDelegate (إظهار الإشعارات حتى أثناء فتح التطبيق)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}
