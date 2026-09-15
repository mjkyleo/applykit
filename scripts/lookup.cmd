@echo off
rem applykit fast lookup via 12_索引 (wrapper; args forwarded to ps1)
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lookup.ps1" %*
exit /b %errorlevel%
