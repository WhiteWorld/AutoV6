import SwiftUI
import ServiceManagement

struct MenuBarView: View {

    @Environment(RuleStore.self) private var ruleStore
    @Environment(WiFiMonitor.self) private var wifiMonitor
    @Environment(LocationManager.self) private var locationManager

    @State private var showAddRule  = false
    @State private var editingRule:  Rule?
    @State private var newSSID      = ""
    @State private var newMode      = IPv6Mode.automatic
    @State private var deleteTarget: Rule?
    @State private var showDeleteAlert = false
    @State private var isLoginItem  = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current network status
            statusSection

            Divider()

            // Rules list
            rulesSection

            Divider()

            // Footer
            footerSection
        }
        .frame(width: 300)
        .onAppear {
            refreshLoginItemState()
            wifiMonitor.refresh()
        }
        .alert("删除规则", isPresented: $showDeleteAlert, presenting: deleteTarget) { rule in
            Button("删除", role: .destructive) { ruleStore.delete(id: rule.id) }
            Button("取消", role: .cancel) {}
        } message: { rule in
            Text("确定要删除 \"\(rule.ssid)\" 的规则吗？")
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("当前网络")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 10)

            if let ssid = wifiMonitor.currentSSID {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "wifi")
                        Text(ssid)
                            .fontWeight(.medium)
                        Spacer()
                        Text(wifiMonitor.currentIPv6Mode?.displayName ?? "未知")
                            .foregroundStyle(wifiMonitor.currentIPv6Mode != nil ? .primary : .secondary)
                    }
                    if let error = wifiMonitor.lastError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            } else {
                HStack {
                    Image(systemName: "wifi.slash")
                    Text("未连接")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Rules Section

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("规则")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    newSSID = wifiMonitor.currentSSID ?? ""
                    newMode = .automatic
                    showAddRule = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("添加规则")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if ruleStore.rules.isEmpty {
                Text("暂无规则")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(ruleStore.rules) { rule in
                    ruleRow(rule)
                }
            }

            // Add rule inline form
            if showAddRule {
                addRuleForm
            }

            Text("默认：无匹配规则时保持当前配置不变")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: Rule) -> some View {
        if editingRule?.id == rule.id {
            editRuleForm(rule)
        } else {
            HStack {
                Text(rule.ssid)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("→ \(rule.mode.displayName)")
                    .foregroundStyle(.secondary)
                Button {
                    deleteTarget = rule
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("删除")
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { editingRule = rule }
            .help("点击编辑")
        }
    }

    private var addRuleForm: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Wi-Fi 名称", text: $newSSID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Picker("", selection: $newMode) {
                    ForEach(IPv6Mode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
                Button("添加") {
                    guard !newSSID.isEmpty else { return }
                    ruleStore.add(Rule(ssid: newSSID, mode: newMode))
                    showAddRule = false
                    wifiMonitor.applyCurrentRule()
                }
                .disabled(newSSID.isEmpty || ruleStore.contains(ssid: newSSID))
                Button("取消") { showAddRule = false }
            }
            if ruleStore.contains(ssid: newSSID) && !newSSID.isEmpty {
                Text("已存在相同 Wi-Fi 名称的规则")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func editRuleForm(_ rule: Rule) -> some View {
        let binding = Binding<Rule>(
            get: { editingRule ?? rule },
            set: { editingRule = $0 }
        )
        HStack {
            TextField("Wi-Fi 名称", text: binding.ssid)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
            Picker("", selection: binding.mode) {
                ForEach(IPv6Mode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 90)
            Button("保存") {
                if let updated = editingRule {
                    ruleStore.update(updated)
                }
                editingRule = nil
                wifiMonitor.applyCurrentRule()
            }
            Button("取消") { editingRule = nil }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 0) {
            Toggle("开机自启", isOn: $isLoginItem)
                .toggleStyle(.checkbox)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: isLoginItem) { _, newValue in
                    toggleLoginItem(enabled: newValue)
                }

            Divider()

            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Login Item

    private func refreshLoginItemState() {
        let service = SMAppService.mainApp
        isLoginItem = service.status == .enabled
    }

    private func toggleLoginItem(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("[MenuBarView] Login item toggle failed: \(error)")
            refreshLoginItemState()
        }
    }
}
