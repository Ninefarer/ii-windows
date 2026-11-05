param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$Output)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms,System.Drawing
New-Item -ItemType Directory -Force $Output | Out-Null
$wrapper = Start-Process $Exe -PassThru
$window = $null
function Wait-For([scriptblock]$Check, [string]$Message) {
    $until = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $until) {
        try { $value = & $Check; if ($value) { return $value } } catch {}
        Start-Sleep -Milliseconds 300
    }
    throw $Message
}
function Nodes {
    @($window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))
}
function Continue-Button {
    Nodes | Where-Object { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $_.Current.Name -eq 'Continue' -and $_.Current.IsEnabled } | Select-Object -First 1
}
function Invoke-Button($Button) {
    $Button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}
try {
    $setup = Wait-For { Get-Process ii-windows-setup -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1 } 'Setup window did not open'
    $window = [System.Windows.Automation.AutomationElement]::FromHandle($setup.MainWindowHandle)
    Wait-For { Nodes | Where-Object { $_.Current.Name -like "*Offline package*$Version*" } | Select-Object -First 1 } 'Welcome screen does not recognize the bundled package' | Out-Null
    Invoke-Button (Wait-For { Continue-Button } 'Welcome Continue button unavailable')
    $shell = New-Object -ComObject WScript.Shell
    $shell.AppActivate($setup.Id) | Out-Null
    $shell.SendKeys('{END}')
    $checkbox = Wait-For { Nodes | Where-Object { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::CheckBox -and $_.Current.IsEnabled } | Select-Object -First 1 } 'Readme acknowledgement unavailable'
    $checkbox.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
    Invoke-Button (Wait-For { Continue-Button } 'Readme Continue button unavailable')
    Wait-For { Nodes | Where-Object { $_.Current.Name -like '*Offline package*payload.zip*' } | Select-Object -First 1 } 'Install options did not select the bundled offline package' | Out-Null
    $text = (Nodes | ForEach-Object { $_.Current.Name }) -join "`n"
    if ($text -notlike "*$Version*" -or $text -like '*No package available*') { throw 'Install options show an incorrect package' }
    [IO.File]::WriteAllText((Join-Path $Output 'source-selection.txt'), $text)
    Write-Host "PASS finished EXE interactive Install options: offline payload.zip version=$Version"
} finally {
    if ($window) { try { [IO.File]::WriteAllText((Join-Path $Output 'automation-tree.txt'), ((Nodes | ForEach-Object { $_.Current.Name }) -join "`n")) } catch {} }
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object Drawing.Bitmap($screen.Width, $screen.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bitmap.Size)
    $bitmap.Save((Join-Path $Output 'installer.png'))
    $graphics.Dispose(); $bitmap.Dispose()
    & taskkill /PID $wrapper.Id /T /F 2>$null | Out-Null
}
