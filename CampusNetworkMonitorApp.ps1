[CmdletBinding()]
param(
    [string]$ConfigPath = 'campus-network.config.json',
    [switch]$RunMonitor,
    [switch]$StartInTray,
    [switch]$Once,
    [switch]$Setup,
    [switch]$InstallTask,
    [switch]$StopTask,
    [switch]$UninstallTask,
    [switch]$EnableStartup,
    [switch]$DisableStartup,
    [switch]$RepairTasks,
    [switch]$ForceAuthenticate,
    [switch]$RepairOnStart,
    [switch]$StartMonitorAfterRepair,
    [switch]$ShowConfig,
    [string]$EntryPath = ''
)

$ErrorActionPreference = 'Stop'

$monitorModeRequested = $RunMonitor -or $Once -or $Setup -or $InstallTask -or $StopTask -or $UninstallTask -or $EnableStartup -or $DisableStartup -or $RepairTasks -or $ForceAuthenticate -or $ShowConfig
if ($monitorModeRequested) {
    $compiledRoot = [string](Get-Variable -Name ScriptRoot -ValueOnly -ErrorAction SilentlyContinue)
    $isCompiledHost = -not [string]::IsNullOrWhiteSpace($compiledRoot)
    $embeddedRoot = $compiledRoot
    if ([string]::IsNullOrWhiteSpace($embeddedRoot)) {
        $embeddedRoot = $PSScriptRoot
    }
    $embeddedRoot = [System.IO.Path]::GetFullPath($embeddedRoot)

    $forwardConfigPath = $ConfigPath
    if (-not [System.IO.Path]::IsPathRooted($forwardConfigPath)) {
        $forwardConfigPath = Join-Path $embeddedRoot $forwardConfigPath
    }

    $directoryMonitorScriptPath = Join-Path $embeddedRoot 'CampusNetworkMonitor.ps1'
    # Keep the monitor component beside the executable. This avoids relying on
    # temporary-directory extraction, which can be blocked by endpoint security.
    $monitorScriptPath = $directoryMonitorScriptPath
    if (-not (Test-Path -LiteralPath $monitorScriptPath -PathType Leaf)) {
        throw ('找不到后台监控组件：{0}。请完整复制 campus-network-monitor 文件夹。' -f $directoryMonitorScriptPath)
    }

    $monitorParameters = @{ ConfigPath = $forwardConfigPath }
    $entryArgument = $EntryPath
    if ([string]::IsNullOrWhiteSpace($entryArgument)) {
        try {
            $entryArgument = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        }
        catch {
            $entryArgument = ''
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($entryArgument) -and ([System.IO.Path]::GetExtension($entryArgument) -ieq '.exe') -and ([System.IO.Path]::GetFileName($entryArgument) -notmatch '(?i)^(powershell|pwsh)(\.exe)?$')) {
        $monitorParameters['EntryPath'] = $entryArgument
    }
    if ($Once) { $monitorParameters['Once'] = $true }
    if ($Setup) { $monitorParameters['Setup'] = $true }
    if ($InstallTask) { $monitorParameters['InstallTask'] = $true }
    if ($StopTask) { $monitorParameters['StopTask'] = $true }
    if ($UninstallTask) { $monitorParameters['UninstallTask'] = $true }
    if ($EnableStartup) { $monitorParameters['EnableStartup'] = $true }
    if ($DisableStartup) { $monitorParameters['DisableStartup'] = $true }
    if ($RepairTasks) { $monitorParameters['RepairTasks'] = $true }
    if ($ForceAuthenticate) { $monitorParameters['ForceAuthenticate'] = $true }
    if ($RunMonitor) { $monitorParameters['Background'] = $true }
    if ($ShowConfig) { $monitorParameters['ShowConfig'] = $true }

    # Invoke the component from its text so restrictive execution policies do
    # not block a companion .ps1 file when the user starts the packaged exe.
    $monitorSource = Get-Content -LiteralPath $monitorScriptPath -Raw -Encoding UTF8
    $monitorCommand = [scriptblock]::Create($monitorSource)
    # PS2EXE can materialize Write-Host and information-stream output as a
    # transient GUI window. Scheduled monitoring already writes to the log
    # file, so discard every host stream in the background entry point.
    if ($RunMonitor) {
        & $monitorCommand @monitorParameters *> $null
    }
    else {
        & $monitorCommand @monitorParameters
    }
    if (-not $?) {
        exit 1
    }
    exit 0
}

$StartInTray = [bool]$StartInTray -or (@($args) -contains '-StartInTray')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$compiledScriptRoot = [string](Get-Variable -Name ScriptRoot -ValueOnly -ErrorAction SilentlyContinue)
$script:CurrentExecutablePath = ''
try {
    $runtimeExecutablePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if (-not [string]::IsNullOrWhiteSpace($runtimeExecutablePath) -and
        (Test-Path -LiteralPath $runtimeExecutablePath -PathType Leaf) -and
        ([System.IO.Path]::GetFileName($runtimeExecutablePath) -notmatch '(?i)^(powershell|pwsh)(\.exe)?$')) {
        $script:CurrentExecutablePath = [System.IO.Path]::GetFullPath($runtimeExecutablePath)
    }
}
catch {
    $script:CurrentExecutablePath = ''
}
if (-not [string]::IsNullOrWhiteSpace($script:CurrentExecutablePath)) {
    $script:Directory = Split-Path -Parent $script:CurrentExecutablePath
}
elseif (-not [string]::IsNullOrWhiteSpace($compiledScriptRoot)) {
    $script:Directory = [System.IO.Path]::GetFullPath($compiledScriptRoot)
}
else {
    $script:Directory = [System.IO.Path]::GetFullPath($PSScriptRoot)
}
$script:MonitorScript = Join-Path $script:Directory 'CampusNetworkMonitor.ps1'
$script:MonitorExecutable = Join-Path $script:Directory 'CampusNetworkMonitor.exe'
$script:SingleExecutableMode = ([System.IO.Path]::GetFileName($script:CurrentExecutablePath) -ieq 'CampusNetworkMonitor.exe')
if (-not $script:SingleExecutableMode -and (Test-Path -LiteralPath $script:MonitorExecutable -PathType Leaf) -and -not (Test-Path -LiteralPath (Join-Path $script:Directory 'CampusNetworkMonitorPanel.exe') -PathType Leaf)) {
    $script:SingleExecutableMode = $true
    $script:CurrentExecutablePath = $script:MonitorExecutable
}
$script:ConfigPath = if ([System.IO.Path]::IsPathRooted($ConfigPath)) { [System.IO.Path]::GetFullPath($ConfigPath) } else { [System.IO.Path]::GetFullPath((Join-Path $script:Directory $ConfigPath)) }
$script:LogPath = Join-Path $script:Directory 'campus-network-monitor.log'
$script:PowerShellPath = Join-Path $PSHOME 'powershell.exe'
$script:TaskName = 'CampusNetworkMonitor'
$script:PanelTaskName = 'CampusNetworkMonitorPanel'
$script:BackendProcess = $null
$script:BackendTimer = $null
$script:BackendOperation = ''
$script:BackendCallback = $null
$script:Form = $null
$script:TrayIcon = $null
$script:TrayStartItem = $null
$script:TrayStopItem = $null
$script:TrayStartupItem = $null
$script:UninstallButton = $null
$script:AllowExit = $false
$script:ClosePromptShowing = $false
$script:TrayBitmap = $null
$script:TrayIconHandle = [IntPtr]::Zero
$script:BrandBitmap = $null
$script:StatusTimer = $null
$script:ApplicationContext = $null
$script:AppInitialized = $false
$script:RepairOnStart = [bool]$RepairOnStart
$script:StartMonitorAfterRepair = [bool]$StartMonitorAfterRepair
$script:AppMutex = $null
$script:ActivationEvent = $null
$script:ActivationTimer = $null

# A Windows logon task is intentionally single-instance and starts in the tray.
# A manual double-click must always open a visible panel, even if the tray signal fails.
if ($StartInTray) {
    [bool]$appMutexCreated = $false
    $script:AppMutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $true, 'Local\CampusNetworkMonitorPanel', ([ref]$appMutexCreated)
    if (-not $appMutexCreated) {
        try {
            $activationEvent = [System.Threading.EventWaitHandle]::OpenExisting('Local\CampusNetworkMonitorPanelActivation')
            [void]$activationEvent.Set()
            $activationEvent.Dispose()
        }
        catch {
        }
        exit 0
    }

    [bool]$activationEventCreated = $false
    try {
        $script:ActivationEvent = New-Object -TypeName System.Threading.EventWaitHandle -ArgumentList $false, ([System.Threading.EventResetMode]::AutoReset), 'Local\CampusNetworkMonitorPanelActivation', ([ref]$activationEventCreated)
    }
    catch {
        $script:ActivationEvent = $null
    }
}

$script:Colors = @{
    Teal = [System.Drawing.Color]::FromArgb(15, 118, 110)
    TealDark = [System.Drawing.Color]::FromArgb(17, 94, 89)
    Blue = [System.Drawing.Color]::FromArgb(37, 99, 235)
    BlueSoft = [System.Drawing.Color]::FromArgb(239, 246, 255)
    Green = [System.Drawing.Color]::FromArgb(22, 101, 52)
    GreenSoft = [System.Drawing.Color]::FromArgb(240, 253, 244)
    Orange = [System.Drawing.Color]::FromArgb(194, 65, 12)
    OrangeSoft = [System.Drawing.Color]::FromArgb(255, 247, 237)
    Red = [System.Drawing.Color]::FromArgb(185, 28, 28)
    RedSoft = [System.Drawing.Color]::FromArgb(254, 242, 242)
    Text = [System.Drawing.Color]::FromArgb(31, 41, 55)
    Muted = [System.Drawing.Color]::FromArgb(107, 114, 128)
    Border = [System.Drawing.Color]::FromArgb(226, 232, 240)
    Panel = [System.Drawing.Color]::FromArgb(248, 250, 252)
    White = [System.Drawing.Color]::White
}

function New-AppFont {
    param(
        [float]$Size = 10,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )

    return New-Object -TypeName System.Drawing.Font -ArgumentList @('Microsoft YaHei UI', $Size, $Style)
}

function Get-ApplicationIcon {
    $iconFile = Join-Path $script:Directory 'CampusNetworkMonitor.ico'
    if (Test-Path -LiteralPath $iconFile -PathType Leaf) {
        try {
            return New-Object -TypeName System.Drawing.Icon -ArgumentList $iconFile
        }
        catch {
        }
    }

    $iconPath = $script:CurrentExecutablePath
    if ([string]::IsNullOrWhiteSpace($iconPath)) {
        try {
            $iconPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        }
        catch {
            $iconPath = ''
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($iconPath) -and (Test-Path -LiteralPath $iconPath -PathType Leaf) -and ([System.IO.Path]::GetFileName($iconPath) -notmatch '(?i)^(powershell|pwsh)(\.exe)?$')) {
        try {
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
            if ($icon) {
                return $icon
            }
        }
        catch {
        }
    }

    return [System.Drawing.SystemIcons]::Application
}

function Get-ApplicationBitmap {
    $icon = Get-ApplicationIcon
    try {
        return $icon.ToBitmap()
    }
    finally {
        if ($icon -and $icon -ne [System.Drawing.SystemIcons]::Application) {
            $icon.Dispose()
        }
    }
}

function New-TrayIcon {
    $bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList 32, 32
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $tealBrush = New-Object -TypeName System.Drawing.SolidBrush -ArgumentList $script:Colors.Teal
    $whiteBrush = New-Object -TypeName System.Drawing.SolidBrush -ArgumentList $script:Colors.White
    $orangeBrush = New-Object -TypeName System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(249, 115, 22))
    $linePen = New-Object -TypeName System.Drawing.Pen -ArgumentList $script:Colors.White, 2.2

    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.FillEllipse($tealBrush, 2, 2, 28, 28)
        $graphics.DrawLine($linePen, 10, 16, 16, 10)
        $graphics.DrawLine($linePen, 16, 10, 22, 16)
        $graphics.DrawLine($linePen, 10, 16, 22, 16)
        $graphics.FillEllipse($whiteBrush, 7, 13, 6, 6)
        $graphics.FillEllipse($whiteBrush, 13, 7, 6, 6)
        $graphics.FillEllipse($whiteBrush, 19, 13, 6, 6)
        $graphics.FillEllipse($orangeBrush, 13, 21, 6, 6)
    }
    finally {
        $linePen.Dispose()
        $orangeBrush.Dispose()
        $whiteBrush.Dispose()
        $tealBrush.Dispose()
        $graphics.Dispose()
    }

    $script:TrayBitmap = $bitmap
    $script:TrayIconHandle = $bitmap.GetHicon()
    return [System.Drawing.Icon]::FromHandle($script:TrayIconHandle)
}

function New-DefaultConfiguration {
    return [pscustomobject]@{
        Check = [pscustomobject]@{
            Host = 'www.baidu.com'
            Count = 1
            RetryCount = 2
            RetryIntervalSeconds = 3
            IntervalSeconds = 60
        }
        Portal = [pscustomobject]@{
            BaseUrl = 'http://10.10.9.9'
            ApiPath = '/eportal/InterFace.do'
            Service = 'shu'
            QueryString = ''
            Mac = ''
            UsernamePrefix = ''
        }
        Credentials = [pscustomobject]@{
            Username = ''
            Password = ''
        }
        Email = [pscustomobject]@{
            Enabled = $true
            Address = ''
            Recipient = ''
            Password = ''
            SmtpServer = ''
            Port = 587
            UseSsl = $true
            SubjectPrefix = '[Campus network] '
        }
        Runtime = [pscustomobject]@{
            AuthAttempts = 3
            AuthRetryDelaySeconds = 5
            AfterAuthWaitSeconds = 3
            NotificationCooldownMinutes = 30
            LogFile = 'campus-network-monitor.log'
            TaskName = 'CampusNetworkMonitor'
        }
    }
}

function Get-Configuration {
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
        return New-DefaultConfiguration
    }

    $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw '配置文件为空。'
    }
    return ($raw | ConvertFrom-Json)
}

function Save-Configuration {
    param([Parameter(Mandatory = $true)]$Configuration)

    $Configuration | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
}

function Get-AutoSmtpSettings {
    param([Parameter(Mandatory = $true)][string]$Address)

    $at = $Address.LastIndexOf('@')
    if ($at -lt 0 -or $at -eq ($Address.Length - 1)) {
        return [pscustomobject]@{ Server = ''; Port = 587 }
    }

    $domain = $Address.Substring($at + 1).Trim().ToLowerInvariant()
    switch -Regex ($domain) {
        '^qq\.com$' { return [pscustomobject]@{ Server = 'smtp.qq.com'; Port = 587 } }
        '^foxmail\.com$' { return [pscustomobject]@{ Server = 'smtp.qq.com'; Port = 587 } }
        '^(163|126|yeah)\.com$' { return [pscustomobject]@{ Server = ('smtp.{0}' -f $domain); Port = 25 } }
        '^gmail\.com$' { return [pscustomobject]@{ Server = 'smtp.gmail.com'; Port = 587 } }
        '^(outlook|hotmail|live)\.(com|cn)$' { return [pscustomobject]@{ Server = 'smtp-mail.outlook.com'; Port = 587 } }
    }
    return [pscustomobject]@{ Server = ''; Port = 587 }
}

function Get-ComputerName {
    $name = [string]$env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = [Environment]::MachineName
    }
    return $name
}

function Test-MonitorRunning {
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::OpenExisting('Local\CampusNetworkMonitor')
        return $true
    }
    catch [System.Threading.WaitHandleCannotBeOpenedException] {
        return $false
    }
    catch [System.UnauthorizedAccessException] {
        return $true
    }
    catch {
        return $true
    }
    finally {
        if ($mutex) {
            $mutex.Dispose()
        }
    }
}

function Get-MonitorStatus {
    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    $state = '未安装'
    $monitorStartup = $false

    if ($task) {
        $state = [string]$task.State
        $triggers = @($task.Triggers)
        $enabledTriggers = @($triggers | Where-Object { [bool]$_.Enabled })
        $monitorStartup = ([bool]$task.Settings.Enabled) -and ($enabledTriggers.Count -gt 0)
    }

    $panelTask = Get-ScheduledTask -TaskName $script:PanelTaskName -ErrorAction SilentlyContinue
    $panelStartup = $false
    if ($panelTask) {
        $panelTriggers = @($panelTask.Triggers)
        $enabledPanelTriggers = @($panelTriggers | Where-Object { [bool]$_.Enabled })
        $panelStartup = ([bool]$panelTask.Settings.Enabled) -and ($enabledPanelTriggers.Count -gt 0)
    }

    $lastLog = ''
    if (Test-Path -LiteralPath $script:LogPath -PathType Leaf) {
        $lastLog = [string](Get-Content -LiteralPath $script:LogPath -Tail 1 -Encoding UTF8)
    }

    return [pscustomobject]@{
        TaskExists = [bool]$task
        TaskState = $state
        StartupEnabled = $monitorStartup -and $panelStartup
        PanelTaskExists = [bool]$panelTask
        PanelTaskState = if ($panelTask) { [string]$panelTask.State } else { '未安装' }
        MonitorRunning = (Test-MonitorRunning)
        LastLog = $lastLog
    }
}

function Add-Activity {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [System.Drawing.Color]$Color = $script:Colors.Text
    )

    if (-not $script:ActivityBox) {
        return
    }
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    $script:ActivityBox.SelectionStart = $script:ActivityBox.TextLength
    $script:ActivityBox.SelectionColor = $Color
    $script:ActivityBox.AppendText($line + [Environment]::NewLine)
    $script:ActivityBox.ScrollToCaret()
}

function Set-NetworkVisualState {
    param([string]$LastLog)

    $state = '等待检测'
    $detail = '后台监控正在等待下一次网络检查。'
    $color = $script:Colors.Orange

    if ($LastLog -match 'Internet check passed') {
        $state = '网络正常'
        $detail = '当前可以访问互联网，校园网认证保持正常。'
        $color = $script:Colors.Green
    }
    elseif ($LastLog -match '(?i)auth|认证|login') {
        $state = '正在认证'
        $detail = '检测到网络需要认证，后台正在尝试恢复连接。'
        $color = $script:Colors.Blue
    }
    elseif ($LastLog -match '(?i)error|failed|offline|unreachable|断网|失败') {
        $state = '网络异常'
        $detail = '最近一次检查未通过，请查看运行记录或立即检测。'
        $color = $script:Colors.Red
    }

    if ($script:NetworkStateLabel) {
        $script:NetworkStateLabel.Text = $state
        $script:NetworkStateLabel.ForeColor = $color
    }
    if ($script:NetworkDetailLabel) {
        $script:NetworkDetailLabel.Text = $detail
    }
    if ($script:NetworkDotLabel) {
        $script:NetworkDotLabel.ForeColor = $color
    }
    if ($script:HeaderNetworkLabel) {
        $script:HeaderNetworkLabel.Text = $state
        $script:HeaderNetworkLabel.ForeColor = $color
    }
}

function Set-ActionButtons {
    param([bool]$Enabled)

    foreach ($button in @($script:StartButton, $script:StopButton, $script:TestButton, $script:StartupButton, $script:SettingsButton, $script:RefreshButton, $script:LogButton, $script:FolderButton, $script:UninstallButton)) {
        if ($button) {
            $button.Enabled = $Enabled
        }
    }
}

function Refresh-Status {
    try {
        $status = Get-MonitorStatus
        if ($status.MonitorRunning) {
            $script:MonitorValue.Text = '运行中'
            $script:MonitorValue.ForeColor = $script:Colors.Green
        }
        else {
            $script:MonitorValue.Text = '未运行'
            $script:MonitorValue.ForeColor = $script:Colors.Orange
        }

        if ($status.StartupEnabled) {
            $script:StartupValue.Text = '已开启'
            $script:StartupValue.ForeColor = $script:Colors.Green
            $script:StartupButton.Text = '已开启'
            $script:StartupButton.BackColor = $script:Colors.GreenSoft
            $script:StartupButton.ForeColor = $script:Colors.Green
            if ($script:StartupButton -is [System.Windows.Forms.CheckBox]) { $script:StartupButton.Checked = $true }
        }
        else {
            $script:StartupValue.Text = '未开启'
            $script:StartupValue.ForeColor = $script:Colors.Orange
            $script:StartupButton.Text = '未开启'
            $script:StartupButton.BackColor = $script:Colors.Panel
            $script:StartupButton.ForeColor = $script:Colors.Muted
            if ($script:StartupButton -is [System.Windows.Forms.CheckBox]) { $script:StartupButton.Checked = $false }
        }

        $taskText = switch ([string]$status.TaskState) {
            'Running' { '运行中'; break }
            'Ready' { '已就绪'; break }
            'Disabled' { '已禁用'; break }
            'Unknown' { '未知'; break }
            default { [string]$status.TaskState; break }
        }
        $script:TaskValue.Text = $taskText
        $script:TaskValue.ForeColor = switch ([string]$status.TaskState) {
            'Running' { $script:Colors.Green; break }
            'Ready' { $script:Colors.Green; break }
            'Disabled' { $script:Colors.Orange; break }
            default { if ($status.TaskExists) { $script:Colors.Orange } else { $script:Colors.Red }; break }
        }
        $script:LastLogValue.Text = if ([string]::IsNullOrWhiteSpace($status.LastLog)) { '暂无记录' } else { $status.LastLog }
        if ($script:TaskDetailLabel) {
            if ($status.PanelTaskExists) {
                $script:TaskDetailLabel.Text = if ([string]$status.TaskState -eq 'Ready') { '已注册，等待下次登录自动启动' } elseif ($status.MonitorRunning) { '监控任务和托盘任务已注册' } else { '任务已注册，当前监控未运行' }
            }
            else {
                $script:TaskDetailLabel.Text = if ($status.TaskExists) { '点击“开机自动运行”补注册托盘任务' } else { '首次使用请点击“开机自动运行”' }
            }
        }
        Set-NetworkVisualState -LastLog $status.LastLog
        $script:FooterLabel.Text = '就绪  |  最后刷新：{0}' -f (Get-Date -Format 'HH:mm:ss')
    }
    catch {
        $script:FooterLabel.Text = '状态读取失败：{0}' -f $_.Exception.Message
    }
}

function Show-BackendOutput {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }
    foreach ($line in ($Text -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $color = $script:Colors.Muted
            if ($line -match '\[ERROR\]') { $color = $script:Colors.Red }
            elseif ($line -match '\[WARN\]') { $color = $script:Colors.Orange }
            elseif ($line -match 'Internet check passed|success|sent|成功') { $color = $script:Colors.Green }
            elseif ($line -match '(?i)auth|认证|login') { $color = $script:Colors.Blue }
            Add-Activity -Message $line.Trim() -Color $color
        }
    }
}

function Complete-BackendOperation {
    if (-not $script:BackendProcess -or -not $script:BackendProcess.HasExited) {
        return
    }

    $process = $script:BackendProcess
    $operation = $script:BackendOperation
    $callback = $script:BackendCallback
    $script:BackendTimer.Stop()

    $stdout = ''
    $stderr = ''
    try { $stdout = $process.StandardOutput.ReadToEnd() } catch { }
    try { $stderr = $process.StandardError.ReadToEnd() } catch { }
    $exitCode = $process.ExitCode
    $process.Dispose()

    $script:BackendProcess = $null
    $script:BackendOperation = ''
    $script:BackendCallback = $null
    Set-ActionButtons -Enabled $true
    Show-BackendOutput -Text $stdout
    Show-BackendOutput -Text $stderr

    if ($exitCode -eq 0) {
        Add-Activity -Message ('完成：{0}' -f $operation) -Color $script:Colors.Green
    }
    else {
        Add-Activity -Message ('失败：{0}（退出码 {1}）' -f $operation, $exitCode) -Color $script:Colors.Red
    }

    if ($callback) {
        & $callback $exitCode | Out-Null
    }
    Refresh-Status
}

function Get-SingleExecutablePath {
    $candidates = @($script:CurrentExecutablePath, $script:MonitorExecutable)
    try {
        $candidates += [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    }
    catch {
    }

    foreach ($candidate in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        try {
            $fullPath = [System.IO.Path]::GetFullPath([string]$candidate)
            $directory = Split-Path -Parent $fullPath
            $isCurrentRuntimeExecutable = -not [string]::IsNullOrWhiteSpace($script:CurrentExecutablePath) -and
                ($fullPath -ieq [System.IO.Path]::GetFullPath($script:CurrentExecutablePath))
            $isSingleExecutable = ([System.IO.Path]::GetFileName($fullPath) -ieq 'CampusNetworkMonitor.exe') -and
                (Test-Path -LiteralPath $fullPath -PathType Leaf) -and
                ($isCurrentRuntimeExecutable -or -not (Test-Path -LiteralPath (Join-Path $directory 'CampusNetworkMonitorPanel.exe') -PathType Leaf))
            if ($isSingleExecutable) {
                return $fullPath
            }
        }
        catch {
        }
    }
    return ''
}

function Start-BackendOperation {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Description,
        [scriptblock]$OnCompleted
    )

    if ($script:BackendProcess -and -not $script:BackendProcess.HasExited) {
        Add-Activity -Message '已有操作正在执行，请稍候。' -Color $script:Colors.Orange
        return
    }

    try {
        $psi = New-Object -TypeName System.Diagnostics.ProcessStartInfo
        $singleExecutablePath = Get-SingleExecutablePath
        if (-not [string]::IsNullOrWhiteSpace($singleExecutablePath)) {
            $psi.FileName = $singleExecutablePath
            $psi.Arguments = '-RunMonitor -EntryPath "{0}" -ConfigPath "{1}" {2}' -f $singleExecutablePath, $script:ConfigPath, ($Arguments -join ' ')
        }
        elseif (Test-Path -LiteralPath $script:MonitorExecutable -PathType Leaf) {
            $psi.FileName = $script:MonitorExecutable
            $psi.Arguments = ('-ConfigPath "{0}" {1}' -f $script:ConfigPath, ($Arguments -join ' ')).Trim()
        }
        else {
            $psi.FileName = $script:PowerShellPath
            $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -ConfigPath "{1}" {2}' -f $script:MonitorScript, $script:ConfigPath, ($Arguments -join ' ')
        }
        $psi.WorkingDirectory = $script:Directory
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $process = New-Object -TypeName System.Diagnostics.Process
        $process.StartInfo = $psi
        if (-not $process.Start()) {
            throw '无法启动后台操作。'
        }

        $script:BackendProcess = $process
        $script:BackendOperation = $Description
        $script:BackendCallback = $OnCompleted
        Set-ActionButtons -Enabled $false
        Add-Activity -Message ('正在执行：{0}' -f $Description) -Color $script:Colors.Blue
        $script:BackendTimer.Start()
    }
    catch {
        Add-Activity -Message ('无法执行 {0}：{1}' -f $Description, $_.Exception.Message) -Color $script:Colors.Red
        Set-ActionButtons -Enabled $true
    }
}

function Start-DetachedMonitor {
    # The task uses WScript to create the monitor with no visible window.
    # Starting the executable directly here can briefly show PS2EXE's output
    # form, even when ProcessStartInfo requests a hidden window.
    Start-ScheduledTask -TaskName 'CampusNetworkMonitor' -ErrorAction Stop

    # A newly copied exe can take several seconds to start while Windows
    # performs its first security scan. Do not report a false startup failure.
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        if (Test-MonitorRunning) {
            return
        }
        Start-Sleep -Milliseconds 100
    }

    throw '后台监控程序未能成功运行，请查看日志文件。'
}

function Start-Monitor {
    if (Test-MonitorRunning) {
        Add-Activity -Message '监控已经在运行，没有重复启动。' -Color $script:Colors.Orange
        return
    }

    Start-BackendOperation -Arguments @('-InstallTask') -Description '启动监控' -OnCompleted {
        param($exitCode)
        if ($exitCode -ne 0) { return }
        try {
            Start-DetachedMonitor
            Add-Activity -Message '监控已启动，正在后台检查网络；当前目录已写入计划任务。' -Color $script:Colors.Green
        }
        catch {
            Add-Activity -Message ('后台监控启动失败：{0}' -f $_.Exception.Message) -Color $script:Colors.Red
        }
    }
}

function Stop-Monitor {
    Start-BackendOperation -Arguments @('-StopTask') -Description '停止监控并发送通知邮件'
}

function Get-ApplicationFiles {
    $files = @(
        $script:CurrentExecutablePath
        (Join-Path $script:Directory 'CampusNetworkMonitor.exe')
        (Join-Path $script:Directory 'CampusNetworkMonitor.exe.config')
        (Join-Path $script:Directory 'CampusNetworkMonitorPanel.exe')
        (Join-Path $script:Directory 'CampusNetworkMonitor.ps1')
        (Join-Path $script:Directory 'CampusNetworkMonitorApp.ps1')
        (Join-Path $script:Directory 'CampusNetworkMenu.ps1')
        (Join-Path $script:Directory 'CampusNetworkMenu.bat')
        (Join-Path $script:Directory 'CampusNetworkMonitor.ico')
        (Join-Path $script:Directory 'CampusNetworkMonitorLauncher.vbs')
        (Join-Path $script:Directory 'campus-network.config.json')
        (Join-Path $script:Directory 'campus-network-monitor.log')
        (Join-Path $script:Directory 'README.md')
    )

    return @($files | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
        try { [System.IO.Path]::GetFullPath([string]$_) } catch { }
    } | Sort-Object -Unique)
}

function Stop-ApplicationMonitorProcesses {
    $currentProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $processes = @()
    try {
        $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | Where-Object {
            if ([int]$_.ProcessId -eq $currentProcessId) {
                return $false
            }

            $name = [string]$_.Name
            $commandLine = [string]$_.CommandLine
            if ($name -ieq 'CampusNetworkMonitor.exe') {
                return ($commandLine -match '(?i)(?:^|\s)-RunMonitor(?:\s|$)')
            }
            if ($name -match '(?i)^(powershell|pwsh)(\.exe)?$') {
                return ($commandLine -match '(?i)CampusNetworkMonitor(?:-embedded)?\.ps1') -and
                    ($commandLine -notmatch '(?i)(?:^|\s)-StartInTray(?:\s|$)')
            }
            return $false
        })
    }
    catch {
        return
    }

    foreach ($process in $processes) {
        try { Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function New-UninstallCleanupScript {
    param([Parameter(Mandatory = $true)][string[]]$Files)

    $cleanupPath = Join-Path ([System.IO.Path]::GetTempPath()) ('CampusNetworkMonitor-uninstall-{0}.ps1' -f [Guid]::NewGuid().ToString('N'))
    $fileLines = ($Files | ForEach-Object {
        "    '{0}'" -f ([string]$_ -replace "'", "''")
    }) -join [Environment]::NewLine
    $directory = [string]$script:Directory -replace "'", "''"
    $cleanupContent = @"
`$ErrorActionPreference = 'SilentlyContinue'
Start-Sleep -Seconds 2
`$files = @(
$fileLines
)
for (`$attempt = 0; `$attempt -lt 20; `$attempt++) {
    `$remainingFiles = @()
    foreach (`$file in `$files) {
        if (-not [string]::IsNullOrWhiteSpace([string]`$file) -and (Test-Path -LiteralPath `$file -PathType Leaf)) {
            try { [System.IO.File]::Delete([System.IO.Path]::GetFullPath(`$file)) } catch { }
            if (Test-Path -LiteralPath `$file -PathType Leaf) {
                `$remainingFiles += `$file
            }
        }
    }
    if (`$remainingFiles.Count -eq 0) {
        break
    }
    Start-Sleep -Milliseconds 500
}
`$directory = '$directory'
if (Test-Path -LiteralPath `$directory -PathType Container) {
    `$remaining = @(Get-ChildItem -LiteralPath `$directory -Force)
    if (`$remaining.Count -eq 0) {
        [System.IO.Directory]::Delete(`$directory)
    }
}
try { [System.IO.File]::Delete(`$PSCommandPath) } catch { }
"@
    Set-Content -LiteralPath $cleanupPath -Value $cleanupContent -Encoding UTF8
    return $cleanupPath
}

function Start-UninstallCleanup {
    param([Parameter(Mandatory = $true)][string]$CleanupPath)

    $psi = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:PowerShellPath
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $CleanupPath
    $psi.WorkingDirectory = $script:Directory
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $process = New-Object -TypeName System.Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        throw '无法启动卸载清理程序。'
    }
    $process.Dispose()
}

function Uninstall-Application {
    if ($script:BackendProcess -and -not $script:BackendProcess.HasExited) {
        Show-Message -Message '当前操作尚未完成，请稍候再卸载软件。' -Icon Warning
        return
    }

    $message = "确定要卸载校园网监控吗？`r`n`r`n将停止网络监控、删除两个计划任务，并删除本目录中的程序、配置和日志文件。账号密码和日志删除后无法恢复。"
    $choice = [System.Windows.Forms.MessageBox]::Show($script:Form, $message, '卸载校园网监控', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $cleanupPath = $null
    try {
        $cleanupPath = New-UninstallCleanupScript -Files (Get-ApplicationFiles)
        Start-UninstallCleanup -CleanupPath $cleanupPath

        $script:AllowExit = $true
        if ($script:TrayIcon) {
            $script:TrayIcon.Visible = $false
        }

        foreach ($taskName in @($script:TaskName, $script:PanelTaskName)) {
            try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch { }
            try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
        }
        Stop-ApplicationMonitorProcesses
        $script:Form.Close()
    }
    catch {
        if ($cleanupPath -and (Test-Path -LiteralPath $cleanupPath -PathType Leaf)) {
            try { [System.IO.File]::Delete($cleanupPath) } catch { }
        }
        Show-Message -Message ('卸载未完成：{0}' -f $_.Exception.Message) -Icon Error
    }
}

function Test-Network {
    Start-BackendOperation -Arguments @('-Once') -Description '检测网络并按需认证'
}

function Toggle-Startup {
    $status = Get-MonitorStatus
    $argument = if ($status.StartupEnabled) { '-DisableStartup' } else { '-EnableStartup' }
    $description = if ($status.StartupEnabled) { '关闭开机自启' } else { '开启开机自启' }
    Start-BackendOperation -Arguments @($argument) -Description $description
}

function Open-LogFile {
    if (Test-Path -LiteralPath $script:LogPath) {
        Start-Process -FilePath notepad.exe -ArgumentList ('"{0}"' -f $script:LogPath)
    }
    else {
        Show-Message -Message '日志文件还不存在。'
    }
}

function Open-WorkDirectory {
    Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f $script:Directory)
}

function Initialize-AppState {
    if ($script:AppInitialized) {
        return
    }
    $script:AppInitialized = $true
    Refresh-Status
    Add-Activity -Message '控制面板已启动。监控会在后台独立运行。' -Color $script:Colors.TealDark
    if ($script:RepairOnStart) {
        Add-Activity -Message '正在按本机当前路径检查计划任务。' -Color $script:Colors.Blue
        Start-BackendOperation -Arguments @('-RepairTasks') -Description '修复本机计划任务' -OnCompleted {
            param($exitCode)
            if ($exitCode -eq 0) {
                Add-Activity -Message '本机监控任务和托盘任务已准备好。' -Color $script:Colors.Green
                if ($script:StartMonitorAfterRepair -and -not (Test-MonitorRunning)) {
                    try {
                        Start-DetachedMonitor
                        Add-Activity -Message '后台监控已自动启动。' -Color $script:Colors.Green
                    }
                    catch {
                        Add-Activity -Message ('后台监控自动启动失败：{0}' -f $_.Exception.Message) -Color $script:Colors.Red
                    }
                }
            }
        }
    }
    if ($script:StatusTimer) {
        $script:StatusTimer.Start()
    }
    if ($script:ActivationTimer) {
        $script:ActivationTimer.Start()
    }
}

function Show-AppWindow {
    if (-not $script:Form -or $script:Form.IsDisposed) {
        return
    }
    $script:Form.ShowInTaskbar = $true
    $script:Form.Show()
    $script:Form.WindowState = 'Normal'
    $script:Form.Activate()
    $script:Form.BringToFront()
}

function Hide-AppToTray {
    if ($script:TrayIcon) {
        $script:TrayIcon.Visible = $true
    }
    $script:Form.ShowInTaskbar = $false
    $script:Form.Hide()
}

function Exit-App {
    if ($script:BackendProcess -and -not $script:BackendProcess.HasExited) {
        Show-Message -Message '当前操作尚未完成，请稍候再退出控制面板。' -Icon Warning
        return
    }
    $script:AllowExit = $true
    if ($script:TrayIcon) {
        $script:TrayIcon.Visible = $false
    }
    $script:Form.Close()
}

function Show-CloseChoice {
    $choiceForm = New-Object -TypeName System.Windows.Forms.Form
    $choiceForm.Text = '关闭控制面板'
    $choiceForm.StartPosition = 'CenterParent'
    $choiceForm.ClientSize = New-Object -TypeName System.Drawing.Size -ArgumentList 470, 220
    $choiceForm.FormBorderStyle = 'FixedDialog'
    $choiceForm.MaximizeBox = $false
    $choiceForm.MinimizeBox = $false
    $choiceForm.ShowInTaskbar = $false
    $choiceForm.BackColor = $script:Colors.White
    $choiceForm.Font = New-AppFont -Size 10
    $choiceForm.Icon = [System.Drawing.SystemIcons]::Question

    $title = New-Object -TypeName System.Windows.Forms.Label
    $title.Text = '要如何关闭控制面板？'
    $title.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 24, 20
    $title.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 410, 30
    $title.Font = New-AppFont -Size 14 -Style Bold
    $title.ForeColor = $script:Colors.TealDark
    $choiceForm.Controls.Add($title)

    $description = New-Object -TypeName System.Windows.Forms.Label
    $description.Text = '后台监控会继续运行，关闭窗口不会停止校园网检测。'
    $description.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 26, 58
    $description.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 410, 26
    $description.ForeColor = $script:Colors.Muted
    $description.Font = New-AppFont -Size 9
    $choiceForm.Controls.Add($description)

    $trayButton = New-Object -TypeName System.Windows.Forms.Button
    $trayButton.Text = '最小化到托盘'
    $trayButton.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 24, 116
    $trayButton.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 132, 40
    $trayButton.BackColor = $script:Colors.Teal
    $trayButton.ForeColor = $script:Colors.White
    $trayButton.FlatStyle = 'Flat'
    $trayButton.FlatAppearance.BorderSize = 0
    $trayButton.Font = New-AppFont -Size 9 -Style Bold
    $trayButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $choiceForm.Controls.Add($trayButton)

    $exitButton = New-Object -TypeName System.Windows.Forms.Button
    $exitButton.Text = '直接退出'
    $exitButton.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 169, 116
    $exitButton.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 132, 40
    $exitButton.BackColor = [System.Drawing.Color]::FromArgb(255, 247, 237)
    $exitButton.ForeColor = $script:Colors.Orange
    $exitButton.FlatStyle = 'Flat'
    $exitButton.FlatAppearance.BorderSize = 0
    $exitButton.Font = New-AppFont -Size 9 -Style Bold
    $exitButton.DialogResult = [System.Windows.Forms.DialogResult]::No
    $choiceForm.Controls.Add($exitButton)

    $cancelButton = New-Object -TypeName System.Windows.Forms.Button
    $cancelButton.Text = '取消'
    $cancelButton.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 314, 116
    $cancelButton.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 122, 40
    $cancelButton.BackColor = $script:Colors.Panel
    $cancelButton.ForeColor = $script:Colors.Text
    $cancelButton.FlatStyle = 'Flat'
    $cancelButton.FlatAppearance.BorderColor = $script:Colors.Border
    $cancelButton.Font = New-AppFont -Size 9
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $choiceForm.Controls.Add($cancelButton)
    $choiceForm.CancelButton = $cancelButton

    try {
        if ($script:BackendProcess -and -not $script:BackendProcess.HasExited) {
            Show-Message -Message '当前操作尚未完成，请稍候再关闭控制面板。' -Icon Warning
        }
        else {
            [void]$choiceForm.ShowDialog($script:Form)
            if ($choiceForm.DialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                $hideAction = [System.Windows.Forms.MethodInvoker]{ Hide-AppToTray }
                [void]$script:Form.BeginInvoke($hideAction)
            }
            elseif ($choiceForm.DialogResult -eq [System.Windows.Forms.DialogResult]::No) {
                $script:AllowExit = $true
                if ($script:TrayIcon) {
                    $script:TrayIcon.Visible = $false
                }
                $exitAction = [System.Windows.Forms.MethodInvoker]{ $script:Form.Close() }
                [void]$script:Form.BeginInvoke($exitAction)
            }
        }
    }
    finally {
        $choiceForm.Dispose()
        $script:ClosePromptShowing = $false
    }
}

function New-TrayMenu {
    $menu = New-Object -TypeName System.Windows.Forms.ContextMenuStrip

    $openItem = New-Object -TypeName System.Windows.Forms.ToolStripMenuItem
    $openItem.Text = '打开控制面板'
    $openItem.Add_Click({ Show-AppWindow })
    [void]$menu.Items.Add($openItem)
    [void]$menu.Items.Add((New-Object -TypeName System.Windows.Forms.ToolStripSeparator))

    $script:TrayStartItem = New-Object -TypeName System.Windows.Forms.ToolStripMenuItem
    $script:TrayStartItem.Text = '启动监控'
    $script:TrayStartItem.Add_Click({ Start-Monitor })
    [void]$menu.Items.Add($script:TrayStartItem)

    $script:TrayStopItem = New-Object -TypeName System.Windows.Forms.ToolStripMenuItem
    $script:TrayStopItem.Text = '停止监控'
    $script:TrayStopItem.Add_Click({ Stop-Monitor })
    [void]$menu.Items.Add($script:TrayStopItem)

    $testItem = New-Object -TypeName System.Windows.Forms.ToolStripMenuItem
    $testItem.Text = '立即检测网络'
    $testItem.Add_Click({ Test-Network })
    [void]$menu.Items.Add($testItem)

    $script:TrayStartupItem = New-Object -TypeName System.Windows.Forms.ToolStripMenuItem
    $script:TrayStartupItem.Text = '切换开机自动运行'
    $script:TrayStartupItem.Add_Click({ Toggle-Startup })
    [void]$menu.Items.Add($script:TrayStartupItem)

    [void]$menu.Items.Add((New-Object -TypeName System.Windows.Forms.ToolStripSeparator))

    $logItem = New-Object -TypeName System.Windows.Forms.ToolStripMenuItem
    $logItem.Text = '打开日志'
    $logItem.Add_Click({ Open-LogFile })
    [void]$menu.Items.Add($logItem)

    $folderItem = New-Object -TypeName System.Windows.Forms.ToolStripMenuItem
    $folderItem.Text = '打开工作目录'
    $folderItem.Add_Click({ Open-WorkDirectory })
    [void]$menu.Items.Add($folderItem)

    [void]$menu.Items.Add((New-Object -TypeName System.Windows.Forms.ToolStripSeparator))

    $uninstallItem = New-Object -TypeName System.Windows.Forms.ToolStripMenuItem
    $uninstallItem.Text = '卸载软件'
    $uninstallItem.Add_Click({ Uninstall-Application })
    [void]$menu.Items.Add($uninstallItem)

    $exitItem = New-Object -TypeName System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = '退出控制面板'
    $exitItem.Add_Click({ Exit-App })
    [void]$menu.Items.Add($exitItem)

    $menu.Add_Opening({
        try {
            $status = Get-MonitorStatus
            $script:TrayStartItem.Enabled = -not $status.MonitorRunning
            $script:TrayStopItem.Enabled = $status.MonitorRunning -or $status.TaskExists
            if ($status.StartupEnabled) {
                $script:TrayStartupItem.Text = '关闭开机自动运行'
            }
            else {
                $script:TrayStartupItem.Text = '开启开机自动运行'
            }
        }
        catch {
            $script:TrayStartItem.Enabled = $true
            $script:TrayStopItem.Enabled = $true
        }
    })

    return $menu
}

function Show-Message {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show($script:Form, $Message, '校园网监控', [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Add-SettingsField {
    param(
        [Parameter(Mandatory = $true)]$Form,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$Y,
        [switch]$Password
    )

    $labelControl = New-Object -TypeName System.Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 28, ($Y + 4)
    $labelControl.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 145, 26
    $labelControl.ForeColor = $script:Colors.Text
    $labelControl.Font = New-AppFont -Size 10
    $Form.Controls.Add($labelControl)

    $textBox = New-Object -TypeName System.Windows.Forms.TextBox
    $textBox.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 185, $Y
    $textBox.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 420, 28
    $textBox.Font = New-AppFont -Size 10
    $textBox.BackColor = $script:Colors.White
    $textBox.BorderStyle = 'FixedSingle'
    if ($Password) {
        $textBox.UseSystemPasswordChar = $false
    }
    $Form.Controls.Add($textBox)
    return $textBox
}

function Show-Settings {
    try {
        $config = Get-Configuration
    }
    catch {
        Show-Message -Message ('读取配置失败：{0}' -f $_.Exception.Message) -Icon Error
        return
    }

    $settings = New-Object -TypeName System.Windows.Forms.Form
    $settings.Text = '设置校园网账号和邮箱'
    $settings.StartPosition = 'CenterParent'
    $settings.ClientSize = New-Object -TypeName System.Drawing.Size -ArgumentList 680, 500
    $settings.FormBorderStyle = 'FixedDialog'
    $settings.MaximizeBox = $false
    $settings.MinimizeBox = $false
    $settings.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
    $settings.Font = New-AppFont -Size 10
    $settings.Icon = Get-ApplicationIcon

    $settingsHeader = New-Object -TypeName System.Windows.Forms.Panel
    $settingsHeader.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 0, 0
    $settingsHeader.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 680, 72
    $settingsHeader.BackColor = $script:Colors.Teal
    $settings.Controls.Add($settingsHeader)

    $title = New-Object -TypeName System.Windows.Forms.Label
    $title.Text = '账号和邮件设置'
    $title.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 28, 12
    $title.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 520, 28
    $title.Font = New-AppFont -Size 15 -Style Bold
    $title.ForeColor = $script:Colors.White
    $settingsHeader.Controls.Add($title)

    $settingsSubtitle = New-Object -TypeName System.Windows.Forms.Label
    $settingsSubtitle.Text = '信息保存在当前工作目录，SMTP 服务器会按邮箱自动识别。'
    $settingsSubtitle.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 30, 41
    $settingsSubtitle.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 600, 20
    $settingsSubtitle.Font = New-AppFont -Size 8.5
    $settingsSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
    $settingsHeader.Controls.Add($settingsSubtitle)

    $campusSection = New-Object -TypeName System.Windows.Forms.Label
    $campusSection.Text = '校园网认证'
    $campusSection.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 28, 82
    $campusSection.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 180, 22
    $campusSection.Font = New-AppFont -Size 9 -Style Bold
    $campusSection.ForeColor = $script:Colors.TealDark
    $settings.Controls.Add($campusSection)

    $campusUser = Add-SettingsField -Form $settings -Label '校园网账号' -Y 106
    $campusPassword = Add-SettingsField -Form $settings -Label '校园网密码' -Y 149 -Password

    $emailSection = New-Object -TypeName System.Windows.Forms.Label
    $emailSection.Text = '邮件通知'
    $emailSection.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 28, 202
    $emailSection.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 180, 22
    $emailSection.Font = New-AppFont -Size 9 -Style Bold
    $emailSection.ForeColor = $script:Colors.Blue
    $settings.Controls.Add($emailSection)

    $emailAddress = Add-SettingsField -Form $settings -Label '发件邮箱' -Y 226
    $recipient = Add-SettingsField -Form $settings -Label '收件邮箱' -Y 269
    $emailPassword = Add-SettingsField -Form $settings -Label '邮箱授权码' -Y 312 -Password

    $campusUser.Text = [string]$config.Credentials.Username
    $campusPassword.Text = [string]$config.Credentials.Password
    $emailAddress.Text = [string]$config.Email.Address
    $recipient.Text = [string]$config.Email.Recipient
    $emailPassword.Text = [string]$config.Email.Password

    $note = New-Object -TypeName System.Windows.Forms.Label
    $note.Text = '已保存的密码和授权码会直接显示。SMTP 服务器会按邮箱自动识别。'
    $note.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 28, 355
    $note.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 620, 30
    $note.ForeColor = $script:Colors.Muted
    $note.Font = New-AppFont -Size 9
    $settings.Controls.Add($note)

    $saveButton = New-Object -TypeName System.Windows.Forms.Button
    $saveButton.Text = '保存设置'
    $saveButton.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 410, 420
    $saveButton.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 125, 38
    $saveButton.BackColor = $script:Colors.Teal
    $saveButton.ForeColor = $script:Colors.White
    $saveButton.FlatStyle = 'Flat'
    $saveButton.FlatAppearance.BorderSize = 0
    $saveButton.Font = New-AppFont -Size 10 -Style Bold
    $settings.Controls.Add($saveButton)

    $cancelButton = New-Object -TypeName System.Windows.Forms.Button
    $cancelButton.Text = '取消'
    $cancelButton.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 548, 420
    $cancelButton.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 107, 38
    $cancelButton.BackColor = $script:Colors.Panel
    $cancelButton.ForeColor = $script:Colors.Text
    $cancelButton.FlatStyle = 'Flat'
    $cancelButton.FlatAppearance.BorderColor = $script:Colors.Border
    $cancelButton.Font = New-AppFont -Size 10
    $settings.Controls.Add($cancelButton)
    $settings.AcceptButton = $saveButton
    $settings.CancelButton = $cancelButton

    $cancelButton.Add_Click({ $settings.Close() })
    $saveButton.Add_Click({
        try {
            $username = $campusUser.Text.Trim()
            $from = $emailAddress.Text.Trim()
            $to = $recipient.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($username)) { throw '校园网账号不能为空。' }
            if ([string]::IsNullOrWhiteSpace($from)) { throw '发件邮箱不能为空。' }
            if ([string]::IsNullOrWhiteSpace($to)) { $to = $from }

            $config.Credentials.Username = $username
            if (-not [string]::IsNullOrWhiteSpace($campusPassword.Text)) {
                $config.Credentials.Password = $campusPassword.Text
            }
            if ([string]::IsNullOrWhiteSpace([string]$config.Credentials.Password)) {
                throw '校园网密码不能为空。'
            }

            $config.Email.Enabled = $true
            $config.Email.Address = $from
            $config.Email.Recipient = $to
            if (-not [string]::IsNullOrWhiteSpace($emailPassword.Text)) {
                $config.Email.Password = $emailPassword.Text
            }
            if ([string]::IsNullOrWhiteSpace([string]$config.Email.Password)) {
                throw '邮箱授权码不能为空。'
            }

            $smtp = Get-AutoSmtpSettings -Address $from
            if (-not [string]::IsNullOrWhiteSpace($smtp.Server)) {
                $config.Email.SmtpServer = $smtp.Server
                $config.Email.Port = $smtp.Port
            }
            if ([string]::IsNullOrWhiteSpace([string]$config.Email.SmtpServer)) {
                throw '无法自动识别邮箱服务器，请先用原菜单完成邮箱配置。'
            }

            Save-Configuration -Configuration $config
            Add-Activity -Message '设置已保存。' -Color $script:Colors.Green
            $settings.Close()
        }
        catch {
            [void][System.Windows.Forms.MessageBox]::Show($settings, $_.Exception.Message, '设置未保存', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    })

    [void]$settings.ShowDialog($script:Form)
}

$form = New-Object -TypeName System.Windows.Forms.Form
$script:Form = $form
$form.Text = '校园网监控'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object -TypeName System.Drawing.Size -ArgumentList 860, 680
$form.MinimumSize = New-Object -TypeName System.Drawing.Size -ArgumentList 860, 680
$form.MaximumSize = New-Object -TypeName System.Drawing.Size -ArgumentList 860, 680
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $script:Colors.White
$form.Font = New-AppFont -Size 10
$form.Icon = Get-ApplicationIcon

$script:TrayIcon = New-Object -TypeName System.Windows.Forms.NotifyIcon
try {
    $script:TrayIcon.Icon = Get-ApplicationIcon
}
catch {
    try {
        $script:TrayIcon.Icon = New-TrayIcon
    }
    catch {
        $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Information
    }
}
$script:TrayIcon.Text = '校园网监控'
$script:TrayIcon.ContextMenuStrip = New-TrayMenu
$script:TrayIcon.Visible = $false
$script:TrayIcon.Add_MouseDoubleClick({ Show-AppWindow })

$header = New-Object -TypeName System.Windows.Forms.Panel
$header.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 0, 0
$header.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 860, 105
$header.BackColor = $script:Colors.Teal
$form.Controls.Add($header)

$title = New-Object -TypeName System.Windows.Forms.Label
$title.Text = '校园网监控'
$title.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 28, 18
$title.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 420, 38
$title.Font = New-AppFont -Size 22 -Style Bold
$title.ForeColor = $script:Colors.White
$header.Controls.Add($title)

$subtitle = New-Object -TypeName System.Windows.Forms.Label
$subtitle.Text = '自动检测网络、断网认证，并发送邮件通知'
$subtitle.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 31, 62
$subtitle.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 500, 24
$subtitle.Font = New-AppFont -Size 10
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
$header.Controls.Add($subtitle)

$computerLabel = New-Object -TypeName System.Windows.Forms.Label
$computerLabel.Text = Get-ComputerName
$computerLabel.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 590, 35
$computerLabel.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 235, 30
$computerLabel.TextAlign = 'MiddleRight'
$computerLabel.Font = New-AppFont -Size 11 -Style Bold
$computerLabel.ForeColor = $script:Colors.White
$header.Controls.Add($computerLabel)

$statusPanel = New-Object -TypeName System.Windows.Forms.Panel
$statusPanel.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 22, 120
$statusPanel.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 816, 108
$statusPanel.BackColor = $script:Colors.Panel
$statusPanel.BorderStyle = 'FixedSingle'
$form.Controls.Add($statusPanel)

function Add-StatusCard {
    param([int]$X, [string]$Caption, [int]$Width = 185)

    $captionLabel = New-Object -TypeName System.Windows.Forms.Label
    $captionLabel.Text = $Caption
    $captionLabel.Location = New-Object -TypeName System.Drawing.Point -ArgumentList $X, 18
    $captionLabel.Size = New-Object -TypeName System.Drawing.Size -ArgumentList ($Width - 14), 24
    $captionLabel.Font = New-AppFont -Size 9
    $captionLabel.ForeColor = $script:Colors.Muted
    $statusPanel.Controls.Add($captionLabel)

    $valueLabel = New-Object -TypeName System.Windows.Forms.Label
    $valueLabel.Text = '读取中'
    $valueLabel.Location = New-Object -TypeName System.Drawing.Point -ArgumentList $X, 48
    $valueLabel.Size = New-Object -TypeName System.Drawing.Size -ArgumentList ($Width - 14), 35
    $valueLabel.Font = New-AppFont -Size 15 -Style Bold
    $valueLabel.ForeColor = $script:Colors.Text
    $statusPanel.Controls.Add($valueLabel)
    return $valueLabel
}

$script:MonitorValue = Add-StatusCard -X 22 -Caption '监控状态'
$script:StartupValue = Add-StatusCard -X 220 -Caption '开机自启'
$script:TaskValue = Add-StatusCard -X 418 -Caption '计划任务'
$script:LastLogValue = Add-StatusCard -X 616 -Caption '最近检查' -Width 180

$actionPanel = New-Object -TypeName System.Windows.Forms.Panel
$actionPanel.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 22, 246
$actionPanel.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 816, 132
$actionPanel.BackColor = $script:Colors.White
$actionPanel.BorderStyle = 'FixedSingle'
$form.Controls.Add($actionPanel)

$actionTitle = New-Object -TypeName System.Windows.Forms.Label
$actionTitle.Text = '快速操作'
$actionTitle.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 14, 10
$actionTitle.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 120, 22
$actionTitle.Font = New-AppFont -Size 9 -Style Bold
$actionTitle.ForeColor = $script:Colors.Muted
$actionPanel.Controls.Add($actionTitle)

function New-ActionButton {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [System.Drawing.Color]$BackColor = $script:Colors.Panel,
        [System.Drawing.Color]$ForeColor = $script:Colors.Text
    )

    $button = New-Object -TypeName System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object -TypeName System.Drawing.Point -ArgumentList $X, $Y
    $button.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 178, 38
    $button.BackColor = $BackColor
    $button.ForeColor = $ForeColor
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.Font = New-AppFont -Size 9 -Style Bold
    $actionPanel.Controls.Add($button)
    return $button
}

$script:StartButton = New-ActionButton -Text '▶  启动监控' -X 14 -Y 38 -BackColor $script:Colors.Teal -ForeColor $script:Colors.White
$script:StopButton = New-ActionButton -Text '■  停止监控' -X 202 -Y 38 -BackColor ([System.Drawing.Color]::FromArgb(255, 247, 237)) -ForeColor $script:Colors.Orange
$script:TestButton = New-ActionButton -Text '✓  立即检测' -X 390 -Y 38 -BackColor ([System.Drawing.Color]::FromArgb(239, 246, 255)) -ForeColor $script:Colors.Blue
$script:StartupButton = New-ActionButton -Text '开机自启：读取中' -X 578 -Y 38 -BackColor ([System.Drawing.Color]::FromArgb(240, 253, 250)) -ForeColor $script:Colors.TealDark

$script:SettingsButton = New-ActionButton -Text '⚙  账号和邮箱设置' -X 14 -Y 82
$script:RefreshButton = New-ActionButton -Text '↻  刷新状态' -X 202 -Y 82
$script:LogButton = New-ActionButton -Text '打开日志' -X 390 -Y 82
$script:FolderButton = New-ActionButton -Text '打开工作目录' -X 578 -Y 82

$toolTip = New-Object -TypeName System.Windows.Forms.ToolTip
$toolTip.SetToolTip($script:StartupButton, '同时切换登录 Windows 时的后台监控和托盘控制面板，不会停止当前监控。')
$toolTip.SetToolTip($script:StartButton, '注册监控任务并立即在后台启动。')
$toolTip.SetToolTip($script:StopButton, '停止监控进程和计划任务，并发送关闭通知邮件。')

$activityTitle = New-Object -TypeName System.Windows.Forms.Label
$activityTitle.Text = '运行记录'
$activityTitle.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 25, 395
$activityTitle.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 160, 24
$activityTitle.Font = New-AppFont -Size 9 -Style Bold
$activityTitle.ForeColor = $script:Colors.Muted
$form.Controls.Add($activityTitle)

$script:ActivityBox = New-Object -TypeName System.Windows.Forms.RichTextBox
$script:ActivityBox.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 22, 423
$script:ActivityBox.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 816, 192
$script:ActivityBox.ReadOnly = $true
$script:ActivityBox.BackColor = $script:Colors.Panel
$script:ActivityBox.BorderStyle = 'FixedSingle'
$script:ActivityBox.Font = New-Object -TypeName System.Drawing.Font -ArgumentList @('Consolas', 9)
$script:ActivityBox.DetectUrls = $false
$form.Controls.Add($script:ActivityBox)

$script:FooterLabel = New-Object -TypeName System.Windows.Forms.Label
$script:FooterLabel.Text = '正在读取状态...'
$script:FooterLabel.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 25, 638
$script:FooterLabel.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 810, 24
$script:FooterLabel.Font = New-AppFont -Size 9
$script:FooterLabel.ForeColor = $script:Colors.Muted
$form.Controls.Add($script:FooterLabel)

# Rebuild the visible surface with a compact status-first layout. The legacy controls above
# remain hidden so the existing event handlers and backend operations stay unchanged.
foreach ($legacyControl in @($header, $statusPanel, $actionPanel, $activityTitle, $script:ActivityBox, $script:FooterLabel)) {
    if ($legacyControl) {
        $legacyControl.Visible = $false
    }
}

function New-ModernLabel {
    param(
        [Parameter(Mandatory = $true)]$Parent,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height,
        [float]$Size = 10,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular,
        [System.Drawing.Color]$Color = $script:Colors.Text,
        [System.Drawing.ContentAlignment]$Align = [System.Drawing.ContentAlignment]::MiddleLeft
    )

    $label = New-Object -TypeName System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object -TypeName System.Drawing.Point -ArgumentList $X, $Y
    $label.Size = New-Object -TypeName System.Drawing.Size -ArgumentList $Width, $Height
    $label.Font = New-AppFont -Size $Size -Style $Style
    $label.ForeColor = $Color
    $label.TextAlign = $Align
    $label.AutoEllipsis = $true
    $Parent.Controls.Add($label)
    return $label
}

function New-ModernButton {
    param(
        [Parameter(Mandatory = $true)]$Parent,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [Parameter(Mandatory = $true)][int]$Width,
        [int]$Height = 38,
        [System.Drawing.Color]$BackColor = $script:Colors.White,
        [System.Drawing.Color]$ForeColor = $script:Colors.Text,
        [switch]$Primary
    )

    $button = New-Object -TypeName System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object -TypeName System.Drawing.Point -ArgumentList $X, $Y
    $button.Size = New-Object -TypeName System.Drawing.Size -ArgumentList $Width, $Height
    $button.BackColor = if ($Primary) { $script:Colors.Teal } else { $BackColor }
    $button.ForeColor = if ($Primary) { $script:Colors.White } else { $ForeColor }
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.FlatAppearance.MouseOverBackColor = if ($Primary) { $script:Colors.TealDark } else { $script:Colors.Panel }
    $button.Font = New-AppFont -Size 9 -Style Bold
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.UseVisualStyleBackColor = $false
    $Parent.Controls.Add($button)
    return $button
}

function New-ModernCard {
    param(
        [Parameter(Mandatory = $true)]$Parent,
        [Parameter(Mandatory = $true)][int]$X,
        [Parameter(Mandatory = $true)][int]$Y,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )

    $card = New-Object -TypeName System.Windows.Forms.Panel
    $card.Location = New-Object -TypeName System.Drawing.Point -ArgumentList $X, $Y
    $card.Size = New-Object -TypeName System.Drawing.Size -ArgumentList $Width, $Height
    $card.BackColor = $script:Colors.White
    $card.BorderStyle = 'FixedSingle'
    $Parent.Controls.Add($card)
    return $card
}

$form.ClientSize = New-Object -TypeName System.Drawing.Size -ArgumentList 960, 720
$form.MinimumSize = New-Object -TypeName System.Drawing.Size -ArgumentList 960, 720
$form.MaximumSize = New-Object -TypeName System.Drawing.Size -ArgumentList 960, 720
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

$modernTop = New-Object -TypeName System.Windows.Forms.Panel
$modernTop.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 0, 0
$modernTop.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 960, 88
$modernTop.BackColor = $script:Colors.White
$form.Controls.Add($modernTop)

$brandMark = New-Object -TypeName System.Windows.Forms.PictureBox
$brandMark.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 24, 22
$brandMark.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 36, 36
$brandMark.BackColor = $script:Colors.White
$brandMark.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::CenterImage
$brandMark.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$script:BrandBitmap = Get-ApplicationBitmap
$brandMark.Image = $script:BrandBitmap
$modernTop.Controls.Add($brandMark)
[void](New-ModernLabel -Parent $modernTop -Text '校园网监控' -X 74 -Y 15 -Width 250 -Height 30 -Size 17 -Style Bold -Color $script:Colors.Text)
[void](New-ModernLabel -Parent $modernTop -Text '自动检测网络 · 断网认证 · 邮件通知' -X 76 -Y 45 -Width 330 -Height 22 -Size 9 -Color $script:Colors.Muted)

$script:HeaderNetworkLabel = New-ModernLabel -Parent $modernTop -Text '读取中' -X 694 -Y 14 -Width 146 -Height 26 -Size 10 -Style Bold -Color $script:Colors.Muted -Align ([System.Drawing.ContentAlignment]::MiddleRight)
[void](New-ModernLabel -Parent $modernTop -Text (Get-ComputerName) -X 610 -Y 43 -Width 230 -Height 22 -Size 9 -Color $script:Colors.Muted -Align ([System.Drawing.ContentAlignment]::MiddleRight))
$script:RefreshButton = New-ModernButton -Parent $modernTop -Text '↻' -X 864 -Y 22 -Width 44 -Height 36 -BackColor $script:Colors.Panel -ForeColor $script:Colors.TealDark

$heroPanel = New-ModernCard -Parent $form -X 24 -Y 110 -Width 912 -Height 156
$heroAccent = New-Object -TypeName System.Windows.Forms.Panel
$heroAccent.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 0, 0
$heroAccent.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 5, 156
$heroAccent.BackColor = $script:Colors.Teal
$heroPanel.Controls.Add($heroAccent)
[void](New-ModernLabel -Parent $heroPanel -Text '当前网络状态' -X 28 -Y 14 -Width 180 -Height 22 -Size 9 -Style Bold -Color $script:Colors.Muted)
$script:NetworkDotLabel = New-ModernLabel -Parent $heroPanel -Text '●' -X 28 -Y 43 -Width 24 -Height 34 -Size 18 -Style Bold -Color $script:Colors.Orange -Align ([System.Drawing.ContentAlignment]::MiddleCenter)
$script:NetworkStateLabel = New-ModernLabel -Parent $heroPanel -Text '等待检测' -X 58 -Y 42 -Width 300 -Height 38 -Size 20 -Style Bold -Color $script:Colors.Text
$script:NetworkDetailLabel = New-ModernLabel -Parent $heroPanel -Text '后台监控正在等待下一次网络检查。' -X 59 -Y 82 -Width 480 -Height 24 -Size 9 -Color $script:Colors.Muted
[void](New-ModernLabel -Parent $heroPanel -Text '监控间隔 60 秒  ·  后台自动恢复校园网认证' -X 59 -Y 114 -Width 430 -Height 20 -Size 8.5 -Color $script:Colors.Muted)
$script:TestButton = New-ModernButton -Parent $heroPanel -Text '立即检测' -X 756 -Y 52 -Width 130 -Height 42 -Primary
$toolTip.SetToolTip($script:RefreshButton, '刷新控制面板状态')
$toolTip.SetToolTip($script:TestButton, '立即检查网络，断网时自动尝试认证')

$monitorCard = New-ModernCard -Parent $form -X 24 -Y 284 -Width 292 -Height 106
[void](New-ModernLabel -Parent $monitorCard -Text '后台监控' -X 18 -Y 12 -Width 180 -Height 20 -Size 9 -Style Bold -Color $script:Colors.Muted)
$script:MonitorValue = New-ModernLabel -Parent $monitorCard -Text '读取中' -X 18 -Y 34 -Width 160 -Height 30 -Size 15 -Style Bold -Color $script:Colors.Text
$script:MonitorDetailLabel = New-ModernLabel -Parent $monitorCard -Text '定期检测网络并自动认证' -X 18 -Y 73 -Width 240 -Height 18 -Size 8.5 -Color $script:Colors.Muted

$startupCard = New-ModernCard -Parent $form -X 334 -Y 284 -Width 292 -Height 106
[void](New-ModernLabel -Parent $startupCard -Text '开机自动运行' -X 18 -Y 12 -Width 180 -Height 20 -Size 9 -Style Bold -Color $script:Colors.Muted)
$script:StartupValue = New-ModernLabel -Parent $startupCard -Text '读取中' -X 18 -Y 34 -Width 150 -Height 30 -Size 15 -Style Bold -Color $script:Colors.Text
[void](New-ModernLabel -Parent $startupCard -Text '同时启动监控和托盘图标' -X 18 -Y 73 -Width 180 -Height 18 -Size 8.5 -Color $script:Colors.Muted)
$script:StartupButton = New-Object -TypeName System.Windows.Forms.CheckBox
$script:StartupButton.Appearance = [System.Windows.Forms.Appearance]::Button
$script:StartupButton.Text = '读取中'
$script:StartupButton.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 207, 39
$script:StartupButton.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 68, 30
$script:StartupButton.BackColor = $script:Colors.Panel
$script:StartupButton.ForeColor = $script:Colors.Muted
$script:StartupButton.FlatStyle = 'Flat'
$script:StartupButton.FlatAppearance.BorderSize = 0
$script:StartupButton.Font = New-AppFont -Size 8.5 -Style Bold
$script:StartupButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$script:StartupButton.UseVisualStyleBackColor = $false
$script:StartupButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$startupCard.Controls.Add($script:StartupButton)

$taskCard = New-ModernCard -Parent $form -X 644 -Y 284 -Width 292 -Height 106
[void](New-ModernLabel -Parent $taskCard -Text '计划任务' -X 18 -Y 12 -Width 180 -Height 20 -Size 9 -Style Bold -Color $script:Colors.Muted)
$script:TaskValue = New-ModernLabel -Parent $taskCard -Text '读取中' -X 18 -Y 34 -Width 180 -Height 30 -Size 15 -Style Bold -Color $script:Colors.Text
$script:TaskDetailLabel = New-ModernLabel -Parent $taskCard -Text '正在读取任务状态' -X 18 -Y 73 -Width 250 -Height 18 -Size 8.5 -Color $script:Colors.Muted

$actionBar = New-ModernCard -Parent $form -X 24 -Y 408 -Width 912 -Height 70
[void](New-ModernLabel -Parent $actionBar -Text '操作' -X 18 -Y 20 -Width 55 -Height 24 -Size 9 -Style Bold -Color $script:Colors.Muted)
$script:StartButton = New-ModernButton -Parent $actionBar -Text '▶  启动监控' -X 82 -Y 16 -Width 116 -Height 38 -BackColor $script:Colors.GreenSoft -ForeColor $script:Colors.Green
$script:StopButton = New-ModernButton -Parent $actionBar -Text '■  停止监控' -X 208 -Y 16 -Width 116 -Height 38 -BackColor $script:Colors.OrangeSoft -ForeColor $script:Colors.Orange
$script:SettingsButton = New-ModernButton -Parent $actionBar -Text '⚙  账号和邮箱' -X 344 -Y 16 -Width 132 -Height 38 -BackColor $script:Colors.BlueSoft -ForeColor $script:Colors.Blue
$script:LogButton = New-ModernButton -Parent $actionBar -Text '打开日志' -X 492 -Y 16 -Width 100 -Height 38 -BackColor $script:Colors.Panel -ForeColor $script:Colors.Text
$script:FolderButton = New-ModernButton -Parent $actionBar -Text '打开文件夹' -X 608 -Y 16 -Width 110 -Height 38 -BackColor $script:Colors.Panel -ForeColor $script:Colors.Text
$script:UninstallButton = New-ModernButton -Parent $actionBar -Text '卸载软件' -X 730 -Y 16 -Width 120 -Height 38 -BackColor $script:Colors.RedSoft -ForeColor $script:Colors.Red

[void](New-ModernLabel -Parent $form -Text '最近活动' -X 26 -Y 498 -Width 160 -Height 24 -Size 9 -Style Bold -Color $script:Colors.Muted)
[void](New-ModernLabel -Parent $form -Text '详细过程会同时保存到日志文件' -X 690 -Y 498 -Width 246 -Height 24 -Size 8.5 -Color $script:Colors.Muted -Align ([System.Drawing.ContentAlignment]::MiddleRight))
$script:ActivityBox = New-Object -TypeName System.Windows.Forms.RichTextBox
$script:ActivityBox.Location = New-Object -TypeName System.Drawing.Point -ArgumentList 24, 526
$script:ActivityBox.Size = New-Object -TypeName System.Drawing.Size -ArgumentList 912, 142
$script:ActivityBox.ReadOnly = $true
$script:ActivityBox.BackColor = $script:Colors.White
$script:ActivityBox.BorderStyle = 'FixedSingle'
$script:ActivityBox.Font = New-AppFont -Size 9
$script:ActivityBox.ForeColor = $script:Colors.Text
$script:ActivityBox.DetectUrls = $false
$form.Controls.Add($script:ActivityBox)

$script:FooterLabel = New-ModernLabel -Parent $form -Text '正在读取状态...' -X 26 -Y 682 -Width 900 -Height 24 -Size 8.5 -Color $script:Colors.Muted

$script:BackendTimer = New-Object -TypeName System.Windows.Forms.Timer
$script:BackendTimer.Interval = 400
$script:BackendTimer.Add_Tick({ Complete-BackendOperation })

$script:StatusTimer = New-Object -TypeName System.Windows.Forms.Timer
$script:StatusTimer.Interval = 2000
$script:StatusTimer.Add_Tick({
    if (-not $script:BackendProcess) {
        Refresh-Status
    }
})

$script:ActivationTimer = New-Object -TypeName System.Windows.Forms.Timer
$script:ActivationTimer.Interval = 500
$script:ActivationTimer.Add_Tick({
    if ($script:ActivationEvent -and $script:ActivationEvent.WaitOne(0)) {
        Show-AppWindow
    }
})

$script:StartButton.Add_Click({ Start-Monitor })
$script:StopButton.Add_Click({ Stop-Monitor })
$script:TestButton.Add_Click({ Test-Network })
$script:StartupButton.Add_Click({ Toggle-Startup })
$script:SettingsButton.Add_Click({ Show-Settings; Refresh-Status })
$script:RefreshButton.Add_Click({ Refresh-Status; Add-Activity -Message '状态已刷新。' -Color $script:Colors.Muted })
$script:LogButton.Add_Click({ Open-LogFile })
$script:FolderButton.Add_Click({ Open-WorkDirectory })
$script:UninstallButton.Add_Click({ Uninstall-Application })

$form.Add_Shown({
    Initialize-AppState
})
$form.Add_FormClosing({
    if ($script:AllowExit) {
        return
    }
    if ($script:ClosePromptShowing) {
        $_.Cancel = $true
        return
    }
    $_.Cancel = $true
    $script:ClosePromptShowing = $true
    try {
        Show-CloseChoice
    }
    finally {
        $script:ClosePromptShowing = $false
    }
})
$form.Add_FormClosed({
    if ($script:StatusTimer) { $script:StatusTimer.Stop() }
    if ($script:ActivationTimer) { $script:ActivationTimer.Stop() }
    if ($script:BackendTimer) { $script:BackendTimer.Stop() }
    if ($script:TrayIcon) {
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
    }
    if ($script:TrayBitmap) {
        $script:TrayBitmap.Dispose()
        $script:TrayBitmap = $null
    }
    if ($script:AppMutex) {
        try { $script:AppMutex.ReleaseMutex() } catch { }
        $script:AppMutex.Dispose()
        $script:AppMutex = $null
    }
    if ($script:ApplicationContext) {
        $script:ApplicationContext.ExitThread()
        $script:ApplicationContext = $null
    }
    if ($script:ActivationEvent) {
        $script:ActivationEvent.Dispose()
        $script:ActivationEvent = $null
    }
})

if ($StartInTray) {
    $script:ApplicationContext = New-Object -TypeName System.Windows.Forms.ApplicationContext
    $form.ShowInTaskbar = $false
    $script:TrayIcon.Visible = $true
    Initialize-AppState
    [System.Windows.Forms.Application]::Run($script:ApplicationContext)
}
else {
    [System.Windows.Forms.Application]::Run($form)
}










