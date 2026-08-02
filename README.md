# 校园网自动重连工具

这是一个 Windows 桌面工具，用于定期检测网络连接，在校园网认证失效时自动重新认证，并通过邮件通知运行状态。

## 功能

- 定期检测是否能够访问百度。
- 网络异常时访问校园网认证页面，自动尝试重新认证。
- 认证成功、认证失败、手动停止监控时发送邮件通知。
- 控制面板可最小化到系统托盘。
- 可选开机自动启动后台监控和托盘图标。
- 支持卸载程序及其计划任务。

## 首次使用

1. 将整个项目文件夹放到一个固定位置，之后不要移动该文件夹。
2. 将 `campus-network.config.example.json` 复制一份并改名为 `campus-network.config.json`。
3. 在 `campus-network.config.json` 中填写校园网账号、校园网密码和邮箱信息；也可以先运行程序，在“账号和邮箱”页面中填写。
4. 双击 `CampusNetworkMenu.bat`。控制面板会自动修复计划任务并启动后台监控。
5. 看到“后台监控：运行中”后，选择“最小化到托盘”即可让程序持续在后台运行。

`CampusNetworkMonitor.ps1` 是后台监控组件，必须与 `CampusNetworkMonitor.exe` 保存在同一目录。

## 日常使用

- 双击 `CampusNetworkMonitor.exe`：打开控制面板。
- 双击 `CampusNetworkMenu.bat`：打开控制面板，并检查、修复当前电脑的计划任务。
- “计划任务：已就绪”是正常状态，表示任务已注册，等待下次登录 Windows 时自动启动。
- “后台监控：运行中”表示当前正在检测网络。

## 可选命令

在项目目录打开命令提示符后，可以使用以下命令：

```cmd
CampusNetworkMonitor.exe -Once
```

立即检测网络，必要时尝试认证。

```cmd
CampusNetworkMonitor.exe -StopTask
```

停止当前后台监控，并发送停止通知邮件。

```cmd
CampusNetworkMonitor.exe -EnableStartup
```

开启开机自动启动。

```cmd
CampusNetworkMonitor.exe -DisableStartup
```

关闭开机自动启动。

## 隐私与安全

- `campus-network.config.json` 中可能包含校园网密码和邮箱授权码，已被 `.gitignore` 排除，不能提交到 GitHub。
- `campus-network-monitor.log` 记录运行时间和网络状态，也已被排除，不能提交到 GitHub。
- 仓库只提供 `campus-network.config.example.json` 空白配置示例，不含任何真实账号、密码或邮箱信息。
- 如果误将真实配置提交到 GitHub，即使仓库是私有的，也应立即修改校园网密码和邮箱授权码。

## 认证地址

默认校园网认证地址为 `http://10.10.9.9`。不同学校的认证页面和参数可能不同，使用前请确认该地址适用于你的网络环境。
