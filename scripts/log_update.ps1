# log_update.ps1 —— 向 10_更新日志.md 确定性追加一行（自动时间戳、转义表格符 |）
# 用法：log_update.ps1 <工作目录> -File f -Field x -New v [-Old o] [-Reason r] [-Confirmer c]
# 退出码：0 成功；1 写入错误
param(
    [Parameter(Position = 0, Mandatory = $true)][string]$Workspace,
    [Parameter(Mandatory = $true)][string]$File,
    [Parameter(Mandatory = $true)][string]$Field,
    [string]$Old = '（无）',
    [Parameter(Mandatory = $true)][string]$New,
    [string]$Reason = '（自动）',
    [string]$Confirmer = '（自动）'
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

function Cell([string]$v) {
    return ($v -replace '\|', '\|' -replace "`r|`n", ' ').Trim()
}
function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

$ws = [System.IO.Path]::GetFullPath($Workspace)
$logPath = Join-Path $ws '10_更新日志.md'
$header = @"
# 10 · 更新日志

> 规则：每次写入或更新必须在此留痕。格式：``时间 | 文件 | 字段 | 旧值 | 新值 | 原因 | 确认人``。

## 日志

| 时间 | 文件 | 字段 | 旧值 | 新值 | 原因 | 确认人 |
|---|---|---|---|---|---|---|
"@

$ts = Get-Date -Format 'yyyy-MM-dd HH:mm'
$row = "| $ts | $(Cell $File) | $(Cell $Field) | $(Cell $Old) | $(Cell $New) | $(Cell $Reason) | $(Cell $Confirmer) |"

try {
    if (-not (Test-Path $logPath)) {
        New-Item -ItemType Directory -Path $ws -Force | Out-Null
        Write-Utf8NoBom $logPath ($header + "`r`n" + $row + "`r`n")
    } else {
        $text = [System.IO.File]::ReadAllText($logPath, [System.Text.Encoding]::UTF8)
        if ($text -notmatch '\| 时间 \| 文件 \|') {
            if (-not $text.EndsWith("`n")) { $text += "`r`n" }
            $text = $header + "`r`n" + $text + $row + "`r`n"
        } else {
            if (-not $text.EndsWith("`n")) { $text += "`r`n" }
            $text += $row + "`r`n"
        }
        Write-Utf8NoBom $logPath $text
    }
} catch {
    Write-Output "[错误] 写入日志失败：$_"
    exit 1
}

Write-Output "已记录日志：$logPath"
Write-Output "  $row"
exit 0
