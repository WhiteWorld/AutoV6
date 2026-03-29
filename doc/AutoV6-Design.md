# AutoV6 — 产品设计文档

> 一款 macOS 菜单栏工具，根据当前连接的 Wi-Fi 网络自动切换 IPv6 配置。

---

## 一、产品背景

macOS 的 IPv6 配置（自动 / 仅本地链接 / 关闭）需要手动进入系统设置修改，无法随网络环境自动切换。在家用网络、公司网络、咖啡厅网络之间频繁切换的用户，往往需要反复手动调整，体验很差。

**AutoV6** 解决这个问题：用户预先为每个 Wi-Fi 配置一条规则，之后切换网络时 App 自动完成配置切换，完全无感知。：用户预先为每个 Wi-Fi 配置一条规则，之后切换网络时 App 自动完成配置切换，完全无感知。

---

## 二、目标用户

- 个人开发者 / 技术用户，经常在多个网络环境下工作
- 对网络配置有精细控制需求的用户
- 有 App Store 购买习惯、注重工具品质的 Mac 用户

---

## 三、核心功能

| 功能 | 说明 |
|---|---|
| 自动切换 | Wi-Fi 变化时自动匹配规则并应用 IPv6 模式 |
| 规则管理 | 在菜单栏小窗中增删 Wi-Fi → IPv6 规则 |
| 当前状态显示 | 随时查看当前 Wi-Fi 名称及 IPv6 模式 |
| 默认行为 | 无匹配规则时保持当前配置不变 |
| 开机自启 | 通过 SMAppService 注册为 LaunchDaemon，登录后自动运行 |

### IPv6 模式支持

- **自动**（`-setv6automatic`）
- **仅本地链接**（`-setv6linklocal`）
- **关闭**（`-setv6off`）

### 规则匹配策略

- **精确匹配**：Wi-Fi 名称完全一致才触发
- **无匹配**：保持当前 IPv6 配置不变，不做任何修改

---

## 四、技术方案

### 4.1 整体架构

```
主 App（沙盒）──XPC──▶ Privileged Helper（无沙盒）──▶ networksetup
```

由于 App Store 强制沙盒，`networksetup` 命令不能在主 App 内直接调用。采用 **SMAppService + XPC Privileged Helper** 的合规方案：主 App 负责 UI 和逻辑，Helper 进程负责执行系统命令。

### 4.2 项目结构（2 个 Target）

```
AutoV6.xcodeproj
├── AutoV6/               # Target A — 主 App（沙盒）
│   ├── AutoV6App.swift   # @main 入口，注册 MenuBarExtra
│   ├── MenuBarView.swift       # SwiftUI 弹出小窗 UI
│   ├── RuleStore.swift         # 规则持久化（UserDefaults）
│   ├── WiFiMonitor.swift       # CoreWLAN 监听 SSID 变化
│   ├── HelperClient.swift      # XPC 客户端，发送切换指令
│   └── Models.swift            # 共享数据结构
│
├── AutoV6Helper/                 # Target B — Privileged Helper（无沙盒）
│   ├── HelperMain.swift        # XPC 监听入口
│   ├── IPv6ApplierService.swift# 执行 networksetup 命令
│   └── HelperProtocol.swift    # XPC 接口协议（两个 Target 共享）
│
└── Resources/
    ├── App.entitlements        # App Sandbox + XPC client
    ├── Helper.entitlements     # XPC service，无沙盒
    └── com.xxx.autov6helper.plist  # SMAppService launchd 注册
```

### 4.3 关键模块说明

#### WiFiMonitor
使用 `CoreWLAN` 框架的 `CWWiFiClient` 监听系统网络事件，SSID 变化时触发回调，传递新的 Wi-Fi 名称给 `RuleStore` 进行匹配。原生事件驱动，不使用轮询，功耗极低。

#### RuleStore
规则以 `[Rule]` 数组形式存储在 `UserDefaults`，每条规则包含：
```swift
struct Rule: Codable, Identifiable {
    var id: UUID
    var ssid: String       // Wi-Fi 名称（精确匹配）
    var mode: IPv6Mode     // .automatic | .linkLocal | .off
}
```
匹配逻辑：遍历规则数组，`ssid == currentSSID` 即命中，返回对应 `IPv6Mode`；无命中返回 `nil`（保持不变）。

#### XPC 通信
主 App 通过 `NSXPCConnection` 连接 Helper，调用协议方法：
```swift
@objc protocol AutoV6HelperProtocol {
    func applyMode(_ mode: String, reply: @escaping (Bool) -> Void)
}
```
Helper 收到指令后执行对应的 `networksetup` 命令。

#### IPv6Applier（Helper 内）
```
自动         → networksetup -setv6automatic Wi-Fi
仅本地链接   → networksetup -setv6linklocal Wi-Fi
关闭         → networksetup -setv6off Wi-Fi
```

### 4.4 运行时流程

```
Wi-Fi 切换
    │
    ▼
WiFiMonitor 收到 SSID 变化事件
    │
    ▼
RuleStore 精确匹配 SSID
    ├── 命中 → 返回 IPv6Mode
    └── 未命中 → 不做任何操作（保持不变）
    │
    ▼
HelperClient 通过 XPC 发送模式指令
    │
    ▼
IPv6ApplierService 执行 networksetup
    │
    ▼
系统 IPv6 配置更新完成
```

---

## 五、UI 设计

### 菜单栏图标
- 显示 Wi-Fi 图标 + 当前 IPv6 模式缩写
- 例：`📶 自动` / `📶 仅本地`

### 弹出小窗（MenuBarExtra .window 风格）
```
┌─────────────────────────────┐
│ 当前网络                     │
│ jlhy77-5G · 自动             │
├─────────────────────────────┤
│ 规则                    [+] │
│ ─────────────────────────── │
│ HomeWiFi       →  自动      │
│ CompanyNet     →  仅本地    │
│ CafeGuest      →  关闭      │
├─────────────────────────────┤
│ 默认：保持不变               │
├─────────────────────────────┤
│                        退出 │
└─────────────────────────────┘
```

---

## 六、权限与合规

| 权限项 | 说明 |
|---|---|
| App Sandbox | 主 App 开启沙盒，符合 App Store 要求 |
| Network Information | 读取 Wi-Fi 名称（SSID）所需权限 |
| XPC Service | 主 App 与 Helper 通信 |
| SMAppService | Helper 注册为系统服务，随登录启动 |

首次安装后，App 引导用户授权 Helper 安装（弹出系统权限对话框），之后无需再次授权。

---

## 七、分发方式

- **平台**：Mac App Store
- **签名**：Developer ID + App Store 签名（需 Apple 开发者会员）
- **系统要求**：macOS 13.0+（SMAppService API 最低版本要求）
- **定价**：待定

---

## 八、开发顺序

| 阶段 | 内容 |
|---|---|
| 1 | `Models.swift` + `RuleStore.swift` — 数据层，可独立测试 |
| 2 | `WiFiMonitor.swift` — Wi-Fi 监听，验证事件触发 |
| 3 | `HelperProtocol` + `HelperMain` + `IPv6ApplierService` — Helper 核心 |
| 4 | `HelperClient.swift` — XPC 连接，端到端打通 |
| 5 | `MenuBarView` + `AutoV6App` — UI 收尾，完整可用 |

---

*文档版本：v0.1 · 2026-03-29*
