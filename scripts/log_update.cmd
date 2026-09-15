@echo off
rem applykit append update log (wrapper; args forwarded to ps1)
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0log_update.ps1" %*
exit /b %errorlevel%
