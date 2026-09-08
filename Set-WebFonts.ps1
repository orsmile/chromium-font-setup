[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$FontsOnly,
    [switch]$BrowsersOnly,
    [switch]$Restore,
    [ValidateSet('Chrome','Brave','Edge')]
    [string[]]$Browser = @('Chrome','Brave','Edge')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($FontsOnly -and $BrowsersOnly) {
    throw 'Use either -FontsOnly or -BrowsersOnly, not both.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ManifestPath = Join-Path $Root 'fonts.json'
$StateRoot = Join-Path $env:LOCALAPPDATA 'ChromiumFontSetup'
$CacheRoot = Join-Path $StateRoot 'Cache'
$BackupRoot = Join-Path $StateRoot 'Backups'
$StatePath = Join-Path $StateRoot 'state.json'
$UserFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$FontRegPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

$BrowserDefs = @{
    Chrome = @{ UserData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'; Process = 'chrome' }
    Brave  = @{ UserData = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'; Process = 'brave' }
    Edge   = @{ UserData = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'; Process = 'msedge' }
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Load-JsonFile([string]$Path, $Fallback) {
    if (Test-Path $Path) { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) }
    return $Fallback
}

function Save-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Ensure-Property($Object, [string]$Name, $Value) {
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
        return $Value
    }
    if ($null -eq $p.Value) { $p.Value = $Value }
    return $p.Value
}

function Invoke-Download([string]$Url, [string]$Destination) {
    Write-Host "Downloading $Url"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination
}

function Resolve-FontSource($Font) {
    if ($Font.sourceType -eq 'direct') {
        return [pscustomobject]@{ Url = $Font.url; Version = 'direct'; AssetName = [IO.Path]::GetFileName(([Uri]$Font.url).AbsolutePath) }
    }

    if ($Font.sourceType -eq 'github-release') {
        $api = "https://api.github.com/repos/$($Font.repo)/releases?per_page=20"
        $headers = @{ 'User-Agent' = 'chromium-font-setup' }
        $releases = Invoke-RestMethod -Uri $api -Headers $headers
        foreach ($release in $releases) {
            foreach ($asset in $release.assets) {
                if ($asset.name -match $Font.assetRegex) {
                    return [pscustomobject]@{ Url = $asset.browser_download_url; Version = $release.tag_name; AssetName = $asset.name }
                }
            }
        }
        throw "No matching release asset found for $($Font.displayName)."
    }

    throw "Unsupported sourceType '$($Font.sourceType)'."
}

function Get-FontRegistryName([string]$FileName) {
    $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext = [IO.Path]::GetExtension($FileName).ToLowerInvariant()
    $suffix = if ($ext -eq '.otf') { ' (OpenType)' } else { ' (TrueType)' }
    return "$base$suffix"
}

function Install-FontFile([string]$Path) {
    Ensure-Dir $UserFontDir
    if (-not (Test-Path $FontRegPath)) { New-Item -Path $FontRegPath -Force | Out-Null }

    $dest = Join-Path $UserFontDir ([IO.Path]::GetFileName($Path))
    Copy-Item -LiteralPath $Path -Destination $dest -Force
    $regName = Get-FontRegistryName $dest
    New-ItemProperty -Path $FontRegPath -Name $regName -Value $dest -PropertyType String -Force | Out-Null
}

function Broadcast-FontChange {
    $sig = @'
using System;
using System.Runtime.InteropServices;
public static class FontBroadcast {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
    if (-not ('FontBroadcast' -as [type])) { Add-Type $sig }
    $result = [UIntPtr]::Zero
    [void][FontBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$result)
}

function Update-Fonts($Manifest, $State) {
    if ($WhatIfPreference) {
        foreach ($font in $Manifest.fonts) {
            $source = Resolve-FontSource $font
            Write-Host "$($font.displayName): source $($source.Version) -> $($source.AssetName)"
            [void]$PSCmdlet.ShouldProcess(
                $font.displayName,
                "Check/download $($source.Url), compare SHA-256, and install only if changed"
            )
        }
        return
    }

    Ensure-Dir $CacheRoot
    Ensure-Dir $StateRoot
    if ($null -eq $State.fonts) { $State | Add-Member -NotePropertyName fonts -NotePropertyValue ([pscustomobject]@{}) -Force }

    foreach ($font in $Manifest.fonts) {
        $source = Resolve-FontSource $font
        $fontCache = Join-Path $CacheRoot $font.id
        Ensure-Dir $fontCache
        $archive = Join-Path $fontCache $source.AssetName
        Invoke-Download $source.Url $archive
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
        $old = $State.fonts.PSObject.Properties[$font.id]

        if ($old -and $old.Value.sha256 -eq $hash) {
            Write-Host "$($font.displayName): already current ($($source.Version))."
            continue
        }

        $extract = Join-Path $fontCache 'extracted'
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $extract
        Ensure-Dir $extract
        Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force

        $files = @()
        foreach ($pattern in $font.installPatterns) {
            $files += Get-ChildItem -Path $extract -Recurse -File -Filter $pattern
        }
        $files = $files | Sort-Object FullName -Unique
        if (-not $files) { throw "No font files found after extracting $($font.displayName)." }

        if ($PSCmdlet.ShouldProcess($font.displayName, "Install/update $($files.Count) font files")) {
            foreach ($file in $files) { Install-FontFile $file.FullName }
            $entry = [pscustomobject]@{ version = $source.Version; sha256 = $hash; updatedAt = (Get-Date).ToString('o') }
            if ($old) { $old.Value = $entry } else { $State.fonts | Add-Member -NotePropertyName $font.id -NotePropertyValue $entry }
            Write-Host "$($font.displayName): installed/updated ($($source.Version))."
        }
    }

    Save-JsonFile $StatePath $State
    Broadcast-FontChange
}

function Get-ChromiumProfiles([string]$UserData) {
    if (-not (Test-Path $UserData)) { return @() }
    $dirs = Get-ChildItem -LiteralPath $UserData -Directory | Where-Object {
        $_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$'
    }
    return @($dirs | Where-Object { Test-Path (Join-Path $_.FullName 'Preferences') })
}

function Backup-Preferences([string]$BrowserName, [IO.DirectoryInfo]$Profile, [string]$BackupDir) {
    $destDir = Join-Path $BackupDir "$BrowserName\$($Profile.Name)"
    Ensure-Dir $destDir
    Copy-Item -LiteralPath (Join-Path $Profile.FullName 'Preferences') -Destination (Join-Path $destDir 'Preferences') -Force
}

function Set-FontMap($FontsNode, [string]$Kind, [string]$Family, [string[]]$Scripts) {
    $kindNode = Ensure-Property $FontsNode $Kind ([pscustomobject]@{})
    foreach ($script in $Scripts) {
        $p = $kindNode.PSObject.Properties[$script]
        if ($p) { $p.Value = $Family } else { $kindNode | Add-Member -NotePropertyName $script -NotePropertyValue $Family }
    }
}

function Update-BrowserPreferences([string]$Path, $Settings) {
    $prefs = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    $webkit = Ensure-Property $prefs 'webkit' ([pscustomobject]@{})
    $webprefs = Ensure-Property $webkit 'webprefs' ([pscustomobject]@{})
    $fonts = Ensure-Property $webprefs 'fonts' ([pscustomobject]@{})

    Set-FontMap $fonts 'standard' $Settings.standard $Settings.scripts
    Set-FontMap $fonts 'sansserif' $Settings.sansSerif $Settings.scripts
    Set-FontMap $fonts 'serif' $Settings.serif $Settings.scripts
    Set-FontMap $fonts 'fixed' $Settings.fixed $Settings.scripts

    foreach ($kv in @{
        default_font_size = [int]$Settings.defaultFontSize
        default_fixed_font_size = [int]$Settings.defaultFixedFontSize
        minimum_font_size = [int]$Settings.minimumFontSize
    }.GetEnumerator()) {
        $p = $webprefs.PSObject.Properties[$kv.Key]
        if ($p) { $p.Value = $kv.Value } else { $webprefs | Add-Member -NotePropertyName $kv.Key -NotePropertyValue $kv.Value }
    }

    Save-JsonFile $Path $prefs
}

function Assert-BrowsersClosed([string[]]$Names) {
    $running = @()
    foreach ($name in $Names) {
        $proc = $BrowserDefs[$name].Process
        if (Get-Process -Name $proc -ErrorAction SilentlyContinue) { $running += $name }
    }
    if ($running) { throw "Close these browsers before continuing: $($running -join ', ')." }
}

function Configure-Browsers($Manifest, [string[]]$Names) {
    if (-not $WhatIfPreference) { Assert-BrowsersClosed $Names }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $BackupRoot $stamp
    $changed = 0

    foreach ($name in $Names) {
        $profiles = Get-ChromiumProfiles $BrowserDefs[$name].UserData
        foreach ($profile in $profiles) {
            $pref = Join-Path $profile.FullName 'Preferences'
            if ($PSCmdlet.ShouldProcess("$name/$($profile.Name)", 'Back up and update Chromium font preferences')) {
                Backup-Preferences $name $profile $backupDir
                Update-BrowserPreferences $pref $Manifest.browserSettings
                $changed++
                Write-Host "$name/$($profile.Name): configured."
            }
        }
    }

    if ($changed -gt 0) { Write-Host "Backup saved to: $backupDir" }
}

function Restore-LatestBackup([string[]]$Names) {
    if (-not $WhatIfPreference) { Assert-BrowsersClosed $Names }
    if (-not (Test-Path $BackupRoot)) { throw 'No backups found.' }
    $latest = Get-ChildItem -LiteralPath $BackupRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { throw 'No backups found.' }

    foreach ($name in $Names) {
        $browserBackup = Join-Path $latest.FullName $name
        if (-not (Test-Path $browserBackup)) { continue }
        foreach ($profileDir in Get-ChildItem -LiteralPath $browserBackup -Directory) {
            $target = Join-Path $BrowserDefs[$name].UserData "$($profileDir.Name)\Preferences"
            $source = Join-Path $profileDir.FullName 'Preferences'
            if ((Test-Path $source) -and (Test-Path (Split-Path $target))) {
                if ($PSCmdlet.ShouldProcess("$name/$($profileDir.Name)", "Restore Preferences from $($latest.Name)")) {
                    Copy-Item -LiteralPath $source -Destination $target -Force
                    Write-Host "$name/$($profileDir.Name): restored."
                }
            }
        }
    }
}

if ($env:OS -ne 'Windows_NT') { throw 'This script currently supports Windows only.' }
if (-not (Test-Path $ManifestPath)) { throw "Missing manifest: $ManifestPath" }

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json

if (-not $WhatIfPreference) {
    Ensure-Dir $StateRoot
    Ensure-Dir $BackupRoot
}

$state = Load-JsonFile $StatePath ([pscustomobject]@{ fonts = [pscustomobject]@{} })

if ($Restore) {
    Restore-LatestBackup $Browser
    exit 0
}

if (-not $BrowsersOnly) { Update-Fonts $manifest $state }
if (-not $FontsOnly) { Configure-Browsers $manifest $Browser }
