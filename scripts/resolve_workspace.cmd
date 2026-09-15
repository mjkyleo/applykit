@echo off
rem applykit resolve fixed workspace (wrapper; args forwarded to ps1)
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0resolve_workspace.ps1" %*
exit /b %errorlevel%
