import Foundation

@MainActor
final class QuotaManager: ObservableObject {
    static let shared = QuotaManager()

    @Published var plans: [NetworkQuotaPlan] = []
    @Published var evaluatedStatuses: [EvaluatedQuotaStatus] = []

    private init() {
        reloadPlansAndEvaluate(triggerAlerts: false)
    }

    func reloadPlansAndEvaluate(triggerAlerts: Bool = true) {
        let fetchedPlans = DatabaseManager.shared.fetchQuotaPlans()
        self.plans = fetchedPlans

        let todayKey = ByteFormatterUtil.todayDateKey()
        var updatedStatuses: [EvaluatedQuotaStatus] = []

        for var plan in fetchedPlans {
            let cycle = BillingCycleCalculator.currentCycle(renewalDay: plan.renewalDay)
            let fromKey = ByteFormatterUtil.todayDateKey(for: cycle.start)
            let toKey = ByteFormatterUtil.todayDateKey(for: cycle.end)

            let trackedInCycle = DatabaseManager.shared.fetchTotalBytes(
                networkId: plan.networkId,
                fromDateKey: fromKey,
                toDateKey: toKey
            )
            let todayBytes = DatabaseManager.shared.fetchTotalBytes(
                networkId: plan.networkId,
                fromDateKey: todayKey,
                toDateKey: todayKey
            )

            // حساب المعدل اليومي المسموح بناءً على ما تبقى قبل استهلاك اليوم لضمان ثبات المعدل طوال اليوم
            let usedBeforeToday = max(0, (trackedInCycle - todayBytes) + plan.usedOffsetBytes)
            let remainingAtStartOfDay = max(0, plan.quotaBytes - usedBeforeToday)
            let steadyAllowedDaily = remainingAtStartOfDay / Int64(max(1, cycle.remainingDays))

            let status = EvaluatedQuotaStatus(
                plan: plan,
                cycleStartDate: cycle.start,
                cycleEndDate: cycle.end,
                cycleKey: cycle.cycleKey,
                trackedBytesInCycle: trackedInCycle,
                todayBytesOnNetwork: todayBytes,
                remainingDays: cycle.remainingDays
            )
            updatedStatuses.append(status)

            guard triggerAlerts && plan.isEnabled else { continue }

            var didMutatePlan = false

            // 1. تنبيه تجاوز المعدل اليومي المسموح به
            let effectiveDailyLimit = max(steadyAllowedDaily, status.allowedDailyBytes)
            if plan.dailyOverageAlertEnabled,
               effectiveDailyLimit > 0,
               todayBytes > effectiveDailyLimit,
               plan.lastDailyAlertDate != todayKey {
                plan.lastDailyAlertDate = todayKey
                didMutatePlan = true
                NotificationService.shared.notifyQuotaDailyExceeded(
                    networkName: plan.networkName,
                    todayBytes: todayBytes,
                    allowedDailyBytes: effectiveDailyLimit
                )
            }

            // 2. تنبيه الوصول لنسبة التحذير من إجمالي الباقة الشهرية
            let usedPercent = status.usageRatio * 100.0
            if usedPercent >= plan.warningPercent,
               plan.lastAlertCycleKey != cycle.cycleKey {
                plan.lastAlertCycleKey = cycle.cycleKey
                didMutatePlan = true
                NotificationService.shared.notifyQuotaThresholdReached(
                    networkName: plan.networkName,
                    usedPercent: usedPercent,
                    remainingBytes: status.remainingQuotaBytes
                )
            }

            if didMutatePlan {
                DatabaseManager.shared.upsertQuotaPlan(plan)
            }
        }

        self.evaluatedStatuses = updatedStatuses
    }

    func saveQuotaPlan(
        existingId: String? = nil,
        networkId: String,
        networkName: String,
        connectionType: ConnectionKind,
        quotaAmount: Double,
        quotaUnit: ExplicitDataUnit,
        renewalDay: Int,
        alreadyUsedAmount: Double,
        alreadyUsedUnit: ExplicitDataUnit,
        dailyOverageAlertEnabled: Bool,
        warningPercent: Double,
        isEnabled: Bool = true
    ) {
        let finalId = existingId ?? UUID().uuidString
        let cleanRenewal = min(max(renewalDay, 1), 31)
        let quotaBytes = max(1, quotaUnit.toBytes(quotaAmount))
        let offsetBytes = max(0, alreadyUsedUnit.toBytes(alreadyUsedAmount))

        // التأكد من وجود الشبكة في جدول الشبكات المحفوظة حتى لو أضافها المستخدم مسبقاً
        if DatabaseManager.shared.fetchNetworkProfile(networkId: networkId) == nil {
            let profile = SavedNetworkProfile(
                networkId: networkId,
                customName: networkName,
                connectionType: connectionType,
                gatewayIP: "",
                subnet: "",
                upnpUDN: "",
                routerModelName: "",
                lastSeenAt: Date().timeIntervalSince1970
            )
            DatabaseManager.shared.upsertNetworkProfile(profile)
        }

        let existing = plans.first { $0.networkId == networkId }
        let plan = NetworkQuotaPlan(
            id: existing?.id ?? finalId,
            networkId: networkId,
            networkName: networkName,
            connectionType: connectionType,
            quotaBytes: quotaBytes,
            renewalDay: cleanRenewal,
            usedOffsetBytes: offsetBytes,
            dailyOverageAlertEnabled: dailyOverageAlertEnabled,
            warningPercent: min(max(warningPercent, 10.0), 100.0),
            lastAlertCycleKey: existing?.lastAlertCycleKey,
            lastDailyAlertDate: existing?.lastDailyAlertDate,
            isEnabled: isEnabled
        )

        DatabaseManager.shared.upsertQuotaPlan(plan)
        reloadPlansAndEvaluate(triggerAlerts: false)
    }

    func togglePlanEnabled(_ plan: NetworkQuotaPlan) {
        var updated = plan
        updated.isEnabled.toggle()
        DatabaseManager.shared.upsertQuotaPlan(updated)
        reloadPlansAndEvaluate(triggerAlerts: false)
    }

    func deletePlan(_ plan: NetworkQuotaPlan) {
        DatabaseManager.shared.deleteQuotaPlan(id: plan.id)
        reloadPlansAndEvaluate(triggerAlerts: false)
    }
}
