# scan_library.ps1 —— 网申信息库体检：状态分布、草稿/废弃/缺元数据/长期未复核、待裁决冲突、下一步建议
# 用法：scan_library.ps1 <工作目录> [-StaleDays 180] [-Json]   退出码：0 成功；1 目录无效
param(
    [Parameter(Position = 0, Mandatory = $true)][string]$Workspace,
    [int]$StaleDays = 180,
    [switch]$Json
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$CategoryFiles = @(
    '01_个人基础信息.md', '02_教育经历.md', '03_实习与工作经历.md', '04_项目经历.md',
    '05_奖项与证书.md', '06_技能与语言.md', '07_开放问题库.md'
)
$CoreFiles = @(
    '00_总览与使用说明.md', '09_冲突与待确认.md', '10_更新日志.md', '11_模板/字段记录模板.md'
)
$CompanyDirName = '08_公司岗位记录'
$ConflictName = '09_冲突与待确认.md'
$IndexDirName = '12_索引'
$IndexName = '字段总索引.md'
$ValidStatus = @('草稿', '已确认', '废弃')

function Parse-Entries([string]$path) {
    $entries = @(); $cur = $null
    foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
        if ($line -match '^- 字段名：\s*(.*)$') {
            if ($null -ne $cur) { $entries += ,$cur }
            $cur = @{ name = $Matches[1].Trim(); file = (Split-Path $path -Leaf) }
        } elseif ($null -ne $cur) {
            if ($line.Trim() -eq '---' -or $line.StartsWith('## ')) {
                $entries += ,$cur; $cur = $null
            } elseif ($line -match '^- (版本|状态|最后确认时间|来源|标准答案)：\s*(.*)$') {
                $cur[$Matches[1]] = $Matches[2].Trim()
            }
        }
    }
    if ($null -ne $cur) { $entries += ,$cur }
    return $entries
}

function Count-PendingConflicts([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    $n = 0
    foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
        if (-not $line.StartsWith('|') -or $line.Contains('---')) { continue }
        $cells = $line.Trim('|').Split('|') | ForEach-Object { $_.Trim() }
        if (-not $cells -or $cells[0] -eq '编号' -or $cells[0].StartsWith('例')) { continue }
        if ($cells[-1].Contains('待确认')) { $n++ }
    }
    return $n
}

function Days-Since([string]$text) {
    if ($text -match '(\d{4})-(\d{2})-(\d{2})') {
        try {
            $d = [datetime]::ParseExact($Matches[0], 'yyyy-MM-dd', $null)
            return ([int]((Get-Date).Date - $d.Date).TotalDays)
        } catch { return $null }
    }
    return $null
}

$ws = [System.IO.Path]::GetFullPath($Workspace)
if (-not (Test-Path $ws -PathType Container)) {
    Write-Output "[错误] 工作目录不存在或不可读：$ws"
    exit 1
}

$files = @()
foreach ($n in $CategoryFiles) { $files += (Join-Path $ws $n) }
$companyDir = Join-Path $ws $CompanyDirName
if (Test-Path $companyDir -PathType Container) {
    $files += (Get-ChildItem $companyDir -Filter *.md -File | Sort-Object Name | ForEach-Object { $_.FullName })
}

$missing = @($CategoryFiles + $CoreFiles | Where-Object { -not (Test-Path (Join-Path $ws $_)) })
$entries = @(); $blankByFile = @{}; $emptyFiles = @()
foreach ($p in $files) {
    if (-not (Test-Path $p)) { continue }
    $parsed = @(Parse-Entries $p)
    if ($parsed.Count -eq 0) { $emptyFiles += (Split-Path $p -Leaf) }
    foreach ($e in $parsed) {
        $name = [string]$e.name
        $stripped = $name.Trim(' ', '(', ')', '（', '）', '未', '命', '名')
        if ([string]::IsNullOrWhiteSpace($stripped) -and -not $e['标准答案']) {
            $f = $e.file
            if ($blankByFile.ContainsKey($f)) { $blankByFile[$f]++ } else { $blankByFile[$f] = 1 }
        } else {
            $entries += ,$e
        }
    }
}

$drafts = @(); $confirmed = @(); $deprecated = @(); $badStatus = @(); $noVersion = @(); $stale = @()
foreach ($e in $entries) {
    $st = [string]$e['状态']
    if ($ValidStatus -notcontains $st) { $badStatus += ,$e }
    elseif ($st -eq '草稿') { $drafts += ,$e }
    elseif ($st -eq '已确认') {
        $confirmed += ,$e
        $age = Days-Since ([string]$e['最后确认时间'])
        if ($null -ne $age -and $age -gt $StaleDays) {
            $e['_age'] = $age; $stale += ,$e
        }
    } elseif ($st -eq '废弃') { $deprecated += ,$e }
    if (-not $e['版本']) { $noVersion += ,$e }
}

$pending = Count-PendingConflicts (Join-Path $ws $ConflictName)
$blankTotal = ($blankByFile.Values | Measure-Object -Sum).Sum
if (-not $blankTotal) { $blankTotal = 0 }

# 索引新鲜度：12_索引 是否存在 / 条目数与库是否一致 / 是否比数据文件旧
$indexPath = Join-Path (Join-Path $ws $IndexDirName) $IndexName
$indexStatus = 'missing'; $indexCount = $null; $indexTime = $null
if (Test-Path $indexPath) {
    $indexStatus = 'ok'
    foreach ($line in [System.IO.File]::ReadAllLines($indexPath, [System.Text.Encoding]::UTF8)) {
        if ($line -match '条目数：(\d+)') { $indexCount = [int]$Matches[1] }
        if ($line -match '生成时间：(\d{4}-\d{2}-\d{2} \d{2}:\d{2})') { $indexTime = $Matches[1] }
    }
    if ($null -eq $indexCount -or $indexCount -ne $entries.Count) {
        $indexStatus = 'stale'
    } else {
        $newest = $null
        foreach ($p in $files) {
            if (Test-Path $p) {
                $t = (Get-Item $p).LastWriteTime
                if ($null -eq $newest -or $t -gt $newest) { $newest = $t }
            }
        }
        if ($null -ne $newest -and $newest -gt (Get-Item $indexPath).LastWriteTime) { $indexStatus = 'stale' }
    }
}
$indexCountText = if ($null -eq $indexCount) { '—' } else { [string]$indexCount }
$indexLabel = @{ ok = '有效'; missing = '缺失'; stale = '已过期' }

$nextSteps = @()
if ($missing.Count) { $nextSteps += "运行 init_workspace.cmd 补齐缺失文件：$($missing -join '、')" }
if ($pending) { $nextSteps += "先裁决 09 中 $pending 条待确认冲突" }
if ($badStatus.Count) { $nextSteps += "修正 $($badStatus.Count) 条状态异常条目" }
if ($noVersion.Count) { $nextSteps += "补全 $($noVersion.Count) 条缺版本号条目" }
if ($indexStatus -eq 'missing') { $nextSteps += "运行 reindex.cmd 生成 $IndexDirName（查询/修改/查重先查索引，避免全库扫描）" }
elseif ($indexStatus -eq 'stale') { $nextSteps += "运行 reindex.cmd 重建 $IndexDirName（索引已过期：条目数或文件时间不一致）" }
if ($drafts.Count) { $nextSteps += "确认 $($drafts.Count) 条草稿（确认后成为主答案）" }
foreach ($n in $CategoryFiles) {
    if ($blankByFile.ContainsKey($n)) { $nextSteps += "补充 $n（$($blankByFile[$n]) 个待填块）" }
}
if ($nextSteps.Count -eq 0) { $nextSteps += '信息库完整，无待办' }

if ($Json) {
    $out = [ordered]@{
        total = $entries.Count; blank_slots = $blankTotal; blank_by_file = $blankByFile
        by_status = [ordered]@{ '已确认' = $confirmed.Count; '草稿' = $drafts.Count; '废弃' = $deprecated.Count; '状态异常' = $badStatus.Count }
        drafts = $drafts; deprecated = $deprecated; bad_status = $badStatus; no_version = $noVersion
        stale = $stale; stale_days = $StaleDays; empty_files = $emptyFiles; missing_files = $missing
        index = [ordered]@{ status = $indexStatus; entries = $entries.Count; indexed = $indexCount; generated_at = $indexTime }
        pending_conflicts = $pending; next_steps = $nextSteps
    }
    $out | ConvertTo-Json -Depth 8
    exit 0
}

function Loc($e) { return "$($e.file) :: $($e.name)" }
Write-Output ('=' * 48)
Write-Output '网申信息库体检报告'
Write-Output ('=' * 48)
Write-Output "条目总数：$($entries.Count)    已确认 $($confirmed.Count) / 草稿 $($drafts.Count) / 废弃 $($deprecated.Count) / 状态异常 $($badStatus.Count)"
Write-Output "空白待填块：$blankTotal 个（模板占位，未计入条目总数）"
Write-Output "待裁决冲突：$pending 条"
Write-Output "索引状态（$IndexDirName）：$($indexLabel[$indexStatus])（库内 $($entries.Count) 条 / 索引 $indexCountText 条$(if ($indexTime) { "，生成于 $indexTime" })）"
if ($missing.Count) { Write-Output ("[缺失文件] " + ($missing -join ', ') + '（建议运行 init_workspace 补齐）') }
if ($emptyFiles.Count) { Write-Output ("[空类目文件] " + ($emptyFiles -join ', ')) }
if ($drafts.Count) {
    Write-Output "`n草稿（$($drafts.Count)，确认后才作为主答案）："
    $drafts | ForEach-Object { Write-Output "  · $(Loc $_)" }
}
if ($stale.Count) {
    Write-Output "`n超过 $StaleDays 天未复核的已确认条目（$($stale.Count)）："
    $stale | Sort-Object { -$_['_age'] } | ForEach-Object {
        Write-Output "  · $(Loc $_)（$($_['_age']) 天，确认于 $($_['最后确认时间'])）"
    }
}
if ($noVersion.Count) {
    Write-Output "`n缺版本号（$($noVersion.Count)）："
    $noVersion | ForEach-Object { Write-Output "  · $(Loc $_)" }
}
if ($badStatus.Count) {
    Write-Output "`n状态值异常（$($badStatus.Count)，只允许 草稿/已确认/废弃）："
    $badStatus | ForEach-Object { Write-Output "  · $(Loc $_)（当前：$($_['状态'])）" }
}
if ($deprecated.Count) {
    Write-Output "`n已废弃条目（$($deprecated.Count)）："
    $deprecated | ForEach-Object { Write-Output "  · $(Loc $_)" }
}
Write-Output ('-' * 48)
if ($entries.Count -eq 0 -and $blankTotal -gt 0) {
    Write-Output '信息库还是空的：从 01_个人基础信息 开始即可，'
    Write-Output '随时说「记录一下……」逐条补充，可中断、可续填。'
}
Write-Output '下一步建议：'
$i = 1
foreach ($s in $nextSteps) { Write-Output "  $i. $s"; $i++ }
Write-Output ('=' * 48)
exit 0
