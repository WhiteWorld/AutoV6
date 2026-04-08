# AutoV6

macOS 菜单栏工具，根据连接的 Wi-Fi 自动切换 IPv6 配置。

## 功能

- 按 Wi-Fi 名称（SSID）设置规则，切换网络时自动应用 IPv6 模式
- 支持三种模式：**自动**、**手动**（保留当前地址固定为静态）、**仅本地链接**
- 菜单栏实时显示当前 IPv6 状态
- 规则立即生效，无需重连
- 开机自启

## 系统要求

- macOS 14.0+
- 需要位置服务权限（用于读取 Wi-Fi 名称）

## 安装

从 [Releases](https://github.com/WhiteWorld/AutoV6/releases) 下载最新版本，解压后将 `AutoV6.app` 拖入 `/Applications`。

首次运行需授权：
1. 允许位置服务权限
2. 首次应用规则时通过 Touch ID 或密码授权（之后无需重复）

## 从源码构建

```bash
git clone https://github.com/WhiteWorld/AutoV6.git
cd AutoV6
open AutoV6.xcodeproj
```

在 Xcode 中选择 AutoV6 scheme，构建并运行。需要有效的 Apple 开发者账号进行签名。

## 使用

1. 点击菜单栏图标打开面板
2. 点击 **+** 添加规则，填写 Wi-Fi 名称并选择 IPv6 模式
3. 下次连接到该 Wi-Fi 时自动生效；点击规则也可立即应用

## 许可证

[MIT](LICENSE)
