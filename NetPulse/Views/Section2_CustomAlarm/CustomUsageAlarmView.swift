import SwiftUI

struct CustomUsageAlarmView: View {
    @EnvironmentObject var alarmManager: CustomUsageAlarmManager
    @EnvironmentObject var monitor: NetworkMonitorService
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isInputFocused: Bool

    @State private var amountText: String = "500"
    @State private var warningText: String = "80"

    private var state: CustomUsageAlarmState {
        alarmManager.state
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.screenBackground(colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        SectionHeroBanner(
                            title: "عدّاد ومنبّه الاستهلاك المخصص",
                            subtitle: "حدد كمية بالميجابايت أو الجيجابايت مع منبّه صوتي عند نسبة التحذير وإشعار عاجل عند 100%.",
                            systemImage: "bell.and.waves.left.and.right.fill",
                            gradient: AppTheme.alarmGradient,
                            badgeText: statusBadgeText
                        )

                        visualCircularCounterCard
                        targetQuantityAndUnitCard
                        connectionScopeCard
                        smartAlertsSettingsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("منبّه الاستهلاك المخصص")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("تم") {
                        applyTypedValues()
                        isInputFocused = false
                    }
                }
            }
            .onAppear {
                syncTextFieldsFromState()
            }
        }
    }

    private var statusBadgeText: String {
        if !state.isRunning {
            return "متوقف"
        }
        return state.isPaused ? "إيقاف مؤقت" : "يعمل الآن"
    }

    // MARK: - 1. بطاقة العداد الدائري البصري وأزرار التحكم
    private var visualCircularCounterCard: some View {
        VStack(spacing: 18) {
            CircularUsageGaugeView(
                progress: state.progressRatio,
                warningRatio: state.warningPercentage / 100.0,
                centerPrimaryText: ByteFormatterUtil.formatBytes(state.consumedTotalBytes),
                centerSecondaryText: String(format: "%.1f%% من %@", state.progressPercentage, ByteFormatterUtil.formatBytes(state.targetBytes)),
                statusLabel: state.isRunning ? (state.isPaused ? "موقوف مؤقتاً" : "المستهلك حالياً (\(state.scope.shortArabicTitle))") : "جاهز للبدء",
                lineWidth: 20
            )
            .frame(width: 225, height: 225)
            .padding(.top, 6)

            // إحصائيات المتبقي والمستهلك
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("المستهلك حالياً")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(ByteFormatterUtil.formatBytes(state.consumedTotalBytes))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.secondaryCardBackground(colorScheme)))

                VStack(spacing: 4) {
                    Text(state.exceededBytes > 0 ? "تجاوز الحد بمقدار" : "المتبقي من الكمية")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(ByteFormatterUtil.formatBytes(state.exceededBytes > 0 ? state.exceededBytes : state.remainingBytes))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(state.exceededBytes > 0 ? AppTheme.dangerColor : AppTheme.downloadColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.secondaryCardBackground(colorScheme)))
            }

            HStack(spacing: 10) {
                DirectionMetricBadge(
                    label: "تحميل العداد ↓",
                    valueText: ByteFormatterUtil.formatBytes(state.consumedDownloadBytes),
                    isDownload: true
                )
                DirectionMetricBadge(
                    label: "رفع العداد ↑",
                    valueText: ByteFormatterUtil.formatBytes(state.consumedUploadBytes),
                    isDownload: false
                )
            }

            // أزرار التحكم: بدء / إيقاف مؤقت / تصفير وإعادة ضبط
            HStack(spacing: 10) {
                if !state.isRunning || state.isPaused {
                    Button {
                        applyTypedValues()
                        alarmManager.startCounter()
                        monitor.syncWidgetSummary(forceReload: true)
                    } label: {
                        Label(state.isPaused ? "استئناف العداد" : "بدء العداد", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundColor(.white)
                            .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.downloadColor))
                    }
                } else {
                    Button {
                        alarmManager.pauseCounter()
                        monitor.syncWidgetSummary(forceReload: true)
                    } label: {
                        Label("إيقاف مؤقت", systemImage: "pause.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundColor(.white)
                            .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.warningColor))
                    }
                }

                Button {
                    alarmManager.resetCounter()
                    monitor.syncWidgetSummary(forceReload: true)
                } label: {
                    Label("تصفير وإعادة ضبط", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .foregroundColor(AppTheme.dangerColor)
                        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.dangerColor.opacity(0.12)))
                }
            }
        }
        .modernCard()
    }

    // MARK: - 2. تحديد الكمية واختيار الوحدة بحرية (MB / GB)
    private var targetQuantityAndUnitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("تحديد الكمية ووحدة القياس", systemImage: "slider.horizontal.3")
                .font(.system(size: 15, weight: .bold))

            HStack(spacing: 10) {
                TextField("أدخل الرقم", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryCardBackground(colorScheme)))
                    .onChange(of: amountText) { newValue in
                        if let val = parseLocalizedDouble(newValue), val > 0 {
                            alarmManager.updateTarget(amount: val, unit: state.unit)
                        }
                    }

                Picker("الوحدة", selection: Binding(
                    get: { state.unit },
                    set: { newUnit in
                        let val = parseLocalizedDouble(amountText) ?? state.targetAmountInput
                        alarmManager.updateTarget(amount: val, unit: newUnit)
                    }
                )) {
                    ForEach(ExplicitDataUnit.allCases) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 125)
            }

            // أزرار سريعة للكميات الشائعة
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    presetAmountChip(100, .megabytes)
                    presetAmountChip(250, .megabytes)
                    presetAmountChip(500, .megabytes)
                    presetAmountChip(1, .gigabytes)
                    presetAmountChip(2, .gigabytes)
                    presetAmountChip(5, .gigabytes)
                    presetAmountChip(10, .gigabytes)
                }
            }
        }
        .modernCard()
    }

    private func presetAmountChip(_ val: Double, _ unit: ExplicitDataUnit) -> some View {
        let label = val == floor(val) ? "\(Int(val)) \(unit.rawValue)" : "\(val) \(unit.rawValue)"
        let isCurrent = (abs(state.targetAmountInput - val) < 0.01 && state.unit == unit)
        return Button {
            amountText = val == floor(val) ? "\(Int(val))" : "\(val)"
            alarmManager.updateTarget(amount: val, unit: unit)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundColor(isCurrent ? .white : .primary)
                .background(Capsule().fill(isCurrent ? AppTheme.wifiAccent : AppTheme.secondaryCardBackground(colorScheme)))
        }
    }

    // MARK: - 3. اختيار نوع الاتصال المراد مراقبته لهذا العداد
    private var connectionScopeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("نوع الاتصال المراقَب في هذا العداد", systemImage: "network")
                .font(.system(size: 15, weight: .bold))

            ForEach(MonitoredConnectionScope.allCases) { scope in
                let isSelected = (state.scope == scope)
                Button {
                    alarmManager.updateScope(scope)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: scope.iconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(isSelected ? .white : AppTheme.wifiAccent)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(isSelected ? AppTheme.wifiAccent : AppTheme.wifiAccent.opacity(0.12))
                            )

                        Text(scope.arabicTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(isSelected ? AppTheme.wifiAccent : .secondary.opacity(0.5))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? AppTheme.wifiAccent.opacity(0.10) : AppTheme.secondaryCardBackground(colorScheme))
                    )
                }
            }
        }
        .modernCard()
    }

    // MARK: - 4. نسبة التحذير المسبق وتكرار المنبّه عند التجاوز
    private var smartAlertsSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("إعدادات التحذير المسبق ومنبّه الـ 100%", systemImage: "bell.badge.fill")
                .font(.system(size: 15, weight: .bold))

            HStack {
                Text("نسبة التحذير المسبق:")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 4) {
                    TextField("80", text: $warningText)
                        .keyboardType(.numberPad)
                        .focused($isInputFocused)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 52)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.secondaryCardBackground(colorScheme)))
                        .onChange(of: warningText) { newVal in
                            if let v = parseLocalizedDouble(newVal), v >= 5 && v <= 99 {
                                alarmManager.updateWarningPercentage(v)
                            }
                        }
                    Text("%")
                        .font(.subheadline.weight(.bold))
                }
            }

            Slider(
                value: Binding(
                    get: { state.warningPercentage },
                    set: { newVal in
                        alarmManager.updateWarningPercentage(newVal)
                        warningText = "\(Int(newVal))"
                    }
                ),
                in: 10...95,
                step: 5
            )
            .tint(AppTheme.warningColor)

            HStack(spacing: 8) {
                ForEach([70, 80, 90], id: \.self) { pct in
                    Button("\(pct)%") {
                        warningText = "\(pct)"
                        alarmManager.updateWarningPercentage(Double(pct))
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(Int(state.warningPercentage) == pct ? .white : .primary)
                    .background(Capsule().fill(Int(state.warningPercentage) == pct ? AppTheme.warningColor : AppTheme.secondaryCardBackground(colorScheme)))
                }
                Spacer()
                Text("سيُنبهك عند: \(ByteFormatterUtil.formatBytes(Int64(Double(state.targetBytes) * state.warningPercentage / 100.0)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Toggle(isOn: Binding(
                get: { state.repeatAlertAfterFull },
                set: { enabled in
                    alarmManager.updateRepeatSettings(enabled: enabled, everyMB: state.repeatEveryMB)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("تكرار التنبيه العاجل إذا استمر السحب بعد 100%")
                        .font(.subheadline.weight(.semibold))
                    Text("يرسل تنبيهاً صوتياً متكرراً كل مقدار إضافي بعد انتهاء الكمية")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(AppTheme.dangerColor)

            if state.repeatAlertAfterFull {
                HStack {
                    Text("تكرار المنبّه كل سحب إضافي قدره:")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Picker("تكرار كل", selection: Binding(
                        get: { Int(state.repeatEveryMB) },
                        set: { newMB in
                            alarmManager.updateRepeatSettings(enabled: true, everyMB: Double(newMB))
                        }
                    )) {
                        Text("25 MB").tag(25)
                        Text("50 MB").tag(50)
                        Text("100 MB").tag(100)
                        Text("250 MB").tag(250)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .modernCard()
    }

    private func syncTextFieldsFromState() {
        let v = state.targetAmountInput
        amountText = v == floor(v) ? "\(Int(v))" : String(format: "%.2f", v)
        warningText = "\(Int(state.warningPercentage))"
    }

    private func applyTypedValues() {
        if let val = parseLocalizedDouble(amountText), val > 0 {
            alarmManager.updateTarget(amount: val, unit: state.unit)
        }
        if let warn = parseLocalizedDouble(warningText), warn >= 5 && warn <= 99 {
            alarmManager.updateWarningPercentage(warn)
        }
    }

    private func parseLocalizedDouble(_ str: String) -> Double? {
        let normalized = str
            .replacingOccurrences(of: "٫", with: ".")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }
}
