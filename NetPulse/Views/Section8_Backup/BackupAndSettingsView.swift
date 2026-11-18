import SwiftUI
import UniformTypeIdentifiers

struct BackupAndSettingsView: View {
    @EnvironmentObject var monitor: NetworkMonitorService
    @Binding var appearanceMode: AppAppearanceMode
    @Environment(\.colorScheme) private var colorScheme

    @State private var exportDocument: ExportableDataDocument? = nil
    @State private var exportContentType: UTType = .json
    @State private var exportDefaultFilename: String = "NetPulse_Backup"
    @State private var isShowingExporter: Bool = false
    @State private var isShowingImporter: Bool = false
    @State private var replaceOnImport: Bool = false

    @State private var statusBannerText: String? = nil
    @State private var isStatusError: Bool = false
    @State private var showResetConfirm: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.screenBackground(colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        SectionHeroBanner(
                            title: "النسخ الاحتياطي والمظهر",
                            subtitle: "تصدير واستيراد سجلاتك بصيغتي JSON و CSV لحفظ بياناتك عند تحديث ملف الـ IPA.",
                            systemImage: "externaldrive.fill.badge.checkmark",
                            gradient: AppTheme.routerGradient,
                            badgeText: "\(monitor.allDailyRecords.count) سجل"
                        )

                        if let statusBannerText {
                            HStack(spacing: 8) {
                                Image(systemName: isStatusError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                                    .foregroundColor(isStatusError ? AppTheme.dangerColor : AppTheme.downloadColor)
                                Text(statusBannerText)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill((isStatusError ? AppTheme.dangerColor : AppTheme.downloadColor).opacity(0.14))
                            )
                        }

                        exportSectionCard
                        importSectionCard
                        appearanceModeCard
                        dangerZoneCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("النسخ الاحتياطي والإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .fileExporter(
                isPresented: $isShowingExporter,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportDefaultFilename
            ) { result in
                switch result {
                case .success:
                    isStatusError = false
                    statusBannerText = "تم تصدير وحفظ الملف بنجاح."
                case .failure(let error):
                    isStatusError = true
                    statusBannerText = "تعذر تصدير الملف: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.json, .commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let firstURL = urls.first else { return }
                    do {
                        let msg = try BackupExportService.importFromFileURL(firstURL, replaceExisting: replaceOnImport)
                        isStatusError = false
                        statusBannerText = msg
                    } catch {
                        isStatusError = true
                        statusBannerText = error.localizedDescription
                    }
                case .failure(let error):
                    isStatusError = true
                    statusBannerText = "فشل اختيار الملف: \(error.localizedDescription)"
                }
            }
            .alert("مسح جميع السجلات؟", isPresented: $showResetConfirm) {
                Button("مسح نهائي", role: .destructive) {
                    DatabaseManager.shared.resetAllHistory()
                    monitor.reloadFromDatabase()
                    SpikeAlertManager.shared.reloadIncidents()
                    DualConnectionGuardManager.shared.reloadEvents()
                    QuotaManager.shared.reloadPlansAndEvaluate(triggerAlerts: false)
                    statusBannerText = "تم مسح السجل التاريخي بنجاح."
                    isStatusError = false
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("سيتم حذف سجل الأيام السابقة وحوادث السحب. يُنصح بتصدير نسخة احتياطية JSON أولاً.")
            }
        }
    }

    // MARK: - 1. تصدير البيانات (JSON / CSV)
    private var exportSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("تصدير النسخة الاحتياطية والسجلات", systemImage: "square.and.arrow.up.fill")
                .font(.system(size: 15, weight: .bold))

            Text("احفظ نسخة احتياطية في تطبيق (الملفات Files) على الآيفون أو iCloud لاسترجاعها بسهولة عند تثبيت إصدار جديد من ملف الـ IPA.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button {
                    prepareJSONExport()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.zipper")
                            .font(.title3)
                        Text("تصدير شامل (JSON)")
                            .font(.system(size: 13, weight: .bold))
                        Text("يشمل السجل + الباقات + الإعدادات")
                            .font(.system(size: 10))
                            .opacity(0.9)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.wifiAccent))
                }

                Button {
                    prepareCSVExport()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "tablecells.fill")
                            .font(.title3)
                        Text("تصدير جدول (CSV)")
                            .font(.system(size: 13, weight: .bold))
                        Text("متوافق مع Excel و Numbers")
                            .font(.system(size: 10))
                            .opacity(0.9)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.downloadColor))
                }
            }
        }
        .modernCard()
    }

    // MARK: - 2. استيراد البيانات (JSON / CSV)
    private var importSectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("استيراد نسخة احتياطية (JSON أو CSV)", systemImage: "square.and.arrow.down.fill")
                .font(.system(size: 15, weight: .bold))

            Toggle("استبدال السجلات الحالية بالكامل عند الاستيراد", isOn: $replaceOnImport)
                .font(.subheadline)
                .tint(AppTheme.warningColor)

            Text(replaceOnImport
                 ? "تنبيه: سيتم مسح السجل الحالي واستبداله بمحتوى الملف المختار."
                 : "الوضع الآمن (دمج): سيتم دمج السجلات المستوردة مع السجل الحالي دون فقدان أي بيانات جديدة.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                isShowingImporter = true
            } label: {
                Label("اختيار ملف JSON أو CSV للاستيراد", systemImage: "folder.fill.badge.plus")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(AppTheme.wifiAccent)
                    .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.wifiAccent.opacity(0.12)))
            }
        }
        .modernCard()
    }

    // MARK: - 3. وضع المظهر (الليلي والنهاري)
    private var appearanceModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("مظهر الواجهة (الوضع الليلي والنهاري)", systemImage: "moon.stars.fill")
                .font(.system(size: 15, weight: .bold))

            Picker("المظهر", selection: $appearanceMode) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.arabicTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .modernCard()
    }

    // MARK: - 4. منطقة إعادة الضبط
    private var dangerZoneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("إدارة السجل", systemImage: "trash.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(AppTheme.dangerColor)

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Text("مسح جميع السجلات التاريخية من الهاتف")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.dangerColor.opacity(0.10)))
            }
        }
        .modernCard()
    }

    private func prepareJSONExport() {
        do {
            let data = try BackupExportService.generateJSONBackupData()
            exportDocument = ExportableDataDocument(data: data)
            exportContentType = .json
            exportDefaultFilename = "NetPulse_Backup_\(ByteFormatterUtil.todayDateKey())"
            isShowingExporter = true
        } catch {
            isStatusError = true
            statusBannerText = "تعذر تجهيز ملف JSON: \(error.localizedDescription)"
        }
    }

    private func prepareCSVExport() {
        let data = BackupExportService.generateCSVExportData()
        exportDocument = ExportableDataDocument(data: data)
        exportContentType = .commaSeparatedText
        exportDefaultFilename = "NetPulse_History_\(ByteFormatterUtil.todayDateKey())"
        isShowingExporter = true
    }
}
