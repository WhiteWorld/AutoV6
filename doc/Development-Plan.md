# AutoV6 — 开发计划

基于 `AutoV6-Design.md` v0.2，将开发拆分为 6 个阶段，每个阶段产出可验证的交付物。

---

## 阶段 0：项目工程搭建

**目标**：创建 Xcode 项目骨架，配置好双 Target 和签名。

| 任务 | 说明 |
|------|------|
| 0.1 创建 Xcode 项目 | 新建 macOS App 项目 `AutoV6`，SwiftUI 生命周期 |
| 0.2 配置主 App Target | 开启 App Sandbox，设置 Deployment Target macOS 13.0+ |
| 0.3 创建 Helper Target | 新增 Command Line Tool target `com.xxx.AutoV6Helper` |
| 0.4 创建目录结构 | `AutoV6/`、`AutoV6Helper/`、`Shared/`、`Resources/` |
| 0.5 配置 Entitlements | `App.entitlements`（Sandbox + XPC）、`Helper.entitlements` |
| 0.6 配置 Helper Plist | `Helper-Info.plist`（SMAuthorizedClients）、`Helper-Launchd.plist` |
| 0.7 配置 SMJobBless | 主 App Info.plist 添加 `SMPrivilegedExecutables`，Helper 添加 `SMAuthorizedClients`，确保签名身份匹配 |

**验证**：项目可编译通过，两个 Target 均能构建成功。

---

## 阶段 1：数据层 — Models + RuleStore

**目标**：实现数据模型和规则持久化，可独立单元测试。

| 任务 | 说明 |
|------|------|
| 1.1 Models.swift | 定义 `IPv6Mode` 枚举（`.automatic` / `.linkLocal` / `.off`）和 `Rule` 结构体 |
| 1.2 RuleStore.swift | 基于 `UserDefaults` 实现规则的 CRUD 和 SSID 精确匹配逻辑，使用 `@Observable` |
| 1.3 单元测试 | 测试规则增删改查、匹配命中、匹配未命中返回 nil |

**交付物**：
- `AutoV6/Models.swift`
- `AutoV6/RuleStore.swift`
- `AutoV6Tests/RuleStoreTests.swift`

**验证**：所有单元测试通过。

---

## 阶段 2：Wi-Fi 监听 — WiFiMonitor

**目标**：监听 SSID 变化，触发回调。

| 任务 | 说明 |
|------|------|
| 2.1 WiFiMonitor.swift | 使用 `CWWiFiClient` 的 delegate 监听 Wi-Fi 连接/断开事件 |
| 2.2 位置权限请求 | 集成 `Core Location`，首次启动请求 `whenInUse` 授权 |
| 2.3 Info.plist 配置 | 添加 `NSLocationWhenInUseUsageDescription` 说明文案 |
| 2.4 集成 RuleStore | WiFiMonitor 检测到 SSID 变化 → 调用 RuleStore 匹配 → 输出日志 |

**交付物**：
- `AutoV6/WiFiMonitor.swift`
- `AutoV6/LocationManager.swift`（位置权限管理）

**验证**：运行 App，切换 Wi-Fi 后控制台打印匹配结果日志。

---

## 阶段 3：Privileged Helper — XPC 服务端

**目标**：实现 Helper 进程，能通过命令行执行 `networksetup` 切换 IPv6。

| 任务 | 说明 |
|------|------|
| 3.1 HelperProtocol.swift | 定义 `@objc protocol AutoV6HelperProtocol`，`applyMode(_:reply:)` 方法 |
| 3.2 HelperMain.swift | 实现 XPC listener（`NSXPCListener.service()`），注册服务对象 |
| 3.3 IPv6ApplierService.swift | 实现协议方法，通过 `Process` 调用 `networksetup` 命令 |
| 3.4 XPC 安全验证 | Helper 验证连接方的 code signing 身份，防止非授权调用 |

**交付物**：
- `Shared/HelperProtocol.swift`
- `AutoV6Helper/HelperMain.swift`
- `AutoV6Helper/IPv6ApplierService.swift`

**验证**：手动安装 Helper 后，通过测试代码发送 XPC 消息，确认 IPv6 配置被成功修改。

---

## 阶段 4：XPC 客户端 — 端到端打通

**目标**：主 App 能通过 XPC 调用 Helper 完成 IPv6 切换，全链路打通。

| 任务 | 说明 |
|------|------|
| 4.1 HelperClient.swift | 封装 `NSXPCConnection`，提供 `applyMode(_:)` async 方法 |
| 4.2 SMJobBless 集成 | 主 App 启动时检查 Helper 是否已安装，未安装则调用 `SMJobBless` 安装 |
| 4.3 Helper 版本管理 | 比对 Helper bundle version，升级时重新安装 |
| 4.4 串联完整流程 | WiFiMonitor → RuleStore → HelperClient → Helper → networksetup |
| 4.5 错误处理 | XPC 连接中断重连、Helper 未安装提示、命令执行失败处理 |

**交付物**：
- `AutoV6/HelperClient.swift`
- `AutoV6/HelperInstaller.swift`（SMJobBless 安装逻辑）

**验证**：运行 App，切换 Wi-Fi 后系统 IPv6 配置自动变更（通过 `networksetup -getinfo Wi-Fi` 验证）。

---

## 阶段 5：UI — MenuBarExtra

**目标**：完成菜单栏 UI，产品可用。

| 任务 | 说明 |
|------|------|
| 5.1 AutoV6App.swift | 配置 `MenuBarExtra`（`.window` 风格），使用 SF Symbols `wifi` 图标 |
| 5.2 MenuBarView.swift | 实现弹出小窗 UI：当前网络状态、规则列表、添加/编辑/删除规则 |
| 5.3 规则编辑交互 | 点击规则行进入编辑态（inline 编辑 SSID 和 Mode 的 Picker） |
| 5.4 添加规则 | [+] 按钮，自动填充当前 Wi-Fi 名称，用户选择 IPv6 模式 |
| 5.5 删除规则 | [×] 按钮删除规则，带确认 |
| 5.6 状态栏文字 | 菜单栏显示当前 IPv6 模式缩写，跟随状态实时更新 |
| 5.7 Login Item | 通过 `SMAppService.mainApp` 注册 Login Item，提供开关 |
| 5.8 首次引导 | 首次启动检测权限状态，引导用户完成位置授权和 Helper 安装 |

**交付物**：
- `AutoV6/AutoV6App.swift`
- `AutoV6/MenuBarView.swift`
- `AutoV6/OnboardingView.swift`（首次引导）

**验证**：完整功能可用——菜单栏小窗管理规则，切换 Wi-Fi 后自动切换 IPv6 配置。

---

## 阶段间依赖关系

```
阶段 0（工程搭建）
    │
    ├──▶ 阶段 1（数据层）──▶ 阶段 2（Wi-Fi 监听）──┐
    │                                               │
    └──▶ 阶段 3（Helper）─────────────────────────┐ │
                                                   │ │
                                                   ▼ ▼
                                            阶段 4（XPC 端到端）
                                                   │
                                                   ▼
                                            阶段 5（UI）
```

阶段 1+2 和阶段 3 可以**并行开发**，在阶段 4 汇合。

---

*计划版本：v0.1 · 2026-03-29*
