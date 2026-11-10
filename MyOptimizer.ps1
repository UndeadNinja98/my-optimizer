#Requires -RunAsAdministrator
$dir = "$env:APPDATA\MyOptimizer"; New-Item -ItemType Directory -Force $dir | Out-Null
$backup = "$dir\backup.json"

function Save-Backup {
    $b = @{
        PowerScheme = ((powercfg /getactivescheme) -replace '.*GUID: (\S+).*','$1')
        GameMode    = (Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name AutoGameModeEnabled -EA 0).AutoGameModeEnabled
        GameDVR     = (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name GameDVR_Enabled -EA 0).GameDVR_Enabled
        VisualFX    = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name VisualFXSetting -EA 0).VisualFXSetting
    }
    $b | ConvertTo-Json | Set-Content $backup
    try { Checkpoint-Computer -Description "MyOptimizer" -RestorePointType MODIFY_SETTINGS -EA Stop }
    catch { Write-Host "Restore point skipped (System Protection may be off)." -ForegroundColor Yellow }
}

function Apply-Tweaks {
    if (-not (Test-Path $backup)) { Save-Backup }
    powercfg /setactive SCHEME_MIN
    New-Item "HKCU:\Software\Microsoft\GameBar" -Force | Out-Null
    Set-ItemProperty "HKCU:\Software\Microsoft\GameBar" AutoGameModeEnabled 1 -Type DWord
    Set-ItemProperty "HKCU:\System\GameConfigStore" GameDVR_Enabled 0 -Type DWord
    New-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Force | Out-Null
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" VisualFXSetting 2 -Type DWord
    Write-Host "Tweaks applied. Sign out and back in for visual changes." -ForegroundColor Green
}

function Clean-Temp {
    $before = (Get-PSDrive C).Free
    Remove-Item "$env:TEMP\*","C:\Windows\Temp\*" -Recurse -Force -EA 0
    $freed = [math]::Round(((Get-PSDrive C).Free - $before)/1MB,1)
    Write-Host "Freed about $freed MB." -ForegroundColor Green
}

function Undo-Tweaks {
    if (-not (Test-Path $backup)) { Write-Host "No backup found."; return }
    $b = Get-Content $backup | ConvertFrom-Json
    powercfg /setactive $b.PowerScheme
    if ($null -ne $b.GameMode) { Set-ItemProperty "HKCU:\Software\Microsoft\GameBar" AutoGameModeEnabled $b.GameMode }
    if ($null -ne $b.GameDVR)  { Set-ItemProperty "HKCU:\System\GameConfigStore" GameDVR_Enabled $b.GameDVR }
    if ($null -ne $b.VisualFX) { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" VisualFXSetting $b.VisualFX }
    Remove-Item $backup
    Write-Host "Original settings restored." -ForegroundColor Green
}

do {
    Write-Host "`n=== MyOptimizer ===`n1) Apply gaming tweaks`n2) Clean temp files`n3) Undo all tweaks`n4) Open startup apps`n0) Exit"
    $c = Read-Host "Choose"
    switch ($c) {
        '1' { Apply-Tweaks } '2' { Clean-Temp } '3' { Undo-Tweaks }
        '4' { Start-Process "ms-settings:startupapps" }
    }
} while ($c -ne '0')
