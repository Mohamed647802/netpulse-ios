import Foundation
import Darwin

// MARK: - محلل ملف وصف UPnP XML الخاص بالراوتر
private final class UPnPDeviceXMLParser: NSObject, XMLParserDelegate {
    var friendlyName: String = ""
    var modelName: String = ""
    var manufacturer: String = ""
    var udn: String = ""
    var urlBase: String = ""
    var wanCommonControlURL: String?

    private var currentElement: String = ""
    private var currentText: String = ""
    private var insideService: Bool = false
    private var currentServiceType: String = ""
    private var currentControlURL: String = ""

    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let clean = elementName.components(separatedBy: ":").last ?? elementName
        currentElement = clean
        currentText = ""
        if clean.lowercased() == "service" {
            insideService = true
            currentServiceType = ""
            currentControlURL = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let clean = (elementName.components(separatedBy: ":").last ?? elementName).lowercased()
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if insideService {
            if clean == "servicetype" {
                currentServiceType = trimmed
            } else if clean == "controlurl" {
                currentControlURL = trimmed
            } else if clean == "service" {
                if currentServiceType.contains("WANCommonInterfaceConfig") && !currentControlURL.isEmpty {
                    wanCommonControlURL = currentControlURL
                }
                insideService = false
            }
        } else {
            switch clean {
            case "friendlyname":
                if friendlyName.isEmpty && !trimmed.isEmpty { friendlyName = trimmed }
            case "modelname":
                if modelName.isEmpty && !trimmed.isEmpty { modelName = trimmed }
            case "manufacturer":
                if manufacturer.isEmpty && !trimmed.isEmpty { manufacturer = trimmed }
            case "udn":
                if udn.isEmpty && !trimmed.isEmpty { udn = trimmed }
            case "urlbase":
                if urlBase.isEmpty && !trimmed.isEmpty { urlBase = trimmed }
            default:
                break
            }
        }
        currentText = ""
    }
}

@MainActor
final class RouterUPnPService: ObservableObject {
    static let shared = RouterUPnPService()

    @Published var detectedGatewayIP: String = "192.168.1.1"
    @Published var customGatewayOverride: String = ""
    @Published var routerFriendlyName: String = "الراوتر المنزلي"
    @Published var routerUDN: String = ""
    @Published var fetchMethod: RouterFetchMethod = .none
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "اضغط على تحديث لقراءة إحصائيات الراوتر عبر UPnP"
    @Published var lastErrorMessage: String? = nil
    @Published var todaySnapshot: RouterDailySnapshot? = nil

    private var cachedControlEndpoint: (gateway: String, controlURL: URL, serviceType: String)?

    private init() {
        if let savedOverride = AppGroupStorage.userDefaults.string(forKey: "netpulse.router.override.ip") {
            customGatewayOverride = savedOverride
        }
        loadCachedSnapshot()
    }

    var effectiveGatewayIP: String {
        let trimmed = customGatewayOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? detectedGatewayIP : trimmed
    }

    func updateDetectedGateway(_ ip: String?) {
        guard let ip, !ip.isEmpty else { return }
        if detectedGatewayIP != ip {
            detectedGatewayIP = ip
            loadCachedSnapshot()
        }
    }

    func setCustomGatewayOverride(_ ip: String) {
        customGatewayOverride = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        AppGroupStorage.userDefaults.set(customGatewayOverride, forKey: "netpulse.router.override.ip")
        cachedControlEndpoint = nil
        loadCachedSnapshot()
    }

    func loadCachedSnapshot() {
        let today = ByteFormatterUtil.todayDateKey()
        if let snap = DatabaseManager.shared.fetchRouterSnapshot(dateKey: today, gatewayIP: effectiveGatewayIP) {
            todaySnapshot = snap
            routerFriendlyName = snap.routerName
            if snap.isManual {
                fetchMethod = .manual
            } else if fetchMethod == .none {
                fetchMethod = .upnp
            }
        }
    }

    // MARK: - تحديث وقراءة استهلاك الراوتر الفعلي
    func refreshRouterUsage() async {
        guard !isLoading else { return }
        isLoading = true
        lastErrorMessage = nil
        statusMessage = "جارٍ البحث عن الراوتر والاتصال ببروتوكول UPnP..."

        let gateway = effectiveGatewayIP

        // 1. المحاولة عبر UPnP (SSDP + مسارات الوصف القياسية -> WANCommonInterfaceConfig)
        if let upnpResult = await queryViaUPnP(gatewayIP: gateway) {
            applyLiveRouterCounters(
                gatewayIP: gateway,
                routerName: upnpResult.routerName,
                udn: upnpResult.udn,
                totalRx: upnpResult.bytesReceived,
                totalTx: upnpResult.bytesSent,
                method: .upnp
            )
            statusMessage = "متصل بنجاح عبر UPnP • آخر تحديث الآن"
            isLoading = false
            return
        }

        // 2. المحاولة المساندة عبر واجهة إحصائيات الراوترات الشائعة (Huawei HiLink / CPE API)
        if let hilinkResult = await queryViaCommonRouterHTTP(gatewayIP: gateway) {
            applyLiveRouterCounters(
                gatewayIP: gateway,
                routerName: hilinkResult.routerName,
                udn: "",
                totalRx: hilinkResult.bytesReceived,
                totalTx: hilinkResult.bytesSent,
                method: .hilink
            )
            statusMessage = "تمت القراءة من واجهة إحصائيات الراوتر مباشرة"
            isLoading = false
            return
        }

        // 3. في حال كان UPnP مغلقاً من إعدادات الراوتر، نعرض رسالة واضحة مع إتاحة المزامنة اليدوية المساندة
        isLoading = false
        lastErrorMessage = "لم يستجب الراوتر (\(gateway)) لطلبات UPnP التلقائية. تأكد من تفعيل ميزة UPnP في صفحة إعدادات الراوتر، أو استخدم زر (المزامنة اليدوية المساندة) بالأسفل."
        statusMessage = "تعذرت القراءة التلقائية من \(gateway)"
    }

    // MARK: - المزامنة اليدوية المساندة (عند إغلاق UPnP في الراوتر)
    func saveManualRouterReading(
        todayDownloadMB: Double,
        todayUploadMB: Double,
        customRouterTitle: String? = nil
    ) {
        let today = ByteFormatterUtil.todayDateKey()
        let rxBytes = Int64(max(0, todayDownloadMB) * 1024.0 * 1024.0)
        let txBytes = Int64(max(0, todayUploadMB) * 1024.0 * 1024.0)
        let name = (customRouterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? routerFriendlyName

        let snapshot = RouterDailySnapshot(
            dateKey: today,
            gatewayIP: effectiveGatewayIP,
            routerName: name,
            baselineRx: 0,
            baselineTx: 0,
            latestRx: rxBytes,
            latestTx: txBytes,
            accumulatedRx: rxBytes,
            accumulatedTx: txBytes,
            isManual: true,
            updatedAt: Date().timeIntervalSince1970
        )

        DatabaseManager.shared.upsertRouterSnapshot(snapshot)
        self.todaySnapshot = snapshot
        self.routerFriendlyName = name
        self.fetchMethod = .manual
        self.lastErrorMessage = nil
        self.statusMessage = "تم حفظ المزامنة اليدوية لاستهلاك الراوتر اليوم"
    }

    /// تثبيت خط أساس اليوم الحالي من قراءة الراوتر الحالية لبدء العد من الصفر لليوم
    func resetTodayBaselineToCurrent() {
        guard var snap = todaySnapshot else { return }
        snap.baselineRx = snap.latestRx
        snap.baselineTx = snap.latestTx
        snap.accumulatedRx = 0
        snap.accumulatedTx = 0
        snap.updatedAt = Date().timeIntervalSince1970
        DatabaseManager.shared.upsertRouterSnapshot(snap)
        todaySnapshot = snap
    }

    private func applyLiveRouterCounters(
        gatewayIP: String,
        routerName: String,
        udn: String,
        totalRx: Int64,
        totalTx: Int64,
        method: RouterFetchMethod
    ) {
        let today = ByteFormatterUtil.todayDateKey()
        let now = Date().timeIntervalSince1970
        let cleanName = routerName.isEmpty ? "راوتر (\(gatewayIP))" : routerName

        self.routerFriendlyName = cleanName
        if !udn.isEmpty {
            self.routerUDN = udn
        }
        self.fetchMethod = method

        if var existing = DatabaseManager.shared.fetchRouterSnapshot(dateKey: today, gatewayIP: gatewayIP), !existing.isManual {
            let deltaRx = computeRouterCounterDelta(prev: existing.latestRx, curr: totalRx)
            let deltaTx = computeRouterCounterDelta(prev: existing.latestTx, curr: totalTx)

            existing.routerName = cleanName
            existing.latestRx = totalRx
            existing.latestTx = totalTx
            existing.accumulatedRx += deltaRx
            existing.accumulatedTx += deltaTx
            existing.updatedAt = now

            DatabaseManager.shared.upsertRouterSnapshot(existing)
            self.todaySnapshot = existing
        } else {
            // أول قراءة في هذا اليوم: إذا كانت جلسة الراوتر صغيرة (< 30GB) أو أول تزامن، نعتمد خط الأساس مع إتاحة عرض إجمالي الجلسة أيضاً
            let snap = RouterDailySnapshot(
                dateKey: today,
                gatewayIP: gatewayIP,
                routerName: cleanName,
                baselineRx: totalRx,
                baselineTx: totalTx,
                latestRx: totalRx,
                latestTx: totalTx,
                accumulatedRx: 0,
                accumulatedTx: 0,
                isManual: false,
                updatedAt: now
            )
            DatabaseManager.shared.upsertRouterSnapshot(snap)
            self.todaySnapshot = snap
        }
    }

    private func computeRouterCounterDelta(prev: Int64, curr: Int64) -> Int64 {
        if curr >= prev {
            return curr - prev
        }
        // معالجة التفاف عداد 32-بت في UPnP عند تخطي 4 جيجابايت
        let u32Max = Int64(UInt32.max)
        if prev > 3_000_000_000 && prev <= u32Max {
            return (u32Max - prev + 1) + curr
        }
        // في حال أُعيد تشغيل الراوتر، نضيف ما سُحب منذ إعادة التشغيل
        return max(0, curr)
    }

    // MARK: - تنفيذ استعلام UPnP الكامل (SSDP + XML + SOAP)
    private func queryViaUPnP(gatewayIP: String) async -> (routerName: String, udn: String, bytesReceived: Int64, bytesSent: Int64)? {
        // استخدام نقطة التحكم المخبأة إن كانت لنفس البوابة
        if let cached = cachedControlEndpoint, cached.gateway == gatewayIP {
            if let stats = await fetchWANCommonStats(controlURL: cached.controlURL, serviceType: cached.serviceType) {
                return (routerFriendlyName, routerUDN, stats.rx, stats.tx)
            }
        }

        // 1. جمع روابط وصف XML المحتملة من SSDP ومن المنافذ القياسية للبوابة
        var candidateURLs: [URL] = await discoverSSDPDescriptionURLs(gatewayIP: gatewayIP)

        let fallbackPaths = [
            "http://\(gatewayIP):1900/igd.xml",
            "http://\(gatewayIP):1900/rootDesc.xml",
            "http://\(gatewayIP):5000/rootDesc.xml",
            "http://\(gatewayIP):5000/igd.xml",
            "http://\(gatewayIP):49152/description.xml",
            "http://\(gatewayIP):49152/igd.xml",
            "http://\(gatewayIP):52869/picsdesc.xml",
            "http://\(gatewayIP):5431/dyndev/uuid:0000e068-20a0-00e0-20a0-48a8000808e0",
            "http://\(gatewayIP):37215/upnpdev.xml",
            "http://\(gatewayIP):2869/upnphost/udhisapi.dll?content=uuid:0001",
            "http://\(gatewayIP):80/rootDesc.xml",
            "http://\(gatewayIP):80/igd.xml"
        ]
        for str in fallbackPaths {
            if let u = URL(string: str), !candidateURLs.contains(u) {
                candidateURLs.append(u)
            }
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 2.2
        sessionConfig.timeoutIntervalForResource = 3.5
        let session = URLSession(configuration: sessionConfig)

        for descURL in candidateURLs {
            guard let (data, response) = try? await session.data(from: descURL),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty else {
                continue
            }

            let xmlParser = UPnPDeviceXMLParser()
            xmlParser.parse(data: data)

            guard let rawControlPath = xmlParser.wanCommonControlURL else {
                continue
            }

            let resolvedBase: URL = {
                if !xmlParser.urlBase.isEmpty, let b = URL(string: xmlParser.urlBase) {
                    return b
                }
                return descURL
            }()

            guard let controlURL = resolveControlURL(base: resolvedBase, path: rawControlPath) else {
                continue
            }

            let serviceType = "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1"
            if let stats = await fetchWANCommonStats(controlURL: controlURL, serviceType: serviceType) {
                let discoveredName = [xmlParser.friendlyName, xmlParser.modelName]
                    .first { !$0.isEmpty } ?? "راوتر (\(gatewayIP))"
                cachedControlEndpoint = (gatewayIP, controlURL, serviceType)
                if let host = descURL.host, !host.isEmpty && customGatewayOverride.isEmpty {
                    detectedGatewayIP = host
                }
                return (discoveredName, xmlParser.udn, stats.rx, stats.tx)
            }
        }

        return nil
    }

    private func resolveControlURL(base: URL, path: String) -> URL? {
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            return URL(string: path)
        }
        var comps = URLComponents()
        comps.scheme = base.scheme ?? "http"
        comps.host = base.host
        comps.port = base.port
        if path.hasPrefix("/") {
            comps.path = path
        } else {
            let baseDir = base.deletingLastPathComponent().path
            comps.path = baseDir.hasSuffix("/") ? "\(baseDir)\(path)" : "\(baseDir)/\(path)"
        }
        return comps.url
    }

    private func fetchWANCommonStats(controlURL: URL, serviceType: String) async -> (rx: Int64, tx: Int64)? {
        async let rxOpt = sendSOAPAction(
            controlURL: controlURL,
            serviceType: serviceType,
            action: "GetTotalBytesReceived",
            responseTag: "NewTotalBytesReceived"
        )
        async let txOpt = sendSOAPAction(
            controlURL: controlURL,
            serviceType: serviceType,
            action: "GetTotalBytesSent",
            responseTag: "NewTotalBytesSent"
        )

        let (rx, tx) = await (rxOpt, txOpt)
        guard let rxVal = rx, let txVal = tx else { return nil }
        return (rxVal, txVal)
    }

    private func sendSOAPAction(
        controlURL: URL,
        serviceType: String,
        action: String,
        responseTag: String
    ) async -> Int64? {
        var request = URLRequest(url: controlURL, timeoutInterval: 2.5)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPAction")

        let soapBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body>
                <u:\(action) xmlns:u="\(serviceType)"></u:\(action)>
            </s:Body>
        </s:Envelope>
        """
        request.httpBody = soapBody.data(using: .utf8)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        let session = URLSession(configuration: config)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let xmlText = String(data: data, encoding: .utf8) else {
            return nil
        }

        return extractXMLTagInt64(xml: xmlText, tag: responseTag)
    }

    // MARK: - اكتشاف SSDP عبر مقبس UDP (Multicast + Unicast Gateway)
    nonisolated private func discoverSSDPDescriptionURLs(gatewayIP: String) async -> [URL] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var discovered: [URL] = []
                let sock = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard sock >= 0 else {
                    continuation.resume(returning: [])
                    return
                }
                defer { Darwin.close(sock) }

                var timeout = timeval(tv_sec: 1, tv_usec: 500_000)
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

                let searchTargets = [
                    "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1",
                    "urn:schemas-upnp-org:device:InternetGatewayDevice:1"
                ]

                let destinations = ["239.255.255.250", gatewayIP]

                for dest in destinations {
                    for st in searchTargets {
                        let msg = "M-SEARCH * HTTP/1.1\r\nHOST: \(dest):1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: \(st)\r\n\r\n"
                        var addr = sockaddr_in()
                        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                        addr.sin_family = sa_family_t(AF_INET)
                        addr.sin_port = UInt16(1900).bigEndian
                        inet_pton(AF_INET, dest, &addr.sin_addr)

                        if let data = msg.data(using: .utf8) {
                            data.withUnsafeBytes { rawBuf in
                                guard let base = rawBuf.baseAddress else { return }
                                withUnsafePointer(to: &addr) { addrPtr in
                                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                                        _ = sendto(sock, base, data.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                                    }
                                }
                            }
                        }
                    }
                }

                let deadline = Date().addingTimeInterval(1.6)
                var buffer = [UInt8](repeating: 0, count: 4096)

                while Date() < deadline {
                    let bytesRead = recv(sock, &buffer, buffer.count - 1, 0)
                    if bytesRead <= 0 { break }
                    let responseStr = String(decoding: buffer.prefix(bytesRead), as: UTF8.self)
                    for line in responseStr.components(separatedBy: "\r\n") {
                        if line.lowercased().hasPrefix("location:") {
                            let value = line.dropFirst("location:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let url = URL(string: value), !discovered.contains(url) {
                                discovered.append(url)
                            }
                        }
                    }
                }

                continuation.resume(returning: discovered)
            }
        }
    }

    // MARK: - قراءة إحصائيات الراوترات الشائعة (Huawei HiLink / 4G & 5G CPE)
    private func queryViaCommonRouterHTTP(gatewayIP: String) async -> (routerName: String, bytesReceived: Int64, bytesSent: Int64)? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        let session = URLSession(configuration: config)

        // جلب ملف تعريف الجلسة إن لزم في راوترات HiLink
        if let tokURL = URL(string: "http://\(gatewayIP)/api/webserver/SesTokInfo") {
            _ = try? await session.data(from: tokURL)
        }

        guard let statsURL = URL(string: "http://\(gatewayIP)/api/monitoring/traffic-statistics"),
              let (data, response) = try? await session.data(from: statsURL),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let xml = String(data: data, encoding: .utf8) else {
            return nil
        }

        let rx = extractXMLTagInt64(xml: xml, tag: "TotalDownload") ?? extractXMLTagInt64(xml: xml, tag: "CurrentDownload")
        let tx = extractXMLTagInt64(xml: xml, tag: "TotalUpload") ?? extractXMLTagInt64(xml: xml, tag: "CurrentUpload")

        guard let rxVal = rx, let txVal = tx else { return nil }
        return ("راوتر المنزلي (\(gatewayIP))", rxVal, txVal)
    }

    nonisolated private func extractXMLTagInt64(xml: String, tag: String) -> Int64? {
        let pattern = "<(?:[a-zA-Z0-9_]+:)?\(NSRegularExpression.escapedPattern(for: tag))[^>]*>\\s*([0-9]+)\\s*</(?:[a-zA-Z0-9_]+:)?\(NSRegularExpression.escapedPattern(for: tag))>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range),
              match.numberOfRanges > 1,
              let valRange = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        if let u64 = UInt64(xml[valRange].trimmingCharacters(in: .whitespacesAndNewlines)) {
            return Int64(clamping: u64)
        }
        return nil
    }
}
