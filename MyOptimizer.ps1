# MyOptimizer (preview) - safer backup, undo and cleanup
# Runs as the signed-in user. Administrator is only needed for a restore point and C:\Windows\Temp cleanup.

$dir = Join-Path $env:APPDATA 'MyOptimizer'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$backup = Join-Path $dir 'backup.json'
$HighPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$Settings = @(
    @{ Name = 'Game Mode on';               Path = 'HKCU:\Software\Microsoft\GameBar';      Value = 'AutoGameModeEnabled'; Target = 1 },
    @{ Name = 'Background recording off';   Path = 'HKCU:\System\GameConfigStore';          Value = 'GameDVR_Enabled';     Target = 0 },
    @{ Name = 'Visual effects: performance'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Value = 'VisualFXSetting'; Target = 2 }
)

function Get-RegState($s) {
    $st = [ordered]@{ Name = $s.Name; Path = $s.Path; ValueName = $s.Value; Existed = $false; Kind = $null; Data = $null }
    if (Test-Path -LiteralPath $s.Path) {
        $key = Get-Item -LiteralPath $s.Path
        if ($key.GetValueNames() -contains $s.Value) {
            $st.Existed = $true
            $st.Kind = $key.GetValueKind($s.Value).ToString()
            $st.Data = $key.GetValue($s.Value, $null, 'DoNotExpandEnvironmentNames')
        }
    }
    [pscustomobject]$st
}

function Get-ActiveScheme {
    $out = powercfg /getactivescheme
    if ($LASTEXITCODE -ne 0) { throw "powercfg failed (exit code $LASTEXITCODE)" }
    $m = [regex]::Match(($out -join ' '), '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
    if (-not $m.Success) { throw 'Could not read the active power plan GUID' }
    $m.Value.ToLower()
}

function Set-Scheme($guid) {
    powercfg /setactive $guid | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive failed (exit code $LASTEXITCODE)" }
    if ((Get-ActiveScheme) -ne $guid.ToLower()) { throw 'Power plan did not change' }
}

function Write-Results($results) {
    foreach ($r in $results) {
        $color = switch ($r.Status) { 'OK' { 'Green' } 'Unchanged' { 'Gray' } 'Skipped' { 'Yellow' } default { 'Red' } }
        Write-Host ("[{0}] {1} {2}" -f $r.Status, $r.Name, $r.Detail) -ForegroundColor $color
    }
    $failed = @($results | Where-Object Status -eq 'Failed').Count
    if ($failed) { Write-Host "$failed action(s) failed. Nothing was hidden; see above." -ForegroundColor Red }
    else { Write-Host 'All actions finished without errors.' -ForegroundColor Green }
}

function Save-Backup {
    if (Test-Path -LiteralPath $backup) {
        Write-Host 'Existing backup kept (it holds your original settings).' -ForegroundColor Gray
        return $true
    }
    try {
        $b = [ordered]@{
            Version     = 2
            Created     = (Get-Date).ToString('o')
            User        = "$env:USERDOMAIN\$env:USERNAME"
            PowerScheme = Get-ActiveScheme
            Registry    = @($Settings | ForEach-Object { Get-RegState $_ })
        }
        $b | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $backup -Encoding UTF8
        $check = Get-Content -LiteralPath $backup -Raw | ConvertFrom-Json
        if (-not $check.PowerScheme) { throw 'Backup file could not be verified' }
    } catch {
        Write-Host "Backup failed: $($_.Exception.Message). No changes were made." -ForegroundColor Red
        Remove-Item -LiteralPath $backup -ErrorAction SilentlyContinue
        return $false
    }
    if ($IsAdmin) {
        try { Checkpoint-Computer -Description 'MyOptimizer' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Host 'Restore point created (extra safety net).' -ForegroundColor Gray }
        catch { Write-Host "Restore point not created: $($_.Exception.Message). Settings backup still saved." -ForegroundColor Yellow }
    } else {
        Write-Host 'Not running as administrator: no restore point. Settings backup still saved.' -ForegroundColor Yellow
    }
    return $true
}

function Apply-Tweaks {
    Write-Host "`nPlanned changes:" -ForegroundColor Cyan
    $cur = $null; try { $cur = Get-ActiveScheme } catch { }
    Write-Host "  Power plan: $cur -> High performance ($HighPerfGuid) [uses more power/heat on laptops]"
    foreach ($s in $Settings) {
        $st = Get-RegState $s
        $now = if ($st.Existed) { $st.Data } else { '(not set)' }
        Write-Host "  $($s.Name): $now -> $($s.Target)"
    }
    Write-Host '  Note: background recording off disables Xbox Game Bar clip capture.' -ForegroundColor Yellow
    if ((Read-Host 'Apply these changes? (Y/N)') -ne 'Y') { Write-Host 'Cancelled. Nothing changed.'; return }
    if (-not (Save-Backup)) { return }

    $results = @()
    $plans = (powercfg /list) -join ' '
    if ($LASTEXITCODE -ne 0 -or $plans -notmatch $HighPerfGuid) {
        $results += [pscustomobject]@{ Name = 'Power plan'; Status = 'Skipped'; Detail = '(High performance plan not available on this PC)' }
    } elseif ($cur -eq $HighPerfGuid) {
        $results += [pscustomobject]@{ Name = 'Power plan'; Status = 'Unchanged'; Detail = '(already High performance)' }
    } else {
        try { Set-Scheme $HighPerfGuid; $results += [pscustomobject]@{ Name = 'Power plan'; Status = 'OK'; Detail = '' } }
        catch { $results += [pscustomobject]@{ Name = 'Power plan'; Status = 'Failed'; Detail = "($($_.Exception.Message))" } }
    }

    foreach ($s in $Settings) {
        $st = Get-RegState $s
        if ($st.Existed -and "$($st.Data)" -eq "$($s.Target)") {
            $results += [pscustomobject]@{ Name = $s.Name; Status = 'Unchanged'; Detail = '(already set)' }; continue
        }
        try {
            if (-not (Test-Path -LiteralPath $s.Path)) { New-Item -Path $s.Path -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty -LiteralPath $s.Path -Name $s.Value -Value $s.Target -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            $after = Get-RegState $s
            if (-not $after.Existed -or "$($after.Data)" -ne "$($s.Target)") { throw 'value did not stick' }
            $results += [pscustomobject]@{ Name = $s.Name; Status = 'OK'; Detail = '' }
        } catch {
            $results += [pscustomobject]@{ Name = $s.Name; Status = 'Failed'; Detail = "($($_.Exception.Message))" }
        }
    }
    Write-Results $results
    Write-Host 'Sign out and back in for visual changes. Use option 3 to undo.' -ForegroundColor Cyan
}

function Undo-Tweaks {
    if (-not (Test-Path -LiteralPath $backup)) { Write-Host 'No backup found. Nothing to undo.'; return }
    try { $b = Get-Content -LiteralPath $backup -Raw | ConvertFrom-Json }
    catch { Write-Host 'Backup file is unreadable. It was left in place.' -ForegroundColor Red; return }
    if (-not $b.Version) { Write-Host 'This backup is from v1.0 and lacks the detail needed for a safe undo. Restore manually or use System Restore.' -ForegroundColor Yellow; return }

    $results = @()
    try {
        if ((Get-ActiveScheme) -eq $b.PowerScheme) { $results += [pscustomobject]@{ Name = 'Power plan'; Status = 'Unchanged'; Detail = '' } }
        else { Set-Scheme $b.PowerScheme; $results += [pscustomobject]@{ Name = 'Power plan'; Status = 'OK'; Detail = '' } }
    } catch { $results += [pscustomobject]@{ Name = 'Power plan'; Status = 'Failed'; Detail = "($($_.Exception.Message))" } }

    foreach ($r in $b.Registry) {
        try {
            if ($r.Existed) {
                if (-not (Test-Path -LiteralPath $r.Path)) { New-Item -Path $r.Path -Force -ErrorAction Stop | Out-Null }
                New-ItemProperty -LiteralPath $r.Path -Name $r.ValueName -Value $r.Data -PropertyType $r.Kind -Force -ErrorAction Stop | Out-Null
            } elseif (Test-Path -LiteralPath $r.Path) {
                Remove-ItemProperty -LiteralPath $r.Path -Name $r.ValueName -ErrorAction SilentlyContinue
            }
            $now = Get-RegState @{ Name = $r.Name; Path = $r.Path; Value = $r.ValueName }
            $ok = if ($r.Existed) { $now.Existed -and "$($now.Data)" -eq "$($r.Data)" } else { -not $now.Existed }
            if (-not $ok) { throw 'value does not match the backup' }
            $results += [pscustomobject]@{ Name = $r.Name; Status = 'OK'; Detail = '' }
        } catch {
            $results += [pscustomobject]@{ Name = $r.Name; Status = 'Failed'; Detail = "($($_.Exception.Message))" }
        }
    }
    Write-Results $results
    if (@($results | Where-Object Status -eq 'Failed').Count -eq 0) {
        $done = Join-Path $dir ("backup-restored-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Move-Item -LiteralPath $backup -Destination $done
        Write-Host "Original settings restored. Old backup archived as $done" -ForegroundColor Green
    } else {
        Write-Host "Backup kept at $backup so you can try undo again." -ForegroundColor Yellow
    }
}

function Get-TempCandidates($root, $cutoff) {
    $stack = New-Object System.Collections.Stack
    $stack.Push((Get-Item -LiteralPath $root -Force))
    while ($stack.Count) {
        $d = $stack.Pop()
        foreach ($i in (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) {
            if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($i.PSIsContainer) { $stack.Push($i) }
            elseif ($i.LastWriteTime -lt $cutoff) { $i }
        }
    }
}

function Clean-Temp {
    $roots = @()
    $userTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    $blocked = @($env:USERPROFILE, $env:SystemRoot, $env:SystemDrive, "$env:SystemDrive\") | ForEach-Object { "$_".TrimEnd('\') }
    if ((Test-Path -LiteralPath $userTemp) -and ($blocked -notcontains $userTemp) -and ($userTemp -match '\\Temp$')) { $roots += $userTemp }
    else { Write-Host "Skipping user TEMP ($userTemp): unexpected location." -ForegroundColor Yellow }
    if ($IsAdmin) { $roots += (Join-Path $env:SystemRoot 'Temp') }
    else { Write-Host 'Not administrator: skipping Windows\Temp.' -ForegroundColor Gray }

    $cutoff = (Get-Date).AddDays(-1)
    $files = @($roots | ForEach-Object { Get-TempCandidates $_ $cutoff })
    if (-not $files.Count) { Write-Host 'No temp files older than 24 hours found.'; return }
    $total = ($files | Measure-Object Length -Sum).Sum
    Write-Host "`nFound $($files.Count) temp files older than 24 hours (about $([math]::Round($total/1MB,1)) MB) in:" -ForegroundColor Cyan
    $roots | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Deleted files CANNOT be restored by Undo.' -ForegroundColor Yellow
    if ((Read-Host 'Type DELETE to remove them') -cne 'DELETE') { Write-Host 'Cancelled. Nothing deleted.'; return }

    $deleted = 0; $freed = 0; $skipped = 0
    foreach ($f in $files) {
        try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $deleted++; $freed += $len }
        catch { $skipped++ }
    }
    Write-Host "Deleted $deleted files (about $([math]::Round($freed/1MB,1)) MB). Skipped $skipped in use or protected." -ForegroundColor Green
}

do {
    Write-Host "`n=== MyOptimizer (preview) ===`n1) Preview and apply gaming tweaks`n2) Clean old temp files`n3) Undo tweaks`n4) Open startup apps`n0) Exit"
    $c = Read-Host 'Choose'
    switch ($c) {
        '1' { Apply-Tweaks } '2' { Clean-Temp } '3' { Undo-Tweaks }
        '4' { Start-Process 'ms-settings:startupapps' }
    }
} while ($c -ne '0')
