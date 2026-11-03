param(
    [string]$GamePath = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Files that make up the mod (all live next to install.ps1)
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

    # User selected the game root (contains BadCheese.exe)
    if (Test-Path -LiteralPath (Join-Path $p "BadCheese.exe")) { return $p }

    # User selected the BadCheese folder (contains Content\Paks)
    if (Test-Path -LiteralPath (Join-Path $p "Content\Paks")) {
        return (Split-Path -Parent $p)
    }

    # User selected a folder above the game root (e.g. steamapps\common)
    if (Test-Path -LiteralPath (Join-Path $p "BadCheese\Content\Paks")) {
        $child = Join-Path $p "BadCheese.exe"
        if (Test-Path -LiteralPath $child) { return $p }
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

    # 1) Epic Games Launcher manifests
    $manifestDir = Join-Path $env:ProgramData "Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path -LiteralPath $manifestDir) {
        Get-ChildItem -LiteralPath $manifestDir -Filter "*.item" -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $json = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                $name = [string]$json.DisplayName
                $app  = [string]$json.AppName
                if ($name -match "Bad\s*Cheese" -or $app -match "BadCheese") {
                    if (-not [string]::IsNullOrWhiteSpace([string]$json.InstallLocation)) {
                        $found += @{ Path = [string]$json.InstallLocation; Store = "Epic Games" }
                    }
                }
            } catch { }
        }
    }

    # 2) Steam libraries (registry + libraryfolders.vdf)
    foreach ($lib in Get-SteamLibraryFolders) {
        $common = Join-Path $lib "steamapps\common"
        if (-not (Test-Path -LiteralPath $common)) { continue }
        foreach ($dir in @("Bad Cheese", "BadCheese", "Bad Cheese Demo")) {
            $cand = Join-Path $common $dir
            if (Test-GameRoot $cand) { $found += @{ Path = $cand; Store = "Steam" } }
        }
        # Any other folder name: look one level deep for BadCheese.exe
        Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-GameRoot $_.FullName) { $found += @{ Path = $_.FullName; Store = "Steam" } }
        }
    }

    # 3) Common install locations
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
    foreach ($c in $commonPaths) {
        if (Test-GameRoot $c) { $found += @{ Path = $c; Store = "common path" } }
    }

    # Pick the first valid candidate, preferring a unique one
    $seen = @{}
    foreach ($f in $found) {
        $full = $f.Path
        if (Test-Path -LiteralPath $full) { $full = (Resolve-Path -LiteralPath $full).Path }
        if ($seen.ContainsKey($full.ToLower())) { continue }
        $seen[$full.ToLower()] = $true
        if (Test-GameRoot $full) { return @{ Path = $full; Store = $f.Store } }
    }
    return $null
}

Write-Info "Bad Cheese - Thai Subtitles Mod installer"
Write-Info "-----------------------------------------"

$missing = @()
foreach ($f in $modFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $scriptDir $f) -PathType Leaf)) { $missing += $f }
}
if ($missing.Count -gt 0) {
    Write-Err "These mod files were not found next to install.ps1:"
    foreach ($f in $missing) { Write-Err "  $f" }
    Write-Err "Please extract the whole ZIP file before installing."
    exit 1
}

$running = Get-Process -Name "BadCheese*" -ErrorAction SilentlyContinue
if ($running) {
    Write-Warn "Bad Cheese is running. Please close the game first."
    Read-Host "Press Enter after closing the game" | Out-Null
    $running = Get-Process -Name "BadCheese*" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Err "The game is still running. Installation cancelled."
        exit 1
    }
}

$detected = $null
if (-not [string]::IsNullOrWhiteSpace($GamePath)) {
    $manualRoot = Get-GameRootFromInput $GamePath
    if ($null -ne $manualRoot) { $detected = @{ Path = $manualRoot; Store = "manual" } }
} else {
    $detected = Find-GameRoot
}

if ($null -eq $detected) {
    Write-Warn "Could not find Bad Cheese automatically (Steam or Epic Games)."
    $manual = Read-Host "Enter the game folder (the folder containing BadCheese.exe)"
    $manualRoot = Get-GameRootFromInput $manual
    if ($null -ne $manualRoot) { $detected = @{ Path = $manualRoot; Store = "manual" } }
}

if ($null -eq $detected) {
    Write-Err "Invalid game folder. The folder must contain BadCheese.exe."
    exit 1
}

$gameRoot = $detected.Path
$paksDir = Join-Path $gameRoot "BadCheese\Content\Paks"
if (-not (Test-Path -LiteralPath $paksDir -PathType Container)) {
    Write-Err "Paks folder not found: $paksDir"
    exit 1
}

Write-Info "Game folder: $gameRoot"
Write-Info "Detected:    $($detected.Store)"
Write-Info ""

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$installed = @()

foreach ($f in $modFiles) {
    $src = Join-Path $scriptDir $f
    $dst = Join-Path $paksDir $f

    if (Test-Path -LiteralPath $dst -PathType Leaf) {
        $same = ((Get-FileHash -LiteralPath $src  -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash)
        if (-not $same) {
            if (Test-OurPak $dst) {
                Write-Info "Updating older Thai mod $f"
            } else {
                $backup = "$dst.bak_$stamp"
                Copy-Item -LiteralPath $dst -Destination $backup -Force
                Write-Info "Backed up old $f"
            }
        }
    }

    try {
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $installed += $f
    } catch {
        Write-Err "Could not copy $f"
        Write-Err $_.Exception.Message
        Write-Err "If the game is in Program Files, run install.bat as Administrator."
        exit 1
    }
}

Write-Ok "Installed successfully."
foreach ($f in $installed) { Write-Info "  $($paksDir)\$f" }
Write-Info ""
Write-Info "Open the game, go to Settings > Language, and select Thai."
Write-Info "The main menu shows the translator credit at the top right."
Write-Info "If Thai does not appear, restart the game."
