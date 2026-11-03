param(
    [string]$GamePath = ""
)

$ErrorActionPreference = "Stop"

$modFiles = @(
    "Thai_P.pak",
    "ThaiMenu_P.pak",
    "ThaiMenu_P.ucas",
    "ThaiMenu_P.utoc"
)

function Write-Info($text) { Write-Host $text -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host $text -ForegroundColor Green }
function Write-Warn($text) { Write-Host $text -ForegroundColor Yellow }
function Write-Err($text)  { Write-Host $text -ForegroundColor Red }

# Our pak contains BadCheese/Content/ThaiModCredits.txt, so the file name shows
# up in the (uncompressed) pak index. Used to tell our own older version apart
# from a pak that already existed before the mod was installed.
function Test-OurPak([string]$path) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        return $text.Contains("ThaiModCredits.txt")
    } catch {
        return $false
    }
}

function Get-GameRootFromInput([string]$inputPath) {
    if ([string]::IsNullOrWhiteSpace($inputPath)) { return $null }
    $p = $inputPath.Trim().Trim('"')
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        if ([System.IO.Path]::GetFileName($p) -ieq "BadCheese.exe") {
            return (Split-Path -Parent $p)
        }
        return $null
    }
    if (-not (Test-Path -LiteralPath $p -PathType Container)) { return $null }
    $p = (Resolve-Path -LiteralPath $p).Path

    if (Test-Path -LiteralPath (Join-Path $p "BadCheese.exe")) { return $p }

    if (Test-Path -LiteralPath (Join-Path $p "Content\Paks")) {
        return (Split-Path -Parent $p)
    }

    return $null
}

function Test-GameRoot([string]$root) {
    if ([string]::IsNullOrWhiteSpace($root)) { return $false }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $root "BadCheese.exe") -PathType Leaf)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $root "BadCheese\Content\Paks") -PathType Container)
}

function Get-SteamLibraryFolders {
    $libs = New-Object System.Collections.Generic.List[string]
    $steamPath = $null

    $keys = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )
    foreach ($k in $keys) {
        if ($steamPath) { break }
        foreach ($prop in @("SteamPath", "InstallPath")) {
            try {
                $v = (Get-ItemProperty -Path $k -Name $prop -ErrorAction Stop).$prop
                if (-not [string]::IsNullOrWhiteSpace($v)) { $steamPath = $v; break }
            } catch { }
        }
    }

    if (-not $steamPath) { return $libs }

    $steamPath = $steamPath -replace '/', '\'
    if (Test-Path -LiteralPath $steamPath) { $libs.Add($steamPath) }

    $vdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
    if (Test-Path -LiteralPath $vdf) {
        try {
            $text = Get-Content -LiteralPath $vdf -Raw
            foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $path = $m.Groups[1].Value -replace '\\\\', '\'
                if ((Test-Path -LiteralPath $path) -and (-not $libs.Contains($path))) {
                    $libs.Add($path)
                }
            }
        } catch { }
    }
    return $libs
}

function Find-GameRoot {
    $found = @()

    $manifestDir = Join-Path $env:ProgramData "Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path -LiteralPath $manifestDir) {
        Get-ChildItem -LiteralPath $manifestDir -Filter "*.item" -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $json = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                $name = [string]$json.DisplayName
                $app  = [string]$json.AppName
                if ($name -match "Bad\s*Cheese" -or $app -match "BadCheese") {
                    if (-not [string]::IsNullOrWhiteSpace([string]$json.InstallLocation)) {
                        $found += [string]$json.InstallLocation
                    }
                }
            } catch { }
        }
    }

    foreach ($lib in Get-SteamLibraryFolders) {
        $common = Join-Path $lib "steamapps\common"
        if (-not (Test-Path -LiteralPath $common)) { continue }
        foreach ($dir in @("Bad Cheese", "BadCheese", "Bad Cheese Demo")) {
            $found += (Join-Path $common $dir)
        }
        Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $found += $_.FullName
        }
    }

    $commonPaths = @(
        "C:\Program Files\Epic Games\BadCheese",
        "C:\Program Files\Epic Games\BadCheeseMA8aG",
        "C:\Program Files (x86)\Epic Games\BadCheese",
        "C:\Program Files (x86)\Epic Games\BadCheeseMA8aG",
        "D:\Epic Games\BadCheese",
        "D:\Epic Games\BadCheeseMA8aG",
        "E:\Epic Games\BadCheese",
        "E:\Epic Games\BadCheeseMA8aG",
        "C:\Program Files (x86)\Steam\steamapps\common\Bad Cheese",
        "C:\Program Files\Steam\steamapps\common\Bad Cheese",
        "D:\SteamLibrary\steamapps\common\Bad Cheese",
        "D:\Steam\steamapps\common\Bad Cheese",
        "E:\SteamLibrary\steamapps\common\Bad Cheese"
    )
    foreach ($c in $commonPaths) { $found += $c }

    $seen = @{}
    foreach ($f in $found) {
        if ([string]::IsNullOrWhiteSpace($f)) { continue }
        $full = $f
        if (Test-Path -LiteralPath $f) { $full = (Resolve-Path -LiteralPath $f).Path }
        if ($seen.ContainsKey($full.ToLower())) { continue }
        $seen[$full.ToLower()] = $true
        if (Test-GameRoot $full) { return $full }
    }
    return $null
}

Write-Info "Bad Cheese - Thai Subtitles Mod uninstaller"
Write-Info "-------------------------------------------"

$running = Get-Process -Name "BadCheese*" -ErrorAction SilentlyContinue
if ($running) {
    Write-Warn "Bad Cheese is running. Please close the game first."
    Read-Host "Press Enter after closing the game" | Out-Null
    $running = Get-Process -Name "BadCheese*" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Err "The game is still running. Uninstallation cancelled."
        exit 1
    }
}

$gameRoot = $null
if (-not [string]::IsNullOrWhiteSpace($GamePath)) {
    $gameRoot = Get-GameRootFromInput $GamePath
} else {
    $gameRoot = Find-GameRoot
}

if ($null -eq $gameRoot) {
    Write-Warn "Could not find Bad Cheese automatically."
    $manual = Read-Host "Enter the game folder (the folder containing BadCheese.exe)"
    $gameRoot = Get-GameRootFromInput $manual
}

if ($null -eq $gameRoot) {
    Write-Err "Invalid game folder. The folder must contain BadCheese.exe."
    exit 1
}

$paksDir = Join-Path $gameRoot "BadCheese\Content\Paks"
Write-Info "Game folder: $gameRoot"
Write-Info ""

$removed = 0
$restored = $false
foreach ($f in $modFiles) {
    $target = Join-Path $paksDir $f
    $backups = @(Get-ChildItem -LiteralPath $paksDir -Filter "$f.bak_*" -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending)
    $removedThis = $false
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        try {
            Remove-Item -LiteralPath $target -Force
            Write-Ok "Removed $f"
            $removed++
            $removedThis = $true
        } catch {
            Write-Err "Could not remove $f"
            Write-Err $_.Exception.Message
            Write-Err "If the game is in Program Files, run uninstall.bat as Administrator."
            exit 1
        }
    }

    # Only a pak that existed before the mod was installed is worth restoring.
    # Backups made from an older version of this mod are simply deleted, so the
    # game really goes back to English.
    if ($f -eq "Thai_P.pak") {
        $foreign = $backups | Where-Object { -not (Test-OurPak $_.FullName) } | Select-Object -First 1
        if ($removedThis -and $null -ne $foreign) {
            Copy-Item -LiteralPath $foreign.FullName -Destination $target -Force
            Write-Info "  Restored the pak that was in the folder before the mod"
            $restored = $true
        }
    }

    foreach ($b in $backups) {
        Remove-Item -LiteralPath $b.FullName -Force -ErrorAction SilentlyContinue
    }
}

if ($removed -eq 0) {
    Write-Info "The Thai mod is not installed in this game folder."
} else {
    Write-Ok "Uninstalled $removed file(s)."
    if ($restored) {
        Write-Info "Your previous Thai_P.pak was put back in place."
    } else {
        Write-Info "The game is back to English."
    }
}
