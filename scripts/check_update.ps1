# check_update.ps1 —— applykit 版本更新检查：比对本地 VERSION 与默认 GitHub 地址最新版本，只读、离线安全
# 用法：check_update.ps1 [-Repo owner/repo] [-Branch main] [-Json]
# 退出码：0 最新；4 有新版本；3 无法访问远端；2 本地 VERSION 异常
param(
    [string]$Repo = 'mjkyleo/applykit',
    [string]$Branch = 'main',
    [switch]$Json
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$skillRoot = Split-Path $PSScriptRoot -Parent
$localFile = Join-Path $skillRoot 'VERSION'

function Parse-Ver([string]$text) {
    if ($text -match '(\d+)\.(\d+)\.(\d+)') {
        return [version]("$($Matches[1]).$($Matches[2]).$($Matches[3])")
    }
    return $null
}

if (-not (Test-Path $localFile)) {
    $msg = "本地 VERSION 缺失或格式错误：$localFile"
    if ($Json) { @{ status = 'error'; message = $msg } | ConvertTo-Json } else { Write-Output "[错误] $msg" }
    exit 2
}
$local = Parse-Ver ([System.IO.File]::ReadAllText($localFile, [System.Text.Encoding]::UTF8))
if (-not $local) {
    Write-Output "[错误] 本地 VERSION 格式错误：$localFile"; exit 2
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://raw.githubusercontent.com/$Repo/$Branch/VERSION"
    $remoteText = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8).Content
} catch {
    $payload = [ordered]@{ status = 'unreachable'; local = "$local"; message = '无法访问更新地址，可稍后重试；不影响当前使用' }
    if ($Json) { $payload | ConvertTo-Json } else { Write-Output "[无法检查] $($payload.message)" }
    exit 3
}

$remote = Parse-Ver $remoteText
if (-not $remote) {
    if ($Json) { @{ status = 'unreachable'; message = '远端 VERSION 格式异常' } | ConvertTo-Json }
    else { Write-Output '[无法检查] 远端版本格式异常' }
    exit 3
}

$releases = "https://github.com/$Repo/releases"
if ($remote -eq $local) {
    $state = 'up-to-date'
} elseif ($remote -gt $local) {
    $state = 'behind'
} else {
    $state = 'ahead'
}

if ($Json) {
    [ordered]@{ status = $state; local = "$local"; remote = "$remote"; releases_url = $releases } | ConvertTo-Json
} elseif ($state -eq 'up-to-date') {
    Write-Output "[已是最新] 本地 v$local = 远端 v$remote"
} elseif ($state -eq 'behind') {
    Write-Output "[发现新版本] 本地 v$local → 最新 v$remote"
    Write-Output "更新方式：在本 Skill 目录执行 git pull（个人数据与 config/ 不受影响）；更新说明：$releases"
} else {
    Write-Output "[本地版本更新] 本地 v$local 领先远端 v$remote（可能是开发版）"
}
if ($state -eq 'behind') { exit 4 } else { exit 0 }
