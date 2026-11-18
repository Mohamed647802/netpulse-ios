import Foundation
import BackgroundTasks

final class BackgroundTaskService {
    static let shared = BackgroundTaskService()

    static let refreshTaskIdentifier = "com.netpulse.app.refresh"
    static let processingTaskIdentifier = "com.netpulse.app.processing"

    private var didRegister = false

    private init() {}

    /// يجب استدعاؤها أثناء إطلاق التطبيق قبل انتهاء didFinishLaunchingWithOptions
    func registerBackgroundTasks() {
        guard !didRegister else { return }
        didRegister = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleAppRefresh(task: refreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleProcessingTask(task: processingTask)
        }
    }

    func scheduleBackgroundTasks() {
        let refreshRequest = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(refreshRequest)

        let processingRequest = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        processingRequest.requiresNetworkConnectivity = false
        processingRequest.requiresExternalPower = false
        processingRequest.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(processingRequest)
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundTasks()

        let workTask = Task { @MainActor in
            NetworkMonitorService.shared.pollOnce(forceWidgetReload: true)
            QuotaManager.shared.reloadPlansAndEvaluate(triggerAlerts: true)
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        Task {
            _ = await workTask.result
            task.setTaskCompleted(success: true)
        }
    }

    private func handleProcessingTask(task: BGProcessingTask) {
        scheduleBackgroundTasks()

        let workTask = Task { @MainActor in
            NetworkMonitorService.shared.pollOnce(forceWidgetReload: true)
            QuotaManager.shared.reloadPlansAndEvaluate(triggerAlerts: true)
            if NetworkMonitorService.shared.activeConnectionKind == .wifi {
                await RouterUPnPService.shared.refreshRouterUsage()
            }
        }

        task.expirationHandler = {
            workTask.cancel()
        }

        Task {
            _ = await workTask.result
            task.setTaskCompleted(success: true)
        }
    }
}
