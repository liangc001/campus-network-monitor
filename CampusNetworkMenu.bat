@echo off
chcp 65001 >nul
if exist "%~dp0CampusNetworkMonitor.exe" (
    start "" "%~dp0CampusNetworkMonitor.exe" -RepairOnStart -StartMonitorAfterRepair
) else (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0CampusNetworkMonitorApp.ps1" -RepairOnStart -StartMonitorAfterRepair
)
exit /b
