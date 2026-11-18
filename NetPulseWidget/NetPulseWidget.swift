import WidgetKit
import SwiftUI

struct NetPulseTimelineEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSharedSummary
}

struct NetPulseTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetPulseTimelineEntry {
        NetPulseTimelineEntry(date: Date(), summary: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NetPulseTimelineEntry) -> Void) {
        let summary = AppGroupStorage.loadWidgetSummary() ?? .placeholder
        completion(NetPulseTimelineEntry(date: Date(), summary: summary))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetPulseTimelineEntry>) -> Void) {
        let summary = AppGroupStorage.loadWidgetSummary() ?? WidgetSharedSummary(
            updatedAt: Date().timeIntervalSince1970,
            activeNetworkName: "بانتظار فتح التطبيق",
            activeConnectionKind: .wifi,
            todayWifiDownload: 0,
            todayWifiUpload: 0,
            todayCellularDownload: 0,
            todayCellularUpload: 0,
            customAlarmActive: false,
            customAlarmConsumedBytes: 0,
            customAlarmTargetBytes: 1,
            primaryQuotaName: nil,
            primaryQuotaRemainingBytes: nil,
            primaryQuotaTotalBytes: nil,
            isDualWifiCellularActive: false
        )

        let entry = NetPulseTimelineEntry(date: Date(), summary: summary)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct NetPulseWidgetEntryView: View {
    var entry: NetPulseTimelineProvider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallWidgetView
            case .accessoryRectangular:
                lockScreenRectangularView
            default:
                mediumWidgetView
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetCardBackground(
            colorScheme == .dark
                ? Color(red: 0.08, green: 0.11, blue: 0.17)
                : Color.white
        )
    }

    private var smallWidgetView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: entry.summary.activeConnectionKind.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.blue)
                Text(entry.summary.activeNetworkName)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("إجمالي اليوم")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            Text(ByteFormatterUtil.formatBytes(entry.summary.todayGrandTotal))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Divider()

            HStack {
                Label(ByteFormatterUtil.formatBytes(entry.summary.todayWifiTotal, decimals: 1), systemImage: "wifi")
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
            }
            HStack {
                Label(ByteFormatterUtil.formatBytes(entry.summary.todayCellularTotal, decimals: 1), systemImage: "cellularbars")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.green)
                    .lineLimit(1)
                Spacer(minLength: 2)
            }
        }
        .padding(12)
    }

    private var mediumWidgetView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: entry.summary.activeConnectionKind.systemImage)
                        .foregroundColor(.blue)
                    Text(entry.summary.activeNetworkName)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                }

                Text(ByteFormatterUtil.formatBytes(entry.summary.todayGrandTotal))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))

                HStack(spacing: 10) {
                    Text("واي فاي: \(ByteFormatterUtil.formatBytes(entry.summary.todayWifiTotal, decimals: 1))")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("داتا: \(ByteFormatterUtil.formatBytes(entry.summary.todayCellularTotal, decimals: 1))")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.green)
                }

                if entry.summary.isDualWifiCellularActive {
                    Text("⚠️ الداتا مفتوحة مع الواي فاي!")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                if entry.summary.customAlarmActive {
                    let ratio = min(1.0, Double(entry.summary.customAlarmConsumedBytes) / Double(max(1, entry.summary.customAlarmTargetBytes)))
                    Text("منبّه الكمية: \(Int(ratio * 100))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                    Text("\(ByteFormatterUtil.formatBytes(entry.summary.customAlarmConsumedBytes, decimals: 1)) / \(ByteFormatterUtil.formatBytes(entry.summary.customAlarmTargetBytes, decimals: 1))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                } else if let qName = entry.summary.primaryQuotaName,
                          let qRem = entry.summary.primaryQuotaRemainingBytes {
                    Text("باقة \(qName)")
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                    Text("المتبقي: \(ByteFormatterUtil.formatBytes(qRem))")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.blue)
                } else {
                    Text("نبض البيانات")
                        .font(.system(size: 11, weight: .bold))
                    Text("افتح التطبيق لإعداد الباقات والمنبّه")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 125, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
        }
        .padding(14)
    }

    private var lockScreenRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("نبض البيانات • \(entry.summary.activeNetworkName)")
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
            Text("واي فاي: \(ByteFormatterUtil.formatBytes(entry.summary.todayWifiTotal, decimals: 1))")
                .font(.system(size: 11))
            Text("داتا: \(ByteFormatterUtil.formatBytes(entry.summary.todayCellularTotal, decimals: 1))")
                .font(.system(size: 11))
        }
    }
}

private extension View {
    @ViewBuilder
    func widgetCardBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                color
            }
        } else {
            self.background(color)
        }
    }
}

@main
struct NetPulseWidget: Widget {
    let kind: String = "NetPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetPulseTimelineProvider()) { entry in
            NetPulseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("عدّاد نبض البيانات")
        .description("يعرض استهلاك اليوم للواي فاي وبيانات الهاتف وحالة المنبّه والباقة باللغة العربية.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
