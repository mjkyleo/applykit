@echo off
rem applykit rebuild 12_索引 (wrapper; args forwarded to ps1)
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reindex.ps1" %*
exit /b %errorlevel%
