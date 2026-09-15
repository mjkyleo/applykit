# resolve_workspace.ps1 —— 每次调用 Skill 时首先运行，确认唯一固定的网申工作目录
# 隐私约束：网申数据只允许在已注册的固定私有目录内读写，避免散落。
# 退出码：0 已注册且有效；2 参数错误；3 尚未注册；4 目录已丢失；5 配置损坏
param(
    [string]$Set,
    [switch]$Create,
    [switch]$Clear,
    [string]$Cwd,
    [switch]$Json
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$SkillRoot  = Split-Path $PSScriptRoot -Parent
$ConfigDir  = Join-Path $SkillRoot 'config'
$ConfigPath = Join-Path $ConfigDir 'workspace.json'

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Emit($payload) {
    if ($Json) {
        $payload | ConvertTo-Json -Depth 6
    } else {
        $labels = @{ ok = '[已固定]'; unconfigured = '[未注册]'; missing = '[目录丢失]'; corrupt = '[配置损坏]' }
        $lab = if ($labels.ContainsKey($payload.status)) { $labels[$payload.status] } else { '[状态]' }
        Write-Output "$lab $($payload.message)"
        if ($payload.workspace) { Write-Output "固定工作目录：$($payload.workspace)" }
        if ($payload.registered_at) { Write-Output "注册时间：$($payload.registered_at)" }
        if ($null -ne $payload.cwd_match) {
            Write-Output ("与当前项目目录：" + $(if ($payload.cwd_match) { '一致' } else { '不一致（仍以固定目录为准）' }))
        }
    }
}

function Load-Config {
    if (-not (Test-Path $ConfigPath)) { return $null }
    try {
        return [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        return 'CORRUPT'
    }
}

# --clear：取消注册
if ($Clear) {
    if (Test-Path $ConfigPath) { Remove-Item $ConfigPath -Force }
    Emit ([ordered]@{ status = 'ok'; message = '已取消固定目录注册（不删除任何数据文件）' })
    exit 0
}

# --set：注册/更换固定目录（须用户明确确认后调用）
if ($Set) {
    $ws = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $Set))
    if (-not (Test-Path $ws)) {
        if ($Create) {
            try { New-Item -ItemType Directory -Path $ws -Force | Out-Null }
            catch { Emit ([ordered]@{ status = 'error'; message = "创建目录失败：$_" }); exit 2 }
        } else {
            Emit ([ordered]@{ status = 'error'; message = "路径不存在（如需新建请加 -Create）：$ws" }); exit 2
        }
    }
    if (Test-Path $ws -PathType Leaf) {
        Emit ([ordered]@{ status = 'error'; message = "该路径不是文件夹：$ws" }); exit 2
    }
    $changed = Test-Path $ConfigPath
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    $obj = [ordered]@{
        workspace     = $ws
        registered_at = (Get-Date -Format 'yyyy-MM-dd HH:mm')
        confirmed_by  = 'user'
    }
    Write-Utf8NoBom $ConfigPath ($obj | ConvertTo-Json -Depth 6)
    $msg = ($(if ($changed) { '已更换固定工作目录' } else { '已注册固定工作目录' }) + '（用户明确确认）')
    Emit ([ordered]@{ status = 'ok'; message = $msg; workspace = $ws })
    exit 0
}

# 默认：查看状态
$cfg = Load-Config
if ($cfg -eq 'CORRUPT') {
    Emit ([ordered]@{ status = 'corrupt'; message = "配置无法解析：$ConfigPath，请用 -Set 重新注册" }); exit 5
}
if ($null -eq $cfg) {
    Emit ([ordered]@{ status = 'unconfigured'; message = '尚未注册固定工作目录，请用户指定后用 -Set 注册' }); exit 3
}

$wsPath = [string]$cfg.workspace
$exists = Test-Path $wsPath -PathType Container
$payload = [ordered]@{ workspace = $wsPath; registered_at = [string]$cfg.registered_at }
if ($Cwd) {
    try {
        $payload.cwd_match = ([System.IO.Path]::GetFullPath($wsPath) -eq [System.IO.Path]::GetFullPath($Cwd))
    } catch { $payload.cwd_match = $false }
}
if (-not $exists) {
    $payload.status = 'missing'
    $payload.message = '注册的固定目录已不存在，需用户决定：原路径重建 或 -Set 改到新路径'
    Emit $payload; exit 4
}
$payload.status = 'ok'
$payload.message = '固定工作目录有效，本次所有读写均限定在此目录内'
Emit $payload
exit 0
