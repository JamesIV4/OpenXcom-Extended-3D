# Run the X-COM 3D Unit Animation & Directional Attack Previewer
param(
    [ValidateSet("HUMAN", "SECTOID", "SNAKEMAN", "FLOATER", "sectoid", "snakeman", "floater")]
    [string]$Unit = "SECTOID",

    [string]$Version = "",

    [string]$Resolution = "1440x900",

    [switch]$Fullscreen
)

$ErrorActionPreference = 'Stop'

# Locate Godot
$godotPaths = @(
    'C:/GameDev/Godot_v4.7-stable_win64/Godot_v4.7-stable_win64_console.exe',
    'C:/GameDev/Godot_v4.7-stable_win64/Godot_v4.7-stable_win64.exe'
)

$godot = $null
foreach ($p in $godotPaths) {
    if (Test-Path $p) {
        $godot = $p
        break
    }
}

if (-not $godot) {
    $cmd = Get-Command "godot" -ErrorAction SilentlyContinue
    if ($cmd) {
        $godot = $cmd.Source
    }
}

if (-not $godot) {
    Write-Error "Could not find Godot executable. Please ensure Godot 4.7 is installed at C:/GameDev/Godot_v4.7-stable_win64/."
    exit 1
}

$labDir = (Resolve-Path "$PSScriptRoot/xcom-3d-godot/unit-lab").Path

$argsList = @(
    "--path", $labDir,
    "res://scenes/unit_previewer.tscn",
    "--resolution", $Resolution
)

if ($Fullscreen) {
    $argsList += "--fullscreen"
}

$userArgs = @()
if ($Unit) {
    $userArgs += "--unit", $Unit.ToUpper()
}
if ($Version) {
    $userArgs += "--version", $Version
}

if ($userArgs.Count -gt 0) {
    $argsList += "--"
    $argsList += $userArgs
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   X-COM 3D // Unit Animation & Attack Hit Previewer      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Engine:      $godot" -ForegroundColor DarkGray
Write-Host "  Project:     $labDir" -ForegroundColor DarkGray
Write-Host "  Unit:        $($Unit.ToUpper())" -ForegroundColor Yellow
if ($Version) {
    Write-Host "  Version:     $Version" -ForegroundColor Yellow
}
Write-Host "  Resolution:  $Resolution" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Hotkeys inside utility:" -ForegroundColor White
Write-Host "  Space / H : Fire Non-Lethal Hit" -ForegroundColor Green
Write-Host "  K         : Fire Lethal Attack (Ragdoll + Twist)" -ForegroundColor Red
Write-Host "  A         : Unit Attack Animation & Fire Weapon" -ForegroundColor Yellow
Write-Host "  R         : Reset Unit to Clean State" -ForegroundColor Cyan
Write-Host "  C         : Cycle Camera Presets (Battlescape/Top/POV/Orbit)" -ForegroundColor Magenta
Write-Host "  1 .. 8    : Quick Compass Attack Angles (N..NW)" -ForegroundColor White
Write-Host "  Tab       : Toggle / Hide UI Overlay" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan

& $godot $argsList
