param([Parameter(Mandatory)][string]$InstallPath, [Parameter(Mandatory)][string]$ShellPath, [string]$LogDirectory = (Join-Path $env:RUNNER_TEMP 'native-glass-logs'))
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class GlassWindows {
    delegate bool Callback(IntPtr w, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(Callback f, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr w, Callback f, IntPtr p);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr w, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr w, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr w, out uint p);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr w);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] public static extern IntPtr Style(IntPtr w, int index);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr w);
    public static IntPtr Find(uint process) {
        IntPtr found=IntPtr.Zero;
        Callback check=(w,p)=>{
            uint pid; GetWindowThreadProcessId(w,out pid);
            if(pid!=process) return true;
            var name=new StringBuilder(128); GetClassName(w,name,128);
            if(IsWindowVisible(w) && name.ToString().StartsWith("Qt",StringComparison.Ordinal)) found=w;
            return true;
        };
        EnumWindows((w,p)=>{check(w,p); EnumChildWindows(w,check,p); return true;},IntPtr.Zero);
        return found;
    }
    public static int Backdrops(uint process) {
        int count=0;
        EnumWindows((w,p)=>{
            uint pid; GetWindowThreadProcessId(w,out pid);
            var name=new StringBuilder(128); GetClassName(w,name,128);
            if(pid==process && IsWindowVisible(w) && name.ToString()=="QuickshellBlurBackdrop") count++;
            return true;
        },IntPtr.Zero);
        return count;
    }
}
'@
$qml = Join-Path $ShellPath 'native-glass-lifecycle.qml'
$phase = Join-Path $env:RUNNER_TEMP ('native-glass-' + [guid]::NewGuid().ToString('N') + '.json')
$previous = $env:IIW_GLASS_TEST_PHASE
$process = $null
$started = Get-Date
try {
    Copy-Item (Join-Path $PSScriptRoot 'native-glass.qml') $qml -Force
    $env:IIW_GLASS_TEST_PHASE = $phase
    $process = Start-Process (Join-Path $InstallPath 'qsw.exe') -ArgumentList @('-n', '-p', ('"' + $qml + '"')) -WorkingDirectory $InstallPath -PassThru
    $observed = @{}
    $deadline = (Get-Date).AddSeconds(35)
    while ((Get-Date) -lt $deadline -and -not $process.HasExited) {
        if (Test-Path $phase) {
            try { $state = Get-Content $phase -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $state = $null }
            $window = [GlassWindows]::Find([uint32]$process.Id)
            if ($window -ne [IntPtr]::Zero -and $state -and $state.phase -in @('embedded', 'native', 'embedded-again', 'native-again')) {
                $embedded = ([GlassWindows]::Style($window, -16).ToInt64() -band 0x40000000) -ne 0
                $native = $state.phase -like 'native*'
                $backdrops = [GlassWindows]::Backdrops([uint32]$process.Id)
                if ($embedded -eq (-not $native) -and ($native -or $backdrops -eq 0)) {
                    $style = [GlassWindows]::Style($window, -20).ToInt64()
                    if ($native -and (($style -band 8) -ne 0 -or ($style -band 128) -eq 0 -or ($style -band 0x08000000) -eq 0)) {
                        throw 'Native widget window must be non-topmost, a tool window and nonactivating'
                    }
                    if (-not $native -or -not $state.available -or $backdrops -gt 0) {
                        if (-not $observed.ContainsKey($state.phase)) {
                            Write-Host "PASS native glass phase $($state.phase): embedded=$embedded backdrops=$backdrops compositorAvailable=$($state.available)"
                        }
                        $observed[$state.phase] = $true
                    }
                }
            }
        }
        Start-Sleep -Milliseconds 100
        $process.Refresh()
    }
    if (-not $process.HasExited) { throw 'Native glass lifecycle timed out' }
    foreach ($name in 'embedded', 'native', 'embedded-again', 'native-again') {
        if (-not $observed.ContainsKey($name)) { throw "Missing native glass lifecycle phase: $name" }
    }
    if ($process.ExitCode -ne 0) { throw 'Native glass harness exited with an error' }
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    $env:IIW_GLASS_TEST_PHASE = $previous
    try {
        New-Item -ItemType Directory -Force $LogDirectory | Out-Null
        if (Test-Path $phase) { Copy-Item $phase (Join-Path $LogDirectory 'last-phase.json') -Force }
        $runRoot = Join-Path $env:LOCALAPPDATA 'quickshell\run\by-id'
        Get-ChildItem $runRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -ge $started.AddSeconds(-2) } | ForEach-Object {
            $log = Join-Path $_.FullName 'log.log'
            if (Test-Path $log) {
                Copy-Item $log (Join-Path $LogDirectory ($_.Name + '.log')) -Force
                Get-Content $log | Select-String -Pattern 'ERROR|TypeError|ReferenceError|Cannot assign|not a type|Failed to load' | ForEach-Object { Write-Host $_.Line }
            }
        }
    } catch { Write-Warning "Could not collect native glass logs: $_" }
    Remove-Item $qml, $phase -ErrorAction SilentlyContinue
}
