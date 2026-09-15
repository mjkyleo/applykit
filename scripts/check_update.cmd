@echo off
rem applykit check update (wrapper; args forwarded to ps1)
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check_update.ps1" %*
exit /b %errorlevel%
