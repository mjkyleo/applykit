# log_update.ps1 —— 向 10_更新日志.md 确定性追加一行（自动时间戳、转义表格符 |）
# 用法：log_update.ps1 <工作目录> -File f -Field x -New v [-Old o] [-Reason r] [-Confirmer c] [-Sensitive]
# 退出码：0 成功；1 写入错误
param(
    [Parameter(Position = 0, Mandatory = $true)][string]$Workspace,
    [Parameter(Mandatory = $true)][string]$File,
    [Parameter(Mandatory = $true)][string]$Field,
    [string]$Old = '（无）',
    [Parameter(Mandatory = $true)][string]$New,
    [string]$Reason = '（自动）',
    [string]$Confirmer = '（自动）',
    [switch]$Sensitive
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

function Cell([string]$v) {
    return ($v -replace '\|', '\|' -replace "`r|`n", ' ').Trim()
}
function Mask([string]$v) {
    if ([string]::IsNullOrWhiteSpace($v)) { return $v }
    if ($v -eq '（无）') { return $v }
    if ($v -match '^(\d{3})\d{4}(\d{4})$') { return "$($Matches[1])****$($Matches[2])" }
    $len = $v.Length
    if ($len -le 2) { return '**' }
    if ($len -le 6) { return $v.Substring(0, 1) + ('*' * ($len - 1)) }
    return $v.Substring(0, 2) + '****' + $v.Substring($len - 2)
}
function Fingerprint([string]$v) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($v)
    $hex = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    return $hex.Substring(0, 8)
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
$oldCell = $Old
$newCell = $New
if ($Sensitive) {
    $oldCell = "$(Mask $Old)（脱敏 sha256:$(Fingerprint $Old)）"
    $newCell = "$(Mask $New)（脱敏 sha256:$(Fingerprint $New)）"
}
$row = "| $ts | $(Cell $File) | $(Cell $Field) | $(Cell $oldCell) | $(Cell $newCell) | $(Cell $Reason) | $(Cell $Confirmer) |"

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
