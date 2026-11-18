import Foundation
import SQLite3

private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.netpulse.sqlite.queue", qos: .userInitiated)

    private init() {
        queue.sync {
            openDatabase()
            createTablesIfNeeded()
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        let path = AppGroupStorage.databaseFileURL.path
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
            executeRawSQL("PRAGMA journal_mode = WAL;")
            executeRawSQL("PRAGMA synchronous = NORMAL;")
        }
    }

    private func executeRawSQL(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func createTablesIfNeeded() {
        let schema = """
        CREATE TABLE IF NOT EXISTS daily_usage (
            id TEXT PRIMARY KEY,
            date_key TEXT NOT NULL,
            network_id TEXT NOT NULL,
            network_name TEXT NOT NULL,
            connection_type TEXT NOT NULL,
            download_bytes INTEGER NOT NULL DEFAULT 0,
            upload_bytes INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_daily_usage_date ON daily_usage(date_key);
        CREATE INDEX IF NOT EXISTS idx_daily_usage_network ON daily_usage(network_id);

        CREATE TABLE IF NOT EXISTS network_profiles (
            network_id TEXT PRIMARY KEY,
            custom_name TEXT NOT NULL,
            connection_type TEXT NOT NULL,
            gateway_ip TEXT NOT NULL DEFAULT '',
            subnet TEXT NOT NULL DEFAULT '',
            upnp_udn TEXT NOT NULL DEFAULT '',
            router_name TEXT NOT NULL DEFAULT '',
            last_seen_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS network_quotas (
            id TEXT PRIMARY KEY,
            network_id TEXT NOT NULL UNIQUE,
            network_name TEXT NOT NULL,
            connection_type TEXT NOT NULL,
            quota_bytes INTEGER NOT NULL,
            renewal_day INTEGER NOT NULL,
            used_offset_bytes INTEGER NOT NULL DEFAULT 0,
            daily_overage_alert_enabled INTEGER NOT NULL DEFAULT 1,
            warning_percent REAL NOT NULL DEFAULT 80.0,
            last_alert_cycle_key TEXT,
            last_daily_alert_date TEXT,
            is_enabled INTEGER NOT NULL DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS spike_events (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            network_id TEXT NOT NULL,
            network_name TEXT NOT NULL,
            connection_type TEXT NOT NULL,
            bytes_delta INTEGER NOT NULL,
            window_minutes INTEGER NOT NULL,
            download_bytes INTEGER NOT NULL,
            upload_bytes INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS dual_guard_events (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            wifi_network_name TEXT NOT NULL,
            event_type TEXT NOT NULL,
            leaked_bytes INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS router_snapshots (
            date_key TEXT NOT NULL,
            gateway_ip TEXT NOT NULL,
            router_name TEXT NOT NULL,
            baseline_rx INTEGER NOT NULL,
            baseline_tx INTEGER NOT NULL,
            latest_rx INTEGER NOT NULL,
            latest_tx INTEGER NOT NULL,
            accumulated_rx INTEGER NOT NULL,
            accumulated_tx INTEGER NOT NULL,
            is_manual INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL,
            PRIMARY KEY (date_key, gateway_ip)
        );
        """
        executeRawSQL(schema)
    }

    // MARK: - المساعدات لربط وقراءة النصوص بأمان
    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT_DESTRUCTOR)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnString(_ stmt: OpaquePointer?, index: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cStr)
    }

    private func columnOptionalString(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    // MARK: - 1. السجل اليومي للاستهلاك (Daily Usage)
    func addUsageDelta(
        dateKey: String,
        networkId: String,
        networkName: String,
        connectionType: ConnectionKind,
        downloadDelta: Int64,
        uploadDelta: Int64
    ) {
        guard downloadDelta > 0 || uploadDelta > 0 else { return }
        queue.sync {
            guard let db else { return }
            let rowId = "\(dateKey)_\(networkId)"
            let now = Date().timeIntervalSince1970
            let sql = """
            INSERT INTO daily_usage (id, date_key, network_id, network_name, connection_type, download_bytes, upload_bytes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                download_bytes = download_bytes + excluded.download_bytes,
                upload_bytes = upload_bytes + excluded.upload_bytes,
                network_name = excluded.network_name,
                updated_at = excluded.updated_at;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, index: 1, value: rowId)
                bindText(stmt, index: 2, value: dateKey)
                bindText(stmt, index: 3, value: networkId)
                bindText(stmt, index: 4, value: networkName)
                bindText(stmt, index: 5, value: connectionType.rawValue)
                sqlite3_bind_int64(stmt, 6, downloadDelta)
                sqlite3_bind_int64(stmt, 7, uploadDelta)
                sqlite3_bind_double(stmt, 8, now)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    func upsertDailyRecord(_ record: DailyUsageRecord) {
        queue.sync {
            upsertDailyRecordInternal(record)
        }
    }

    private func upsertDailyRecordInternal(_ record: DailyUsageRecord) {
        guard let db else { return }
        let sql = """
        INSERT INTO daily_usage (id, date_key, network_id, network_name, connection_type, download_bytes, upload_bytes, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            network_name = excluded.network_name,
            connection_type = excluded.connection_type,
            download_bytes = MAX(daily_usage.download_bytes, excluded.download_bytes),
            upload_bytes = MAX(daily_usage.upload_bytes, excluded.upload_bytes),
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: record.id)
            bindText(stmt, index: 2, value: record.dateKey)
            bindText(stmt, index: 3, value: record.networkId)
            bindText(stmt, index: 4, value: record.networkName)
            bindText(stmt, index: 5, value: record.connectionType.rawValue)
            sqlite3_bind_int64(stmt, 6, record.downloadBytes)
            sqlite3_bind_int64(stmt, 7, record.uploadBytes)
            sqlite3_bind_double(stmt, 8, record.updatedAt)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchAllDailyRecords() -> [DailyUsageRecord] {
        queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT id, date_key, network_id, network_name, connection_type, download_bytes, upload_bytes, updated_at
            FROM daily_usage
            ORDER BY date_key DESC, updated_at DESC;
            """
            var stmt: OpaquePointer?
            var result: [DailyUsageRecord] = []
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let record = DailyUsageRecord(
                        id: columnString(stmt, index: 0),
                        dateKey: columnString(stmt, index: 1),
                        networkId: columnString(stmt, index: 2),
                        networkName: columnString(stmt, index: 3),
                        connectionType: ConnectionKind(rawValue: columnString(stmt, index: 4)) ?? .wifi,
                        downloadBytes: sqlite3_column_int64(stmt, 5),
                        uploadBytes: sqlite3_column_int64(stmt, 6),
                        updatedAt: sqlite3_column_double(stmt, 7)
                    )
                    result.append(record)
                }
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    func fetchTotalBytes(networkId: String, fromDateKey: String, toDateKey: String) -> Int64 {
        queue.sync {
            guard let db else { return 0 }
            let sql = """
            SELECT COALESCE(SUM(download_bytes + upload_bytes), 0)
            FROM daily_usage
            WHERE network_id = ? AND date_key >= ? AND date_key <= ?;
            """
            var stmt: OpaquePointer?
            var total: Int64 = 0
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, index: 1, value: networkId)
                bindText(stmt, index: 2, value: fromDateKey)
                bindText(stmt, index: 3, value: toDateKey)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    total = sqlite3_column_int64(stmt, 0)
                }
            }
            sqlite3_finalize(stmt)
            return total
        }
    }

    // MARK: - 2. ملفات تعريف الشبكات وتسمياتها (Network Profiles)
    func upsertNetworkProfile(_ profile: SavedNetworkProfile) {
        queue.sync {
            upsertNetworkProfileInternal(profile)
        }
    }

    private func upsertNetworkProfileInternal(_ profile: SavedNetworkProfile) {
        guard let db else { return }
        let sql = """
        INSERT INTO network_profiles (network_id, custom_name, connection_type, gateway_ip, subnet, upnp_udn, router_name, last_seen_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(network_id) DO UPDATE SET
            gateway_ip = CASE WHEN excluded.gateway_ip != '' THEN excluded.gateway_ip ELSE network_profiles.gateway_ip END,
            subnet = CASE WHEN excluded.subnet != '' THEN excluded.subnet ELSE network_profiles.subnet END,
            upnp_udn = CASE WHEN excluded.upnp_udn != '' THEN excluded.upnp_udn ELSE network_profiles.upnp_udn END,
            router_name = CASE WHEN excluded.router_name != '' THEN excluded.router_name ELSE network_profiles.router_name END,
            last_seen_at = excluded.last_seen_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: profile.networkId)
            bindText(stmt, index: 2, value: profile.customName)
            bindText(stmt, index: 3, value: profile.connectionType.rawValue)
            bindText(stmt, index: 4, value: profile.gatewayIP)
            bindText(stmt, index: 5, value: profile.subnet)
            bindText(stmt, index: 6, value: profile.upnpUDN)
            bindText(stmt, index: 7, value: profile.routerModelName)
            sqlite3_bind_double(stmt, 8, profile.lastSeenAt)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func renameNetwork(networkId: String, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.sync {
            guard let db else { return }
            let queries = [
                "UPDATE network_profiles SET custom_name = ? WHERE network_id = ?;",
                "UPDATE daily_usage SET network_name = ? WHERE network_id = ?;",
                "UPDATE network_quotas SET network_name = ? WHERE network_id = ?;"
            ]
            for sql in queries {
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    bindText(stmt, index: 1, value: trimmed)
                    bindText(stmt, index: 2, value: networkId)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
        }
    }

    func fetchNetworkProfile(networkId: String) -> SavedNetworkProfile? {
        queue.sync {
            guard let db else { return nil }
            let sql = """
            SELECT network_id, custom_name, connection_type, gateway_ip, subnet, upnp_udn, router_name, last_seen_at
            FROM network_profiles WHERE network_id = ? LIMIT 1;
            """
            var stmt: OpaquePointer?
            var found: SavedNetworkProfile?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, index: 1, value: networkId)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    found = SavedNetworkProfile(
                        networkId: columnString(stmt, index: 0),
                        customName: columnString(stmt, index: 1),
                        connectionType: ConnectionKind(rawValue: columnString(stmt, index: 2)) ?? .wifi,
                        gatewayIP: columnString(stmt, index: 3),
                        subnet: columnString(stmt, index: 4),
                        upnpUDN: columnString(stmt, index: 5),
                        routerModelName: columnString(stmt, index: 6),
                        lastSeenAt: sqlite3_column_double(stmt, 7)
                    )
                }
            }
            sqlite3_finalize(stmt)
            return found
        }
    }

    func fetchAllNetworkProfiles() -> [SavedNetworkProfile] {
        queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT network_id, custom_name, connection_type, gateway_ip, subnet, upnp_udn, router_name, last_seen_at
            FROM network_profiles ORDER BY last_seen_at DESC;
            """
            var stmt: OpaquePointer?
            var list: [SavedNetworkProfile] = []
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    list.append(
                        SavedNetworkProfile(
                            networkId: columnString(stmt, index: 0),
                            customName: columnString(stmt, index: 1),
                            connectionType: ConnectionKind(rawValue: columnString(stmt, index: 2)) ?? .wifi,
                            gatewayIP: columnString(stmt, index: 3),
                            subnet: columnString(stmt, index: 4),
                            upnpUDN: columnString(stmt, index: 5),
                            routerModelName: columnString(stmt, index: 6),
                            lastSeenAt: sqlite3_column_double(stmt, 7)
                        )
                    )
                }
            }
            sqlite3_finalize(stmt)
            return list
        }
    }

    // MARK: - 3. الباقات المستقلة لكل شبكة (Network Quotas)
    func upsertQuotaPlan(_ plan: NetworkQuotaPlan) {
        queue.sync {
            upsertQuotaPlanInternal(plan)
        }
    }

    private func upsertQuotaPlanInternal(_ plan: NetworkQuotaPlan) {
        guard let db else { return }
        let sql = """
        INSERT INTO network_quotas (
            id, network_id, network_name, connection_type, quota_bytes, renewal_day,
            used_offset_bytes, daily_overage_alert_enabled, warning_percent,
            last_alert_cycle_key, last_daily_alert_date, is_enabled
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(network_id) DO UPDATE SET
            network_name = excluded.network_name,
            connection_type = excluded.connection_type,
            quota_bytes = excluded.quota_bytes,
            renewal_day = excluded.renewal_day,
            used_offset_bytes = excluded.used_offset_bytes,
            daily_overage_alert_enabled = excluded.daily_overage_alert_enabled,
            warning_percent = excluded.warning_percent,
            last_alert_cycle_key = excluded.last_alert_cycle_key,
            last_daily_alert_date = excluded.last_daily_alert_date,
            is_enabled = excluded.is_enabled;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: plan.id)
            bindText(stmt, index: 2, value: plan.networkId)
            bindText(stmt, index: 3, value: plan.networkName)
            bindText(stmt, index: 4, value: plan.connectionType.rawValue)
            sqlite3_bind_int64(stmt, 5, plan.quotaBytes)
            sqlite3_bind_int(stmt, 6, Int32(plan.renewalDay))
            sqlite3_bind_int64(stmt, 7, plan.usedOffsetBytes)
            sqlite3_bind_int(stmt, 8, plan.dailyOverageAlertEnabled ? 1 : 0)
            sqlite3_bind_double(stmt, 9, plan.warningPercent)
            bindText(stmt, index: 10, value: plan.lastAlertCycleKey)
            bindText(stmt, index: 11, value: plan.lastDailyAlertDate)
            sqlite3_bind_int(stmt, 12, plan.isEnabled ? 1 : 0)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchQuotaPlans() -> [NetworkQuotaPlan] {
        queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT id, network_id, network_name, connection_type, quota_bytes, renewal_day,
                   used_offset_bytes, daily_overage_alert_enabled, warning_percent,
                   last_alert_cycle_key, last_daily_alert_date, is_enabled
            FROM network_quotas ORDER BY network_name ASC;
            """
            var stmt: OpaquePointer?
            var list: [NetworkQuotaPlan] = []
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    list.append(
                        NetworkQuotaPlan(
                            id: columnString(stmt, index: 0),
                            networkId: columnString(stmt, index: 1),
                            networkName: columnString(stmt, index: 2),
                            connectionType: ConnectionKind(rawValue: columnString(stmt, index: 3)) ?? .wifi,
                            quotaBytes: sqlite3_column_int64(stmt, 4),
                            renewalDay: Int(sqlite3_column_int(stmt, 5)),
                            usedOffsetBytes: sqlite3_column_int64(stmt, 6),
                            dailyOverageAlertEnabled: sqlite3_column_int(stmt, 7) != 0,
                            warningPercent: sqlite3_column_double(stmt, 8),
                            lastAlertCycleKey: columnOptionalString(stmt, index: 9),
                            lastDailyAlertDate: columnOptionalString(stmt, index: 10),
                            isEnabled: sqlite3_column_int(stmt, 11) != 0
                        )
                    )
                }
            }
            sqlite3_finalize(stmt)
            return list
        }
    }

    func deleteQuotaPlan(id: String) {
        queue.sync {
            guard let db else { return }
            let sql = "DELETE FROM network_quotas WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, index: 1, value: id)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - 4. حوادث السحب المفاجئ (Spike Incidents)
    func insertSpikeIncident(_ incident: SpikeIncidentRecord) {
        queue.sync {
            insertSpikeIncidentInternal(incident)
        }
    }

    private func insertSpikeIncidentInternal(_ incident: SpikeIncidentRecord) {
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO spike_events
        (id, timestamp, network_id, network_name, connection_type, bytes_delta, window_minutes, download_bytes, upload_bytes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: incident.id)
            sqlite3_bind_double(stmt, 2, incident.timestamp)
            bindText(stmt, index: 3, value: incident.networkId)
            bindText(stmt, index: 4, value: incident.networkName)
            bindText(stmt, index: 5, value: incident.connectionType.rawValue)
            sqlite3_bind_int64(stmt, 6, incident.bytesDelta)
            sqlite3_bind_int(stmt, 7, Int32(incident.windowMinutes))
            sqlite3_bind_int64(stmt, 8, incident.downloadBytes)
            sqlite3_bind_int64(stmt, 9, incident.uploadBytes)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchSpikeIncidents(limit: Int = 200) -> [SpikeIncidentRecord] {
        queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT id, timestamp, network_id, network_name, connection_type, bytes_delta, window_minutes, download_bytes, upload_bytes
            FROM spike_events ORDER BY timestamp DESC LIMIT ?;
            """
            var stmt: OpaquePointer?
            var list: [SpikeIncidentRecord] = []
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    list.append(
                        SpikeIncidentRecord(
                            id: columnString(stmt, index: 0),
                            timestamp: sqlite3_column_double(stmt, 1),
                            networkId: columnString(stmt, index: 2),
                            networkName: columnString(stmt, index: 3),
                            connectionType: ConnectionKind(rawValue: columnString(stmt, index: 4)) ?? .wifi,
                            bytesDelta: sqlite3_column_int64(stmt, 5),
                            windowMinutes: Int(sqlite3_column_int(stmt, 6)),
                            downloadBytes: sqlite3_column_int64(stmt, 7),
                            uploadBytes: sqlite3_column_int64(stmt, 8)
                        )
                    )
                }
            }
            sqlite3_finalize(stmt)
            return list
        }
    }

    func clearSpikeIncidents() {
        queue.sync {
            executeRawSQL("DELETE FROM spike_events;")
        }
    }

    // MARK: - 5. سجل حارس الداتا مع الواي فاي و Wi-Fi Assist
    func insertDualGuardEvent(_ event: DualGuardEventRecord) {
        queue.sync {
            insertDualGuardEventInternal(event)
        }
    }

    private func insertDualGuardEventInternal(_ event: DualGuardEventRecord) {
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO dual_guard_events (id, timestamp, wifi_network_name, event_type, leaked_bytes)
        VALUES (?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: event.id)
            sqlite3_bind_double(stmt, 2, event.timestamp)
            bindText(stmt, index: 3, value: event.wifiNetworkName)
            bindText(stmt, index: 4, value: event.eventType.rawValue)
            sqlite3_bind_int64(stmt, 5, event.leakedBytes)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchDualGuardEvents(limit: Int = 200) -> [DualGuardEventRecord] {
        queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT id, timestamp, wifi_network_name, event_type, leaked_bytes
            FROM dual_guard_events ORDER BY timestamp DESC LIMIT ?;
            """
            var stmt: OpaquePointer?
            var list: [DualGuardEventRecord] = []
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(limit))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    list.append(
                        DualGuardEventRecord(
                            id: columnString(stmt, index: 0),
                            timestamp: sqlite3_column_double(stmt, 1),
                            wifiNetworkName: columnString(stmt, index: 2),
                            eventType: DualGuardEventKind(rawValue: columnString(stmt, index: 3)) ?? .dualActive,
                            leakedBytes: sqlite3_column_int64(stmt, 4)
                        )
                    )
                }
            }
            sqlite3_finalize(stmt)
            return list
        }
    }

    func clearDualGuardEvents() {
        queue.sync {
            executeRawSQL("DELETE FROM dual_guard_events;")
        }
    }

    // MARK: - 6. لقطات استهلاك الراوتر اليومي (Router Snapshots)
    func upsertRouterSnapshot(_ snapshot: RouterDailySnapshot) {
        queue.sync {
            upsertRouterSnapshotInternal(snapshot)
        }
    }

    private func upsertRouterSnapshotInternal(_ snapshot: RouterDailySnapshot) {
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO router_snapshots
        (date_key, gateway_ip, router_name, baseline_rx, baseline_tx, latest_rx, latest_tx, accumulated_rx, accumulated_tx, is_manual, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: snapshot.dateKey)
            bindText(stmt, index: 2, value: snapshot.gatewayIP)
            bindText(stmt, index: 3, value: snapshot.routerName)
            sqlite3_bind_int64(stmt, 4, snapshot.baselineRx)
            sqlite3_bind_int64(stmt, 5, snapshot.baselineTx)
            sqlite3_bind_int64(stmt, 6, snapshot.latestRx)
            sqlite3_bind_int64(stmt, 7, snapshot.latestTx)
            sqlite3_bind_int64(stmt, 8, snapshot.accumulatedRx)
            sqlite3_bind_int64(stmt, 9, snapshot.accumulatedTx)
            sqlite3_bind_int(stmt, 10, snapshot.isManual ? 1 : 0)
            sqlite3_bind_double(stmt, 11, snapshot.updatedAt)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchRouterSnapshot(dateKey: String, gatewayIP: String) -> RouterDailySnapshot? {
        queue.sync {
            guard let db else { return nil }
            let sql = """
            SELECT date_key, gateway_ip, router_name, baseline_rx, baseline_tx, latest_rx, latest_tx,
                   accumulated_rx, accumulated_tx, is_manual, updated_at
            FROM router_snapshots WHERE date_key = ? AND gateway_ip = ? LIMIT 1;
            """
            var stmt: OpaquePointer?
            var found: RouterDailySnapshot?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, index: 1, value: dateKey)
                bindText(stmt, index: 2, value: gatewayIP)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    found = RouterDailySnapshot(
                        dateKey: columnString(stmt, index: 0),
                        gatewayIP: columnString(stmt, index: 1),
                        routerName: columnString(stmt, index: 2),
                        baselineRx: sqlite3_column_int64(stmt, 3),
                        baselineTx: sqlite3_column_int64(stmt, 4),
                        latestRx: sqlite3_column_int64(stmt, 5),
                        latestTx: sqlite3_column_int64(stmt, 6),
                        accumulatedRx: sqlite3_column_int64(stmt, 7),
                        accumulatedTx: sqlite3_column_int64(stmt, 8),
                        isManual: sqlite3_column_int(stmt, 9) != 0,
                        updatedAt: sqlite3_column_double(stmt, 10)
                    )
                }
            }
            sqlite3_finalize(stmt)
            return found
        }
    }

    func fetchAllRouterSnapshots() -> [RouterDailySnapshot] {
        queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT date_key, gateway_ip, router_name, baseline_rx, baseline_tx, latest_rx, latest_tx,
                   accumulated_rx, accumulated_tx, is_manual, updated_at
            FROM router_snapshots ORDER BY date_key DESC;
            """
            var stmt: OpaquePointer?
            var list: [RouterDailySnapshot] = []
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    list.append(
                        RouterDailySnapshot(
                            dateKey: columnString(stmt, index: 0),
                            gatewayIP: columnString(stmt, index: 1),
                            routerName: columnString(stmt, index: 2),
                            baselineRx: sqlite3_column_int64(stmt, 3),
                            baselineTx: sqlite3_column_int64(stmt, 4),
                            latestRx: sqlite3_column_int64(stmt, 5),
                            latestTx: sqlite3_column_int64(stmt, 6),
                            accumulatedRx: sqlite3_column_int64(stmt, 7),
                            accumulatedTx: sqlite3_column_int64(stmt, 8),
                            isManual: sqlite3_column_int(stmt, 9) != 0,
                            updatedAt: sqlite3_column_double(stmt, 10)
                        )
                    )
                }
            }
            sqlite3_finalize(stmt)
            return list
        }
    }

    // MARK: - 7. الاسترجاع والنسخ الاحتياطي الشامل
    func restoreBackup(_ backup: NetPulseFullBackup, replaceExisting: Bool) {
        queue.sync {
            executeRawSQL("BEGIN TRANSACTION;")
            if replaceExisting {
                executeRawSQL("DELETE FROM daily_usage;")
                executeRawSQL("DELETE FROM network_profiles;")
                executeRawSQL("DELETE FROM network_quotas;")
                executeRawSQL("DELETE FROM spike_events;")
                executeRawSQL("DELETE FROM dual_guard_events;")
                executeRawSQL("DELETE FROM router_snapshots;")
            }

            for profile in backup.networkProfiles {
                upsertNetworkProfileInternal(profile)
            }
            for record in backup.dailyRecords {
                upsertDailyRecordInternal(record)
            }
            for quota in backup.quotaPlans {
                upsertQuotaPlanInternal(quota)
            }
            for spike in backup.spikeIncidents {
                insertSpikeIncidentInternal(spike)
            }
            for event in backup.dualGuardEvents {
                insertDualGuardEventInternal(event)
            }
            for snap in backup.routerSnapshots {
                upsertRouterSnapshotInternal(snap)
            }
            executeRawSQL("COMMIT;")
        }
    }

    func importCSVRecords(_ records: [DailyUsageRecord], replaceExisting: Bool) {
        queue.sync {
            executeRawSQL("BEGIN TRANSACTION;")
            if replaceExisting {
                executeRawSQL("DELETE FROM daily_usage;")
            }
            for record in records {
                upsertDailyRecordInternal(record)
            }
            executeRawSQL("COMMIT;")
        }
    }

    func resetAllHistory() {
        queue.sync {
            executeRawSQL("DELETE FROM daily_usage;")
            executeRawSQL("DELETE FROM spike_events;")
            executeRawSQL("DELETE FROM dual_guard_events;")
            executeRawSQL("DELETE FROM router_snapshots;")
        }
    }
}
