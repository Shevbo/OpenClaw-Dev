<#
ssh-passwordless-setup.ps1

PowerShell скрипт для Windows: настраивает SSH по ключу (без пароля) к удалённой Ubuntu.

Что делает:
1) Спрашивает Host/IP, User, Password (secure)
2) Генерирует ed25519 ключ (если нет)
3) Подключается по паролю через Posh-SSH (SSH.NET) и добавляет public key в ~/.ssh/authorized_keys
4) Добавляет алиас в %USERPROFILE%\.ssh\config

Требования:
- Windows PowerShell 5+ или PowerShell 7+
- Доступ к удалённому SSH по паролю (первый раз)
- Модуль Posh-SSH (установится автоматически при необходимости)

Запуск:
  powershell -ExecutionPolicy Bypass -File .\ssh-passwordless-setup.ps1

Без вопросов (пароль — первая строка файла):
  powershell -ExecutionPolicy Bypass -File .\ssh-passwordless-setup.ps1 -RemoteHost 192.168.1.50 -Login user -SshAlias my-pi -PasswordFile C:\path\pass.txt

Прокси для powershellgallery.com (curl / Install-Module / NuGet):
  -ProxyUri http://127.0.0.1:8080
  или задайте HTTPS_PROXY / HTTP_PROXY в окружении.
  С учётной записью: -ProxyUri http://proxy:8080 -ProxyCredential (Get-Credential)
  Proxy6.net: положите api_key (и опционально пароль в первой строке) в файл, например C:\dev\p.txt —
  скрипт вызовет getproxy и возьмёт активный IPv6-прокси. Явный -ProxyUri имеет приоритет.

Кодировка: сохраните этот файл как UTF-8 с BOM (в VS Code: статусная строка → «UTF-8» → «Save with Encoding» → UTF-8 with BOM).
Иначе в Windows PowerShell 5.1 кириллица в строках скрипта читается неверно (РЅР°РїСЂ…).
#>

[CmdletBinding()]
param(
  [string]$RemoteHost = "",
  [string]$Login = "",
  [string]$SshAlias = "",
  [string]$PasswordFile = "",
  [string]$ProxyUri = "",
  [System.Management.Automation.PSCredential]$ProxyCredential = $null,
  [string]$Proxy6ConfigFile = ""
)

$ErrorActionPreference = "Stop"

# Консоль в UTF-8 — чтобы Read-Host / Write-Host с кириллицей отображались корректно
try {
	if ($Host.Name -eq 'ConsoleHost' -and $PSVersionTable.PSVersion.Major -lt 6) {
		chcp 65001 | Out-Null
	}
	[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
	[Console]::InputEncoding = [System.Text.Encoding]::UTF8
} catch { }

function ConvertTo-SecureStringFromPlain([string]$Plain) {
  if ([string]::IsNullOrEmpty($Plain)) { throw "Password is empty" }
  $sec = New-Object System.Security.SecureString
  foreach ($ch in $Plain.ToCharArray()) { [void]$sec.AppendChar($ch) }
  return $sec
}

# Строки на русском через кодовые точки Unicode — отображение не зависит от кодировки .ps1 (ANSI/UTF-8 без BOM).
function U([int[]]$Codepoints) {
  -join ($Codepoints | ForEach-Object { [char]$_ })
}

$script:GalleryProxyUri = $null
$script:GalleryProxyCredential = $null

function Get-Proxy6GalleryFromConfigFile {
  param([string]$Path)
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $m = [regex]::Match($raw, '(?i)"api_key"\s*:\s*"([^"]+)"')
  if (-not $m.Success) { throw "api_key not found in config file" }
  $apiKey = $m.Groups[1].Value.Trim()

  $firstLine = ($raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
  if ($null -ne $firstLine) { $firstLine = $firstLine.Trim() }
  $passFallback = $null
  if ($firstLine -and $firstLine -notmatch '^[\{\[]' -and $firstLine -notmatch '"') {
    $passFallback = $firstLine
  }

  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch { }

  $apiUrl = ('https://px6.link/api/' + [uri]::EscapeDataString($apiKey) + '/getproxy?state=active')
  $resp = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
  if ($resp.status -ne 'yes') {
    $err = $resp.error
    if (-not $err) { $err = ($resp | ConvertTo-Json -Compress -Depth 5) }
    throw ("Proxy6 API: " + $err)
  }
  if (-not $resp.list) { throw "Proxy6: empty proxy list" }

  $items = @()
  foreach ($p in $resp.list.PSObject.Properties) {
    $o = $p.Value
    if ($null -eq $o) { continue }
    if ($o.active -eq '1' -or $o.active -eq 1) { $items += $o }
  }
  if ($items.Count -eq 0) { throw "Proxy6: no active proxies" }

  $pick = $items | Where-Object { $_.ip -and ($_.ip -match ':') } | Select-Object -First 1
  if (-not $pick) { $pick = $items | Select-Object -First 1 }

  $hostName = [string]$pick.host
  $port = [string]$pick.port
  $userName = [string]$pick.user
  $plainPass = [string]$pick.pass
  if ([string]::IsNullOrWhiteSpace($plainPass)) { $plainPass = $passFallback }
  if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($plainPass)) {
    throw "Proxy6: user/pass missing (check API response and optional first line in config)"
  }

  $proxyUri = 'http://' + $hostName + ':' + $port
  $sec = ConvertTo-SecureStringFromPlain $plainPass
  $cred = New-Object System.Management.Automation.PSCredential($userName, $sec)

  return @{
    ProxyUri     = $proxyUri
    Credential   = $cred
    Proxy6Host   = $hostName
    Proxy6Port   = $port
  }
}

function Initialize-GalleryProxy {
  param(
    [string]$Uri,
    [System.Management.Automation.PSCredential]$Credential,
    [string]$Proxy6ConfigFile
  )
  $u = $Uri.Trim()
  $cred = $Credential

  $configPath = $Proxy6ConfigFile
  if ([string]::IsNullOrWhiteSpace($configPath) -and (Test-Path -LiteralPath 'c:\dev\p.txt')) {
    $configPath = 'c:\dev\p.txt'
  }

  if ([string]::IsNullOrWhiteSpace($u) -and $configPath -and (Test-Path -LiteralPath $configPath)) {
    try {
      $p6 = Get-Proxy6GalleryFromConfigFile -Path $configPath
      $u = $p6.ProxyUri
      $cred = $p6.Credential
      Write-Host ("[setup] Proxy6 Gallery proxy: " + $p6.Proxy6Host + ":" + $p6.Proxy6Port + " (IPv6 via API)") -ForegroundColor DarkGray
    } catch {
      Write-Host ("[setup] Proxy6: " + $_.Exception.Message) -ForegroundColor DarkYellow
    }
  }

  if ([string]::IsNullOrWhiteSpace($u)) {
    $u = $env:HTTPS_PROXY
    if ([string]::IsNullOrWhiteSpace($u)) { $u = $env:HTTP_PROXY }
  }
  if ([string]::IsNullOrWhiteSpace($u)) {
    return
  }
  $script:GalleryProxyUri = $u
  $script:GalleryProxyCredential = $cred
  $env:HTTPS_PROXY = $u
  $env:HTTP_PROXY = $u
  $proxy = New-Object System.Net.WebProxy($u, $true)
  if ($cred) {
    $proxy.Credentials = $cred.GetNetworkCredential()
  } else {
    $proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
  }
  [System.Net.WebRequest]::DefaultWebProxy = $proxy
  Write-Host "[setup] Proxy for PowerShell Gallery: $u" -ForegroundColor DarkGray
}

function Get-GalleryProxyJobArgs {
  $pu = $null
  $pp = $null
  if ($script:GalleryProxyCredential) {
    $nc = $script:GalleryProxyCredential.GetNetworkCredential()
    $pu = $nc.UserName
    $pp = $nc.Password
  }
  return @{
    Uri = $script:GalleryProxyUri
    User = $pu
    Pass = $pp
  }
}

function Ensure-NuGetProvider {
  # Install-Module требует NuGet PackageProvider ≥ 2.8.5.201.
  $min = [version]'2.8.5.201'
  $existing = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
    Where-Object { $_.Version -ge $min } |
    Select-Object -First 1
  if ($existing) { return }

  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch { }

  # 1) Онлайн (с таймаутом — без DLL Install-PackageProvider иногда «висит» на PSGallery).
  $onlineDone = $false
  try {
    Write-Host "[setup] Install-PackageProvider NuGet (PSGallery, online, timeout 120s)..." -ForegroundColor Yellow
    $pj = Get-GalleryProxyJobArgs
    $job = Start-Job -ScriptBlock {
      param([string]$minVer, [string]$proxyUrl, [string]$proxyUser, [string]$proxyPass)
      $ErrorActionPreference = 'Stop'
      [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
      if ($proxyUrl) {
        $env:HTTPS_PROXY = $proxyUrl
        $env:HTTP_PROXY = $proxyUrl
        $pr = New-Object System.Net.WebProxy($proxyUrl, $true)
        if ($proxyUser) {
          $pr.Credentials = New-Object System.Net.NetworkCredential($proxyUser, $proxyPass)
        } else {
          $pr.Credentials = [System.Net.CredentialCache]::DefaultCredentials
        }
        [System.Net.WebRequest]::DefaultWebProxy = $pr
      }
      Install-PackageProvider -Name NuGet -MinimumVersion $minVer -Scope CurrentUser -Force
    } -ArgumentList $min.ToString(), $pj.Uri, $pj.User, $pj.Pass
    $null = Wait-Job -Job $job -Timeout 120
    if ($job.State -eq 'Completed') {
      try {
        Receive-Job -Job $job -ErrorAction Stop | Out-Null
      } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
      }
      $verify = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
        Where-Object { $_.Version -ge $min } | Select-Object -First 1
      if ($verify) { return }
    } else {
      Write-Host "[setup] Online NuGet timed out (120s). Fallback: local DLL or retry later." -ForegroundColor DarkYellow
      Stop-Job -Job $job -ErrorAction SilentlyContinue
      Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
  } catch {
    Write-Host ("[setup] Online NuGet failed: " + $_.Exception.Message) -ForegroundColor DarkYellow
  }

  $destDir = Join-Path $env:LOCALAPPDATA 'PackageManagement\ProviderAssemblies'
  $destDll = Join-Path $destDir 'Microsoft.PackageManagement.NuGetProvider.dll'
  if (!(Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  }

  $candidates = @(
    (Join-Path $PSScriptRoot 'Microsoft.PackageManagement.NuGetProvider-2.8.5.208.dll')
    (Join-Path $PSScriptRoot 'Microsoft.PackageManagement.NuGetProvider.dll')
  ) + (Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'Microsoft.PackageManagement.NuGetProvider*.dll' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)

  $src = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  if (-not $src) {
    throw @"
NuGet provider not installed. Fix one of:
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force
Or place Microsoft.PackageManagement.NuGetProvider-2.8.5.208.dll next to this script: $PSScriptRoot
"@
  }

  Write-Host ("[setup] " + (U 1050,1086,1087,1080,1088,1091,1102,32,78,117,71,101,116,32,112,114,111,118,105,100,101,114,32,1080,1079,58) + " $src") -ForegroundColor Yellow
  Copy-Item -LiteralPath $src -Destination $destDll -Force
  Unblock-File -LiteralPath $destDll -ErrorAction SilentlyContinue

  try {
    Import-Module PackageManagement -Force -ErrorAction Stop | Out-Null
    Import-PackageProvider -Name NuGet -MinimumVersion $min -Force -ErrorAction Stop | Out-Null
  } catch {
    Write-Host ("[setup] Import-PackageProvider: " + $_.Exception.Message) -ForegroundColor DarkYellow
  }

  $after = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue |
    Where-Object { $_.Version -ge $min } |
    Select-Object -First 1
  if (-not $after) {
    throw @"
NuGet DLL copied to $destDll but this session still does not register it.
Open a NEW PowerShell window and run this script again (provider cache is per process),
or run once:
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force
"@
  }
}

function Get-PowerShellUserModulePath {
  $docs = [Environment]::GetFolderPath('MyDocuments')
  $candidates = @(
    (Join-Path $docs 'PowerShell\Modules')
    (Join-Path $docs 'WindowsPowerShell\Modules')
  )
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  $fallback = Join-Path $docs 'WindowsPowerShell\Modules'
  New-Item -ItemType Directory -Path $fallback -Force | Out-Null
  return $fallback
}

function Install-PoshSshFromGalleryNupkg {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  Write-Host "[setup] Download Posh-SSH .nupkg from PowerShell Gallery (curl)..." -ForegroundColor Yellow
  $api = 'https://www.powershellgallery.com/api/v2/package/Posh-SSH'
  $tmpNupkg = Join-Path $env:TEMP ('posh-ssh-' + [guid]::NewGuid().ToString() + '.nupkg')
  $tmpDir = Join-Path $env:TEMP ('posh-ssh-ex-' + [guid]::NewGuid().ToString())
  try {
    # PS 5.1: curl — часто алиас на Invoke-WebRequest; берём настоящий exe
    $curlExe = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path -LiteralPath $curlExe) {
      $curlArgs = @('-sSL', '--max-time', '600', '-L', '-o', $tmpNupkg)
      if ($script:GalleryProxyUri) {
        $proxyPrefix = @('-x', $script:GalleryProxyUri)
        if ($script:GalleryProxyCredential) {
          $nc = $script:GalleryProxyCredential.GetNetworkCredential()
          $proxyPrefix += '--proxy-user'
          $proxyPrefix += ($nc.UserName + ':' + $nc.Password)
        }
        $curlArgs = $proxyPrefix + $curlArgs
      }
      $curlArgs += $api
      & $curlExe @curlArgs
      if ($LASTEXITCODE -ne 0) { throw "curl.exe exited with $LASTEXITCODE" }
    } else {
      $wc = New-Object System.Net.WebClient
      $wc.Headers.Add('User-Agent', 'ssh-passwordless-setup')
      $wc.Proxy = [System.Net.WebRequest]::DefaultWebProxy
      $wc.DownloadFile($api, $tmpNupkg)
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tmpNupkg, $tmpDir)
    $psd1 = Get-ChildItem -LiteralPath $tmpDir -Recurse -Filter 'Posh-SSH.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $psd1) { throw "Posh-SSH.psd1 not found inside .nupkg" }
    $modVersion = (Import-PowerShellDataFile -LiteralPath $psd1.FullName).ModuleVersion
    if (-not $modVersion) { $modVersion = '0.0.0' }
    $moduleRoot = Split-Path -Parent $psd1.FullName
    $destRoot = Join-Path (Get-PowerShellUserModulePath) ('Posh-SSH\' + $modVersion)
    if (Test-Path -LiteralPath $destRoot) { Remove-Item -LiteralPath $destRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $destRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $moduleRoot '*') -Destination $destRoot -Recurse -Force
    Write-Host "[setup] Posh-SSH installed to $destRoot" -ForegroundColor Green
  } finally {
    Remove-Item -LiteralPath $tmpNupkg -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Ensure-PoshSsh {
  if (Get-Module -ListAvailable -Name Posh-SSH) { return }
  Write-Host ("[setup] " + (U 1059,1089,1090,1072,1085,1072,1074,1083,1080,1074,1072,1102,32,1084,1086,1076,1091,1083,1100,32,80,111,115,104,45,83,83,72,32,40,1090,1088,1077,1073,1091,1077,1090,1089,1103,32,1086,1076,1080,1085,32,1088,1072,1079,41,46,46,46)) -ForegroundColor Yellow
  # Сначала быстрый .nupkg (curl) — без NuGet provider и без зависшего Install-Module
  try {
    Install-PoshSshFromGalleryNupkg
  } catch {
    Write-Host ("[setup] .nupkg install failed: " + $_.Exception.Message) -ForegroundColor DarkYellow
  }
  if (Get-Module -ListAvailable -Name Posh-SSH) { return }

  Ensure-NuGetProvider
  try {
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction SilentlyContinue | Out-Null
  } catch { }
  $ConfirmPreference = 'None'
  Write-Host "[setup] Install-Module Posh-SSH (timeout 180s)..." -ForegroundColor Yellow
  $pj2 = Get-GalleryProxyJobArgs
  $modJob = Start-Job -ScriptBlock {
    param([string]$proxyUrl, [string]$proxyUser, [string]$proxyPass)
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if ($proxyUrl) {
      $env:HTTPS_PROXY = $proxyUrl
      $env:HTTP_PROXY = $proxyUrl
      $pr = New-Object System.Net.WebProxy($proxyUrl, $true)
      if ($proxyUser) {
        $pr.Credentials = New-Object System.Net.NetworkCredential($proxyUser, $proxyPass)
      } else {
        $pr.Credentials = [System.Net.CredentialCache]::DefaultCredentials
      }
      [System.Net.WebRequest]::DefaultWebProxy = $pr
    }
    Install-Module -Name Posh-SSH -Scope CurrentUser -Force
  } -ArgumentList $pj2.Uri, $pj2.User, $pj2.Pass
  $null = Wait-Job -Job $modJob -Timeout 180
  if ($modJob.State -eq 'Completed') {
    try {
      Receive-Job -Job $modJob -ErrorAction Stop | Out-Null
    } finally {
      Remove-Job -Job $modJob -Force -ErrorAction SilentlyContinue
    }
  } else {
    Write-Host "[setup] Install-Module timed out." -ForegroundColor DarkYellow
    Stop-Job -Job $modJob -ErrorAction SilentlyContinue
    Remove-Job -Job $modJob -Force -ErrorAction SilentlyContinue
  }
  if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    throw "Posh-SSH could not be installed. Try: Install-Module Posh-SSH -Scope CurrentUser -Force"
  }
}

function Ensure-SshKey([string]$KeyPath) {
  $pub = "$KeyPath.pub"
  # Скобки обязательны: иначе -and «липнет» к параметрам Test-Path и ломается парсер
  if ((Test-Path -LiteralPath $KeyPath -PathType Leaf) -and (Test-Path -LiteralPath $pub -PathType Leaf)) { return }

  $dir = Split-Path -Parent $KeyPath
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

  Write-Host ("[setup] " + (U 1043,1077,1085,1077,1088,1080,1088,1091,32,101,100,50,53,53,49,57,32,1082,1083,1102,1095,58) + " $KeyPath") -ForegroundColor Yellow

  # Без вложенных `"`"" — иначе PS5 может сломать разбор всего файла
  $cmd = 'ssh-keygen -t ed25519 -f "' + $KeyPath + '" -C "win->ssh-passwordless" -N ""'
  cmd /c $cmd | Out-Null
}

function Upsert-SshConfigAlias([string]$Alias, [string]$HostName, [string]$User, [string]$IdentityFile) {
  $sshDir = Join-Path $env:USERPROFILE ".ssh"
  $cfg = Join-Path $sshDir "config"
  if (!(Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }

  # Формируем блок без here-string (устойчивее к копипасте/кодировкам)
  $blockLines = @(
    "",
    "Host $Alias",
    "  HostName $HostName",
    "  User $User",
    "  IdentityFile $IdentityFile",
    "  IdentitiesOnly yes",
    "  StrictHostKeyChecking accept-new"
  )
  $block = ($blockLines -join "`r`n")

  if (!(Test-Path $cfg)) {
    Set-Content -Path $cfg -Value $block -Encoding ascii
    return
  }

  # Удаляем существующий Host-блок этого алиаса без сложных regex (стабильно для PS 5/7)
  $lines = Get-Content -Path $cfg
  $out = New-Object System.Collections.Generic.List[string]
  $skip = $false
  $hostLine = ("host " + $Alias).ToLowerInvariant()

  foreach ($line in $lines) {
    $trim = ($line.Trim())
    $trimLower = $trim.ToLowerInvariant()

    if ($trimLower -like "host *") {
      # Начало нового блока Host
      if ($trimLower -eq $hostLine) {
        $skip = $true
        continue
      }
      $skip = $false
    }

    if (-not $skip) {
      [void]$out.Add($line)
    }
  }

  # Склеиваем обратно + добавляем новый блок
  $newContent = ($out -join "`r`n").TrimEnd() + $block
  Set-Content -Path $cfg -Value $newContent -Encoding ascii
}

function Add-PublicKeyToRemoteAuthorizedKeys([string]$HostName, [string]$User, [securestring]$Password, [string]$PublicKeyPath) {
  Import-Module Posh-SSH -ErrorAction Stop

  $pub = (Get-Content -Path $PublicKeyPath -Raw).Trim()
  if (!$pub.StartsWith("ssh-ed25519 ")) { throw ((U 1055,1091,1073,1083,1080,1095,1085,1099,1081,32,1082,1083,1102,1095,32,1074,1099,1075,1083,1103,1076,1080,1090,32,1089,1090,1088,1072,1085,1085,1086,58) + " $PublicKeyPath") }

  $cred = New-Object System.Management.Automation.PSCredential($User, $Password)
  $session = New-SSHSession -ComputerName $HostName -Credential $cred -AcceptKey -ConnectionTimeout 15
  try {
    $pubEsc = $pub.Replace("'", "'\''")
    $remoteKeyLine = ('grep -qxF ''{0}'' ~/.ssh/authorized_keys || echo ''{0}'' >> ~/.ssh/authorized_keys' -f $pubEsc)
    $cmds = @(
      "set -e",
      "mkdir -p ~/.ssh",
      "chmod 700 ~/.ssh",
      "touch ~/.ssh/authorized_keys",
      "chmod 600 ~/.ssh/authorized_keys",
      $remoteKeyLine,
      "echo OK"
    ) -join " && "

    $r = Invoke-SSHCommand -SessionId $session.SessionId -Command $cmds
    if ($r.ExitStatus -ne 0) {
      throw ((U 1059,1076,1072,1083,1105,1085,1085,1072,1103,32,1082,1086,1084,1072,1085,1076,1072,32,1079,1072,1074,1077,1088,1096,1080,1083,1072,1089,1100,32,1089,32,1082,1086,1076,1086,1084,32,123,48,125,58,32,123,49,125) -f $r.ExitStatus, ($r.Error -join "`n"))
    }
  } finally {
    Remove-SSHSession -SessionId $session.SessionId | Out-Null
  }
}

Write-Host "=== SSH passwordless setup (Windows) ===" -ForegroundColor Cyan

Initialize-GalleryProxy -Uri $ProxyUri -Credential $ProxyCredential -Proxy6ConfigFile $Proxy6ConfigFile

if ($RemoteHost -and $Login -and $PasswordFile) {
  $HostName = $RemoteHost.Trim()
  $User = $Login.Trim()
  if ($SshAlias) { $Alias = $SshAlias.Trim() } else { $Alias = $HostName }
  if (-not (Test-Path -LiteralPath $PasswordFile)) { throw "PasswordFile not found: $PasswordFile" }
  $plain = (Get-Content -LiteralPath $PasswordFile -Raw).Trim()
  $Password = ConvertTo-SecureStringFromPlain $plain
  Write-Host "[setup] Non-interactive: host=$HostName user=$User alias=$Alias" -ForegroundColor DarkGray
} elseif ($RemoteHost -or $Login -or $PasswordFile -or $SshAlias) {
  throw "For non-interactive mode specify all: -RemoteHost, -Login, -PasswordFile (optional: -SshAlias)."
} else {
  $HostName = Read-Host (U 72,111,115,116,47,73,80,32,40,1085,1072,1087,1088,1080,1084,1077,1088,32,49,57,50,46,49,54,56,46,49,46,53,48,41)
  $User = Read-Host (U 76,111,103,105,110,32,40,1085,1072,1087,1088,1080,1084,1077,1088,32,115,104,101,118,98,111,41)
  $Alias = Read-Host (U 83,83,72,32,97,108,105,97,115,32,1074,32,99,111,110,102,105,103,32,40,1085,1072,1087,1088,1080,1084,1077,1088,32,115,104,101,118,98,111,45,112,105,41)
  if ([string]::IsNullOrWhiteSpace($Alias)) { $Alias = $HostName }
  $Password = Read-Host -AsSecureString (U 80,97,115,115,119,111,114,100,32,40,1074,1074,1086,1076,32,1089,1082,1088,1099,1090,59,32,1085,1091,1078,1077,1085,32,1090,1086,1083,1100,1082,1086,32,49,32,1088,1072,1079,32,1076,1083,1103,32,1091,1089,1090,1072,1085,1086,1074,1082,1080,32,1082,1083,1102,1095,1072,41)
}

Ensure-PoshSsh

$keyName = ($Alias -replace "[^a-zA-Z0-9._-]", "_")
$KeyPath = Join-Path $env:USERPROFILE ".ssh\$keyName`_ed25519"
Ensure-SshKey -KeyPath $KeyPath

Write-Host ("[setup] " + (U 1044,1086,1073,1072,1074,1083,1102,32,112,117,98,108,105,99,32,107,101,121,32,1085,1072,32,1089,1077,1088,1074,1077,1088,32,40) + $HostName + (U 41,46,46,46)) -ForegroundColor Yellow
Add-PublicKeyToRemoteAuthorizedKeys -HostName $HostName -User $User -Password $Password -PublicKeyPath "$KeyPath.pub"

Write-Host ("[setup] " + (U 1054,1073,1085,1086,1074,1083,1102,32,126,47,46,115,115,104,47,99,111,110,102,105,103,46,46,46)) -ForegroundColor Yellow
Upsert-SshConfigAlias -Alias $Alias -HostName $HostName -User $User -IdentityFile "~/.ssh/$($keyName)_ed25519"

Write-Host ("[done] " + (U 1043,1086,1090,1086,1074,1086,46,32,1055,1088,1086,1074,1077,1088,1082,1072,58)) -ForegroundColor Green
Write-Host "  ssh -o BatchMode=yes $Alias echo OK"

