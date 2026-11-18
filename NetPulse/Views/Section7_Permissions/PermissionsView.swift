import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var permissions: PermissionsManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.screenBackground(colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        SectionHeroBanner(
                            title: "مركز الصلاحيات والأذونات",
                            subtitle: "تأكد من تفعيل الصلاحيات لضمان عمل المنبّهات الصوتية والاتصال بالراوتر والعمل بالخلفية.",
                            systemImage: "checkmark.shield.fill",
                            gradient: permissions.allEssentialPermissionsGranted ? AppTheme.primaryGradient : AppTheme.alarmGradient,
                            badgeText: permissions.missingPermissionsCount == 0 ? "مكتملة" : "\(permissions.missingPermissionsCount) تحتاج مراجعة"
                        )

                        // أزرار التفعيل السريع وفتح الإعدادات
                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await permissions.requestAllPermissions()
                                }
                            } label: {
                                Label("تفعيل الصلاحيات الآن", systemImage: "sparkles")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundColor(.white)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.wifiAccent))
                            }

                            Button {
                                permissions.openSystemSettings()
                            } label: {
                                Label("فتح الإعدادات", systemImage: "gear")
                                    .font(.system(size: 14, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .foregroundColor(.primary)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.secondaryCardBackground(colorScheme)))
                            }
                        }

                        // 1. صلاحية الإشعارات الفورية
                        permissionRowCard(
                            icon: "bell.badge.fill",
                            iconColor: AppTheme.alarmGradient,
                            title: "1. الإشعارات والتنبيهات الفورية",
                            description: "ضرورية لإطلاق منبّه انتهاء الكمية (100%)، ومنبّه نسيان الداتا مع الواي فاي، وإنذار السحب المفاجئ وتنبيهات الباقات.",
                            state: permissions.notificationsState,
                            actionTitle: permissions.notificationsState == .denied ? "تفعيل من الإعدادات" : "طلب صلاحية الإشعارات",
                            extraActionTitle: permissions.notificationsState == .granted ? "اختبار إشعار فوري" : nil,
                            onAction: {
                                if permissions.notificationsState == .denied {
                                    permissions.openSystemSettings()
                                } else {
                                    Task { _ = await permissions.requestNotificationsPermission() }
                                }
                            },
                            onExtraAction: {
                                NotificationService.shared.sendTestNotification()
                            }
                        )

                        // 2. صلاحية الشبكة المحلية والراوتر
                        permissionRowCard(
                            icon: "wifi.router.fill",
                            iconColor: AppTheme.routerGradient,
                            title: "2. الشبكة المحلية والراوتر (Local Network)",
                            description: "تسمح للتطبيق بالاتصال بالراوتر المحلي (192.168.x.x) عبر UPnP وبروتوكول HTTP المحلي لقراءة إجمالي سحب الشبكة المنزلية.",
                            state: permissions.localNetworkState,
                            actionTitle: permissions.isCheckingLocalNetwork
                                ? "جارٍ فحص الشبكة المحلية..."
                                : (permissions.localNetworkState == .denied ? "تفعيل من الإعدادات" : "فحص وتفعيل الشبكة المحلية"),
                            extraActionTitle: nil,
                            onAction: {
                                if permissions.localNetworkState == .denied {
                                    permissions.openSystemSettings()
                                } else {
                                    permissions.requestAndCheckLocalNetworkPermission()
                                }
                            }
                        )

                        // 3. العمل والتحديث في الخلفية
                        permissionRowCard(
                            icon: "arrow.triangle.2.circlepath.circle.fill",
                            iconColor: AppTheme.primaryGradient,
                            title: "3. التحديث والعمل بالخلفية (BGTaskScheduler)",
                            description: "لتحديث عدادات الواي فاي والداتا دورياً بالخلفية ومزامنة الويدجت وإطلاق التنبيهات تلقائياً.",
                            state: permissions.backgroundRefreshState,
                            actionTitle: permissions.backgroundRefreshState == .granted ? "تحديث الحالة" : "فتح إعدادات الخلفية",
                            extraActionTitle: nil,
                            onAction: {
                                if permissions.backgroundRefreshState == .granted {
                                    permissions.refreshBackgroundStatus()
                                } else {
                                    permissions.openSystemSettings()
                                }
                            }
                        )

                        // 4. صلاحية الموقع لرصد تغير الشبكة
                        permissionRowCard(
                            icon: "location.fill.viewfinder",
                            iconColor: AppTheme.primaryGradient,
                            title: "4. الموقع الجغرافي عند انتقال الشبكة (اختياري مساند)",
                            description: "يساعد النظام على تنبيه التطبيق بالخلفية عند خروجك من نطاق الواي فاي والانتقال إلى بيانات الهاتف دون الحاجة لأي صلاحيات مدفوعة.",
                            state: permissions.locationState,
                            actionTitle: permissions.locationState == .denied
                                ? "فتح الإعدادات"
                                : (permissions.locationState == .partial ? "ترقية إلى (دائماً)" : "طلب صلاحية الموقع"),
                            extraActionTitle: nil,
                            onAction: {
                                if permissions.locationState == .denied {
                                    permissions.openSystemSettings()
                                } else if permissions.locationState == .partial {
                                    permissions.requestLocationPermission(always: true)
                                } else {
                                    permissions.requestLocationPermission(always: false)
                                }
                            }
                        )

                        freeSigningCompatibilityNote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("الصلاحيات والأذونات")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task { await permissions.refreshAllStatuses() }
            }
        }
    }

    private func permissionRowCard(
        icon: String,
        iconColor: LinearGradient,
        title: String,
        description: String,
        state: PermissionState,
        actionTitle: String,
        extraActionTitle: String?,
        onAction: @escaping () -> Void,
        onExtraAction: (() -> Void)? = nil
    ) -> some View {
        let stateColor: Color = {
            switch state {
            case .granted: return AppTheme.downloadColor
            case .partial: return AppTheme.warningColor
            case .denied: return AppTheme.dangerColor
            case .notDetermined: return .secondary
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconColor)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.system(size: 14.5, weight: .bold))
                        Spacer()
                        Text(state.arabicLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(stateColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(stateColor.opacity(0.14)))
                    }

                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                if state != .granted || extraActionTitle != nil {
                    if state != .granted {
                        Button(action: onAction) {
                            Text(actionTitle)
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .foregroundColor(.white)
                                .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.wifiAccent))
                        }
                    }

                    if let extraActionTitle, let onExtraAction {
                        Button(action: onExtraAction) {
                            Label(extraActionTitle, systemImage: "speaker.wave.2.fill")
                                .font(.system(size: 12.5, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .foregroundColor(AppTheme.downloadColor)
                                .background(RoundedRectangle(cornerRadius: 11).fill(AppTheme.downloadColor.opacity(0.12)))
                        }
                    }
                }
            }
        }
        .modernCard()
    }

    private var freeSigningCompatibilityNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(AppTheme.downloadColor)
                Text("متوافق 100% مع التوقيع المجاني (Sideloadly / AltStore / SideStore / TrollStore)")
                    .font(.system(size: 13, weight: .bold))
            }
            Text("تم بناء التطبيق بدون أي Entitlements مقيدة بحساب مطور Apple مدفوع، مع دعم تلقائي لحاوية البيانات المشتركة (\(AppGroupStorage.isAppGroupAvailable ? "App Group مفعّلة" : "وضع التخزين المحلي الآمن مفعّل")).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .modernCard()
    }
}
