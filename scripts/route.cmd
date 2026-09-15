@echo off
rem applykit routing hub driven by registry.json (wrapper; args forwarded to ps1)
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0route.ps1" %*
exit /b %errorlevel%
