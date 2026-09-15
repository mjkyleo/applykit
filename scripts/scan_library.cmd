@echo off
rem applykit library health scan (wrapper; args forwarded to ps1)
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scan_library.ps1" %*
exit /b %errorlevel%
