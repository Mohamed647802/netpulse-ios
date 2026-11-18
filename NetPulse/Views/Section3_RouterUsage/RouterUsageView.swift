import SwiftUI

struct RouterUsageView: View {
    @EnvironmentObject var routerService: RouterUPnPService
    @EnvironmentObject var monitor: NetworkMonitorService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var comparisonMode: RouterComparisonMode = .todayTracked
    @State private var showManualSyncSheet: Bool = false
    @State private var showGatewayEditAlert: Bool = false
    @State private var gatewayInputText: String = ""

    // حقول المزامنة اليدوية المساندة
    @State private var manualDownText: String = ""
    @State private var manualUpText: String = ""
    @State private var manualUnit: ExplicitDataUnit = .gigabytes
    @State private var manualRouterName: String = ""

    enum RouterComparisonMode: String, CaseIterable, Identifiable {
        case todayTracked = "استهلاك اليوم"
        case routerSession = "إجمالي جلسة الراوتر"
        var id: String { rawValue }
    }

    private var iphoneTodayWifiBytes: Int64 {
        monitor.todayCurrentNetworkDownload + monitor.todayCurrentNetworkUpload
    }

    private var routerComparedBytes: Int64 {
        guard let snap = routerService.todaySnapshot else { return 0 }
        if snap.isManual {
            return max(snap.todayTotalBytes, iphoneTodayWifiBytes)
        }
        switch comparisonMode {
        case .todayTracked:
            // إذا كانت أول قراءة للتو (0 دلتا)، نستخدم إما المسجل اليوم أو نعرض القيمة الفعلية بما لا يقل عن سحب الهاتف
            return snap.todayTotalBytes > 0 ? max(snap.todayTotalBytes, iphoneTodayWifiBytes) : snap.rawSessionTotalBytes
        case .routerSession:
            return snap.rawSessionTotalBytes
        }
    }

    private var otherDevicesBytes: Int64 {
        max(0, routerComparedBytes - iphoneTodayWifiBytes)
    }

    private var iphoneSharePercentage: Double {
        guard routerComparedBytes > 0 else { return 0 }
        return min(100.0, (Double(iphoneTodayWifiBytes) / Double(routerComparedBytes)) * 100.0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.screenBackground(colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        SectionHeroBanner(
                            title: "استهلاك الراوتر والبيت بالكامل",
                            subtitle: "قراءة عداد الراوتر عبر UPnP ومقارنة سحب آيفونك اليوم بإجمالي كل الأجهزة المتصلة.",
                            systemImage: "wifi.router.fill",
                            gradient: AppTheme.routerGradient,
                            badgeText: routerService.effectiveGatewayIP
                        )

                        routerConnectionControlCard
                        comparisonVisualCard
                        routerDetailedCountersCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("استهلاك الراوتر بالكامل")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showManualSyncSheet) {
                manualRouterSyncSheet
            }
            .alert("تعديل عنوان البوابة (Gateway IP)", isPresented: $showGatewayEditAlert) {
                TextField("مثال: 192.168.1.1", text: $gatewayInputText)
                    .keyboardType(.numbersAndPunctuation)
                Button("حفظ") {
                    routerService.setCustomGatewayOverride(gatewayInputText)
                }
                Button("استخدام التلقائي") {
                    routerService.setCustomGatewayOverride("")
                }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("البوابة المكتشفة تلقائياً هي \(routerService.detectedGatewayIP). يمكنك كتابة عنوان مخصص إذا كان الراوتر يستخدم عنواناً آخر.")
            }
        }
    }

    // MARK: - 1. بطاقة الاتصال بالراوتر عبر UPnP وأدوات المزامنة
    private var routerConnectionControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routerService.routerFriendlyName)
                        .font(.system(size: 16, weight: .bold))
                    Text("عنوان الراوتر: \(routerService.effectiveGatewayIP) • المصدر: \(routerService.fetchMethod.rawValue)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    gatewayInputText = routerService.effectiveGatewayIP
                    showGatewayEditAlert = true
                } label: {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.title3)
                        .foregroundColor(AppTheme.wifiAccent)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await routerService.refreshRouterUsage()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if routerService.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "bolt.horizontal.circle.fill")
                        }
                        Text(routerService.isLoading ? "جارٍ القراءة..." : "قراءة الراوتر الآن (UPnP)")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.wifiAccent))
                }
                .disabled(routerService.isLoading)

                Button {
                    manualRouterName = routerService.routerFriendlyName
                    showManualSyncSheet = true
                } label: {
                    Label("مزامنة يدوية", systemImage: "square.and.pencil")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .foregroundColor(.primary)
                        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.secondaryCardBackground(colorScheme)))
                }
            }

            if let errorMsg = routerService.lastErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(AppTheme.warningColor)

                    Button {
                        if let url = URL(string: "http://\(routerService.effectiveGatewayIP)") {
                            openURL(url)
                        }
                    } label: {
                        Label("فتح صفحة إعدادات الراوتر (\(routerService.effectiveGatewayIP))", systemImage: "safari.fill")
                            .font(.caption.weight(.bold))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.warningColor.opacity(0.10)))
            } else {
                Text(routerService.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .modernCard()
    }

    // MARK: - 2. بطاقة المقارنة البصرية: آيفونك مقابل إجمالي البيت/الشبكة كله
    private var comparisonVisualCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("استهلاك آيفونك اليوم مقارنة بإجمالي الشبكة/البيت كله", systemImage: "chart.pie.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }

            if let snap = routerService.todaySnapshot, !snap.isManual {
                Picker("نطاق المقارنة", selection: $comparisonMode) {
                    ForEach(RouterComparisonMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            if routerComparedBytes > 0 {
                // النسبة المئوية البارزة
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(AppTheme.uploadColor.opacity(0.20), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: CGFloat(iphoneSharePercentage / 100.0))
                            .stroke(AppTheme.wifiAccent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f%%", iphoneSharePercentage))
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundColor(AppTheme.wifiAccent)
                            Text("حصتك")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 8) {
                        comparisonLegendRow(
                            color: AppTheme.wifiAccent,
                            title: "استهلاك آيفونك اليوم",
                            value: ByteFormatterUtil.formatBytes(iphoneTodayWifiBytes)
                        )
                        comparisonLegendRow(
                            color: AppTheme.uploadColor,
                            title: "باقي أجهزة البيت المتصلة",
                            value: ByteFormatterUtil.formatBytes(otherDevicesBytes)
                        )
                        Divider()
                        comparisonLegendRow(
                            color: AppTheme.downloadColor,
                            title: "إجمالي كل أجهزة الراوتر",
                            value: ByteFormatterUtil.formatBytes(routerComparedBytes),
                            isBold: true
                        )
                    }
                }
                .padding(.vertical, 4)

                // شريط التوزيع المقسّم
                GeometryReader { geo in
                    let totalWidth = max(1, geo.size.width)
                    let iphoneWidth = totalWidth * CGFloat(iphoneSharePercentage / 100.0)
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.wifiAccent)
                            .frame(width: max(6, iphoneWidth))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppTheme.uploadColor.opacity(0.45))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 12)
            } else {
                EmptyStateCardView(
                    icon: "wifi.router",
                    title: "بانتظار قراءة بيانات الراوتر",
                    message: "اضغط على (قراءة الراوتر الآن UPnP) أو استخدم (مزامنة يدوية) لعرض مقارنة استهلاك آيفونك بإجمالي استهلاك الشبكة المنزلية."
                )
            }
        }
        .modernCard()
    }

    private func comparisonLegendRow(color: Color, title: String, value: String, isBold: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.system(size: 12, weight: isBold ? .bold : .medium))
                .foregroundColor(isBold ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
    }

    // MARK: - 3. تفاصيل عدادات الراوتر الخام (GetTotalBytesReceived / Sent)
    private var routerDetailedCountersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("تفاصيل عدادات الراوتر (WAN Interface)", systemImage: "server.rack")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if routerService.todaySnapshot != nil {
                    Button("تصفير خط أساس اليوم") {
                        routerService.resetTodayBaselineToCurrent()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppTheme.wifiAccent)
                }
            }

            if let snap = routerService.todaySnapshot {
                HStack(spacing: 10) {
                    DirectionMetricBadge(
                        label: snap.isManual ? "تحميل الراوتر اليوم ↓" : "إجمالي المستلم Rx ↓",
                        valueText: ByteFormatterUtil.formatBytes(snap.isManual ? snap.accumulatedRx : snap.latestRx),
                        isDownload: true
                    )
                    DirectionMetricBadge(
                        label: snap.isManual ? "رفع الراوتر اليوم ↑" : "إجمالي المرسل Tx ↑",
                        valueText: ByteFormatterUtil.formatBytes(snap.isManual ? snap.accumulatedTx : snap.latestTx),
                        isDownload: false
                    )
                }

                Text("آخر تحديث لقراءة الراوتر: \(ByteFormatterUtil.arabicDateTime(from: snap.updatedAt))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("عند تفعيل بروتوكول UPnP في الراوتر، يجلب التطبيق القيم الحقيقية لدوال GetTotalBytesReceived و GetTotalBytesSent تلقائياً.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .modernCard()
    }

    // MARK: - نافذة المزامنة اليدوية المساندة
    private var manualRouterSyncSheet: some View {
        NavigationStack {
            Form {
                Section("بيانات الراوتر") {
                    TextField("اسم الراوتر (مثال: راوتر البيت WE)", text: $manualRouterName)

                    Picker("وحدة الإدخال", selection: $manualUnit) {
                        ForEach(ExplicitDataUnit.allCases) { u in
                            Text(u.arabicTitle).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("إجمالي تحميل الراوتر اليوم (\(manualUnit.rawValue))", text: $manualDownText)
                        .keyboardType(.decimalPad)

                    TextField("إجمالي رفع الراوتر اليوم - اختياري (\(manualUnit.rawValue))", text: $manualUpText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Button {
                        let dVal = Double(manualDownText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let uVal = Double(manualUpText.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let factor = (manualUnit == .gigabytes) ? 1024.0 : 1.0
                        routerService.saveManualRouterReading(
                            todayDownloadMB: dVal * factor,
                            todayUploadMB: uVal * factor,
                            customRouterTitle: manualRouterName
                        )
                        showManualSyncSheet = false
                    } label: {
                        Label("حفظ ومقارنة مع استهلاك الآيفون", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                } footer: {
                    Text("تُستخدم المزامنة اليدوية المساندة في حال كان الراوتر الخاص بمزود الخدمة يغلق بروتوكول UPnP من المصنع.")
                }
            }
            .navigationTitle("المزامنة اليدوية للراوتر")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { showManualSyncSheet = false }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
