import SwiftUI

struct CounterAndHistoryView: View {
    @EnvironmentObject var monitor: NetworkMonitorService
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedFilter: HistoryFilterOption = .all
    @State private var displayMode: HistoryDisplayMode = .list
    @State private var selectedDateKeys: Set<String> = []
    @State private var summaryUnit: DataUnitPreference = .auto
    @State private var showRenameSheet: Bool = false
    @State private var showDateRangePicker: Bool = false
    @State private var rangeStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var rangeEndDate: Date = Date()
    @State private var calendarMonthDate: Date = Date()
    @State private var expandedDayKeys: Set<String> = []

    enum HistoryDisplayMode: String, CaseIterable, Identifiable {
        case list = "القائمة التفصيلية"
        case calendar = "التقويم التفاعلي"
        var id: String { rawValue }
    }

    // السجلات المفلترة حسب خيار المستخدم
    private var filteredRecords: [DailyUsageRecord] {
        switch selectedFilter {
        case .currentNetwork:
            let targetId = monitor.currentActiveNetworkIdForFilter
            return monitor.allDailyRecords.filter { $0.networkId == targetId }
        case .allWifi:
            return monitor.allDailyRecords.filter { $0.connectionType == .wifi }
        case .cellular:
            return monitor.allDailyRecords.filter { $0.connectionType == .cellular }
        case .all:
            return monitor.allDailyRecords
        }
    }

    // تجميع السجلات حسب اليوم الواحد لعدم تكرار احتساب اليوم الواحد في المتوسط اليومي
    private var dayGroups: [AggregatedDayGroup] {
        let grouped = Dictionary(grouping: filteredRecords, by: { $0.dateKey })
        return grouped.map { key, recs in
            AggregatedDayGroup(
                dateKey: key,
                date: ByteFormatterUtil.date(fromKey: key),
                records: recs.sorted { $0.totalBytes > $1.totalBytes }
            )
        }
        .sorted { $0.dateKey > $1.dateKey }
    }

    private var dayGroupsByKey: [String: AggregatedDayGroup] {
        Dictionary(uniqueKeysWithValues: dayGroups.map { ($0.dateKey, $0) })
    }

    // حساب ملخص الأيام المحددة للجمع
    private var selectedAggregation: (daysCount: Int, download: Int64, upload: Int64, total: Int64, dailyAverage: Int64) {
        let count = selectedDateKeys.count
        guard count > 0 else { return (0, 0, 0, 0, 0) }
        var down: Int64 = 0
        var up: Int64 = 0
        for key in selectedDateKeys {
            if let group = dayGroupsByKey[key] {
                down += group.downloadBytes
                up += group.uploadBytes
            }
        }
        let total = down + up
        let avg = total / Int64(max(1, count))
        return (count, down, up, total, avg)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.screenBackground(colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        liveNetworkCounterCard
                        todayQuickComparisonRow
                        filterAndSelectionToolbar

                        if showDateRangePicker {
                            connectedDateRangeCard
                        }

                        if displayMode == .calendar {
                            interactiveCalendarCard
                        } else {
                            dailyHistoryListSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, selectedDateKeys.count >= 2 ? 225 : 30)
                }

                // بطاقة ملخص الجمع الفوري بأسفل الشاشة فور تحديد يومين أو أكثر
                if selectedDateKeys.count >= 2 {
                    floatingAggregationSummaryCard
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedDateKeys.count)
            .navigationTitle("عدّاد الشبكة والسجل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showRenameSheet = true
                    } label: {
                        Label("تسمية الواي فاي", systemImage: "pencil.and.outline")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        monitor.pollOnce(forceWidgetReload: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                NetworkRenameSheet()
            }
        }
    }

    // MARK: - 1. بطاقة القياس الفعلي اللحظي
    private var liveNetworkCounterCard: some View {
        let todayCurrentTotal = monitor.todayCurrentNetworkDownload + monitor.todayCurrentNetworkUpload
        return VStack(spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: monitor.activeConnectionKind.systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.22)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(monitor.currentActiveDisplayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)

                        Text(monitor.activeConnectionKind == .wifi
                             ? "بوابة: \(monitor.gatewayIPAddress) • هاتفك: \(monitor.localIPAddress)"
                             : "حالة الاتصال: \(monitor.activeConnectionKind.arabicTitle)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.88))
                    }
                }

                Spacer()

                if monitor.activeConnectionKind == .wifi {
                    Button {
                        showRenameSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                            Text("تسمية")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                    }
                }
            }

            Divider().background(Color.white.opacity(0.25))

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("استهلاك اليوم على الشبكة الحالية")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))

                    Text(ByteFormatterUtil.formatBytes(todayCurrentTotal))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text(ByteFormatterUtil.formatSpeed(monitor.liveDownloadSpeedBps))
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text(ByteFormatterUtil.formatSpeed(monitor.liveUploadSpeedBps))
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.18)))
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("تحميل: \(ByteFormatterUtil.formatBytes(monitor.todayCurrentNetworkDownload))")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("رفع: \(ByteFormatterUtil.formatBytes(monitor.todayCurrentNetworkUpload))")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.14)))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.primaryGradient)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    // MARK: - 2. مقارنة اليوم السريعة بين كل الواي فاي وداتا الهاتف
    private var todayQuickComparisonRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi")
                        .foregroundColor(AppTheme.wifiAccent)
                    Text("واي فاي اليوم")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                }
                Text(ByteFormatterUtil.formatBytes(monitor.todayAllWifiDownload + monitor.todayAllWifiUpload))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text("↓ \(ByteFormatterUtil.formatBytes(monitor.todayAllWifiDownload)) • ↑ \(ByteFormatterUtil.formatBytes(monitor.todayAllWifiUpload))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modernCard(padding: 13)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(AppTheme.cellularAccent)
                    Text("داتا الهاتف اليوم")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                }
                Text(ByteFormatterUtil.formatBytes(monitor.todayCellularDownload + monitor.todayCellularUpload))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text("↓ \(ByteFormatterUtil.formatBytes(monitor.todayCellularDownload)) • ↑ \(ByteFormatterUtil.formatBytes(monitor.todayCellularUpload))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modernCard(padding: 13)
        }
    }

    // MARK: - 3. شريط الفلترة وأدوات التحديد المتعدد والجمع السريع
    private var filterAndSelectionToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("سجل الأيام السابقة والجمع المخصص")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Picker("العرض", selection: $displayMode) {
                    ForEach(HistoryDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 195)
            }

            // أزرار فلترة الشبكة
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HistoryFilterOption.allCases) { option in
                        let isSelected = (selectedFilter == option)
                        Button {
                            selectedFilter = option
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: option.iconName)
                                Text(option.arabicTitle)
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundColor(isSelected ? .white : .primary)
                            .background(
                                Capsule().fill(isSelected ? AppTheme.wifiAccent : AppTheme.secondaryCardBackground(colorScheme))
                            )
                        }
                    }
                }
            }

            Divider()

            // الأزرار السريعة لتحديد وجمع الأيام
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("اضغط على أي أيام متفرقة لجمعها أو اختر تحديداً سريعاً:", systemImage: "checkmark.circle.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !selectedDateKeys.isEmpty {
                        Text("محدد: \(selectedDateKeys.count) يوم")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.wifiAccent)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        quickSelectChip(title: "آخر 7 أيام", icon: "7.circle.fill") {
                            selectLastNDays(7)
                        }
                        quickSelectChip(title: "آخر 14 يوم", icon: "14.circle.fill") {
                            selectLastNDays(14)
                        }
                        quickSelectChip(title: "هذا الشهر", icon: "calendar") {
                            selectCurrentMonth()
                        }
                        quickSelectChip(title: "فترة من - إلى", icon: "calendar.badge.clock", isHighlighted: showDateRangePicker) {
                            withAnimation { showDateRangePicker.toggle() }
                        }
                        quickSelectChip(title: "تحديد الكل", icon: "checkmark.rectangle.stack.fill") {
                            selectedDateKeys = Set(dayGroups.map { $0.dateKey })
                        }
                        if !selectedDateKeys.isEmpty {
                            quickSelectChip(title: "إلغاء التحديد", icon: "xmark.circle.fill", isDestructive: true) {
                                selectedDateKeys.removeAll()
                            }
                        }
                    }
                }
            }
        }
        .modernCard()
    }

    private func quickSelectChip(
        title: String,
        icon: String,
        isHighlighted: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundColor(isDestructive ? AppTheme.dangerColor : (isHighlighted ? .white : .primary))
            .background(
                Capsule().fill(
                    isDestructive
                        ? AppTheme.dangerColor.opacity(0.12)
                        : (isHighlighted ? AppTheme.wifiAccent : AppTheme.secondaryCardBackground(colorScheme))
                )
            )
        }
    }

    // MARK: - 4. بطاقة اختيار فترة متصلة (من تاريخ إلى تاريخ)
    private var connectedDateRangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("تحديد فترة متصلة وجمعها", systemImage: "calendar.day.timeline.leading")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("إغلاق") {
                    withAnimation { showDateRangePicker = false }
                }
                .font(.caption.weight(.bold))
            }

            DatePicker("من تاريخ:", selection: $rangeStartDate, displayedComponents: .date)
                .environment(\.locale, ByteFormatterUtil.arabicLocale)
                .font(.subheadline)

            DatePicker("إلى تاريخ:", selection: $rangeEndDate, displayedComponents: .date)
                .environment(\.locale, ByteFormatterUtil.arabicLocale)
                .font(.subheadline)

            Button {
                selectedDateKeys = ByteFormatterUtil.dateKeysBetween(start: rangeStartDate, end: rangeEndDate)
            } label: {
                Label("تطبيق الفترة وحساب المجموع", systemImage: "sum")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .modernCard()
    }

    // MARK: - 5. التقويم الشهري التفاعلي لتحديد أيام متفرقة بحرية
    private var interactiveCalendarCard: some View {
        let calendar = gregorianArabicCalendar
        let daysInGrid = generateMonthGrid(for: calendarMonthDate, calendar: calendar)
        let weekdaySymbols = ["سبت", "أحد", "اثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة"]

        return VStack(spacing: 14) {
            HStack {
                Button {
                    if let prev = calendar.date(byAdding: .month, value: -1, to: calendarMonthDate) {
                        calendarMonthDate = prev
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppTheme.wifiAccent)
                }

                Spacer()
                Text(ByteFormatterUtil.arabicMonthYear(from: calendarMonthDate))
                    .font(.system(size: 16, weight: .bold))
                Spacer()

                Button {
                    if let next = calendar.date(byAdding: .month, value: 1, to: calendarMonthDate) {
                        calendarMonthDate = next
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppTheme.wifiAccent)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { dayTitle in
                    Text(dayTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }

                ForEach(Array(daysInGrid.enumerated()), id: \.offset) { _, optionalDate in
                    if let cellDate = optionalDate {
                        let key = ByteFormatterUtil.todayDateKey(for: cellDate)
                        let dayNum = calendar.component(.day, from: cellDate)
                        let isSelected = selectedDateKeys.contains(key)
                        let usageBytes = dayGroupsByKey[key]?.totalBytes ?? 0

                        Button {
                            toggleSelection(for: key)
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(dayNum)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .primary)

                                Text(usageBytes > 0 ? ByteFormatterUtil.formatBytes(usageBytes, decimals: 0) : "—")
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? .white.opacity(0.92) : (usageBytes > 0 ? AppTheme.downloadColor : .secondary))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? AppTheme.wifiAccent : AppTheme.secondaryCardBackground(colorScheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(key == ByteFormatterUtil.todayDateKey() ? AppTheme.wifiAccent : .clear, lineWidth: 1.5)
                            )
                        }
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }

            Text("اضغط على أي أيام متفرقة من التقويم (مثلاً: السبت + الثلاثاء + الخميس) وسيظهر مجموعها بالأسفل فوراً.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .modernCard()
    }

    // MARK: - 6. قائمة السجل اليومي مع التحديد المتعدد وتفصيل الشبكات
    private var dailyHistoryListSection: some View {
        VStack(spacing: 10) {
            if dayGroups.isEmpty {
                EmptyStateCardView(
                    icon: "tray.fill",
                    title: "لا توجد سجلات لهذا الفلتر بعد",
                    message: "سيتم حفظ استهلاكك اليومي تلقائياً وبشكل مستمر للواي فاي وبيانات الهاتف دون أن يتصفر عند إعادة تشغيل الآيفون."
                )
            } else {
                ForEach(dayGroups) { group in
                    let isSelected = selectedDateKeys.contains(group.dateKey)
                    let isExpanded = expandedDayKeys.contains(group.dateKey)

                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Button {
                                toggleSelection(for: group.dateKey)
                            } label: {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 23, weight: .semibold))
                                    .foregroundColor(isSelected ? AppTheme.wifiAccent : .secondary.opacity(0.6))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(ByteFormatterUtil.arabicFullDate(fromKey: group.dateKey))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.primary)

                                Text(group.networksSummary)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(ByteFormatterUtil.formatBytes(group.totalBytes))
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                                    .foregroundColor(isSelected ? AppTheme.wifiAccent : .primary)

                                HStack(spacing: 6) {
                                    Text("↓ \(ByteFormatterUtil.formatBytes(group.downloadBytes, decimals: 1))")
                                        .foregroundColor(AppTheme.downloadColor)
                                    Text("↑ \(ByteFormatterUtil.formatBytes(group.uploadBytes, decimals: 1))")
                                        .foregroundColor(AppTheme.uploadColor)
                                }
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            }

                            if group.records.count > 1 {
                                Button {
                                    toggleExpanded(for: group.dateKey)
                                } label: {
                                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(for: group.dateKey)
                        }

                        // تفصيل الشبكات داخل اليوم الواحد عند وجود أكثر من شبكة
                        if isExpanded && group.records.count > 1 {
                            Divider()
                            VStack(spacing: 6) {
                                ForEach(group.records) { rec in
                                    HStack {
                                        Image(systemName: rec.connectionType.systemImage)
                                            .font(.caption)
                                            .foregroundColor(rec.connectionType == .wifi ? AppTheme.wifiAccent : AppTheme.cellularAccent)
                                        Text(rec.networkName)
                                            .font(.caption.weight(.semibold))
                                        Spacer()
                                        Text("↓ \(ByteFormatterUtil.formatBytes(rec.downloadBytes, decimals: 1)) • ↑ \(ByteFormatterUtil.formatBytes(rec.uploadBytes, decimals: 1))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(ByteFormatterUtil.formatBytes(rec.totalBytes))
                                            .font(.caption.weight(.bold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.secondaryCardBackground(colorScheme)))
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isSelected ? AppTheme.wifiAccent.opacity(colorScheme == .dark ? 0.18 : 0.08) : AppTheme.cardBackground(colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? AppTheme.wifiAccent : AppTheme.cardBorder(colorScheme), lineWidth: isSelected ? 1.6 : 1)
                    )
                }
            }
        }
    }

    // MARK: - 7. بطاقة ملخص الجمع الفوري العائمة بأسفل الشاشة
    private var floatingAggregationSummaryCard: some View {
        let agg = selectedAggregation
        return VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sum")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(AppTheme.wifiAccent))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("ملخص جمع الأيام المحددة")
                            .font(.system(size: 13, weight: .bold))
                        Text("عدد الأيام المحددة: \(agg.daysCount) يوم • الفلتر: \(selectedFilter.arabicTitle)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Menu {
                    ForEach(DataUnitPreference.allCases) { u in
                        Button(u.arabicTitle) { summaryUnit = u }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(summaryUnit.rawValue == "auto" ? "تلقائي" : summaryUnit.rawValue)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.secondaryCardBackground(colorScheme)))
                }

                Button {
                    selectedDateKeys.removeAll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("المجموع الكلي")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(ByteFormatterUtil.formatBytes(agg.total, unit: summaryUnit))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(AppTheme.wifiAccent)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("المتوسط اليومي")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("\(ByteFormatterUtil.formatBytes(agg.dailyAverage, unit: summaryUnit)) / يوم")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }

            HStack(spacing: 10) {
                DirectionMetricBadge(
                    label: "مجموع التحميل ↓",
                    valueText: ByteFormatterUtil.formatBytes(agg.download, unit: summaryUnit),
                    isDownload: true
                )
                DirectionMetricBadge(
                    label: "مجموع الرفع ↑",
                    valueText: ByteFormatterUtil.formatBytes(agg.upload, unit: summaryUnit),
                    isDownload: false
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.cardBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.wifiAccent.opacity(0.45), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.14), radius: 16, x: 0, y: 6)
    }

    // MARK: - دوال المساعدة للتحديد والتقويم
    private func toggleSelection(for key: String) {
        if selectedDateKeys.contains(key) {
            selectedDateKeys.remove(key)
        } else {
            selectedDateKeys.insert(key)
        }
    }

    private func toggleExpanded(for key: String) {
        if expandedDayKeys.contains(key) {
            expandedDayKeys.remove(key)
        } else {
            expandedDayKeys.insert(key)
        }
    }

    private func selectLastNDays(_ n: Int) {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(n - 1), to: end) ?? end
        selectedDateKeys = ByteFormatterUtil.dateKeysBetween(start: start, end: end)
    }

    private func selectCurrentMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        let firstOfMonth = cal.date(from: comps) ?? now
        selectedDateKeys = ByteFormatterUtil.dateKeysBetween(start: firstOfMonth, end: now)
    }

    private var gregorianArabicCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = 7 // السبت بداية الأسبوع العربي
        return cal
    }

    private func generateMonthGrid(for monthDate: Date, calendar: Calendar) -> [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: monthDate)
        guard let firstOfMonth = calendar.date(from: comps),
              let daysRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        // تحويل الفهرس بحيث يبدأ الأسبوع يوم السبت (weekday == 7 -> offset 0)
        let leadingEmptyCount = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingEmptyCount)
        for day in daysRange {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(d)
            }
        }
        return cells
    }
}
