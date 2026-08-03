[CmdletBinding()]
param(
    [string]$ConfigPath = 'campus-network.config.json',
    [switch]$Once,
    [switch]$Setup,
    [switch]$InstallTask,
    [switch]$StopTask,
    [switch]$UninstallTask,
    [switch]$EnableStartup,
    [switch]$DisableStartup,
    [switch]$RepairTasks,
    [switch]$ForceAuthenticate,
    [switch]$Background,
    [switch]$ShowConfig,
    [string]$EntryPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CompiledRuntime = $false
$script:ScriptDirectory = $null
$script:ScriptPathFull = $null
$script:SourceScriptPathFull = $null
$script:MonitorExecutablePath = $null
$script:EntryExecutablePath = $null
$script:SingleExecutableMode = $false
$compiledScriptRoot = [string](Get-Variable -Name ScriptRoot -ValueOnly -ErrorAction SilentlyContinue)
$providedEntryPath = [string]$EntryPath

if (-not [string]::IsNullOrWhiteSpace($providedEntryPath)) {
    $entryFullPath = [System.IO.Path]::GetFullPath($providedEntryPath)
    $script:SingleExecutableMode = $true
    $script:EntryExecutablePath = $entryFullPath
    $script:CompiledRuntime = ([System.IO.Path]::GetExtension($entryFullPath) -ieq '.exe')
    $script:ScriptDirectory = Split-Path -Parent $entryFullPath
    $script:ScriptPathFull = $entryFullPath
    $script:SourceScriptPathFull = Join-Path $script:ScriptDirectory 'CampusNetworkMonitor.ps1'
}
elseif (-not [string]::IsNullOrWhiteSpace($compiledScriptRoot)) {
    $script:CompiledRuntime = $true
    $script:ScriptDirectory = [System.IO.Path]::GetFullPath($compiledScriptRoot)
    try {
        $script:ScriptPathFull = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    }
    catch {
        $script:ScriptPathFull = Join-Path $script:ScriptDirectory 'CampusNetworkMonitor.exe'
    }
    $script:SourceScriptPathFull = Join-Path $script:ScriptDirectory 'CampusNetworkMonitor.ps1'
}
else {
    $script:ScriptDirectory = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($script:ScriptDirectory)) {
        $script:ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $invocationPath = [string]$MyInvocation.MyCommand.Path
    if ([string]::IsNullOrWhiteSpace($invocationPath)) {
        $invocationPath = [string](Get-Variable -Name PSCommandPath -ValueOnly -ErrorAction SilentlyContinue)
    }
    if ([string]::IsNullOrWhiteSpace($invocationPath)) {
        $invocationPath = Join-Path $script:ScriptDirectory 'CampusNetworkMonitor.ps1'
    }
    $script:ScriptPathFull = [System.IO.Path]::GetFullPath($invocationPath)
    $script:SourceScriptPathFull = $script:ScriptPathFull
}

$defaultMonitorExecutablePath = [System.IO.Path]::GetFullPath((Join-Path $script:ScriptDirectory 'CampusNetworkMonitor.exe'))
if (-not $script:SingleExecutableMode -and (Test-Path -LiteralPath $defaultMonitorExecutablePath -PathType Leaf) -and -not (Test-Path -LiteralPath (Join-Path $script:ScriptDirectory 'CampusNetworkMonitorPanel.exe') -PathType Leaf)) {
    $script:SingleExecutableMode = $true
    $script:EntryExecutablePath = $defaultMonitorExecutablePath
}
$script:MonitorExecutablePath = if ($script:SingleExecutableMode) { $script:EntryExecutablePath } else { $defaultMonitorExecutablePath }
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $script:ScriptDirectory $ConfigPath
}
$script:ConfigPathFull = [System.IO.Path]::GetFullPath($ConfigPath)
$script:ConfigDirectory = Split-Path -Parent $script:ConfigPathFull
$script:LogPath = $null
$script:SuppressHostOutput = [bool]$Background -or (@([Environment]::GetCommandLineArgs()) -contains '-RunMonitor')

function Resolve-ConfigFilePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return (Join-Path $script:ConfigDirectory $Path)
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if (-not $script:SuppressHostOutput) {
        Write-Host $line
    }
    if ($script:LogPath) {
        try {
            Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
        }
        catch {
            if (-not $script:SuppressHostOutput) {
                Write-Host ('Log write failed: {0}' -f $_.Exception.Message)
            }
        }
    }
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

function Read-Configuration {
    if (-not (Test-Path -LiteralPath $script:ConfigPathFull -PathType Leaf)) {
        throw ('Configuration file not found: {0}. Run with -Setup first.' -f $script:ConfigPathFull)
    }

    $raw = Get-Content -LiteralPath $script:ConfigPathFull -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw 'Configuration file is empty.'
    }
    return ($raw | ConvertFrom-Json)
}

function Write-Configuration {
    param([Parameter(Mandatory = $true)]$Configuration)

    $parent = Split-Path -Parent $script:ConfigPathFull
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $Configuration | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:ConfigPathFull -Encoding UTF8
}

function ConvertTo-PlainText {
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$SecureString)

    $ptr = [IntPtr]::Zero
    try {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        if ($ptr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    }
}

function Read-SetupPassword {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    # Input is hidden at the console, but the returned value is intentionally
    # stored as plain text in the local JSON configuration.
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    return ConvertTo-PlainText -SecureString $secure
}

function Get-AutoSmtpServer {
    param([Parameter(Mandatory = $true)][string]$Address)

    $at = $Address.LastIndexOf('@')
    if ($at -lt 0 -or $at -eq ($Address.Length - 1)) {
        return ''
    }

    $domain = $Address.Substring($at + 1).Trim().ToLowerInvariant()
    switch -Regex ($domain) {
        '^qq\.com$' { return 'smtp.qq.com' }
        '^foxmail\.com$' { return 'smtp.qq.com' }
        '^(163|126|yeah)\.com$' { return ('smtp.{0}' -f $domain) }
        '^gmail\.com$' { return 'smtp.gmail.com' }
        '^(outlook|hotmail|live)\.(com|cn)$' { return 'smtp-mail.outlook.com' }
    }
    return ''
}

function Get-AutoSmtpPort {
    param([Parameter(Mandatory = $true)][string]$Address)

    $at = $Address.LastIndexOf('@')
    if ($at -ge 0 -and $at -lt ($Address.Length - 1)) {
        $domain = $Address.Substring($at + 1).Trim().ToLowerInvariant()
        if ($domain -match '^(163|126|yeah)\.com$') {
            return 25
        }
    }
    return 587
}

function Get-ComputerLabel {
    $name = [string]$env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = [Environment]::MachineName
    }
    return $name
}

function Initialize-Configuration {
    if (Test-Path -LiteralPath $script:ConfigPathFull -PathType Leaf) {
        $config = Read-Configuration
    }
    else {
        $config = New-DefaultConfiguration
    }

    Write-Host ''
    Write-Host 'Campus network monitor setup'
    Write-Host ('Config file: {0}' -f $script:ConfigPathFull)
    Write-Host ''

    $username = Read-Host -Prompt ('Campus username [{0}]' -f [string]$config.Credentials.Username)
    if (-not [string]::IsNullOrWhiteSpace($username)) {
        $config.Credentials.Username = $username.Trim()
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.Credentials.Username)) {
        throw 'Campus username cannot be empty.'
    }

    $campusPassword = Read-SetupPassword -Prompt 'Campus password'
    if (-not [string]::IsNullOrWhiteSpace($campusPassword)) {
        $config.Credentials.Password = $campusPassword
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.Credentials.Password)) {
        throw 'Campus password cannot be empty.'
    }

    $config.Email.Enabled = $true
    $value = Read-Host -Prompt ('发件邮箱（例如 yourname@qq.com） [{0}]' -f [string]$config.Email.Address)
    if (-not [string]::IsNullOrWhiteSpace($value)) { $config.Email.Address = $value.Trim() }
    if ([string]::IsNullOrWhiteSpace([string]$config.Email.Address)) {
        throw '发件邮箱不能为空。'
    }

    $value = Read-Host -Prompt ('收件邮箱（直接回车发给自己） [{0}]' -f [string]$config.Email.Recipient)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        $config.Email.Recipient = $value.Trim()
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.Email.Recipient)) {
        $config.Email.Recipient = [string]$config.Email.Address
    }

    $autoSmtp = Get-AutoSmtpServer -Address ([string]$config.Email.Address)
    if ([string]::IsNullOrWhiteSpace([string]$config.Email.SmtpServer) -and -not [string]::IsNullOrWhiteSpace($autoSmtp)) {
        $config.Email.SmtpServer = $autoSmtp
        $config.Email.Port = Get-AutoSmtpPort -Address ([string]$config.Email.Address)
        Write-Host ('已自动识别邮箱服务器：{0}' -f $autoSmtp)
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.Email.SmtpServer)) {
        $value = Read-Host -Prompt '无法自动识别邮箱服务器，请输入 SMTP 服务器地址'
        if (-not [string]::IsNullOrWhiteSpace($value)) { $config.Email.SmtpServer = $value.Trim() }
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.Email.SmtpServer)) {
        throw 'SMTP 服务器不能为空。'
    }

    $smtpPassword = Read-SetupPassword -Prompt '邮箱授权码（输入时不会显示）'
    if (-not [string]::IsNullOrWhiteSpace($smtpPassword)) {
        $config.Email.Password = $smtpPassword
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.Email.Password)) {
        throw '邮箱授权码不能为空。'
    }

    Write-Configuration -Configuration $config
    Write-Host ''
    Write-Host 'Setup complete.'
    Write-Host ('Portal URL: {0}' -f $config.Portal.BaseUrl)
    Write-Host ('Config: {0}' -f $script:ConfigPathFull)
    Write-Host 'You can now run the monitor with -Once.'
}

function Get-LogPath {
    param([Parameter(Mandatory = $true)]$Configuration)

    $path = [string]$Configuration.Runtime.LogFile
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = 'campus-network-monitor.log'
    }
    return Resolve-ConfigFilePath -Path $path
}

function Get-MonitorProcesses {
    $knownMonitorPaths = @(
        $script:ScriptPathFull,
        $script:SourceScriptPathFull,
        $script:MonitorExecutablePath
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
    $scriptPatterns = @($knownMonitorPaths | ForEach-Object { [regex]::Escape([string]$_) })
    $configPattern = [regex]::Escape($script:ConfigPathFull)

    try {
        return @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | Where-Object {
            $commandLine = [string]$_.CommandLine
            $isPowerShell = [string]$_.Name -match '^(powershell|pwsh)(\.exe)?$'
            $isDirectScriptInvocation = $commandLine -notmatch '(?i)(?:^|\s)-(?:Command|EncodedCommand|EncodedArguments)(?:\s|=)'
            $hasScriptPath = $false
            foreach ($scriptPattern in $scriptPatterns) {
                if ($commandLine -match "(?i)$scriptPattern") {
                    $hasScriptPath = $true
                    break
                }
            }
            $hasMatchingConfig = ($commandLine -match "(?i)$configPattern") -or ($commandLine -notmatch '(?i)(?:^|\s)-ConfigPath(?:\s|=)')
            $isMonitorExecutable = ([string]$_.Name -ieq 'CampusNetworkMonitor.exe') -and
                ($commandLine -match '(?i)(?:^|\s)-RunMonitor(?:\s|$)') -and $hasScriptPath -and
                ($commandLine -notmatch '(?i)(?:^|\s)-StartInTray(?:\s|$)')
            (($isPowerShell -and $isDirectScriptInvocation -and $hasScriptPath) -or $isMonitorExecutable) -and $_.ProcessId -ne $PID -and $hasMatchingConfig
        })
    }
    catch {
        Write-Log ('Unable to inspect monitor processes: {0}' -f $_.Exception.Message) 'WARN'
        return @()
    }
}

function Stop-MonitorProcesses {
    $processes = @(Get-MonitorProcesses)
    foreach ($process in $processes) {
        try {
            Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
            Write-Log ('Stopped monitor process {0}.' -f $process.ProcessId)
        }
        catch {
            Write-Log ('Could not stop monitor process {0}: {1}' -f $process.ProcessId, $_.Exception.Message) 'WARN'
        }
    }

    if ($processes.Count -gt 0) {
        Start-Sleep -Milliseconds 500
    }
    return $processes.Count
}

function Test-ExpectedInternetHost {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateHost,
        [Parameter(Mandatory = $true)][string]$ExpectedHost
    )

    return ($CandidateHost -ieq $ExpectedHost) -or $CandidateHost.EndsWith(('.' + $ExpectedHost), [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-HttpInternetConnection {
    param([Parameter(Mandatory = $true)][string]$HostName)

    $probeUri = 'http://{0}/' -f $HostName
    $response = $null
    try {
        try {
            $response = Invoke-WebRequest -Uri $probeUri -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 8 -UserAgent 'CampusNetworkMonitor/1.0' -ErrorAction Stop
        }
        catch [System.Net.WebException] {
            $response = $_.Exception.Response
        }

        if ($null -eq $response) {
            return $false
        }

        $location = [string]$response.Headers['Location']
        if (-not [string]::IsNullOrWhiteSpace($location)) {
            try {
                $redirectUri = New-Object -TypeName System.Uri -ArgumentList @([System.Uri]$probeUri, $location)
                return (Test-ExpectedInternetHost -CandidateHost $redirectUri.Host -ExpectedHost $HostName)
            }
            catch {
                return $false
            }
        }

        $responseUri = $null
        if ($response.PSObject.Properties['BaseResponse']) {
            $responseUri = $response.BaseResponse.ResponseUri
        }
        elseif ($response.PSObject.Properties['ResponseUri']) {
            $responseUri = $response.ResponseUri
        }
        if ($null -eq $responseUri) {
            return $false
        }
        return (Test-ExpectedInternetHost -CandidateHost $responseUri.Host -ExpectedHost $HostName)
    }
    catch {
        return $false
    }
    finally {
        if ($response -and $response -is [System.IDisposable]) {
            $response.Dispose()
        }
    }
}

function Test-InternetConnection {
    param([Parameter(Mandatory = $true)]$Configuration)

    $hostName = [string]$Configuration.Check.Host
    $count = [int]$Configuration.Check.Count
    $retries = [int]$Configuration.Check.RetryCount
    $retryDelay = [int]$Configuration.Check.RetryIntervalSeconds

    for ($attempt = 1; $attempt -le $retries; $attempt++) {
        $pingSucceeded = $false
        try {
            $pingSucceeded = Test-Connection -ComputerName $hostName -Count $count -Quiet -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log ('Ping check error: {0}' -f $_.Exception.Message) 'WARN'
        }

        if ($pingSucceeded -and (Test-HttpInternetConnection -HostName $hostName)) {
            return $true
        }
        if ($pingSucceeded) {
            Write-Log 'Ping passed, but the HTTP internet check failed.' 'WARN'
        }

        if ($attempt -lt $retries -and $retryDelay -gt 0) {
            Start-Sleep -Seconds $retryDelay
        }
    }
    return $false
}

function ConvertTo-DoubleUrlEncoded {
    param([AllowEmptyString()][string]$Value)

    $once = [System.Uri]::EscapeDataString([string]$Value)
    return [System.Uri]::EscapeDataString($once)
}

function ConvertTo-PortalRsaHex {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$ExponentHex,
        [Parameter(Mandatory = $true)][string]$ModulusHex
    )

    Add-Type -AssemblyName System.Numerics

    $cleanModulus = $ModulusHex.Trim().TrimStart('0')
    if ([string]::IsNullOrWhiteSpace($cleanModulus)) {
        throw 'Portal RSA modulus is empty.'
    }

    $numberStyles = [System.Globalization.NumberStyles]::AllowHexSpecifier
    $modulus = [System.Numerics.BigInteger]::Parse(('00' + $cleanModulus), $numberStyles)
    $exponent = [System.Numerics.BigInteger]::Parse(('00' + $ExponentHex.Trim()), $numberStyles)

    # RSA.js uses 16-bit little-endian digits and a chunk size of twice the
    # highest modulus digit index. The portal uses raw RSA, not PKCS#1 padding.
    $digitCount = [int][Math]::Ceiling($cleanModulus.Length / 4.0)
    $chunkSize = 2 * ($digitCount - 1)
    if ($chunkSize -le 0) {
        throw 'Portal RSA modulus is too short.'
    }

    if ($Text.Length -eq 0) {
        return ''
    }

    $result = New-Object System.Text.StringBuilder
    for ($offset = 0; $offset -lt $Text.Length; $offset += $chunkSize) {
        $length = [Math]::Min($chunkSize, $Text.Length - $offset)
        $chunk = $Text.Substring($offset, $length)
        if ($chunk.Length -lt $chunkSize) {
            $chunk = $chunk.PadRight($chunkSize, [char]0)
        }

        # RSAUtils.encryptedString packs one low byte from each JavaScript
        # character code, two characters per 16-bit little-endian digit.
        $inputBytes = New-Object byte[] $chunkSize
        for ($index = 0; $index -lt $chunkSize; $index++) {
            $inputBytes[$index] = ([byte]([int][char]$chunk[$index] -band 0xFF))
        }
        $blockBytes = New-Object byte[] ($inputBytes.Length + 1)
        [Array]::Copy($inputBytes, $blockBytes, $inputBytes.Length)
        $block = New-Object System.Numerics.BigInteger -ArgumentList (,$blockBytes)
        $crypt = [System.Numerics.BigInteger]::ModPow($block, $exponent, $modulus)

        $hex = $crypt.ToString('x')
        $padding = (4 - ($hex.Length % 4)) % 4
        if ($padding -gt 0) {
            $hex = ('0' * $padding) + $hex
        }
        [void]$result.Append($hex)
        if (($offset + $chunkSize) -lt $Text.Length) {
            [void]$result.Append(' ')
        }
    }
    return $result.ToString()
}

function Invoke-PortalRequest {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Body
    )

    $baseUrl = ([string]$Configuration.Portal.BaseUrl).TrimEnd('/')
    $apiPath = [string]$Configuration.Portal.ApiPath
    $uri = '{0}{1}?method={2}' -f $baseUrl, $apiPath, $Method
    return Invoke-WebRequest -Uri $uri -Method Post -Body $Body -ContentType 'application/x-www-form-urlencoded; charset=UTF-8' -UseBasicParsing -TimeoutSec 10 -UserAgent 'CampusNetworkMonitor/1.0'
}

function Get-QueryStringParameterValue {
    param(
        [AllowEmptyString()][string]$QueryString,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $query = $QueryString.Trim().TrimStart('?')
    foreach ($part in ($query -split '&')) {
        if ([string]::IsNullOrWhiteSpace($part)) {
            continue
        }
        $separator = $part.IndexOf('=')
        $rawName = if ($separator -ge 0) { $part.Substring(0, $separator) } else { $part }
        if ([System.Uri]::UnescapeDataString($rawName.Replace('+', ' ')) -ieq $Name) {
            $rawValue = if ($separator -ge 0) { $part.Substring($separator + 1) } else { '' }
            return [System.Uri]::UnescapeDataString($rawValue.Replace('+', ' '))
        }
    }
    return ''
}

function Get-CaptivePortalQueryString {
    param([Parameter(Mandatory = $true)]$Configuration)

    try {
        $portalHost = ([System.Uri]([string]$Configuration.Portal.BaseUrl)).Host
    }
    catch {
        return ''
    }

    foreach ($probeUri in @('http://www.baidu.com/', 'http://neverssl.com/')) {
        $response = $null
        try {
            try {
                $response = Invoke-WebRequest -Uri $probeUri -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 8 -UserAgent 'CampusNetworkMonitor/1.0' -ErrorAction Stop
            }
            catch [System.Net.WebException] {
                $response = $_.Exception.Response
            }

            if (-not $response) {
                continue
            }
            $location = [string]$response.Headers['Location']
            if ([string]::IsNullOrWhiteSpace($location)) {
                continue
            }

            try {
                $redirectUri = New-Object -TypeName System.Uri -ArgumentList @([System.Uri]$probeUri, $location)
            }
            catch {
                continue
            }
            if ($redirectUri.Host -ieq $portalHost) {
                $queryString = $redirectUri.Query.TrimStart('?')
                if (-not [string]::IsNullOrWhiteSpace($queryString)) {
                    return $queryString
                }
            }
        }
        finally {
            if ($response -and $response -is [System.IDisposable]) {
                $response.Dispose()
            }
        }
    }
    return ''
}

function Get-PortalContext {
    param([Parameter(Mandatory = $true)]$Configuration)

    $configuredQueryString = [string]$Configuration.Portal.QueryString
    $capturedQueryString = Get-CaptivePortalQueryString -Configuration $Configuration
    $queryString = if ([string]::IsNullOrWhiteSpace($capturedQueryString)) { $configuredQueryString } else { $capturedQueryString }
    if (-not [string]::IsNullOrWhiteSpace($capturedQueryString)) {
        Write-Log 'Captured the current captive-portal context for authentication.'
    }

    $mac = Get-QueryStringParameterValue -QueryString $queryString -Name 'mac'
    if ([string]::IsNullOrWhiteSpace($mac)) {
        $mac = [string]$Configuration.Portal.Mac
    }

    return [pscustomobject]@{
        QueryString = $queryString
        Mac = $mac
    }
}

function Get-PortalPageInfo {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)]$PortalContext
    )

    $queryString = ConvertTo-DoubleUrlEncoded -Value ([string]$PortalContext.QueryString)
    $body = 'queryString={0}' -f $queryString
    $response = Invoke-PortalRequest -Configuration $Configuration -Method 'pageInfo' -Body $body
    if ([string]::IsNullOrWhiteSpace($response.Content)) {
        throw 'Portal pageInfo response is empty.'
    }
    return ($response.Content | ConvertFrom-Json)
}

function Get-PortalLoginBody {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)]$PageInfo,
        [Parameter(Mandatory = $true)]$PortalContext
    )

    $service = [string]$Configuration.Portal.Service
    if ([string]::IsNullOrWhiteSpace($service)) {
        $service = 'shu'
    }

    $encrypt = [string]$PageInfo.passwordEncrypt
    if ([string]::IsNullOrWhiteSpace($encrypt)) {
        $encrypt = 'true'
    }

    $passwordValue = $Password
    if ($encrypt -eq 'true' -and $Password.Length -lt 150) {
        $mac = [string]$PortalContext.Mac
        if ([string]::IsNullOrWhiteSpace($mac)) {
            $mac = '111111111'
        }
        # The portal's JavaScript reverses the complete password-and-device value
        # before applying raw RSA encryption.
        $passwordWithMac = $Password + '>' + $mac
        $characters = $passwordWithMac.ToCharArray()
        [Array]::Reverse($characters)
        $passwordValue = ConvertTo-PortalRsaHex -Text (-join $characters) -ExponentHex ([string]$PageInfo.publicKeyExponent) -ModulusHex ([string]$PageInfo.publicKeyModulus)
    }
    elseif ($encrypt -ne 'true' -and $Password.Length -gt 150) {
        $encrypt = 'true'
    }

    # The portal displays its account category prefix as an optional checkbox.
    # Use it only when the user has explicitly configured that account format.
    $usernamePrefix = [string]$Configuration.Portal.UsernamePrefix
    $usernameValue = $usernamePrefix + $Username.Trim()
    $queryString = [string]$PortalContext.QueryString
    $fields = [ordered]@{
        userId = $usernameValue
        password = $passwordValue
        service = $service
        queryString = $queryString
        operatorPwd = ''
        operatorUserId = ''
        validcode = ''
        passwordEncrypt = $encrypt
    }

    $parts = foreach ($entry in $fields.GetEnumerator()) {
        '{0}={1}' -f $entry.Key, (ConvertTo-DoubleUrlEncoded -Value ([string]$entry.Value))
    }
    return ($parts -join '&')
}

function Invoke-PortalApiLogin {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password
    )

    try {
        $portalContext = Get-PortalContext -Configuration $Configuration
        $pageInfo = Get-PortalPageInfo -Configuration $Configuration -PortalContext $portalContext
        $body = Get-PortalLoginBody -Configuration $Configuration -Username $Username -Password $Password -PageInfo $pageInfo -PortalContext $portalContext
        $response = Invoke-PortalRequest -Configuration $Configuration -Method 'login' -Body $body
        if ([string]::IsNullOrWhiteSpace($response.Content)) {
            Write-Log 'Portal login response is empty.' 'WARN'
            return $false
        }

        $result = $response.Content | ConvertFrom-Json
        if ([string]$result.result -eq 'success') {
            Write-Log ('Portal login accepted: {0}' -f [string]$result.message)
            return $true
        }

        Write-Log ('Portal login rejected: {0}' -f [string]$result.message) 'WARN'
        return $false
    }
    catch {
        Write-Log ('Portal login request failed: {0}' -f $_.Exception.Message) 'WARN'
        return $false
    }
}

function Invoke-PortalBrowserLogin {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password
    )

    # The campus login page owns its encryption and service-selection rules.
    # Use its script when Internet Explorer's built-in automation component is
    # available, then fall back to the API implementation on unsupported PCs.
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        Write-Log 'Webpage authentication is unavailable outside an STA thread; using the API fallback.' 'WARN'
        return $null
    }

    $browser = $null
    try {
        $portalContext = Get-PortalContext -Configuration $Configuration
        if ([string]::IsNullOrWhiteSpace([string]$portalContext.QueryString)) {
            Write-Log 'Webpage authentication needs a captive-portal context.' 'WARN'
            return $null
        }

        $baseUrl = ([string]$Configuration.Portal.BaseUrl).TrimEnd('/')
        $loginUrl = '{0}/eportal/index.jsp?{1}' -f $baseUrl, [string]$portalContext.QueryString
        $browser = New-Object -ComObject InternetExplorer.Application
        $browser.Visible = $false
        $browser.Silent = $true
        $browser.Left = -32000
        $browser.Top = -32000
        $browser.Width = 1
        $browser.Height = 1
        $browser.MenuBar = $false
        $browser.StatusBar = $false
        $browser.ToolBar = 0
        [void]$browser.Navigate2($loginUrl)

        $deadline = (Get-Date).AddSeconds(20)
        $document = $null
        while ((Get-Date) -lt $deadline) {
            try {
                if (-not $browser.Busy -and [int]$browser.ReadyState -eq 4) {
                    $candidate = $browser.Document
                    $usernameField = $candidate.getElementById('username')
                    $passwordField = $candidate.getElementById('pwd')
                    $encryptField = $candidate.getElementById('passwordEncrypt')
                    $modulusField = $candidate.getElementById('publicKeyModulus')
                    $encryptionReady = ($null -ne $encryptField -and [string]$encryptField.value -ne 'true') -or
                        ($null -ne $modulusField -and -not [string]::IsNullOrWhiteSpace([string]$modulusField.value))
                    if ($null -ne $usernameField -and $null -ne $passwordField -and $encryptionReady) {
                        $document = $candidate
                        break
                    }
                }
            }
            catch {
                # The document is being replaced while the portal initializes.
            }
            Start-Sleep -Milliseconds 250
        }

        if ($null -eq $document) {
            Write-Log 'Webpage authentication could not load the portal login form.' 'WARN'
            return $null
        }

        $document.getElementById('username').value = $Username.Trim()
        $document.getElementById('pwd').value = $Password
        if (-not [string]::IsNullOrWhiteSpace([string]$Configuration.Portal.UsernamePrefix)) {
            [void]$document.parentWindow.execScript('chooseTj();', 'JavaScript')
        }

        $loginLink = $document.getElementById('loginLink')
        if ($null -ne $loginLink) {
            $loginLink.click()
        }
        else {
            [void]$document.parentWindow.execScript('doauthen();', 'JavaScript')
        }

        Start-Sleep -Seconds 6
        try {
            $errorElement = $browser.Document.getElementById('errorInfo_center')
            $errorMessage = if ($null -ne $errorElement) { [string]$errorElement.innerText } else { '' }
            if (-not [string]::IsNullOrWhiteSpace($errorMessage)) {
                Write-Log ('Webpage portal login rejected: {0}' -f $errorMessage.Trim()) 'WARN'
                return $false
            }
        }
        catch {
            # The page may redirect immediately after a successful login.
        }

        Write-Log 'Webpage portal login submitted.'
        return $true
    }
    catch {
        Write-Log ('Webpage authentication is unavailable: {0}' -f $_.Exception.Message) 'WARN'
        return $null
    }
    finally {
        if ($null -ne $browser) {
            try { $browser.Quit() } catch {}
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($browser)
        }
    }
}

function Invoke-PortalLogin {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password
    )

    $browserResult = Invoke-PortalBrowserLogin -Configuration $Configuration -Username $Username -Password $Password
    if ($null -ne $browserResult) {
        return [bool]$browserResult
    }
    return (Invoke-PortalApiLogin -Configuration $Configuration -Username $Username -Password $Password)
}

function Send-NotificationEmail {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string]$Body
    )

    if (-not [bool]$Configuration.Email.Enabled) {
        Write-Log 'Email notification is disabled.' 'WARN'
        return $false
    }

    $email = $Configuration.Email
    $from = [string]$email.Address
    $recipients = @(([string]$email.Recipient -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $smtpServer = [string]$email.SmtpServer
    if ([string]::IsNullOrWhiteSpace($smtpServer)) {
        $smtpServer = Get-AutoSmtpServer -Address $from
    }
    if ([string]::IsNullOrWhiteSpace($from) -or [string]::IsNullOrWhiteSpace($smtpServer) -or $recipients.Count -eq 0) {
        Write-Log 'Email settings are incomplete; notification was not sent.' 'WARN'
        return $false
    }

    $mailMessage = $null
    $smtpClient = $null
    try {
        $computer = Get-ComputerLabel
        $mailMessage = New-Object System.Net.Mail.MailMessage
        $mailMessage.From = New-Object -TypeName System.Net.Mail.MailAddress -ArgumentList $from
        foreach ($recipient in $recipients) {
            [void]$mailMessage.To.Add((New-Object -TypeName System.Net.Mail.MailAddress -ArgumentList ([string]$recipient)))
        }
        $mailMessage.Subject = '[{0}] {1}{2}' -f $computer, ([string]$email.SubjectPrefix), $Subject
        $mailMessage.Body = "Computer: $computer`r`nWindows user: $env:USERNAME`r`n`r`n$Body"
        $mailMessage.BodyEncoding = [System.Text.Encoding]::UTF8
        $mailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8

        $smtpClient = New-Object -TypeName System.Net.Mail.SmtpClient -ArgumentList $smtpServer, ([int]$email.Port)
        $smtpClient.EnableSsl = [bool]$email.UseSsl
        $smtpClient.UseDefaultCredentials = $false
        if ([string]::IsNullOrWhiteSpace([string]$email.Password)) {
            throw 'SMTP password is empty.'
        }
        $smtpClient.Credentials = New-Object -TypeName System.Net.NetworkCredential -ArgumentList $from, ([string]$email.Password)
        $smtpClient.Send($mailMessage)
        Write-Log ('Notification email sent to {0}' -f ($recipients -join ', '))
        return $true
    }
    catch {
        $details = $_.Exception.Message
        $inner = $_.Exception.InnerException
        while ($inner) {
            $details += ' Inner: {0}' -f $inner.Message
            $inner = $inner.InnerException
        }
        Write-Log ('Notification email failed: {0}' -f $details) 'WARN'
        return $false
    }
    finally {
        if ($mailMessage) { $mailMessage.Dispose() }
        if ($smtpClient) { $smtpClient.Dispose() }
    }
}

function Install-MonitorTask {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [bool]$SendNotification = $true
    )

    $taskName = [string]$Configuration.Runtime.TaskName
    if ([string]::IsNullOrWhiteSpace($taskName)) { $taskName = 'CampusNetworkMonitor' }
    $arguments = Get-MonitorTaskArguments

    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $startupEnabled = $true
    if ($existingTask) {
        $existingTriggers = @($existingTask.Triggers)
        if ($existingTriggers.Count -gt 0) {
            $startupEnabled = @($existingTriggers | Where-Object { [bool]$_.Enabled }).Count -gt 0
        }
    }

    $action = New-ApplicationTaskAction -ScriptPath $script:SourceScriptPathFull -ExecutablePath $script:MonitorExecutablePath -Arguments $arguments -HideWindow
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    $trigger.Enabled = $startupEnabled
    $principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Description 'Monitor campus network and re-authenticate when needed.' -Force | Out-Null

    $registeredTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $registeredAction = @($registeredTask.Actions) | Select-Object -First 1
    $registeredExecutable = if ($registeredAction) { ([string]$registeredAction.Execute).Trim().Trim('"') } else { '' }
    if ([string]::IsNullOrWhiteSpace($registeredExecutable) -or -not (Test-Path -LiteralPath $registeredExecutable -PathType Leaf)) {
        throw ('计划任务已注册，但动作文件不存在：{0}' -f $registeredExecutable)
    }

    Write-Host ('Scheduled task installed: {0}' -f $taskName)

    if ($SendNotification) {
        $sent = Send-NotificationEmail -Configuration $Configuration -Subject 'Monitor enabled' -Body ('Campus network monitor was enabled successfully at {0}. The scheduled task is ready to run at Windows logon.' -f (Get-Date))
        if ($sent) {
            Write-Host 'Confirmation email sent.'
        }
        else {
            Write-Host 'The scheduled task was installed, but the confirmation email could not be sent.'
        }
    }
}

function Get-PanelTaskName {
    return 'CampusNetworkMonitorPanel'
}

function Get-MonitorTaskArguments {
    $modeArguments = ''
    if ($script:SingleExecutableMode) {
        $modeArguments = '-RunMonitor -EntryPath "{0}"' -f $script:EntryExecutablePath
    }
    return ('{0} -ConfigPath "{1}"' -f $modeArguments, $script:ConfigPathFull).Trim()
}

function Get-TaskActionExecutable {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $action = @($task.Actions) | Select-Object -First 1
        if (-not $action) {
            return ''
        }
        return ([string]$action.Execute).Trim().Trim('"')
    }
    catch {
        return ''
    }
}

function Test-TaskActionMatchesExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [string]$ExpectedArguments = '',
        [switch]$HideWindow
    )

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $action = @($task.Actions) | Select-Object -First 1
        if (-not $action) {
            return $false
        }

        $registeredExecutable = ([string]$action.Execute).Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($registeredExecutable) -or -not (Test-Path -LiteralPath $registeredExecutable -PathType Leaf)) {
            return $false
        }
        if ($HideWindow) {
            $launcherPath = Join-Path $env:WINDIR 'System32\wscript.exe'
            if ([System.IO.Path]::GetFullPath($registeredExecutable) -ine [System.IO.Path]::GetFullPath($launcherPath)) {
                return $false
            }
            $expectedLauncherArguments = Get-HiddenLauncherArguments -ExecutablePath $ExecutablePath -Arguments $ExpectedArguments
            return ([string]$action.Arguments).Trim() -ieq $expectedLauncherArguments.Trim()
        }
        if ([System.IO.Path]::GetFullPath($registeredExecutable) -ine [System.IO.Path]::GetFullPath($ExecutablePath)) {
            return $false
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedArguments) -and ([string]$action.Arguments).Trim() -ine $ExpectedArguments.Trim()) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Get-HiddenLauncherPath {
    return (Join-Path $script:ScriptDirectory 'CampusNetworkMonitorLauncher.vbs')
}

function Ensure-HiddenLauncherScript {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [string]$Arguments = ''
    )

    # WScript starts the compiled monitor with SW_HIDE from process creation.
    # This is more reliable than a second PowerShell process, which can briefly
    # expose PS2EXE's output window during portal re-authentication.
    $launcherPath = Get-HiddenLauncherPath
    $vbsExecutable = $ExecutablePath.Replace('"', '""')
    $vbsArguments = $Arguments.Replace('"', '""')
    $content = @"
Option Explicit
Dim shell, target, arguments, command
target = "$vbsExecutable"
arguments = "$vbsArguments"
Set shell = CreateObject("WScript.Shell")
command = Chr(34) & target & Chr(34)
If Len(arguments) > 0 Then command = command & " " & arguments
shell.Run command, 0, True
"@
    Set-Content -LiteralPath $launcherPath -Value $content -Encoding ASCII
    return $launcherPath
}

function Get-HiddenLauncherArguments {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [string]$Arguments = ''
    )

    $launcherPath = Ensure-HiddenLauncherScript -ExecutablePath $ExecutablePath -Arguments $Arguments
    return ('//B //NoLogo "{0}"' -f $launcherPath)
}

function New-ApplicationTaskAction {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [string]$Arguments = '',
        [switch]$HideWindow
    )

    if ($script:SingleExecutableMode -and -not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        throw ('单一入口程序不存在，无法创建计划任务：{0}' -f $ExecutablePath)
    }

    if (Test-Path -LiteralPath $ExecutablePath -PathType Leaf) {
        $workingDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($ExecutablePath))
        if ($HideWindow) {
            $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
            if (-not (Test-Path -LiteralPath $wscript -PathType Leaf)) {
                throw ('Windows Script Host 不可用，无法创建静默监控任务：{0}' -f $wscript)
            }
            $launcherArguments = Get-HiddenLauncherArguments -ExecutablePath ([System.IO.Path]::GetFullPath($ExecutablePath)) -Arguments $Arguments
            try {
                return New-ScheduledTaskAction -Execute $wscript -Argument $launcherArguments -WorkingDirectory $workingDirectory
            }
            catch {
                return New-ScheduledTaskAction -Execute $wscript -Argument $launcherArguments
            }
        }
        try {
            return New-ScheduledTaskAction -Execute ([System.IO.Path]::GetFullPath($ExecutablePath)) -Argument $Arguments -WorkingDirectory $workingDirectory
        }
        catch {
            return New-ScheduledTaskAction -Execute ([System.IO.Path]::GetFullPath($ExecutablePath)) -Argument $Arguments
        }
    }

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw ('监控脚本不存在，无法创建计划任务：{0}' -f $ScriptPath)
    }

    $powershell = Join-Path $PSHOME 'powershell.exe'
    $scriptArguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $ScriptPath
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $scriptArguments += ' ' + $Arguments
    }
    $workingDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($ScriptPath))
    try {
        return New-ScheduledTaskAction -Execute $powershell -Argument $scriptArguments -WorkingDirectory $workingDirectory
    }
    catch {
        return New-ScheduledTaskAction -Execute $powershell -Argument $scriptArguments
    }
}

function Install-PanelTask {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [bool]$Enabled = $true
    )

    $taskName = Get-PanelTaskName
    if ($script:SingleExecutableMode) {
        $panelScript = $script:SourceScriptPathFull
        $panelExecutable = $script:EntryExecutablePath
    }
    else {
        $panelScript = [System.IO.Path]::GetFullPath((Join-Path $script:ScriptDirectory 'CampusNetworkMonitorApp.ps1'))
        $panelExecutable = [System.IO.Path]::GetFullPath((Join-Path $script:ScriptDirectory 'CampusNetworkMonitorPanel.exe'))
        if (-not (Test-Path -LiteralPath $panelScript -PathType Leaf)) {
            throw ('Control panel script not found: {0}' -f $panelScript)
        }
    }

    $action = New-ApplicationTaskAction -ScriptPath $panelScript -ExecutablePath $panelExecutable -Arguments '-StartInTray -RepairOnStart -StartMonitorAfterRepair'
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    $trigger.Enabled = $Enabled
    $principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Description 'Start the campus network control panel in the notification area.' -Force | Out-Null

    $registeredTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $registeredAction = @($registeredTask.Actions) | Select-Object -First 1
    $registeredExecutable = if ($registeredAction) { ([string]$registeredAction.Execute).Trim().Trim('"') } else { '' }
    if ([string]::IsNullOrWhiteSpace($registeredExecutable) -or -not (Test-Path -LiteralPath $registeredExecutable -PathType Leaf)) {
        throw ('托盘任务已注册，但动作文件不存在：{0}' -f $registeredExecutable)
    }

    Write-Host ('Panel startup task installed: {0}' -f $taskName)
}

function Repair-Tasks {
    param([Parameter(Mandatory = $true)]$Configuration)

    $repairedTasks = @()
    $monitorTaskName = [string]$Configuration.Runtime.TaskName
    if ([string]::IsNullOrWhiteSpace($monitorTaskName)) { $monitorTaskName = 'CampusNetworkMonitor' }
    $monitorArguments = Get-MonitorTaskArguments
    if (Test-TaskActionMatchesExecutable -TaskName $monitorTaskName -ExecutablePath $script:MonitorExecutablePath -ExpectedArguments $monitorArguments -HideWindow) {
        Write-Host ('Monitor task already points to the current program: {0}' -f $monitorTaskName)
    }
    else {
        Install-MonitorTask -Configuration $Configuration -SendNotification:$false
        $repairedTasks += $monitorTaskName
        Write-Host ('Monitor task repaired for the current computer: {0}' -f $monitorTaskName)
    }

    $panelTaskName = Get-PanelTaskName
    $panelExecutable = if ($script:SingleExecutableMode) { $script:EntryExecutablePath } else { [System.IO.Path]::GetFullPath((Join-Path $script:ScriptDirectory 'CampusNetworkMonitorPanel.exe')) }
    $panelArguments = '-StartInTray -RepairOnStart -StartMonitorAfterRepair'
    if (Test-TaskActionMatchesExecutable -TaskName $panelTaskName -ExecutablePath $panelExecutable -ExpectedArguments $panelArguments) {
        Write-Host ('Panel task already points to the current program: {0}' -f $panelTaskName)
    }
    else {
        Install-PanelTask -Configuration $Configuration -Enabled $true
        $repairedTasks += $panelTaskName
        Write-Host ('Panel task repaired for the current computer: {0}' -f $panelTaskName)
    }

    if ($repairedTasks.Count -gt 0) {
        $body = 'Campus network monitor was configured automatically on {0} at {1}. Repaired tasks: {2}.' -f $env:COMPUTERNAME, (Get-Date), ($repairedTasks -join ', ')
        if (Send-NotificationEmail -Configuration $Configuration -Subject 'Monitor enabled' -Body $body) {
            Write-Host 'Automatic setup confirmation email sent.'
        }
        else {
            Write-Host 'Tasks were repaired, but the automatic setup confirmation email could not be sent.'
        }
    }
}

function Set-PanelStartup {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][bool]$Enabled
    )

    $taskName = Get-PanelTaskName
    if ($Enabled) {
        Install-PanelTask -Configuration $Configuration -Enabled $true
        Write-Host 'Control panel startup at Windows logon: enabled.'
        return
    }

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host ('Panel startup task not found: {0}' -f $taskName)
        return
    }

    $triggers = @($task.Triggers)
    if ($triggers.Count -eq 0) {
        Write-Host 'The control panel task has no startup trigger.'
        return
    }

    foreach ($trigger in $triggers) {
        $trigger.Enabled = $false
    }
    Set-ScheduledTask -TaskName $taskName -Trigger $triggers -ErrorAction Stop | Out-Null
    Write-Host 'Control panel startup at Windows logon: disabled.'
}

function Set-MonitorStartup {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)][bool]$Enabled
    )

    $taskName = [string]$Configuration.Runtime.TaskName
    if ([string]::IsNullOrWhiteSpace($taskName)) { $taskName = 'CampusNetworkMonitor' }

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        if ($Enabled) {
            Install-MonitorTask -Configuration $Configuration
            Set-PanelStartup -Configuration $Configuration -Enabled $true
            Write-Host 'Startup at Windows logon enabled.'
        }
        else {
            Write-Host ('Scheduled task not found: {0}' -f $taskName)
            Set-PanelStartup -Configuration $Configuration -Enabled $false
        }
        return
    }

    $triggers = @($task.Triggers)
    if ($triggers.Count -eq 0) {
        if (-not $Enabled) {
            Write-Host 'This task has no startup trigger.'
            Set-PanelStartup -Configuration $Configuration -Enabled $false
            return
        }
        $triggers = @((New-ScheduledTaskTrigger -AtLogOn -User ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)))
    }

    foreach ($trigger in $triggers) {
        $trigger.Enabled = $Enabled
    }
    Set-ScheduledTask -TaskName $taskName -Trigger $triggers -ErrorAction Stop | Out-Null

    if ($Enabled) {
        Write-Host 'Startup at Windows logon: enabled.'
    }
    else {
        Write-Host 'Startup at Windows logon: disabled.'
    }

    Set-PanelStartup -Configuration $Configuration -Enabled $Enabled
}

function Uninstall-MonitorTask {
    param([Parameter(Mandatory = $true)]$Configuration)

    $taskName = [string]$Configuration.Runtime.TaskName
    if ([string]::IsNullOrWhiteSpace($taskName)) { $taskName = 'CampusNetworkMonitor' }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host ('Scheduled task removed if it existed: {0}' -f $taskName)

    $panelTaskName = Get-PanelTaskName
    Unregister-ScheduledTask -TaskName $panelTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host ('Panel startup task removed if it existed: {0}' -f $panelTaskName)
}

function Stop-MonitorTask {
    param([Parameter(Mandatory = $true)]$Configuration)

    $taskName = [string]$Configuration.Runtime.TaskName
    if ([string]::IsNullOrWhiteSpace($taskName)) { $taskName = 'CampusNetworkMonitor' }

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $monitorProcesses = @(Get-MonitorProcesses)
    if (-not $task -and $monitorProcesses.Count -eq 0) {
        Write-Host ('Scheduled task and monitor process were not found: {0}' -f $taskName)
        return
    }

    if ($task) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Write-Host ('Scheduled task stopped: {0}' -f $taskName)
    }
    else {
        Write-Host ('Scheduled task not found: {0}' -f $taskName)
    }

    $stoppedProcessCount = Stop-MonitorProcesses
    if ($stoppedProcessCount -gt 0) {
        Write-Host ('Monitor process stopped: {0}' -f $stoppedProcessCount)
    }

    $sent = Send-NotificationEmail -Configuration $Configuration -Subject 'Monitor disabled' -Body ('Campus network monitor was stopped manually at {0}.' -f (Get-Date))
    if ($sent) {
        Write-Host 'Shutdown notification email sent.'
    }
    else {
        Write-Host 'The task was stopped, but the shutdown notification email could not be sent.'
    }
}

function Invoke-Monitor {
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [switch]$RunOnce,
        [switch]$ForceAuthentication
    )

    $campusPassword = [string]$Configuration.Credentials.Password
    if ([string]::IsNullOrWhiteSpace($campusPassword)) {
        throw 'Campus password is empty.'
    }
    $username = [string]$Configuration.Credentials.Username
    if ([string]::IsNullOrWhiteSpace($username)) {
        throw 'Campus username is empty.'
    }

    $authAttempts = [int]$Configuration.Runtime.AuthAttempts
    if ($ForceAuthentication) {
        $authAttempts = 1
    }
    $authDelay = [int]$Configuration.Runtime.AuthRetryDelaySeconds
    $afterAuthWait = [int]$Configuration.Runtime.AfterAuthWaitSeconds
    $interval = [int]$Configuration.Check.IntervalSeconds
    $cooldown = [int]$Configuration.Runtime.NotificationCooldownMinutes
    $lastState = $null
    $lastFailureNotice = [DateTime]::MinValue

    $mutex = New-Object System.Threading.Mutex($false, 'Local\CampusNetworkMonitor')
    $mutexAcquired = $false
    try {
        $mutexAcquired = $mutex.WaitOne(0)
        if (-not $mutexAcquired) {
            Write-Log 'Monitor is already running; this instance will exit.'
            return
        }

        do {
            $online = if ($ForceAuthentication) { $false } else { Test-InternetConnection -Configuration $Configuration }
            if ($online) {
                Write-Log 'Internet check passed.'
                if ($lastState -eq $false) {
                    [void](Send-NotificationEmail -Configuration $Configuration -Subject 'Network recovered' -Body ('Internet access recovered at {0}.' -f (Get-Date)))
                }
                $lastState = $true
            }
            else {
                Write-Log 'Internet check failed; starting portal re-authentication.' 'WARN'
                $authenticated = $false
                for ($attempt = 1; $attempt -le $authAttempts; $attempt++) {
                    Write-Log ('Authentication attempt {0}/{1}.' -f $attempt, $authAttempts)
                    if (Invoke-PortalLogin -Configuration $Configuration -Username $username -Password $campusPassword) {
                        if ($afterAuthWait -gt 0) { Start-Sleep -Seconds $afterAuthWait }
                        if (Test-InternetConnection -Configuration $Configuration) {
                            $authenticated = $true
                            break
                        }
                        Write-Log 'Portal accepted the request, but the internet check is still failing.' 'WARN'
                    }
                    if ($attempt -lt $authAttempts -and $authDelay -gt 0) {
                        Start-Sleep -Seconds $authDelay
                    }
                }

                if ($authenticated) {
                    Write-Log 'Network restored after portal re-authentication.'
                    # Re-authentication is an event in its own right. The
                    # previous ping state can still be online immediately
                    # before the portal session expires, so it must not
                    # suppress this notification.
                    [void](Send-NotificationEmail -Configuration $Configuration -Subject 'Network re-authenticated' -Body ('Campus network was re-authenticated successfully at {0}.' -f (Get-Date)))
                    $lastState = $true
                }
                else {
                    Write-Log 'Portal re-authentication did not restore internet access.' 'ERROR'
                    $now = Get-Date
                    if (($lastState -ne $false) -or (($now - $lastFailureNotice).TotalMinutes -ge $cooldown)) {
                        [void](Send-NotificationEmail -Configuration $Configuration -Subject 'Network authentication failed' -Body ('Campus network authentication failed at {0}. Check the log: {1}' -f $now, $script:LogPath))
                        $lastFailureNotice = $now
                    }
                    $lastState = $false
                }
            }

            if (-not $RunOnce -and $interval -gt 0) {
                Start-Sleep -Seconds $interval
            }
        } while (-not $RunOnce)
    }
    finally {
        if ($mutex) {
            try {
                if ($mutexAcquired) {
                    $mutex.ReleaseMutex()
                }
            }
            catch {
                # The process is exiting; the named mutex will be released.
            }
            $mutex.Dispose()
        }
    }
}

try {
    if ($Setup) {
        Initialize-Configuration
        exit 0
    }

    $configuration = Read-Configuration
    $script:LogPath = Get-LogPath -Configuration $configuration
    $logParent = Split-Path -Parent $script:LogPath
    if ($logParent -and -not (Test-Path -LiteralPath $logParent)) {
        New-Item -ItemType Directory -Path $logParent -Force | Out-Null
    }

    if ($ShowConfig) {
        $safeConfiguration = $configuration | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $safeConfiguration.Credentials.Password = '<hidden>'
        $safeConfiguration.Email.Password = '<hidden>'
        $safeConfiguration | ConvertTo-Json -Depth 10
        exit 0
    }
    if ($InstallTask) {
        Install-MonitorTask -Configuration $configuration
        exit 0
    }
    if ($RepairTasks) {
        Repair-Tasks -Configuration $configuration
        exit 0
    }
    if ($ForceAuthenticate) {
        Invoke-Monitor -Configuration $configuration -RunOnce -ForceAuthentication
        exit 0
    }
    if ($StopTask) {
        Stop-MonitorTask -Configuration $configuration
        exit 0
    }
    if ($EnableStartup -and $DisableStartup) {
        throw 'Choose either -EnableStartup or -DisableStartup, not both.'
    }
    if ($EnableStartup) {
        Set-MonitorStartup -Configuration $configuration -Enabled $true
        exit 0
    }
    if ($DisableStartup) {
        Set-MonitorStartup -Configuration $configuration -Enabled $false
        exit 0
    }
    if ($UninstallTask) {
        Uninstall-MonitorTask -Configuration $configuration
        exit 0
    }

    Invoke-Monitor -Configuration $configuration -RunOnce:$Once
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    exit 1
}

