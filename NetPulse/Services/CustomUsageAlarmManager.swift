import Foundation

@MainActor
final class CustomUsageAlarmManager: ObservableObject {
    static let shared = CustomUsageAlarmManager()

    @Published var state: CustomUsageAlarmState

    private init() {
        self.state = AppGroupStorage.loadCustomAlarmState()
    }

    func save() {
        AppGroupStorage.saveCustomAlarmState(state)
    }

    func updateTarget(amount: Double, unit: ExplicitDataUnit) {
        state.targetAmountInput = max(0.1, amount)
        state.unit = unit
        recheckThresholdsAfterEdit()
        save()
    }

    func updateScope(_ scope: MonitoredConnectionScope) {
        state.scope = scope
        save()
    }

    func updateWarningPercentage(_ percentage: Double) {
        let clamped = min(max(percentage, 5.0), 99.0)
        state.warningPercentage = clamped
        if state.progressPercentage < clamped {
            state.warningNotificationSent = false
        }
        save()
    }

    func updateRepeatSettings(enabled: Bool, everyMB: Double) {
        state.repeatAlertAfterFull = enabled
        state.repeatEveryMB = max(5.0, everyMB)
        save()
    }

    func startCounter() {
        if !state.isRunning {
            state.isRunning = true
            state.isPaused = false
            if state.startedAt == nil {
                state.startedAt = Date().timeIntervalSince1970
            }
        } else if state.isPaused {
            state.isPaused = false
        }
        save()
    }

    func pauseCounter() {
        guard state.isRunning else { return }
        state.isPaused = true
        save()
    }

    func resetCounter() {
        state.isRunning = false
        state.isPaused = false
        state.consumedDownloadBytes = 0
        state.consumedUploadBytes = 0
        state.startedAt = nil
        state.warningNotificationSent = false
        state.fullLimitNotificationSent = false
        state.lastRepeatMilestoneBytes = 0
        save()
    }

    func processNetworkDelta(
        wifiDownload: Int64,
        wifiUpload: Int64,
        cellularDownload: Int64,
        cellularUpload: Int64
    ) {
        guard state.isRunning && !state.isPaused else { return }

        let addDown: Int64
        let addUp: Int64

        switch state.scope {
        case .wifiOnly:
            addDown = wifiDownload
            addUp = wifiUpload
        case .cellularOnly:
            addDown = cellularDownload
            addUp = cellularUpload
        case .both:
            addDown = wifiDownload + cellularDownload
            addUp = wifiUpload + cellularUpload
        }

        guard addDown > 0 || addUp > 0 else { return }

        state.consumedDownloadBytes += addDown
        state.consumedUploadBytes += addUp

        evaluateAndSendAlertsIfNeeded()
        save()
    }

    private func recheckThresholdsAfterEdit() {
        if state.consumedTotalBytes < state.targetBytes {
            state.fullLimitNotificationSent = false
            state.lastRepeatMilestoneBytes = 0
        }
        if state.progressPercentage < state.warningPercentage {
            state.warningNotificationSent = false
        }
    }

    private func evaluateAndSendAlertsIfNeeded() {
        let pct = state.progressPercentage
        let target = state.targetBytes
        let consumed = state.consumedTotalBytes

        // 1. وصول الاستهلاك إلى 100% بالكامل
        if consumed >= target {
            if !state.fullLimitNotificationSent {
                state.fullLimitNotificationSent = true
                state.warningNotificationSent = true
                state.lastRepeatMilestoneBytes = consumed
                NotificationService.shared.notifyCustomAlarmCompleted(
                    targetBytes: target,
                    exceededBytes: state.exceededBytes,
                    scopeTitle: state.scope.shortArabicTitle,
                    isRepeat: false
                )
            } else if state.repeatAlertAfterFull {
                let stepBytes = Int64(max(5.0, state.repeatEveryMB) * 1024.0 * 1024.0)
                if consumed - state.lastRepeatMilestoneBytes >= stepBytes {
                    state.lastRepeatMilestoneBytes = consumed
                    NotificationService.shared.notifyCustomAlarmCompleted(
                        targetBytes: target,
                        exceededBytes: state.exceededBytes,
                        scopeTitle: state.scope.shortArabicTitle,
                        isRepeat: true
                    )
                }
            }
            return
        }

        // 2. وصول الاستهلاك إلى النسبة المئوية للتحذير المسبق
        if pct >= state.warningPercentage && !state.warningNotificationSent {
            state.warningNotificationSent = true
            NotificationService.shared.notifyCustomAlarmWarning(
                percentage: pct,
                remainingBytes: state.remainingBytes,
                scopeTitle: state.scope.shortArabicTitle
            )
        }
    }
}
