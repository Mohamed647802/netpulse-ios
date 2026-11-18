import Foundation

struct RollingTrafficSample: Codable {
    var timestamp: TimeInterval
    var networkId: String
    var networkName: String
    var connectionKind: ConnectionKind
    var downloadBytes: Int64
    var uploadBytes: Int64

    var totalBytes: Int64 { downloadBytes + uploadBytes }
}

@MainActor
final class SpikeAlertManager: ObservableObject {
    static let shared = SpikeAlertManager()

    @Published var settings: SpikeAlertSettings
    @Published var incidents: [SpikeIncidentRecord] = []
    @Published var currentWifiWindowBytes: Int64 = 0
    @Published var currentCellularWindowBytes: Int64 = 0

    private var samples: [RollingTrafficSample] = []
    private var lastWifiAlertTime: TimeInterval = 0
    private var lastCellularAlertTime: TimeInterval = 0

    private let samplesStorageKey = "netpulse.spike.rolling.samples.v1"

    private init() {
        self.settings = AppGroupStorage.loadSpikeSettings()
        self.samples = AppGroupStorage.loadCodable([RollingTrafficSample].self, forKey: samplesStorageKey) ?? []
        self.incidents = DatabaseManager.shared.fetchSpikeIncidents()
        recomputeWindowTotals()
    }

    func updateSettings(_ newSettings: SpikeAlertSettings) {
        self.settings = newSettings
        AppGroupStorage.saveSpikeSettings(newSettings)
        recomputeWindowTotals()
    }

    func reloadIncidents() {
        self.incidents = DatabaseManager.shared.fetchSpikeIncidents()
    }

    func clearIncidentLog() {
        DatabaseManager.shared.clearSpikeIncidents()
        self.incidents = []
    }

    func recordTraffic(
        wifiNetworkId: String,
        wifiNetworkName: String,
        wifiDownload: Int64,
        wifiUpload: Int64,
        cellularDownload: Int64,
        cellularUpload: Int64
    ) {
        let now = Date().timeIntervalSince1970
        var added = false

        if wifiDownload > 0 || wifiUpload > 0 {
            samples.append(
                RollingTrafficSample(
                    timestamp: now,
                    networkId: wifiNetworkId,
                    networkName: wifiNetworkName,
                    connectionKind: .wifi,
                    downloadBytes: wifiDownload,
                    uploadBytes: wifiUpload
                )
            )
            added = true
        }

        if cellularDownload > 0 || cellularUpload > 0 {
            samples.append(
                RollingTrafficSample(
                    timestamp: now,
                    networkId: "cellular_mobile",
                    networkName: "بيانات الهاتف",
                    connectionKind: .cellular,
                    downloadBytes: cellularDownload,
                    uploadBytes: cellularUpload
                )
            )
            added = true
        }

        pruneOldSamples(now: now)
        recomputeWindowTotals(now: now)

        guard added else { return }
        evaluateSpikes(now: now, activeWifiId: wifiNetworkId, activeWifiName: wifiNetworkName)
        AppGroupStorage.saveCodable(samples, forKey: samplesStorageKey)
    }

    private func pruneOldSamples(now: TimeInterval) {
        let maxMinutes = max(settings.wifiWindowMinutes, settings.cellularWindowMinutes, 60)
        let cutoff = now - Double(maxMinutes * 60 + 120)
        samples.removeAll { $0.timestamp < cutoff }
    }

    private func recomputeWindowTotals(now: TimeInterval = Date().timeIntervalSince1970) {
        let wifiCutoff = now - Double(max(1, settings.wifiWindowMinutes) * 60)
        let cellCutoff = now - Double(max(1, settings.cellularWindowMinutes) * 60)

        currentWifiWindowBytes = samples
            .filter { $0.connectionKind == .wifi && $0.timestamp >= wifiCutoff }
            .reduce(0) { $0 + $1.totalBytes }

        currentCellularWindowBytes = samples
            .filter { $0.connectionKind == .cellular && $0.timestamp >= cellCutoff }
            .reduce(0) { $0 + $1.totalBytes }
    }

    private func evaluateSpikes(now: TimeInterval, activeWifiId: String, activeWifiName: String) {
        // 1. فحص السحب المفاجئ على الواي فاي
        if settings.isWifiSpikeEnabled {
            let windowSec = Double(max(1, settings.wifiWindowMinutes) * 60)
            let thresholdBytes = Int64(max(1.0, settings.wifiThresholdMB) * 1024.0 * 1024.0)
            let wifiSamples = samples.filter { $0.connectionKind == .wifi && $0.timestamp >= (now - windowSec) }
            let downSum = wifiSamples.reduce(0) { $0 + $1.downloadBytes }
            let upSum = wifiSamples.reduce(0) { $0 + $1.uploadBytes }
            let total = downSum + upSum

            if total >= thresholdBytes && (now - lastWifiAlertTime) >= windowSec {
                lastWifiAlertTime = now
                let incident = SpikeIncidentRecord(
                    id: UUID().uuidString,
                    timestamp: now,
                    networkId: activeWifiId,
                    networkName: activeWifiName,
                    connectionType: .wifi,
                    bytesDelta: total,
                    windowMinutes: settings.wifiWindowMinutes,
                    downloadBytes: downSum,
                    uploadBytes: upSum
                )
                DatabaseManager.shared.insertSpikeIncident(incident)
                incidents.insert(incident, at: 0)
                NotificationService.shared.notifySpikeDetected(
                    networkName: activeWifiName,
                    bytesDelta: total,
                    windowMinutes: settings.wifiWindowMinutes,
                    connectionKind: .wifi
                )
                // تصفير عينات الواي فاي السابقة بعد إطلاق الإنذار لبدء نافذة رصد جديدة نظيفة
                samples.removeAll { $0.connectionKind == .wifi }
                currentWifiWindowBytes = 0
            }
        }

        // 2. فحص السحب المفاجئ على بيانات الهاتف
        if settings.isCellularSpikeEnabled {
            let windowSec = Double(max(1, settings.cellularWindowMinutes) * 60)
            let thresholdBytes = Int64(max(1.0, settings.cellularThresholdMB) * 1024.0 * 1024.0)
            let cellSamples = samples.filter { $0.connectionKind == .cellular && $0.timestamp >= (now - windowSec) }
            let downSum = cellSamples.reduce(0) { $0 + $1.downloadBytes }
            let upSum = cellSamples.reduce(0) { $0 + $1.uploadBytes }
            let total = downSum + upSum

            if total >= thresholdBytes && (now - lastCellularAlertTime) >= windowSec {
                lastCellularAlertTime = now
                let incident = SpikeIncidentRecord(
                    id: UUID().uuidString,
                    timestamp: now,
                    networkId: "cellular_mobile",
                    networkName: "بيانات الهاتف",
                    connectionType: .cellular,
                    bytesDelta: total,
                    windowMinutes: settings.cellularWindowMinutes,
                    downloadBytes: downSum,
                    uploadBytes: upSum
                )
                DatabaseManager.shared.insertSpikeIncident(incident)
                incidents.insert(incident, at: 0)
                NotificationService.shared.notifySpikeDetected(
                    networkName: "بيانات الهاتف",
                    bytesDelta: total,
                    windowMinutes: settings.cellularWindowMinutes,
                    connectionKind: .cellular
                )
                samples.removeAll { $0.connectionKind == .cellular }
                currentCellularWindowBytes = 0
            }
        }
    }
}
