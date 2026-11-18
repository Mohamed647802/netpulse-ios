import SwiftUI

struct QuotaManagerView: View {
    @EnvironmentObject var quotaManager: QuotaManager
    @EnvironmentObject var monitor: NetworkMonitorService
    @Environment(\.colorScheme) private var colorScheme

    @State private var showAddEditSheet: Bool = false
    @State private var editingPlan: NetworkQuotaPlan? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.screenBackground(colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        SectionHeroBanner(
                            title: "الباقات المستقلة لكل شبكة",
                            subtitle: "خصّص حجم باقة ويوم تجديد مستقل لكل واي فاي ولداتا الموبايل مع حساب المعدل اليومي المسموح.",
                            systemImage: "chart.bar.doc.horizontal.fill",
                            gradient: AppTheme.primaryGradient,
                            badgeText: "\(quotaManager.evaluatedStatuses.count) باقة"
                        )

                        Button {
                            editingPlan = nil
                            showAddEditSheet = true
                        } label: {
                            Label("إضافة باقة جديدة لشبكة واي فاي أو داتا", systemImage: "plus.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundColor(.white)
                                .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.wifiAccent))
                        }

                        if quotaManager.evaluatedStatuses.isEmpty {
                            EmptyStateCardView(
                                icon: "tray.2.fill",
                                title: "لم تضف أي باقة شهرية بعد",
                                message: "أضف باقة (واي فاي البيت مثلاً 200 جيجا تتجدد يوم 5) وباقة (داتا الموبايل 20 جيجا تتجدد يوم 18) لحساب المعدل اليومي تلقائياً."
                            )
                        } else {
                            ForEach(quotaManager.evaluatedStatuses) { status in
                                quotaStatusCard(status)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("إدارة الباقات الشهرية")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        quotaManager.reloadPlansAndEvaluate(triggerAlerts: false)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showAddEditSheet) {
                QuotaAddEditSheet(existingPlan: editingPlan)
            }
        }
    }

    private func quotaStatusCard(_ status: EvaluatedQuotaStatus) -> some View {
        let ratio = min(max(status.usageRatio, 0), 1.0)
        let pct = status.usageRatio * 100.0
        let barColor: Color = pct >= 95 ? AppTheme.dangerColor : (pct >= status.plan.warningPercent ? AppTheme.warningColor : AppTheme.downloadColor)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: status.plan.connectionType.systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(status.plan.connectionType == .wifi ? AppTheme.wifiAccent : AppTheme.cellularAccent)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.plan.networkName)
                            .font(.system(size: 16, weight: .bold))
                        Text("تتجدد يوم \(status.plan.renewalDay) من كل شهر • باقي \(status.remainingDays) يوم للتجديد")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Menu {
                    Button {
                        editingPlan = status.plan
                        showAddEditSheet = true
                    } label: {
                        Label("تعديل الباقة", systemImage: "pencil")
                    }
                    Button {
                        quotaManager.togglePlanEnabled(status.plan)
                    } label: {
                        Label(status.plan.isEnabled ? "إيقاف التنبيهات مؤقتاً" : "تفعيل التنبيهات", systemImage: "bell")
                    }
                    Button(role: .destructive) {
                        quotaManager.deletePlan(status.plan)
                    } label: {
                        Label("حذف الباقة", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            // شريط التقدم
            VStack(spacing: 6) {
                HStack {
                    Text("المتبقي: \(ByteFormatterUtil.formatBytes(status.remainingQuotaBytes))")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(barColor)
                    Spacer()
                    Text(String(format: "%.1f%% من %@", pct, ByteFormatterUtil.formatBytes(status.plan.quotaBytes)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(barColor)
                            .frame(width: geo.size.width * CGFloat(ratio))
                    }
                }
                .frame(height: 10)
            }

            // بطاقات المعدل اليومي المسموح واستهلاك اليوم والأيام المتبقية
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("المعدل اليومي المسموح")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("\(ByteFormatterUtil.formatBytes(status.allowedDailyBytes)) / يوم")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.wifiAccent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryCardBackground(colorScheme)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("استهلاك اليوم")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(ByteFormatterUtil.formatBytes(status.todayBytesOnNetwork))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(status.isDailyLimitExceeded ? AppTheme.dangerColor : AppTheme.downloadColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryCardBackground(colorScheme)))
            }

            if status.isDailyLimitExceeded {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.dangerColor)
                    Text("تجاوزت اليوم المعدل اليومي المسموح به لهذه الباقة بمقدار \(ByteFormatterUtil.formatBytes(status.todayBytesOnNetwork - status.allowedDailyBytes))!")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(AppTheme.dangerColor)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.dangerColor.opacity(0.11)))
            }
        }
        .opacity(status.plan.isEnabled ? 1.0 : 0.65)
        .modernCard()
    }
}

// MARK: - نافذة إضافة أو تعديل باقة شبكة
struct QuotaAddEditSheet: View {
    let existingPlan: NetworkQuotaPlan?

    @EnvironmentObject var quotaManager: QuotaManager
    @EnvironmentObject var monitor: NetworkMonitorService
    @Environment(\.dismiss) private var dismiss

    @State private var selectionMode: Int = 0 // 0: شبكة موجودة، 1: شبكة جديدة بالاسم
    @State private var selectedProfileId: String = ""
    @State private var customNetworkName: String = ""
    @State private var customKind: ConnectionKind = .wifi

    @State private var quotaAmountText: String = "200"
    @State private var quotaUnit: ExplicitDataUnit = .gigabytes
    @State private var renewalDay: Int = 5

    @State private var alreadyUsedText: String = "0"
    @State private var alreadyUsedUnit: ExplicitDataUnit = .gigabytes
    @State private var dailyOverageAlert: Bool = true
    @State private var warningPercent: Double = 80.0

    var body: some View {
        NavigationStack {
            Form {
                if existingPlan == nil {
                    Section("اختيار الشبكة") {
                        Picker("طريقة التحديد", selection: $selectionMode) {
                            Text("من الشبكات المسجلة").tag(0)
                            Text("إضافة اسم شبكة جديد").tag(1)
                        }
                        .pickerStyle(.segmented)

                        if selectionMode == 0 {
                            Picker("الشبكة", selection: $selectedProfileId) {
                                ForEach(monitor.savedNetworkProfiles) { p in
                                    Text("\(p.customName) (\(p.connectionType.arabicTitle))").tag(p.networkId)
                                }
                            }
                        } else {
                            TextField("اسم الشبكة (مثال: واي فاي البيت / واي فاي العمل)", text: $customNetworkName)
                            Picker("نوع الشبكة", selection: $customKind) {
                                Text("واي فاي").tag(ConnectionKind.wifi)
                                Text("بيانات الهاتف").tag(ConnectionKind.cellular)
                            }
                        }
                    }
                } else {
                    Section("الشبكة") {
                        Text(existingPlan?.networkName ?? "")
                            .font(.headline)
                    }
                }

                Section("حجم الباقة وموعد التجديد الشهري") {
                    HStack {
                        TextField("حجم الباقة", text: $quotaAmountText)
                            .keyboardType(.decimalPad)
                        Picker("الوحدة", selection: $quotaUnit) {
                            ForEach(ExplicitDataUnit.allCases) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 115)
                    }

                    Stepper("يوم التجديد الشهري: يوم \(renewalDay)", value: $renewalDay, in: 1...31)
                }

                Section {
                    HStack {
                        TextField("المستهلك مسبقاً في الدورة الحالية", text: $alreadyUsedText)
                            .keyboardType(.decimalPad)
                        Picker("الوحدة", selection: $alreadyUsedUnit) {
                            ForEach(ExplicitDataUnit.allCases) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 115)
                    }
                } header: {
                    Text("رصيد مستهلك مسبقاً (اختياري)")
                } footer: {
                    Text("إذا كنت في منتصف الشهر واستهلكت جزءاً من الباقة قبل تثبيت التطبيق، اكتبه هنا ليكون حساب المتبقي دقيقاً 100%.")
                }

                Section("التنبيهات الذكية للباقة") {
                    Toggle("تنبيه عند تجاوز المعدل اليومي المسموح", isOn: $dailyOverageAlert)
                    VStack(alignment: .leading) {
                        Text("التنبيه عند استهلاك \(Int(warningPercent))% من الباقة")
                            .font(.subheadline)
                        Slider(value: $warningPercent, in: 50...95, step: 5)
                    }
                }

                Section {
                    Button {
                        savePlan()
                    } label: {
                        Label("حفظ الباقة", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                }
            }
            .navigationTitle(existingPlan == nil ? "إضافة باقة مستقلة" : "تعديل الباقة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
            .onAppear {
                populateInitialValues()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func populateInitialValues() {
        if let plan = existingPlan {
            selectedProfileId = plan.networkId
            customNetworkName = plan.networkName
            customKind = plan.connectionType
            let gbVal = ExplicitDataUnit.gigabytes.fromBytes(plan.quotaBytes)
            if gbVal >= 1.0 {
                quotaUnit = .gigabytes
                quotaAmountText = String(format: gbVal == floor(gbVal) ? "%.0f" : "%.2f", gbVal)
            } else {
                quotaUnit = .megabytes
                quotaAmountText = String(format: "%.0f", ExplicitDataUnit.megabytes.fromBytes(plan.quotaBytes))
            }
            renewalDay = plan.renewalDay
            let offsetGB = ExplicitDataUnit.gigabytes.fromBytes(plan.usedOffsetBytes)
            if plan.usedOffsetBytes == 0 {
                alreadyUsedText = "0"
                alreadyUsedUnit = .gigabytes
            } else if offsetGB >= 1.0 {
                alreadyUsedUnit = .gigabytes
                alreadyUsedText = String(format: "%.2f", offsetGB)
            } else {
                alreadyUsedUnit = .megabytes
                alreadyUsedText = String(format: "%.0f", ExplicitDataUnit.megabytes.fromBytes(plan.usedOffsetBytes))
            }
            dailyOverageAlert = plan.dailyOverageAlertEnabled
            warningPercent = plan.warningPercent
        } else {
            selectedProfileId = monitor.currentActiveNetworkIdForFilter
            if selectedProfileId.isEmpty, let first = monitor.savedNetworkProfiles.first {
                selectedProfileId = first.networkId
            }
        }
    }

    private func savePlan() {
        let qVal = Double(quotaAmountText.replacingOccurrences(of: ",", with: ".")) ?? 100
        let offVal = Double(alreadyUsedText.replacingOccurrences(of: ",", with: ".")) ?? 0

        let netId: String
        let netName: String
        let kind: ConnectionKind

        if let plan = existingPlan {
            netId = plan.networkId
            netName = plan.networkName
            kind = plan.connectionType
        } else if selectionMode == 0,
                  let prof = monitor.savedNetworkProfiles.first(where: { $0.networkId == selectedProfileId }) {
            netId = prof.networkId
            netName = prof.customName
            kind = prof.connectionType
        } else {
            let trimmed = customNetworkName.trimmingCharacters(in: .whitespacesAndNewlines)
            netName = trimmed.isEmpty ? "شبكة مخصصة" : trimmed
            kind = customKind
            netId = customKind == .cellular ? NetworkMonitorService.cellularNetworkId : "wifi_plan_\(UUID().uuidString.prefix(8))"
        }

        quotaManager.saveQuotaPlan(
            existingId: existingPlan?.id,
            networkId: netId,
            networkName: netName,
            connectionType: kind,
            quotaAmount: qVal,
            quotaUnit: quotaUnit,
            renewalDay: renewalDay,
            alreadyUsedAmount: offVal,
            alreadyUsedUnit: alreadyUsedUnit,
            dailyOverageAlertEnabled: dailyOverageAlert,
            warningPercent: warningPercent
        )
        monitor.reloadFromDatabase()
        monitor.syncWidgetSummary(forceReload: true)
        dismiss()
    }
}
