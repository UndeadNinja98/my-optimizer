# MyOptimizer

A free, safe Windows 10/11 optimizer. Every change is backed up and can be undone with one option.

## What it does

1. **Apply gaming tweaks** - High-performance power plan, Game Mode on, Xbox Game Bar recording off, performance-focused visual effects. Creates a restore point and saves your old settings first.
2. **Clean temp files** - Clears Windows and user temp folders.
3. **Undo all tweaks** - Restores your original settings from the backup.
4. **Open startup apps** - Opens Windows settings so you can turn off apps that slow startup.

## How to run

1. Download `MyOptimizer.ps1`.
2. Press the Windows key, type `PowerShell`, right-click it, and choose **Run as administrator**.
3. Type `powershell -ExecutionPolicy Bypass -File ` (with a space), then right-click the downloaded file, choose **Copy as path**, and paste it in.
4. Press Enter and pick an option from the menu.

## Safety

- Does not disable Windows Defender, Windows Update, or core services.
- Backup is saved to `%APPDATA%\MyOptimizer\backup.json`.
- Read the script before running it - it's short and plain text.

Use at your own risk. Provided as-is with no warranty.
