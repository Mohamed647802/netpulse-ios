import Foundation
import Darwin

struct SystemInterfaceReading {
    var bootTime: Int64
    var timestamp: TimeInterval

    // عدادات كل واجهة بشكل خام (en0, pdp_ip0 ... pdp_ip4)
    var rawCounters: [String: InterfaceCountersSnapshot.RawCounter]

    // معلومات الواي فاي المحلية (en0)
    var wifiIPv4: String?
    var wifiNetmask: String?
    var wifiSubnetCIDR: String?
    var probableGatewayIP: String?
    var alternateGatewayIP: String?
    var isWifiInterfaceUp: Bool

    // معلومات داتا الهاتف (pdp_ip0) للقسم السادس
    var hasActiveCellularIP: Bool
    var cellularIPAddress: String?
    var pdp0TotalRawBytes: UInt64
}

enum SystemNetworkReader {
    static let wifiInterfaceName = "en0"
    static let cellularInterfaceNames: Set<String> = [
        "pdp_ip0", "pdp_ip1", "pdp_ip2", "pdp_ip3", "pdp_ip4"
    ]

    /// قراءة وقت إقلاع النواة (kern.boottime) لحساب الدلتا بأمان عند عمل Restart للآيفون
    static func systemBootTimestamp() -> Int64 {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, 2, &boottime, &size, nil, 0) == 0 {
            return Int64(boottime.tv_sec)
        }
        return Int64(Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime)
    }

    /// قراءة عدادات الشبكة الحقيقية وحالة العناوين عبر getifaddrs()
    static func readCurrentState() -> SystemInterfaceReading {
        let bootTime = systemBootTimestamp()
        let now = Date().timeIntervalSince1970

        var rawCounters: [String: InterfaceCountersSnapshot.RawCounter] = [:]
        var wifiIPv4: String?
        var wifiNetmask: String?
        var wifiSubnetCIDR: String?
        var probableGatewayIP: String?
        var alternateGatewayIP: String?
        var isWifiUp = false

        var hasActiveCellularIP = false
        var cellularIPAddress: String?
        var pdp0TotalRawBytes: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return SystemInterfaceReading(
                bootTime: bootTime,
                timestamp: now,
                rawCounters: [:],
                wifiIPv4: nil,
                wifiNetmask: nil,
                wifiSubnetCIDR: nil,
                probableGatewayIP: nil,
                alternateGatewayIP: nil,
                isWifiInterfaceUp: false,
                hasActiveCellularIP: false,
                cellularIPAddress: nil,
                pdp0TotalRawBytes: 0
            )
        }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }

            guard let namePtr = ptr.pointee.ifa_name,
                  let addr = ptr.pointee.ifa_addr else {
                continue
            }

            let name = String(cString: namePtr)
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUpAndRunning = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            let family = addr.pointee.sa_family

            // 1. قراءة عدادات البايتات الحقيقية من طبقة AF_LINK
            if family == UInt8(AF_LINK) {
                if name == wifiInterfaceName || cellularInterfaceNames.contains(name) {
                    if let dataPtr = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                        let ibytes = dataPtr.pointee.ifi_ibytes
                        let obytes = dataPtr.pointee.ifi_obytes

                        if let existing = rawCounters[name] {
                            rawCounters[name] = InterfaceCountersSnapshot.RawCounter(
                                ibytes: existing.ibytes &+ ibytes,
                                obytes: existing.obytes &+ obytes
                            )
                        } else {
                            rawCounters[name] = InterfaceCountersSnapshot.RawCounter(
                                ibytes: ibytes,
                                obytes: obytes
                            )
                        }

                        if name == "pdp_ip0" {
                            pdp0TotalRawBytes = UInt64(ibytes) + UInt64(obytes)
                        }
                    }
                }
            }

            // 2. قراءة عنوان IPv4 وبصمة الشبكة المحلية لواجهة الواي فاي en0
            if name == wifiInterfaceName && isUpAndRunning {
                if family == UInt8(AF_INET) {
                    if let ipStr = numericAddressString(from: addr),
                       !ipStr.hasPrefix("169.254.") && !ipStr.hasPrefix("127.") {
                        wifiIPv4 = ipStr
                        isWifiUp = true

                        let ipHost = ipv4HostOrder(from: addr)
                        var maskHost: UInt32 = 0xFFFF_FF00
                        if let maskAddr = ptr.pointee.ifa_netmask,
                           maskAddr.pointee.sa_family == UInt8(AF_INET) {
                            wifiNetmask = numericAddressString(from: maskAddr)
                            let extractedMask = ipv4HostOrder(from: maskAddr)
                            if extractedMask != 0 {
                                maskHost = extractedMask
                            }
                        }

                        let networkAddr = ipHost & maskHost
                        let prefixLen = maskHost.nonzeroBitCount
                        wifiSubnetCIDR = "\(ipv4String(fromHostOrder: networkAddr))/\(prefixLen)"

                        let gw1 = networkAddr | 1
                        probableGatewayIP = ipv4String(fromHostOrder: gw1)

                        let hostMask = ~maskHost
                        if hostMask > 2 {
                            let gw254 = networkAddr | (hostMask - 1)
                            alternateGatewayIP = ipv4String(fromHostOrder: gw254)
                        }
                    }
                }
            }

            // 3. فحص وجود عنوان IP فعّال على واجهة بيانات الهاتف pdp_ip0
            if name == "pdp_ip0" && isUpAndRunning {
                if family == UInt8(AF_INET) {
                    if let ip = numericAddressString(from: addr),
                       !ip.isEmpty && ip != "0.0.0.0" && !ip.hasPrefix("127.") {
                        hasActiveCellularIP = true
                        cellularIPAddress = ip
                    }
                } else if family == UInt8(AF_INET6) {
                    if let ip6 = numericAddressString(from: addr),
                       !ip6.isEmpty && !ip6.lowercased().hasPrefix("fe80") && ip6 != "::1" {
                        hasActiveCellularIP = true
                        if cellularIPAddress == nil {
                            cellularIPAddress = ip6
                        }
                    }
                }
            }
        }

        return SystemInterfaceReading(
            bootTime: bootTime,
            timestamp: now,
            rawCounters: rawCounters,
            wifiIPv4: wifiIPv4,
            wifiNetmask: wifiNetmask,
            wifiSubnetCIDR: wifiSubnetCIDR,
            probableGatewayIP: probableGatewayIP,
            alternateGatewayIP: alternateGatewayIP,
            isWifiInterfaceUp: isWifiUp,
            hasActiveCellularIP: hasActiveCellularIP,
            cellularIPAddress: cellularIPAddress,
            pdp0TotalRawBytes: pdp0TotalRawBytes
        )
    }

    /// حساب الدلتا بأمان مع معالجة التفاف UInt32 (عند 4GB) ومعالجة إعادة تشغيل الهاتف (Reboot-Safe Delta)
    static func computeSafeDelta(
        previous: InterfaceCountersSnapshot?,
        currentReading: SystemInterfaceReading
    ) -> (
        wifiDownloadDelta: Int64,
        wifiUploadDelta: Int64,
        cellularDownloadDelta: Int64,
        cellularUploadDelta: Int64,
        newSnapshot: InterfaceCountersSnapshot,
        didRebootOccur: Bool
    ) {
        let newSnapshot = InterfaceCountersSnapshot(
            bootTime: currentReading.bootTime,
            timestamp: currentReading.timestamp,
            interfaces: currentReading.rawCounters
        )

        // أول تشغيل على الإطلاق: نحفظ خط الأساس بدون إضافة استهلاك الأيام السابقة ليوم التثبيت
        guard let previous else {
            return (0, 0, 0, 0, newSnapshot, false)
        }

        // السماح بهامش 5 ثوانٍ في kern.boottime لتعديلات مزامنة الوقت NTP
        let didReboot = abs(currentReading.bootTime - previous.bootTime) > 5

        var wifiIn: UInt64 = 0
        var wifiOut: UInt64 = 0
        var cellIn: UInt64 = 0
        var cellOut: UInt64 = 0

        let allNames = Set(previous.interfaces.keys).union(currentReading.rawCounters.keys)

        for name in allNames {
            guard let curr = currentReading.rawCounters[name] else {
                continue
            }

            let dIn: UInt64
            let dOut: UInt64

            if didReboot {
                // بعد إعادة تشغيل الهاتف تبدأ عدادات النواة من الصفر، فنضيف كل ما استُهلك منذ الإقلاع الجديد دون المساس بسجل اليوم المحفوظ
                dIn = UInt64(curr.ibytes)
                dOut = UInt64(curr.obytes)
            } else if let prev = previous.interfaces[name] {
                dIn = singleCounterDelta(prev: prev.ibytes, curr: curr.ibytes)
                dOut = singleCounterDelta(prev: prev.obytes, curr: curr.obytes)
            } else {
                dIn = UInt64(curr.ibytes)
                dOut = UInt64(curr.obytes)
            }

            if name == wifiInterfaceName {
                wifiIn += dIn
                wifiOut += dOut
            } else if cellularInterfaceNames.contains(name) {
                cellIn += dIn
                cellOut += dOut
            }
        }

        return (
            Int64(clamping: wifiIn),
            Int64(clamping: wifiOut),
            Int64(clamping: cellIn),
            Int64(clamping: cellOut),
            newSnapshot,
            didReboot
        )
    }

    private static func singleCounterDelta(prev: UInt32, curr: UInt32) -> UInt64 {
        if curr >= prev {
            return UInt64(curr - prev)
        }
        // إذا كان العداد السابق قريباً من سقف UInt32.max (أكبر من 3GB) فهذا التفاف 4GB طبيعي
        if prev > 0xC000_0000 {
            return (UInt64(UInt32.max) - UInt64(prev) + 1) + UInt64(curr)
        }
        // أما إذا أعادت واجهة نفق الخلوي تصفير نفسها، نأخذ القراءة الجديدة منذ التصفير
        return UInt64(curr)
    }

    private static func numericAddressString(from addr: UnsafePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = socklen_t(addr.pointee.sa_len)
        guard getnameinfo(addr, len, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        let raw = String(cString: buffer)
        // إزالة لاحقة النطاق مثل %pdp_ip0 في عناوين IPv6 إن وجدت
        if let percentIdx = raw.firstIndex(of: "%") {
            return String(raw[..<percentIdx])
        }
        return raw
    }

    private static func ipv4HostOrder(from addr: UnsafePointer<sockaddr>) -> UInt32 {
        addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sinPtr in
            UInt32(bigEndian: sinPtr.pointee.sin_addr.s_addr)
        }
    }

    private static func ipv4String(fromHostOrder ip: UInt32) -> String {
        let b1 = (ip >> 24) & 0xFF
        let b2 = (ip >> 16) & 0xFF
        let b3 = (ip >> 8) & 0xFF
        let b4 = ip & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }
}
