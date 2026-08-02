# 校园网自动重连工具

用于 Windows 的校园网监控工具。它会定期检测网络；认证失效时自动重新认证，并通过邮件通知认证结果。

## 能做什么

- 定期检测能否访问百度。
- 断网后自动访问校园网认证页面并尝试重新认证。
- 认证成功、认证失败、手动停止监控时发送邮件通知。
- 控制面板可最小化到右下角托盘。
- 支持开机自动启动、计划任务修复和卸载。

## 快速开始

1. 将整个项目文件夹放到一个固定位置。首次设置完成后不要移动该文件夹，计划任务会记住它的位置。
2. 复制 `campus-network.config.example.json`，将副本改名为 `campus-network.config.json`。
3. 打开 `campus-network.config.json`，填写校园网账号、校园网密码和邮箱信息。也可以先打开控制面板，再在“账号和邮箱”中填写。
4. 双击 `CampusNetworkMenu.bat`。它会打开控制面板、修复当前电脑的计划任务，并启动后台监控。
5. 等待约 10 秒，确认“后台监控”显示“运行中”。首次自动注册成功时会收到一封确认邮件。
6. 关闭控制面板时选择“最小化到托盘”，程序会继续在后台运行。

## 日常使用

| 操作 | 作用 |
| --- | --- |
| 双击 `CampusNetworkMonitor.exe` | 打开控制面板。 |
| 双击 `CampusNetworkMenu.bat` | 打开控制面板，并按当前文件夹路径检查、修复计划任务。 |
| 右键托盘图标 | 快速启动或停止监控、立即检测网络、切换开机自动启动。 |
| 关闭控制面板 | 可选择最小化到托盘，或只退出控制面板。后台监控不会因此停止。 |

控制面板中的状态含义：

- `后台监控：运行中`：当前正在定期检测网络。
- `计划任务：已就绪`：正常状态，表示已注册，会在下次登录 Windows 时自动启动。
- `开机自动运行：已开启`：登录 Windows 后会启动后台监控和托盘图标。

## 文件说明

| 文件 | 用途 |
| --- | --- |
| `CampusNetworkMonitor.exe` | 程序入口和控制面板。 |
| `CampusNetworkMonitor.ps1` | 后台监控组件，必须与 exe 保存在同一目录。 |
| `CampusNetworkMenu.bat` | 首次使用或移动文件夹后使用的启动器。 |
| `campus-network.config.json` | 个人配置，包含密码和邮箱授权码，仅保存在本机。 |
| `campus-network.config.example.json` | 不含任何真实信息的配置模板。 |

## 可选命令

在项目目录打开命令提示符后，可使用以下命令：

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

- `campus-network.config.json` 可能包含校园网密码和邮箱授权码，已被 `.gitignore` 排除，不能提交到 GitHub。
- `campus-network-monitor.log` 会记录运行时间和网络状态，也已被排除，不能提交到 GitHub。
- 本仓库只提供空白配置模板，不包含任何真实账号、密码、邮箱地址或日志。
- 如果误将真实配置提交到 GitHub，即使仓库是私有仓库，也应立即修改校园网密码和邮箱授权码。

## 认证地址

默认认证地址为 `http://10.10.9.9`。不同学校的认证页面和参数可能不同，请在使用前确认该地址适用于你的网络环境。
