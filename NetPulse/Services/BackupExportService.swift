import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ExportableDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupImportError: LocalizedError {
    case emptyFile
    case invalidJSON
    case invalidCSV

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "الملف المختار فارغ أو تعذرت قراءته."
        case .invalidJSON:
            return "بنية ملف النسخة الاحتياطية JSON غير صالحة."
        case .invalidCSV:
            return "لم يتم العثور على صفوف صالحة داخل ملف CSV."
        }
    }
}

@MainActor
enum BackupExportService {
    // MARK: - تصدير النسخة الاحتياطية الشاملة بصيغة JSON
    static func generateJSONBackupData() throws -> Data {
        let backup = NetPulseFullBackup(
            schemaVersion: 1,
            exportedAt: Date().timeIntervalSince1970,
            appVersion: "1.0.0",
            dailyRecords: DatabaseManager.shared.fetchAllDailyRecords(),
            networkProfiles: DatabaseManager.shared.fetchAllNetworkProfiles(),
            quotaPlans: DatabaseManager.shared.fetchQuotaPlans(),
            spikeIncidents: DatabaseManager.shared.fetchSpikeIncidents(limit: 1000),
            dualGuardEvents: DatabaseManager.shared.fetchDualGuardEvents(limit: 1000),
            routerSnapshots: DatabaseManager.shared.fetchAllRouterSnapshots(),
            customAlarmState: CustomUsageAlarmManager.shared.state,
            spikeSettings: SpikeAlertManager.shared.settings,
            dualGuardSettings: DualConnectionGuardManager.shared.settings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    // MARK: - تصدير سجل الاستهلاك بصيغة CSV متوافقة مع Excel واللغة العربية
    static func generateCSVExportData() -> Data {
        let records = DatabaseManager.shared.fetchAllDailyRecords()
        var lines: [String] = []

        lines.append("date,network_id,network_name,connection_type,download_bytes,upload_bytes,total_bytes,download_mb,upload_mb,total_mb")

        for r in records {
            let downMB = String(format: "%.2f", Double(r.downloadBytes) / (1024.0 * 1024.0))
            let upMB = String(format: "%.2f", Double(r.uploadBytes) / (1024.0 * 1024.0))
            let totMB = String(format: "%.2f", Double(r.totalBytes) / (1024.0 * 1024.0))
            let escapedName = escapeCSVField(r.networkName)
            let escapedId = escapeCSVField(r.networkId)
            let line = "\(r.dateKey),\(escapedId),\(escapedName),\(r.connectionType.rawValue),\(r.downloadBytes),\(r.uploadBytes),\(r.totalBytes),\(downMB),\(upMB),\(totMB)"
            lines.append(line)
        }

        // إضافة UTF-8 BOM لدعم الأسماء العربية في Excel مباشرة
        let csvString = "\u{FEFF}" + lines.joined(separator: "\r\n")
        return csvString.data(using: .utf8) ?? Data()
    }

    // MARK: - استيراد ملف JSON أو CSV
    static func importFromFileURL(_ url: URL, replaceExisting: Bool) throws -> String {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw BackupImportError.emptyFile
        }

        let ext = url.pathExtension.lowercased()
        if ext == "csv" {
            return try importCSVData(data, replaceExisting: replaceExisting)
        } else {
            // محاولة قراءة JSON أولاً، وإذا لم ينجح نجرب CSV
            if let summary = try? importJSONData(data, replaceExisting: replaceExisting) {
                return summary
            }
            if let csvSummary = try? importCSVData(data, replaceExisting: replaceExisting) {
                return csvSummary
            }
            throw BackupImportError.invalidJSON
        }
    }

    private static func importJSONData(_ data: Data, replaceExisting: Bool) throws -> String {
        guard let backup = try? JSONDecoder().decode(NetPulseFullBackup.self, from: data) else {
            throw BackupImportError.invalidJSON
        }

        DatabaseManager.shared.restoreBackup(backup, replaceExisting: replaceExisting)

        CustomUsageAlarmManager.shared.state = backup.customAlarmState
        CustomUsageAlarmManager.shared.save()

        SpikeAlertManager.shared.updateSettings(backup.spikeSettings)
        SpikeAlertManager.shared.reloadIncidents()

        DualConnectionGuardManager.shared.updateSettings(backup.dualGuardSettings)
        DualConnectionGuardManager.shared.reloadEvents()

        QuotaManager.shared.reloadPlansAndEvaluate(triggerAlerts: false)
        RouterUPnPService.shared.loadCachedSnapshot()
        NetworkMonitorService.shared.reloadFromDatabase()
        NetworkMonitorService.shared.syncWidgetSummary(forceReload: true)

        return "تم استيراد النسخة الاحتياطية بنجاح (\(backup.dailyRecords.count) سجل يومي و \(backup.quotaPlans.count) باقة)."
    }

    private static func importCSVData(_ data: Data, replaceExisting: Bool) throws -> String {
        guard var rawText = String(data: data, encoding: .utf8) else {
            throw BackupImportError.invalidCSV
        }
        rawText = rawText.replacingOccurrences(of: "\u{FEFF}", with: "")

        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count > 1 else {
            throw BackupImportError.invalidCSV
        }

        var importedRecords: [DailyUsageRecord] = []
        let now = Date().timeIntervalSince1970

        for (idx, line) in lines.enumerated() {
            if idx == 0 && line.lowercased().contains("date") {
                continue
            }
            let cols = parseCSVRow(line)
            guard cols.count >= 6 else { continue }

            let dateKey = cols[0].trimmingCharacters(in: .whitespaces)
            let netId = cols[1].trimmingCharacters(in: .whitespaces)
            let netName = cols[2].trimmingCharacters(in: .whitespaces)
            let kind = ConnectionKind(rawValue: cols[3].trimmingCharacters(in: .whitespaces)) ?? .wifi
            let downBytes = Int64(cols[4].trimmingCharacters(in: .whitespaces)) ?? 0
            let upBytes = Int64(cols[5].trimmingCharacters(in: .whitespaces)) ?? 0

            guard !dateKey.isEmpty && !netId.isEmpty else { continue }

            let record = DailyUsageRecord(
                id: "\(dateKey)_\(netId)",
                dateKey: dateKey,
                networkId: netId,
                networkName: netName.isEmpty ? netId : netName,
                connectionType: kind,
                downloadBytes: max(0, downBytes),
                uploadBytes: max(0, upBytes),
                updatedAt: now
            )
            importedRecords.append(record)

            if DatabaseManager.shared.fetchNetworkProfile(networkId: netId) == nil {
                let profile = SavedNetworkProfile(
                    networkId: netId,
                    customName: record.networkName,
                    connectionType: kind,
                    gatewayIP: "",
                    subnet: "",
                    upnpUDN: "",
                    routerModelName: "",
                    lastSeenAt: now
                )
                DatabaseManager.shared.upsertNetworkProfile(profile)
            }
        }

        guard !importedRecords.isEmpty else {
            throw BackupImportError.invalidCSV
        }

        DatabaseManager.shared.importCSVRecords(importedRecords, replaceExisting: replaceExisting)
        NetworkMonitorService.shared.reloadFromDatabase()
        QuotaManager.shared.reloadPlansAndEvaluate(triggerAlerts: false)
        NetworkMonitorService.shared.syncWidgetSummary(forceReload: true)

        return "تم استيراد \(importedRecords.count) سجل يومي من ملف CSV بنجاح."
    }

    private static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let doubled = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        }
        return field
    }

    private static func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(row)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        current.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            i += 1
        }
        fields.append(current)
        return fields
    }
}
