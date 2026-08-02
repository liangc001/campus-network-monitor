$ErrorActionPreference = 'Stop'

$scriptDirectory = [System.IO.Path]::GetFullPath($PSScriptRoot)
$scriptPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory 'CampusNetworkMonitor.ps1'))
$executablePath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory 'CampusNetworkMonitor.exe'))
$powershellPath = Join-Path $PSHOME 'powershell.exe'
$taskName = 'CampusNetworkMonitor'
$logPath = Join-Path $scriptDirectory 'campus-network-monitor.log'

try {
    $Host.UI.RawUI.WindowTitle = '校园网监控控制台'
}
catch {
    # Window titles are not available in every host.
}

function Invoke-MonitorScript {
    param([string[]]$Arguments)

    if (Test-Path -LiteralPath $executablePath -PathType Leaf) {
        $configPath = Join-Path $scriptDirectory 'campus-network.config.json'
        $output = @(& $executablePath -ConfigPath $configPath @Arguments 2>&1)
    }
    else {
        $output = @(& $powershellPath -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments 2>&1)
    }
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host ([string]$line)
    }

    if ($exitCode -ne 0) {
        Write-Host ('操作失败，退出码：{0}' -f $exitCode) -ForegroundColor Red
        return $false
    }
    return $true
}

function Invoke-ScheduledTaskNow {
    $output = @(& schtasks.exe /Run /TN $taskName 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host ([string]$line)
    }

    if ($exitCode -ne 0) {
        Write-Host ('启动计划任务失败，退出码：{0}' -f $exitCode) -ForegroundColor Red
        return $false
    }
    return $true
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
        Write-Host ('无法确认监控状态：{0}' -f $_.Exception.Message) -ForegroundColor Yellow
        return $true
    }
    finally {
        if ($mutex) {
            $mutex.Dispose()
        }
    }
}

function Get-MonitorStatus {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $taskState = '未安装'
    $startupEnabled = $false

    if ($task) {
        $taskState = [string]$task.State
        $triggers = @($task.Triggers)
        $enabledTriggers = @($triggers | Where-Object { [bool]$_.Enabled })
        $startupEnabled = $enabledTriggers.Count -gt 0
    }

    return [pscustomobject]@{
        TaskExists = [bool]$task
        TaskState = $taskState
        StartupEnabled = $startupEnabled
        MonitorRunning = (Test-MonitorRunning)
    }
}

function Write-StatusLine {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Value,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host ('  {0,-10}' -f $Label) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Write-Header {
    $status = Get-MonitorStatus
    $computerName = [string]$env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($computerName)) {
        $computerName = [Environment]::MachineName
    }

    Clear-Host
    Write-Host ''
    Write-Host '  +============================================================+' -ForegroundColor DarkCyan
    Write-Host '  |              CAMPUS NETWORK MONITOR                       |' -ForegroundColor Cyan
    Write-Host '  |              校园网自动认证控制台                         |' -ForegroundColor White
    Write-Host '  +============================================================+' -ForegroundColor DarkCyan
    Write-Host ''
    Write-StatusLine -Label '电脑' -Value $computerName -Color Cyan

    $monitorText = if ($status.MonitorRunning) { '运行中' } else { '未运行' }
    $monitorColor = if ($status.MonitorRunning) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkYellow }
    Write-StatusLine -Label '监控' -Value $monitorText -Color $monitorColor

    $startupText = if ($status.StartupEnabled) { '已开启' } else { '未开启' }
    $startupColor = if ($status.StartupEnabled) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkYellow }
    Write-StatusLine -Label '开机自启' -Value $startupText -Color $startupColor
    Write-StatusLine -Label '任务状态' -Value $status.TaskState -Color DarkCyan
    Write-Host ''
}

function Write-Menu {
    Write-Host '  操作' -ForegroundColor Yellow
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  [1]  配置校园网账号和邮箱'
    Write-Host '  [2]  立即检测一次网络'
    Write-Host '  [3]  启动监控（后台运行）' -ForegroundColor Green
    Write-Host '  [4]  停止监控并发送邮件' -ForegroundColor DarkYellow
    Write-Host ''
    Write-Host '  开机行为' -ForegroundColor Yellow
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  [5]  开启开机自启' -ForegroundColor Green
    Write-Host '  [6]  关闭开机自启' -ForegroundColor DarkYellow
    Write-Host ''
    Write-Host '  工具' -ForegroundColor Yellow
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  [7]  查看状态和最近日志'
    Write-Host '  [8]  删除监控任务'
    Write-Host '  [0]  退出'
    Write-Host ''
}

function Write-RecentLog {
    if (-not (Test-Path -LiteralPath $logPath)) {
        Write-Host '  还没有日志。' -ForegroundColor DarkGray
        return
    }

    Write-Host '  最近 8 条日志：' -ForegroundColor Cyan
    $lines = @(Get-Content -LiteralPath $logPath -Tail 8 -Encoding UTF8)
    foreach ($line in $lines) {
        $color = [ConsoleColor]::Gray
        if ($line -match '\[ERROR\]') {
            $color = [ConsoleColor]::Red
        }
        elseif ($line -match '\[WARN\]') {
            $color = [ConsoleColor]::Yellow
        }
        elseif ($line -match '\[INFO\]') {
            $color = [ConsoleColor]::Gray
        }
        Write-Host ('  ' + $line) -ForegroundColor $color
    }
}

function Wait-ForMenu {
    Write-Host ''
    [void](Read-Host '按回车返回主菜单')
}

while ($true) {
    try {
        Write-Header
        Write-Menu
        $choice = Read-Host '  请输入选项编号'

        switch ($choice) {
            '1' {
                Invoke-MonitorScript @('-Setup') | Out-Null
                Wait-ForMenu
            }
            '2' {
                Invoke-MonitorScript @('-Once') | Out-Null
                Wait-ForMenu
            }
            '3' {
                if (Test-MonitorRunning) {
                    Write-Host '监控已经在运行，不重复启动，也不会重复发送确认邮件。' -ForegroundColor Yellow
                }
                else {
                    $installed = Invoke-MonitorScript @('-InstallTask')
                    if ($installed) {
                        Start-Sleep -Milliseconds 500
                        [void](Invoke-ScheduledTaskNow)
                    }
                }
                Wait-ForMenu
            }
            '4' {
                Invoke-MonitorScript @('-StopTask') | Out-Null
                Wait-ForMenu
            }
            '5' {
                Invoke-MonitorScript @('-EnableStartup') | Out-Null
                Wait-ForMenu
            }
            '6' {
                Invoke-MonitorScript @('-DisableStartup') | Out-Null
                Wait-ForMenu
            }
            '7' {
                Write-Header
                $status = Get-MonitorStatus
                Write-StatusLine -Label '监控' -Value $(if ($status.MonitorRunning) { '运行中' } else { '未运行' }) -Color $(if ($status.MonitorRunning) { 'Green' } else { 'DarkYellow' })
                Write-StatusLine -Label '开机自启' -Value $(if ($status.StartupEnabled) { '已开启' } else { '未开启' }) -Color $(if ($status.StartupEnabled) { 'Green' } else { 'DarkYellow' })
                Write-StatusLine -Label '任务状态' -Value $status.TaskState -Color DarkCyan
                Write-Host ''
                Write-RecentLog
                Wait-ForMenu
            }
            '8' {
                Write-Host '删除后将不再开机自动启动，当前正在运行的监控不会自动恢复。' -ForegroundColor Yellow
                $confirm = Read-Host '确定删除计划任务吗？输入 Y 确认'
                if ($confirm -match '^(Y|y)$') {
                    Invoke-MonitorScript @('-UninstallTask') | Out-Null
                }
                else {
                    Write-Host '已取消。' -ForegroundColor DarkGray
                }
                Wait-ForMenu
            }
            '0' {
                break
            }
            default {
                Write-Host '请输入 0 到 8 之间的数字。' -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }
    catch {
        Write-Host ('操作出现问题：{0}' -f $_.Exception.Message) -ForegroundColor Red
        Wait-ForMenu
    }
}

