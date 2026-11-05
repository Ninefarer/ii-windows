param([Parameter(Mandatory)][string]$InstallPath, [Parameter(Mandatory)][string]$ShellPath, [Parameter(Mandatory)][string]$Output)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SettingsMouse {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
    public static void Click(int x,int y) {
        if(!SetCursorPos(x,y)) throw new Exception("Cannot move test cursor");
        mouse_event(2,0,0,0,UIntPtr.Zero); mouse_event(4,0,0,0,UIntPtr.Zero);
    }
}
'@
New-Item -ItemType Directory -Force $Output | Out-Null
$config = Join-Path $env:LOCALAPPDATA 'illogical-impulse/config.json'
$original = if (Test-Path $config) { [IO.File]::ReadAllBytes($config) } else { $null }
$qml = Join-Path $ShellPath 'settings-layout-test.qml'
$oldScale = $env:QT_SCALE_FACTOR
$oldState = $env:IIW_UI_TEST_STATE
$oldImages = $env:IIW_UI_TEST_IMAGES
$p = $null
try {
    New-Item -ItemType Directory -Force (Split-Path $config) | Out-Null
    if (-not (Test-Path $config)) { [IO.File]::WriteAllText($config, '{}', (New-Object Text.UTF8Encoding($false))) }
    Copy-Item (Join-Path $PSScriptRoot 'settings-layout.qml') $qml -Force
    foreach ($scale in '1', '1.5') {
        $folder = Join-Path $Output ('scale-' + $scale)
        New-Item -ItemType Directory -Force $folder | Out-Null
        $stateFile = Join-Path $folder 'state.json'
        $env:QT_SCALE_FACTOR = $scale
        $env:IIW_UI_TEST_STATE = $stateFile
        $env:IIW_UI_TEST_IMAGES = $folder
        $p = Start-Process (Join-Path $InstallPath 'qsw.exe') -ArgumentList @('-n','-p',('"' + $qml + '"')) -WorkingDirectory $InstallPath -PassThru
        $clicked = @{}; $passed = @{}
        $deadline = (Get-Date).AddSeconds(65)
        while ((Get-Date) -lt $deadline -and -not $p.HasExited) {
            if (Test-Path $stateFile) {
                try { $state = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $state = $null }
                if ($state) {
                    if ($state.phase -eq 'error') { throw ($state | ConvertTo-Json -Compress) }
                    $key = "$($state.width)-$($state.phase)"
                    if ($state.phase -in 'open-owner','choose-external','enable-glass' -and -not $clicked.ContainsKey($key)) {
                        $x = [int][Math]::Round($state.target.x * $state.dpr)
                        $y = [int][Math]::Round($state.target.y * $state.dpr)
                        if ($x -lt 0 -or $y -lt 0 -or $x -ge [SettingsMouse]::GetSystemMetrics(0) -or $y -ge [SettingsMouse]::GetSystemMetrics(1)) { throw 'Click target is outside the screen' }
                        [SettingsMouse]::Click($x,$y)
                        $clicked[$key] = $true
                        Start-Sleep -Milliseconds 350
                    }
                    if ($state.phase -eq 'passed') {
                        if ($state.owner -ne 'external' -or -not $state.nativeGlass -or -not $state.glass -or -not $state.behindIcons) { throw 'Real clicks did not apply native-glass settings' }
                        if (-not $passed.ContainsKey([string]$state.width)) { Write-Host "PASS Settings real clicks: width=$($state.width) scale=$scale dropdown=external nativeGlass=True" }
                        $passed[[string]$state.width] = $true
                    }
                }
            }
            Start-Sleep -Milliseconds 100
            $p.Refresh()
        }
        if (-not $p.HasExited) { throw 'Settings UI test timed out' }
        foreach ($width in '420','600','820') { if (-not $passed.ContainsKey($width)) { throw "Missing Settings UI pass: width=$width scale=$scale" } }
        if ($p.ExitCode -ne 0) { throw 'Settings UI harness failed' }
    }
} finally {
    if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force }
    $env:QT_SCALE_FACTOR = $oldScale; $env:IIW_UI_TEST_STATE = $oldState; $env:IIW_UI_TEST_IMAGES = $oldImages
    $logs = Join-Path $env:LOCALAPPDATA 'quickshell/run/by-id'
    Get-ChildItem $logs -Recurse -Filter log.log -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $Output ($_.Directory.Name + '.log')) -Force
        Get-Content $_.FullName | Select-String 'UI-LAYOUT-FAIL|ERROR|TypeError|ReferenceError|Cannot assign|Failed to load' | ForEach-Object { Write-Host $_.Line }
    }
    if ($null -ne $original) { [IO.File]::WriteAllBytes($config, $original) } else { Remove-Item $config -ErrorAction SilentlyContinue }
    Remove-Item $qml -ErrorAction SilentlyContinue
}
