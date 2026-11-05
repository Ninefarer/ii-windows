param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$Output)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class InstallerMouse {
 public struct Rect { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr w,out Rect r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
 delegate bool Callback(IntPtr w,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(Callback callback,IntPtr p);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr w);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr w,out uint pid);
 public static IntPtr Find(uint process) {
  IntPtr found=IntPtr.Zero;
  EnumWindows((w,p)=>{ uint pid;GetWindowThreadProcessId(w,out pid);Rect r;
   if(pid==process&&IsWindowVisible(w)&&GetWindowRect(w,out r)&&r.Right-r.Left>=900&&r.Bottom-r.Top>=600) found=w;
   return true;
  },IntPtr.Zero);
  return found;
 }
 public static void Click(IntPtr w,double x,double y) {
  Rect r; if(!GetWindowRect(w,out r)||r.Right-r.Left<900) throw new Exception("Unexpected Setup bounds");
  SetForegroundWindow(w); SetCursorPos(r.Left+(int)((r.Right-r.Left)*x),r.Top+(int)((r.Bottom-r.Top)*y));
  mouse_event(2,0,0,0,UIntPtr.Zero);mouse_event(4,0,0,0,UIntPtr.Zero);
 }
}
'@
New-Item -ItemType Directory -Force $Output | Out-Null
$wrapper = Start-Process $Exe -PassThru
function Capture([string]$Name) {
 $screen = [Windows.Forms.SystemInformation]::VirtualScreen
 $bitmap = New-Object Drawing.Bitmap($screen.Width,$screen.Height)
 $graphics = [Drawing.Graphics]::FromImage($bitmap)
 $graphics.CopyFromScreen($screen.Left,$screen.Top,0,0,$bitmap.Size)
 $bitmap.Save((Join-Path $Output ($Name + '.png')))
 $graphics.Dispose();$bitmap.Dispose()
}
try {
 $until = (Get-Date).AddSeconds(45);$setup = $null
 while ((Get-Date) -lt $until -and -not $setup) {
  $setup = Get-Process ii-windows-setup -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
  Start-Sleep -Milliseconds 300
 }
 if (-not $setup) { throw 'Finished EXE did not open Setup' }
 $handle = [IntPtr]::Zero
 while ((Get-Date) -lt $until -and $handle -eq [IntPtr]::Zero) {
  $handle = [InstallerMouse]::Find([uint32]$setup.Id)
  Start-Sleep -Milliseconds 300
 }
 if ($handle -eq [IntPtr]::Zero) { throw 'Visible Setup surface not found' }
 Start-Sleep -Seconds 3
 Capture '1-welcome'
 [InstallerMouse]::Click($handle,0.89,0.92)
 Start-Sleep -Seconds 3
 (New-Object -ComObject WScript.Shell).SendKeys('{END}')
 Start-Sleep -Seconds 1
 Capture '2-readme'
 [InstallerMouse]::Click($handle,0.275,0.92)
 [InstallerMouse]::Click($handle,0.89,0.92)
 Start-Sleep -Seconds 5
 Capture '3-install-options'
 Write-Host "Captured actual finished installer screens for offline source review: expected=$Version"
} finally {
 Capture 'final'
 & taskkill /PID $wrapper.Id /T /F 2>$null | Out-Null
}
