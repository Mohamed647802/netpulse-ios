import SwiftUI

struct NetworkRenameSheet: View {
    @EnvironmentObject var monitor: NetworkMonitorService
    @Environment(\.dismiss) private var dismiss

    @State private var editedName: String = ""
    @State private var newProfileName: String = ""

    private var wifiProfiles: [SavedNetworkProfile] {
        monitor.savedNetworkProfiles.filter { $0.connectionType == .wifi }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الشبكة المتصل بها حالياً") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "wifi")
                                .foregroundColor(AppTheme.wifiAccent)
                            Text(monitor.currentWifiNetworkName)
                                .font(.headline)
                        }
                        Text("بصمة البوابة: \(monitor.gatewayIPAddress) • النطاق: \(monitor.subnetCIDR) • عنوان هاتفك: \(monitor.localIPAddress)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    TextField("اكتب اسماً واضحاً للشبكة (مثال: واي فاي البيت)", text: $editedName)

                    Button {
                        monitor.renameNetwork(networkId: monitor.currentWifiNetworkId, newName: editedName)
                        dismiss()
                    } label: {
                        Label("حفظ اسم الشبكة الحالية", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section {
                    HStack {
                        TextField("اسم شبكة جديدة (مثال: واي فاي العمل)", text: $newProfileName)
                        Button("إنشاء وتفعيل") {
                            monitor.createAndActivateWifiProfile(customName: newProfileName)
                            newProfileName = ""
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("إنشاء ملف شبكة منفصل")
                } footer: {
                    Text("مفيد في حال تشابه عنوان الراوتر (192.168.1.1) بين شبكتين مختلفتين وأردت فصل سجلاتهما وباقاتهما.")
                }

                if !wifiProfiles.isEmpty {
                    Section("شبكات الواي فاي المحفوظة") {
                        ForEach(wifiProfiles) { profile in
                            Button {
                                monitor.switchActiveWifiProfile(to: profile.networkId)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(profile.customName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.primary)
                                        Text("البوابة: \(profile.gatewayIP.isEmpty ? "—" : profile.gatewayIP) • \(profile.subnet.isEmpty ? "مخصص" : profile.subnet)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if profile.networkId == monitor.currentWifiNetworkId {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundColor(AppTheme.wifiAccent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("تسمية وإدارة شبكة الواي فاي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
            }
            .onAppear {
                editedName = monitor.currentWifiNetworkName
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
