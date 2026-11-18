import SwiftUI

struct DualConnectionGuardView: View {
    @EnvironmentObject var guardManager: DualConnectionGuardManager
    @EnvironmentObject var monitor: NetworkMonitorService
    @Environment(\.colorScheme) private var colorScheme

    private var settings: DualConnectionGuardSettings {
        guardManager.settings
    }

    private var wifiProfiles: [SavedNetworkProfile] {
        monitor.savedNetworkProfiles.filter { $0.connectionType == .wifi }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.screenBackground(colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        SectionHeroBanner(
                            title: "حارس الداتا و Wi-Fi Assist",
                            subtitle: "رصد فوري لبقاء زر الداتا مفتوحاً مع الواي فاي ومراقبة السحب الخفي على pdp_ip0.",
                            systemImage: "shield.lefthalf.filled.badge.checkmark",
                            gradient: guardManager.isDualActiveNow ? AppTheme.alarmGradient : AppTheme.primaryGradient,
                            badgeText: guardManager.isDualActiveNow ? "الداتا مفتوحة!" : "آمن"
                        )

                        liveDualMonitorsCard
                        guardConfigurationCard
                        perNetworkCustomizationCard
                        dualGuardLogCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("حارس الداتا مع الواي فاي")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 1. لوحة الرصد الحي للمراقبَين المنفصلين و pdp_ip0
    private var liveDualMonitorsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: guardManager.isDualActiveNow ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundColor(guardManager.isDualActiveNow ? AppTheme.dangerColor : AppTheme.downloadColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(guardManager.isDualActiveNow
                         ? "تنبيه: الواي فاي وداتا الهاتف مفتوحان في نفس اللحظة!"
                         : "وضع الاتصال آمن حالياً")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(guardManager.isDualActiveNow ? AppTheme.dangerColor : .primary)

                    Text(guardManager.isDualActiveNow
                         ? "يُنصح بإغلاق زر بيانات الهاتف من مركز التحكم لمنع ميزة Wi-Fi Assist من سحب باقتك."
                         : "لا يوجد تداخل نشط بين الواي فاي وبيانات الهاتف الآن.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(guardManager.isWifiPathSatisfied ? AppTheme.wifiAccent : Color.gray)
                            .frame(width: 8, height: 8)
                        Text("مراقب الواي فاي")
                            .font(.caption.weight(.bold))
                    }
                    Text(guardManager.isWifiPathSatisfied ? "متصل (\(monitor.currentWifiNetworkName))" : "غير متصل")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryCardBackground(colorScheme)))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill((guardManager.isCellularPathSatisfied || guardManager.hasPdp0IPAddress) ? AppTheme.warningColor : AppTheme.downloadColor)
                            .frame(width: 8, height: 8)
                        Text("واجهة pdp_ip0 للداتا")
                            .font(.caption.weight(.bold))
                    }
                    Text((guardManager.isCellularPathSatisfied || guardManager.hasPdp0IPAddress)
                         ? "مفتوحة (\(guardManager.pdp0IPString ?? "نشط"))"
                         : "مغلقة بأمان")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryCardBackground(colorScheme)))
            }

            // عداد تسرب Wi-Fi Assist في الجلسة الحالية
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("السحب الخفي من الداتا أثناء اتصال الواي فاي الحالي:")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(ByteFormatterUtil.formatBytes(guardManager.currentSessionLeakedBytes))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(guardManager.currentSessionLeakedBytes > 0 ? AppTheme.dangerColor : AppTheme.downloadColor)
                }
                Spacer()
                if guardManager.currentSessionLeakedBytes > 0 {
                    Button("تصفير الجلسة") {
                        guardManager.resetSessionCounterManually()
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryCardBackground(colorScheme)))
        }
        .modernCard()
    }

    // MARK: - 2. إعدادات منبّه النسيان وحارس Wi-Fi Assist
    private var guardConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("إعدادات المنبّه وحساسية الرصد", systemImage: "gearshape.2.fill")
                .font(.system(size: 15, weight: .bold))

            Toggle(isOn: Binding(
                get: { settings.isDualAlertEnabled },
                set: { val in
                    var copy = settings
                    copy.isDualAlertEnabled = val
                    guardManager.updateSettings(copy)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("إشعار فوري عند بقاء الداتا مفتوحة مع الواي فاي")
                        .font(.subheadline.weight(.semibold))
                    Text("يُذكّرك بإغلاق زر الداتا فور اتصالك بشبكة واي فاي")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(AppTheme.wifiAccent)

            if settings.isDualAlertEnabled {
                Stepper(
                    "إعادة التذكير إذا ظلت مفتوحة كل: \(settings.reminderCooldownMinutes) د",
                    value: Binding(
                        get: { settings.reminderCooldownMinutes },
                        set: { mins in
                            var copy = settings
                            copy.reminderCooldownMinutes = mins
                            guardManager.updateSettings(copy)
                        }
                    ),
                    in: 5...180,
                    step: 5
                )
                .font(.caption.weight(.semibold))
            }

            Divider()

            Toggle(isOn: Binding(
                get: { settings.isWifiAssistGuardEnabled },
                set: { val in
                    var copy = settings
                    copy.isWifiAssistGuardEnabled = val
                    guardManager.updateSettings(copy)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("حارس Wi-Fi Assist (رصد سحب pdp_ip0 الخفي)")
                        .font(.subheadline.weight(.semibold))
                    Text("يُرسل إنذاراً إضافياً إذا سحب الآيفون بيانات فعلية من الداتا رغم اتصال الواي فاي")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(AppTheme.dangerColor)

            if settings.isWifiAssistGuardEnabled {
                HStack {
                    Text("التنبيه عند سحب خفي قدره:")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Picker("حساسية التسرب", selection: Binding(
                        get: { settings.wifiAssistThresholdMB },
                        set: { mb in
                            var copy = settings
                            copy.wifiAssistThresholdMB = mb
                            guardManager.updateSettings(copy)
                        }
                    )) {
                        Text("0.5 MB").tag(0.5)
                        Text("1 MB").tag(1.0)
                        Text("2 MB").tag(2.0)
                        Text("5 MB").tag(5.0)
                        Text("10 MB").tag(10.0)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .modernCard()
    }

    // MARK: - 3. تخصيص المنبّه لشبكات معينة
    private var perNetworkCustomizationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("تخصيص الشبكات المشمولة بالحارس", systemImage: "wifi.circle.fill")
                .font(.system(size: 15, weight: .bold))

            Picker("نطاق التفعيل", selection: Binding(
                get: { settings.ruleMode },
                set: { mode in
                    var copy = settings
                    copy.ruleMode = mode
                    guardManager.updateSettings(copy)
                }
            )) {
                ForEach(DualGuardNetworkRuleMode.allCases) { mode in
                    Text(mode.arabicTitle).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if settings.ruleMode != .allNetworks {
                if wifiProfiles.isEmpty {
                    Text("لا توجد شبكات واي فاي محفوظة بعد.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(wifiProfiles) { profile in
                        let isChecked = settings.targetNetworkIds.contains(profile.networkId)
                        Button {
                            var copy = settings
                            if isChecked {
                                copy.targetNetworkIds.removeAll { $0 == profile.networkId }
                            } else {
                                copy.targetNetworkIds.append(profile.networkId)
                            }
                            guardManager.updateSettings(copy)
                        } label: {
                            HStack {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isChecked ? AppTheme.wifiAccent : .secondary)
                                Text(profile.customName)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .modernCard()
    }

    // MARK: - 4. سجل أحداث الحارس
    private var dualGuardLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("سجل تنبيهات الحارس و Wi-Fi Assist", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                if !guardManager.events.isEmpty {
                    Button(role: .destructive) {
                        guardManager.clearEvents()
                    } label: {
                        Text("مسح السجل")
                            .font(.caption.weight(.bold))
                    }
                }
            }

            if guardManager.events.isEmpty {
                EmptyStateCardView(
                    icon: "shield.checkered",
                    title: "السجل نظيف تماماً",
                    message: "لم يتم تسجيل أي تسرب لبيانات الهاتف أثناء الاتصال بالواي فاي."
                )
            } else {
                ForEach(guardManager.events) { ev in
                    HStack(spacing: 10) {
                        Image(systemName: ev.eventType == .wifiAssistLeak ? "flame.fill" : "wifi.exclamationmark")
                            .foregroundColor(ev.eventType == .wifiAssistLeak ? AppTheme.dangerColor : AppTheme.warningColor)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(ev.eventType.arabicTitle)
                                .font(.system(size: 13, weight: .bold))
                            Text("أثناء الاتصال بـ: \(ev.wifiNetworkName) • \(ByteFormatterUtil.arabicDateTime(from: ev.timestamp))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if ev.leakedBytes > 0 {
                            Text(ByteFormatterUtil.formatBytes(ev.leakedBytes))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(AppTheme.dangerColor)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryCardBackground(colorScheme)))
                }
            }
        }
        .modernCard()
    }
}
