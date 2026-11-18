import SwiftUI

struct SpikeAlertView: View {
    @EnvironmentObject var spikeManager: SpikeAlertManager
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isInputFocused: Bool

    @State private var wifiMBText: String = "500"
    @State private var cellMBText: String = "100"

    private var settings: SpikeAlertSettings {
        spikeManager.settings
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.screenBackground(colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        SectionHeroBanner(
                            title: "جرس إنذار السحب المفاجئ",
                            subtitle: "حماية باقتك من التحديثات التلقائية بالخلفية أو الفيديوهات عالية الجودة مع سجل كامل للحوادث.",
                            systemImage: "bolt.trianglebadge.exclamationmark.fill",
                            gradient: AppTheme.alarmGradient,
                            badgeText: "\(spikeManager.incidents.count) حادثة"
                        )

                        wifiSpikeConfigCard
                        cellularSpikeConfigCard
                        incidentsHistoryCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("إنذار السحب المفاجئ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("تم") {
                        commitTypedThresholds()
                        isInputFocused = false
                    }
                }
            }
            .onAppear {
                wifiMBText = "\(Int(settings.wifiThresholdMB))"
                cellMBText = "\(Int(settings.cellularThresholdMB))"
            }
        }
    }

    // MARK: - 1. إعدادات إنذار الواي فاي
    private var wifiSpikeConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { settings.isWifiSpikeEnabled },
                set: { newVal in
                    var copy = settings
                    copy.isWifiSpikeEnabled = newVal
                    spikeManager.updateSettings(copy)
                }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundColor(AppTheme.wifiAccent)
                    Text("إنذار السحب المفاجئ للواي فاي")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .tint(AppTheme.wifiAccent)

            if settings.isWifiSpikeEnabled {
                HStack {
                    Text("حد السحب المفاجئ (MB):")
                        .font(.subheadline)
                    Spacer()
                    TextField("500", text: $wifiMBText)
                        .keyboardType(.numberPad)
                        .focused($isInputFocused)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 85)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.secondaryCardBackground(colorScheme)))
                        .onChange(of: wifiMBText) { val in
                            if let d = Double(val), d >= 10 {
                                var copy = settings
                                copy.wifiThresholdMB = d
                                spikeManager.updateSettings(copy)
                            }
                        }
                    Text("MB")
                        .font(.caption.weight(.bold))
                }

                Stepper(
                    "خلال مدة زمنية: \(settings.wifiWindowMinutes) دقيقة",
                    value: Binding(
                        get: { settings.wifiWindowMinutes },
                        set: { newMin in
                            var copy = settings
                            copy.wifiWindowMinutes = newMin
                            spikeManager.updateSettings(copy)
                        }
                    ),
                    in: 1...120
                )
                .font(.subheadline)

                HStack {
                    Text("المسحوب في آخر \(settings.wifiWindowMinutes) د:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(ByteFormatterUtil.formatBytes(spikeManager.currentWifiWindowBytes)) من \(Int(settings.wifiThresholdMB)) MB")
                        .font(.caption.weight(.bold))
                        .foregroundColor(AppTheme.wifiAccent)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.secondaryCardBackground(colorScheme)))
            }
        }
        .modernCard()
    }

    // MARK: - 2. إعدادات إنذار بيانات الهاتف
    private var cellularSpikeConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { settings.isCellularSpikeEnabled },
                set: { newVal in
                    var copy = settings
                    copy.isCellularSpikeEnabled = newVal
                    spikeManager.updateSettings(copy)
                }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(AppTheme.cellularAccent)
                    Text("إنذار السحب المفاجئ لداتا الهاتف")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .tint(AppTheme.cellularAccent)

            if settings.isCellularSpikeEnabled {
                HStack {
                    Text("حد السحب المفاجئ (MB):")
                        .font(.subheadline)
                    Spacer()
                    TextField("100", text: $cellMBText)
                        .keyboardType(.numberPad)
                        .focused($isInputFocused)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 85)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.secondaryCardBackground(colorScheme)))
                        .onChange(of: cellMBText) { val in
                            if let d = Double(val), d >= 5 {
                                var copy = settings
                                copy.cellularThresholdMB = d
                                spikeManager.updateSettings(copy)
                            }
                        }
                    Text("MB")
                        .font(.caption.weight(.bold))
                }

                Stepper(
                    "خلال مدة زمنية: \(settings.cellularWindowMinutes) دقيقة",
                    value: Binding(
                        get: { settings.cellularWindowMinutes },
                        set: { newMin in
                            var copy = settings
                            copy.cellularWindowMinutes = newMin
                            spikeManager.updateSettings(copy)
                        }
                    ),
                    in: 1...120
                )
                .font(.subheadline)

                HStack {
                    Text("المسحوب في آخر \(settings.cellularWindowMinutes) د:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(ByteFormatterUtil.formatBytes(spikeManager.currentCellularWindowBytes)) من \(Int(settings.cellularThresholdMB)) MB")
                        .font(.caption.weight(.bold))
                        .foregroundColor(AppTheme.cellularAccent)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.secondaryCardBackground(colorScheme)))
            }
        }
        .modernCard()
    }

    // MARK: - 3. سجل حوادث السحب المفاجئ
    private var incidentsHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("سجل حوادث السحب المفاجئ", systemImage: "list.bullet.clipboard.fill")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                if !spikeManager.incidents.isEmpty {
                    Button(role: .destructive) {
                        spikeManager.clearIncidentLog()
                    } label: {
                        Text("مسح السجل")
                            .font(.caption.weight(.bold))
                    }
                }
            }

            if spikeManager.incidents.isEmpty {
                EmptyStateCardView(
                    icon: "checkmark.shield.fill",
                    title: "لا توجد حوادث سحب مفاجئ مسجلة",
                    message: "وضع شبكتك مستقر. عند حدوث أي استنزاف يتجاوز الحدود المضبوطة أعلاه، سيصلك إشعار إنذار فوري ويُحفظ الحدث هنا."
                )
            } else {
                ForEach(spikeManager.incidents) { inc in
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.title3)
                            .foregroundColor(AppTheme.dangerColor)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(inc.networkName) (\(inc.connectionType.arabicTitle))")
                                .font(.system(size: 14, weight: .bold))
                            Text(ByteFormatterUtil.arabicDateTime(from: inc.timestamp))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("↓ \(ByteFormatterUtil.formatBytes(inc.downloadBytes)) • ↑ \(ByteFormatterUtil.formatBytes(inc.uploadBytes)) خلال \(inc.windowMinutes) د")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(ByteFormatterUtil.formatBytes(inc.bytesDelta))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(AppTheme.dangerColor)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.secondaryCardBackground(colorScheme)))
                }
            }
        }
        .modernCard()
    }

    private func commitTypedThresholds() {
        var copy = settings
        if let w = Double(wifiMBText), w >= 5 { copy.wifiThresholdMB = w }
        if let c = Double(cellMBText), c >= 5 { copy.cellularThresholdMB = c }
        spikeManager.updateSettings(copy)
    }
}
