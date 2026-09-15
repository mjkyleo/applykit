# lookup.ps1 —— 基于 12_索引 的快速检索：查询 / 修改定位 / 新增查重 的统一冷启动入口
# 用法：lookup.ps1 <工作目录> [-Field <字段名>] [-Keyword <关键词>] [-Company <公司或岗位>] [-Status <状态>] [-Json]
# 退出码：0 命中；2 未命中；3 索引缺失（先跑 reindex）；1 错误
param(
    [Parameter(Position = 0, Mandatory = $true)][string]$Workspace,
    [string]$Field,
    [string]$Keyword,
    [string]$Company,
    [string]$Status,
    [switch]$Json
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$IndexDirName = '12_索引'

function Read-Table([string]$path) {
    $rows = @(); $header = $null
    if (-not (Test-Path $path)) { return @() }
    foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
        if (-not $line.StartsWith('|')) { continue }
        $cells = @($line.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if (($cells -join '') -match '^-+$') { continue }
        if ($null -eq $header) { $header = $cells; continue }
        $o = @{}
        for ($i = 0; $i -lt $header.Count; $i++) {
            $o[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
        }
        $rows += ,$o
    }
    return $rows
}
function Has([string]$hay, [string]$needle) {
    if ([string]::IsNullOrWhiteSpace($needle)) { return $true }
    if ([string]::IsNullOrWhiteSpace($hay)) { return $false }
    return $hay.ToLower().Contains($needle.ToLower())
}

$ws = [System.IO.Path]::GetFullPath($Workspace)
if (-not (Test-Path $ws -PathType Container)) {
    Write-Output "[错误] 工作目录不存在或不可读：$ws"
    exit 1
}
if (-not $Field -and -not $Keyword -and -not $Company) {
    Write-Output '[错误] 至少提供 -Field、-Keyword、-Company 之一'
    exit 1
}

$indexDir = Join-Path $ws $IndexDirName
$fieldIdxPath = Join-Path $indexDir '字段总索引.md'
$kwIdxPath    = Join-Path $indexDir '关键词倒排.md'
$coIdxPath    = Join-Path $indexDir '公司岗位索引.md'
if (-not (Test-Path $fieldIdxPath)) {
    Write-Output "[索引缺失] 未找到 $IndexDirName/字段总索引.md，请先运行 reindex.cmd <工作目录>"
    exit 3
}

# 索引新鲜度提示（类目文件比索引新 → 可能过期）
$idxTime = (Get-Item $fieldIdxPath).LastWriteTime
$stale = $false
foreach ($f in (Get-ChildItem $ws -Filter *.md -File)) {
    if ($f.LastWriteTime -gt $idxTime) { $stale = $true; break }
}
$coDir = Join-Path $ws '08_公司岗位记录'
if (-not $stale -and (Test-Path $coDir -PathType Container)) {
    foreach ($f in (Get-ChildItem $coDir -Filter *.md -File)) {
        if ($f.LastWriteTime -gt $idxTime) { $stale = $true; break }
    }
}

# ---- 公司岗位检索 ----
if ($Company) {
    $rows = @(Read-Table $coIdxPath | Where-Object { (Has $_['公司'] $Company) -or (Has $_['岗位'] $Company) -or (Has $_['文件'] $Company) })
    if ($rows.Count -eq 0) {
        Write-Output "[未命中] $IndexDirName/公司岗位索引.md 中没有与「$Company」匹配的公司或岗位"
        exit 2
    }
    if ($Json) {
        [ordered]@{ source = "$IndexDirName/公司岗位索引.md"; stale = $stale; hits = $rows.Count; items = $rows } | ConvertTo-Json -Depth 6
        exit 0
    }
    Write-Output "[命中] $($rows.Count) 条（来源：$IndexDirName/公司岗位索引.md）"
    foreach ($r in $rows) {
        Write-Output "  - $($r['公司']) | $($r['岗位']) | $($r['文件']) | 状态：$($r['投递状态']) | 截止：$($r['截止时间']) | 更新：$($r['最后更新'])"
    }
    if ($rows.Count -gt 1) { Write-Output '[提示] 命中多条候选，列出给用户选择，不要猜测。' }
    if ($stale) { Write-Output '[警告] 索引可能过期（有数据文件比索引新），建议先运行 reindex.cmd。' }
    exit 0
}

# ---- 字段 / 关键词检索 ----
$all = @(Read-Table $fieldIdxPath)
$cands = @()
if ($Keyword) {
    $kwRows = @(Read-Table $kwIdxPath | Where-Object { (Has $_['关键词'] $Keyword) })
    if ($kwRows.Count -gt 0) {
        $keys = @{}
        foreach ($r in $kwRows) { $keys["$($r['字段名'])|$($r['文件'])"] = $true }
        $cands = @($all | Where-Object { $keys.ContainsKey("$($_['字段名'])|$($_['文件'])") })
    } else {
        $cands = @($all | Where-Object { (Has $_['关键词'] $Keyword) })
    }
} else {
    $cands = @($all | Where-Object { (Has $_['字段名'] $Field) })
}
if ($Status) { $cands = @($cands | Where-Object { $_['状态'] -eq $Status }) }

# 排序：完全匹配 > 包含匹配；再按 文件/行号
$needle = if ($Keyword) { $Keyword } else { $Field }
$cands = @($cands | Sort-Object -Property @{ Expression = {
    $n = [string]$_['字段名']
    if ($n -eq $needle) { 0 } elseif ($n.ToLower().Contains($needle.ToLower()) -and $n.Length -eq $needle.Length) { 0 } else { 1 }
} }, @{ Expression = { [string]$_['文件'] } }, @{ Expression = { [int]($_['行号']) } })

if ($cands.Count -eq 0) {
    $what = if ($Keyword) { "关键词「$Keyword」" } else { "字段「$Field」" }
    Write-Output "[未命中] $IndexDirName 中没有 $what 对应的条目（可全库复核一次，仍未找到则按流程 B 询问是否新增）"
    exit 2
}

if ($Json) {
    [ordered]@{ source = "$IndexDirName/字段总索引.md"; stale = $stale; hits = $cands.Count; items = $cands } | ConvertTo-Json -Depth 6
    exit 0
}
Write-Output "[命中] $($cands.Count) 条（来源：$IndexDirName/字段总索引.md）"
foreach ($r in $cands) {
    Write-Output "  - $($r['字段名']) | $($r['文件']):第 $($r['行号']) 行 | $($r['版本']) | $($r['状态']) | 确认于 $($r['最后确认时间']) | 关键词：$($r['关键词'])"
}
if ($cands.Count -gt 1) { Write-Output '[提示] 命中多条候选，列出给用户选择，不要猜测；主答案优先取「已确认」且版本最高。' }
if ($stale) { Write-Output '[警告] 索引可能过期（有数据文件比索引新），建议先运行 reindex.cmd。' }
exit 0
