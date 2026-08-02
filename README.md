# 校园网自动检测、认证和邮件通知

程序目录：`campus-network-monitor`（可放在桌面或任意固定位置）。

脚本已经按当前门户 `http://10.10.9.9` 的锐捷 RG-SAM+ 接口编写，默认服务为 `shu`。它会：

1. 定期 ping `www.baidu.com`。
2. 检测到断网后，获取当前门户跳转上下文。
3. 在后台调用校园网自己的登录网页完成认证，不显示认证窗口。
4. 再次 ping 百度确认认证确实恢复网络。
5. 认证成功或持续失败时发送邮件，并把过程写入日志。

## 完整操作流程

最方便的用法：直接双击 `CampusNetworkMonitor.exe`。整个程序只有这一个入口：普通启动显示控制面板，计划任务通过参数让同一个 exe 在后台执行网络检测和认证，日常运行不需要手动打开 PowerShell。新版界面以网络状态为中心，顶部直接显示“网络正常、正在认证或网络异常”，下面显示后台监控、开机自动运行和计划任务状态，并提供立即检测、账号邮箱设置、查看日志和打开工作目录等操作。关闭这个窗口不会停止后台监控。

开启“开机自启”后，Windows 登录时会同时启动同一个 exe 的后台模式和控制面板模式。控制面板会直接驻留在屏幕右下角的通知区域，只显示小图标，不会自动弹出完整窗口。后台监控仍由独立的 Windows 计划任务运行，因此控制面板关闭后，监控仍会继续工作。仓库保留的旧命令行菜单仅供兼容，日常使用不需要打开它。

账号和邮箱设置窗口会读取当前配置中的账号、密码和邮箱授权码，并直接显示在输入框中，方便修改。配置文件仍按之前的设置以明文保存在本目录，请不要把目录分享给别人。

点击窗口右上角关闭时会出现三个按钮：

- “最小化到托盘”：隐藏到屏幕右下角托盘，后台保留控制面板。
- “直接退出”：退出控制面板，但后台监控不会停止。
- “取消”：返回控制面板。

托盘图标右键可以打开控制面板、启动或停止监控、立即检测网络、切换开机自启、打开日志，以及退出控制面板。双击托盘图标可以重新打开窗口。

控制面板操作区和托盘右键菜单中的“卸载软件”会先请求确认，然后停止监控、删除两个计划任务，并删除本目录中由本程序创建的 exe、脚本、配置、日志和说明文件。账号密码和日志会一起删除。目录中没有列入程序清单的其他文件不会被删除；如果目录因此变为空，目录也会自动删除。

下面命令可以直接在 **CMD 命令提示符** 中执行。打包版命令不会弹出 PowerShell 窗口；日常操作也可以直接使用控制面板按钮。

如果 CMD 当前目录不是这个文件夹，先执行：

```cmd
cd /d "你的程序目录\campus-network-monitor"
```

### 打包文件

- `CampusNetworkMonitor.exe`：唯一入口，包含控制面板、托盘和计划任务启动逻辑。
- `CampusNetworkMonitor.exe.config`：程序运行配置文件，复制到另一台电脑时要一起带上。
- `CampusNetworkMonitor.ico`：exe 使用的网络状态图标源文件。
- `campus-network.config.json`：账号、密码和邮箱配置，按当前设置以明文保存。

### 整个目录复制到新电脑后怎么用

1. 把整个 `campus-network-monitor` 文件夹复制到新电脑桌面或任意固定位置。之后不要移动文件夹；计划任务会记住这个位置。
2. 第一次使用时，双击 `CampusNetworkMonitor.exe`，在控制面板完成账号和邮箱设置后点击“启动监控”。程序会按这台电脑的当前路径注册后台监控和托盘任务。
3. 等待约 10 秒。控制面板的“后台监控”显示“运行中”后即可正常使用；首次自动注册成功会收到一封 `Monitor enabled` 邮件。
4. 关闭控制面板时选择“最小化到托盘”。右下角通知区域会保留图标；看不到时点击通知区域的折叠箭头。
5. 重启新电脑测试一次。登录后不会弹出控制面板，但会出现托盘图标，后台监控会自动运行。

控制面板中“计划任务”显示“已就绪（Ready）”是正常状态，表示它已注册并会在下次登录时启动；只要“后台监控”显示“运行中”，当前监控就在工作。

复制到另一台电脑时，请复制整个 `campus-network-monitor` 文件夹，其中的 `CampusNetworkMonitor.ps1` 是 exe 使用的后台监控组件。计划任务仍只启动 `CampusNetworkMonitor.exe`，不会弹 PowerShell 窗口。复制后双击 `CampusNetworkMonitor.exe`，在控制面板点击“启动监控”，即可按当前路径重新注册任务。计划任务属于当前 Windows，不会随文件夹复制，也不需要手动执行 `schtasks`。

复制后首次启动会按当前路径重新注册任务；注册成功会发送一封 `Monitor enabled` 确认邮件。双击 `CampusNetworkMonitor.exe` 会打开可见控制面板；以后关闭窗口时选择“最小化到托盘”，图标会留在右下角通知区域。

如果另一台电脑上曾经注册过旧版本任务，直接点击“启动监控”即可重新写入当前目录的 exe 路径，不需要手动删除任务。

### 第一次配置

```cmd
CampusNetworkMonitor.exe -Setup
```

按顺序填写校园网账号、校园网密码、发件邮箱、收件邮箱和邮箱授权码。收件邮箱直接回车就会发给自己。常见邮箱会自动识别，不需要填写 SMTP username、From 或端口。

### 测试一次

```cmd
CampusNetworkMonitor.exe -Once
```

打包版不会在 CMD 中显示运行记录，请在控制面板的“最近活动”或 `campus-network-monitor.log` 中查看；看到 `Internet check passed` 表示当前网络检测成功。

### 开启自动监控

```cmd
CampusNetworkMonitor.exe -InstallTask
```

这一步会注册开机自动运行的监控任务，并发送 `Monitor enabled` 确认邮件。日常也可以直接在控制面板中点击“启动监控”；按钮会按当前电脑路径重新注册任务，并直接隐藏启动后台监控，不需要手动执行 `schtasks`。

### 查看是否正在运行

```cmd
schtasks /Query /TN "CampusNetworkMonitor" /FO LIST
```

### 开启开机自启

在快捷菜单中选择 `[5] 开启开机自启`，或在 CMD 中执行：

```cmd
CampusNetworkMonitor.exe -EnableStartup
```

这个选项同时控制两个登录任务：`CampusNetworkMonitor`（后台监控）和 `CampusNetworkMonitorPanel`（托盘控制面板）。开启后不会弹出完整控制面板，只会在右下角显示托盘图标，也不会重复启动当前监控。

如果之前已经开启过旧版开机自启，升级后请在控制面板中再点击一次“开机自启：开启”。程序会自动补建 `CampusNetworkMonitorPanel` 任务；之后下次登录 Windows 时就会同时启动监控和托盘图标。

### 关闭开机自启

在快捷菜单中选择 `[6] 关闭开机自启`，或在 CMD 中执行：

```cmd
CampusNetworkMonitor.exe -DisableStartup
```

关闭开机自启不会停止当前已经运行的监控；需要停止当前监控时，使用下面的“关闭监控”命令。

### 关闭监控并发送邮件

```cmd
CampusNetworkMonitor.exe -StopTask
```

这条命令会停止计划任务，并清理同一目录下遗留的监控进程，然后发送 `Monitor disabled` 通知邮件。关闭后，日志中不应再每分钟出现新的 `Internet check passed`。

### 再次手动启动

双击 `CampusNetworkMonitor.exe`，然后在控制面板点击“启动监控”。如果控制面板已经在托盘中，右键托盘图标选择“打开控制面板”，再点击“启动监控”。

### 删除自动监控任务

```cmd
CampusNetworkMonitor.exe -UninstallTask
```

### 查看最近日志

```cmd
powershell.exe -NoProfile -Command "Get-Content -LiteralPath '.\campus-network-monitor.log' -Tail 10"
```

密码保存在当前目录的 `campus-network.config.json` 中。输入时不会在屏幕显示，但文件中是明文保存，请不要把这个目录分享给别人。每封邮件都会自动包含电脑名，换电脑后可以区分来源。

## 配置要点

- `Portal.BaseUrl` 已设置为 `http://10.10.9.9`。
- `Portal.Service` 已设置为门户当前返回的默认服务 `shu`。
- `Portal.Mac` 和 `Portal.QueryString` 默认留空。程序会优先从当前网络的强制跳转中获取它们；只有特定校园网需要时才在本机配置中保存备用值。不要将实际值提交到 GitHub。
- `Check.IntervalSeconds` 可调检测间隔，单位为秒。

脚本不会执行下线操作，也不会把账号密码写入日志或邮件正文。若门户启用验证码、短信二次验证或修改了接口字段，自动认证会失败，日志中会保留门户返回的错误消息。
