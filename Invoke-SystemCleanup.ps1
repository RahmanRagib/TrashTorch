#Requires -Version 5.1
<#
.SYNOPSIS
    Cleans junk/temp files, empties the Recycle Bin, runs DISM cleanup and manages
    restore points. Creates a System Restore point before making changes.

.PARAMETER DryRun
    Show what would be cleaned without deleting or changing anything.

.PARAMETER Yes
    Skip the interactive confirmation prompt.

.EXAMPLE
    .\Invoke-SystemCleanup.ps1
.EXAMPLE
    .\Invoke-SystemCleanup.ps1 -DryRun
.EXAMPLE
    .\Invoke-SystemCleanup.ps1 -Yes
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host $Message -ForegroundColor $Color
    Add-Content -LiteralPath $LogFile -Value ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message)
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host 'Requesting administrator privileges...' -ForegroundColor Yellow
    $exe = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($DryRun) { $argList += '-DryRun' }
    if ($Yes)    { $argList += '-Yes' }
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList $argList
    exit
}

$LogDir = Join-Path $env:SystemDrive 'clean-logs'
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -File | Remove-Item -Force
$LogFile = Join-Path $LogDir ('cleanup_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date))

function Get-FreeSpaceGB {
    [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace / 1GB, 2)
}

function Clear-FolderContents {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($DryRun) { Write-Log "  [dry-run] Would clean $Label"; return }
    Write-Log "  Cleaning $Label"
    Get-ChildItem -LiteralPath $Path -Force | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}

function Clear-FolderPattern {
    param([string]$Path, [string[]]$Pattern, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($DryRun) { Write-Log "  [dry-run] Would clean $Label"; return }
    Write-Log "  Cleaning $Label"
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File -Include $Pattern |
        Remove-Item -Force
}

Write-Log '==================================================' Cyan
Write-Log ' Windows System Cleanup' Cyan
Write-Log (" Log: {0}" -f $LogFile) Cyan
if ($DryRun) { Write-Log ' Mode: DRY RUN - nothing will be deleted' Yellow }
Write-Log '==================================================' Cyan

if (-not $Yes -and -not $DryRun) {
    Write-Host ''
    Write-Host 'This will delete temp/junk files, empty the Recycle Bin,' -ForegroundColor Yellow
    Write-Host 'remove old restore points and run DISM Cleanup(ResetBase).' -ForegroundColor Yellow
    Write-Host 'After DISM Cleanup, installed Windows updates can no longer be uninstalled.' -ForegroundColor Yellow
    $answer = Read-Host 'Continue? (Y/N)'
    if ($answer -cnotmatch '^(Y|YES)$') {
        Write-Log 'Aborted by user.' Red
        return
    }
}

$startFree = Get-FreeSpaceGB
Write-Log ("Starting free space: {0} GB" -f $startFree) Gray

Write-Log "`n[1/6] Creating a System Restore point..." Cyan
if ($DryRun) {
    Write-Log '  [dry-run] Would create a restore point' Gray
}
else {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\"
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
            -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
        Checkpoint-Computer -Description 'Pre-Cleanup Restore Point' -RestorePointType 'MODIFY_SETTINGS'
        Write-Log '  Restore point created.' Green
    }
    catch {
        Write-Log ("  Could not create restore point: {0}" -f $_.Exception.Message) Yellow
    }
}

Write-Log "`n[2/6] Cleaning temp and cache files..." Cyan
$userProfiles = Get-ChildItem -LiteralPath (Join-Path $env:SystemDrive 'Users') -Directory |
    Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }

foreach ($profile in $userProfiles) {
    Clear-FolderContents -Path (Join-Path $profile.FullName 'AppData\Local\Temp') -Label "user temp ($($profile.Name))"
    Clear-FolderContents -Path (Join-Path $profile.FullName 'AppData\Local\Microsoft\Windows\INetCache') -Label "INetCache ($($profile.Name))"
    Clear-FolderPattern  -Path (Join-Path $profile.FullName 'AppData\Local\Microsoft\Windows\Explorer') -Pattern @('thumbcache_*.db', 'iconcache_*.db') -Label "thumbnail/icon cache ($($profile.Name))"
    Clear-FolderContents -Path (Join-Path $profile.FullName 'AppData\Local\Microsoft\Windows\WER') -Label "WER ($($profile.Name))"
    Clear-FolderContents -Path (Join-Path $profile.FullName 'AppData\Local\CrashDumps') -Label "crash dumps ($($profile.Name))"

    foreach ($browser in @(
        'AppData\Local\Microsoft\Edge\User Data\Default\Cache',
        'AppData\Local\Google\Chrome\User Data\Default\Cache',
        'AppData\Local\Google\Chrome\User Data\Default\Code Cache')) {
        Clear-FolderContents -Path (Join-Path $profile.FullName $browser) -Label "$browser ($($profile.Name))"
    }
}

Clear-FolderContents -Path "$env:SystemRoot\Temp" -Label 'Windows temp'
Clear-FolderContents -Path "$env:SystemRoot\Prefetch" -Label 'Prefetch'
Clear-FolderContents -Path "$env:SystemRoot\SoftwareDistribution\Download" -Label 'Windows Update cache'
Clear-FolderContents -Path "$env:SystemRoot\Logs\CBS" -Label 'CBS logs'
Clear-FolderContents -Path "$env:SystemRoot\Minidump" -Label 'minidumps'
Clear-FolderContents -Path "$env:SystemRoot\Downloaded Program Files" -Label 'Downloaded Program Files'
Clear-FolderContents -Path (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') -Label 'WER archive'
Clear-FolderContents -Path (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') -Label 'WER queue'
Clear-FolderPattern  -Path "$env:SystemRoot\Logs" -Pattern @('*.etl', '*.log') -Label 'old ETL/log files'

if (-not $DryRun) {
    Remove-Item -LiteralPath "$env:SystemRoot\MEMORY.DMP" -Force
    Get-ChildItem -LiteralPath "$env:SystemRoot\LiveKernelReports" -Recurse -Force -File |
        Remove-Item -Force
}

Write-Log "`n[3/6] Emptying the Recycle Bin..." Cyan
if ($DryRun) {
    Write-Log '  [dry-run] Would empty the Recycle Bin' Gray
}
else {
    try {
        Clear-RecycleBin -Force
        Write-Log '  Recycle Bin emptied.' Green
    }
    catch { }
}

Write-Log "`n[4/6] Running DISM component cleanup /ResetBase..." Cyan
if ($DryRun) {
    Write-Log '  [dry-run] Would run: Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase' Gray
}
else {
    Write-Log '  This may take a while, please wait...' DarkGray
    & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
    if ($LASTEXITCODE -eq 0) { Write-Log '  DISM cleanup completed.' Green }
    else { Write-Log "  DISM returned exit code $LASTEXITCODE" Yellow }
}

Write-Log "`n[5/6] Removing old restore points..." Cyan
if ($DryRun) {
    Write-Log '  [dry-run] Would remove old restore points, keep the newest' Gray
}
else {
    try {
        $shadows = Get-CimInstance -ClassName Win32_ShadowCopy | Sort-Object InstallDate -Descending
        if ($shadows.Count -gt 1) {
            $shadows | Select-Object -Skip 1 | ForEach-Object { Remove-CimInstance -InputObject $_ }
            Write-Log ("  Removed {0} old restore point(s), kept the newest." -f ($shadows.Count - 1)) Green
        }
        else {
            Write-Log '  No old restore points to remove.' Gray
        }
        & vssadmin.exe resize shadowstorage /for=$env:SystemDrive /on=$env:SystemDrive /maxsize=5% | Out-Null
    }
    catch {
        Write-Log ("  Could not remove old restore points: {0}" -f $_.Exception.Message) Yellow
    }
}

Write-Log "`n[6/6] Summary" Cyan
$endFree = Get-FreeSpaceGB
$freed = [math]::Round($endFree - $startFree, 2)
Write-Log ("  Free space before : {0} GB" -f $startFree)
Write-Log ("  Free space after  : {0} GB" -f $endFree)
Write-Log ("  Space reclaimed   : {0} GB" -f $freed) Green
Write-Log ("  Log saved to      : {0}" -f $LogFile) Gray
Write-Log 'Done.' Green
