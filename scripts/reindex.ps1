# reindex.ps1 —— 重建 12_索引/（字段总索引、关键词倒排、公司岗位索引），幂等：内容无变化不重写
# 用法：reindex.ps1 <工作目录> [-Json]     退出码：0 成功；1 目录无效
param(
    [Parameter(Position = 0, Mandatory = $true)][string]$Workspace,
    [switch]$Json
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$CategoryFiles = @(
    '01_个人基础信息.md', '02_教育经历.md', '03_实习与工作经历.md', '04_项目经历.md',
    '05_奖项与证书.md', '06_技能与语言.md', '07_开放问题库.md'
)
$CompanyDirName = '08_公司岗位记录'
$IndexDirName   = '12_索引'

function Cell([string]$v) {
    if ($null -eq $v) { return '' }
    return (($v -replace '\|', '\|') -replace "`r|`n", ' ').Trim()
}
function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}
function Save-IfChanged([string]$Path, [string]$Text) {
    $old = $null
    if (Test-Path $Path) { $old = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
    if ($old -eq $Text) { return $false }
    $tmp = "$Path.tmp"
    Write-Utf8NoBom $tmp $Text
    Move-Item $tmp $Path -Force
    return $true
}
function Ver-Num([string]$v) {
    if ($v -match 'v(\d+)') { return [int]$Matches[1] }
    return 0
}
function Parse-Entries([string]$path, [string]$rel) {
    $result = @(); $cur = $null; $ln = 0
    foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
        $ln++
        if ($line -match '^- 字段名：\s*(.*)$') {
            if ($null -ne $cur) { $result += ,$cur }
            $cur = @{ name = $Matches[1].Trim(); file = $rel; line = $ln }
        } elseif ($null -ne $cur) {
            $t = $line.Trim()
            if ($t -eq '---' -or $line.StartsWith('## ')) {
                $result += ,$cur; $cur = $null
            } elseif ($line -match '^- (版本|状态|最后确认时间|来源|标准答案|关键词)：\s*(.*)$') {
                $cur[$Matches[1]] = $Matches[2].Trim()
            }
        }
    }
    if ($null -ne $cur) { $result += ,$cur }
    return $result
}

$ws = [System.IO.Path]::GetFullPath($Workspace)
if (-not (Test-Path $ws -PathType Container)) {
    Write-Output "[错误] 工作目录不存在或不可读：$ws"
    exit 1
}

# 1. 收集待索引文件（类目文件 + 08 公司岗位）
$targets = @()
foreach ($n in $CategoryFiles) {
    $p = Join-Path $ws $n
    if (Test-Path $p) { $targets += @{ path = $p; rel = $n } }
}
$companyDir = Join-Path $ws $CompanyDirName
if (Test-Path $companyDir -PathType Container) {
    Get-ChildItem $companyDir -Filter *.md -File | Sort-Object Name | ForEach-Object {
        $targets += @{ path = $_.FullName; rel = "$CompanyDirName/$($_.Name)" }
    }
}

# 2. 解析条目（跳过模板占位空块）
$raw = @()
foreach ($t in $targets) { $raw += Parse-Entries $t.path $t.rel }
$entries = @()
foreach ($e in $raw) {
    $name = [string]$e.name
    $stripped = $name.Trim(' ', '(', ')', '（', '）', '未', '命', '名')
    if ([string]::IsNullOrWhiteSpace($stripped) -and -not $e['标准答案']) { continue }
    $entries += ,$e
}

$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

# 3. 字段总索引
$fieldLines = @()
$fieldLines += '# 12 · 索引 · 字段总索引'
$fieldLines += ''
$fieldLines += '> 由 `scripts\reindex.cmd` 自动生成，**请勿手工编辑**；数据以 01~08 类目文件为准。'
$fieldLines += '> 检索顺序：先查本索引 → 按「行号」直接跳到对应文件的对应条目 → 再读原文（避免全库扫描）。'
$fieldLines += "> 生成时间：$stamp    条目数：$($entries.Count)"
$fieldLines += ''
$fieldLines += '| 字段名 | 文件 | 行号 | 版本 | 状态 | 最后确认时间 | 关键词 |'
$fieldLines += '|---|---|---|---|---|---|---|'
foreach ($e in ($entries | Sort-Object { $_.file }, { [int]$_.line })) {
    $fieldLines += "| $(Cell $e.name) | $(Cell $e.file) | $($e.line) | $(Cell $e['版本']) | $(Cell $e['状态']) | $(Cell $e['最后确认时间']) | $(Cell $e['关键词']) |"
}

# 4. 关键词倒排
$kwLines = @()
$kwLines += '# 12 · 索引 · 关键词倒排'
$kwLines += ''
$kwLines += '> 由 `scripts\reindex.cmd` 自动生成，**请勿手工编辑**。'
$kwLines += '> 关键词取自各条目「关键词」字段，按空格 / 逗号 / 顿号 / 分号切分；用于「忘了字段名，只知道大概意思」的检索。'
$kwLines += ''
$kwLines += '| 关键词 | 字段名 | 文件 | 行号 | 状态 |'
$kwLines += '|---|---|---|---|---|'
$kwSeen = @{}
foreach ($e in ($entries | Sort-Object { $_.file }, { [int]$_.line })) {
    $kwRaw = [string]$e['关键词']
    if ([string]::IsNullOrWhiteSpace($kwRaw)) { continue }
    foreach ($k in ($kwRaw -split '[,，、;；\s]+')) {
        if ([string]::IsNullOrWhiteSpace($k)) { continue }
        $key = "$k|$($e.name)|$($e.file)"
        if ($kwSeen.ContainsKey($key)) { continue }
        $kwSeen[$key] = $true
        $kwLines += "| $(Cell $k) | $(Cell $e.name) | $(Cell $e.file) | $($e.line) | $(Cell $e['状态']) |"
    }
}

# 5. 公司岗位索引（已确认优先、其次版本号高）
$coLines = @()
$coLines += '# 12 · 索引 · 公司岗位索引'
$coLines += ''
$coLines += '> 由 `scripts\reindex.cmd` 自动生成，**请勿手工编辑**。'
$coLines += '> 公司 / 岗位优先取条目「公司」「岗位」的标准答案（已确认版本优先、其次版本高），缺失时回退文件名 `公司名_岗位名.md`。'
$coLines += ''
$coLines += '| 公司 | 岗位 | 文件 | 投递状态 | 截止时间 | 最后更新 |'
$coLines += '|---|---|---|---|---|---|'
$coCount = 0
foreach ($t in ($targets | Where-Object { $_.rel.StartsWith("$CompanyDirName/") })) {
    $fileEntries = @($entries | Where-Object { $_.file -eq $t.rel })
    if ($fileEntries.Count -eq 0) { continue }
    $pick = @{}
    foreach ($e in $fileEntries) {
        $n = [string]$e.name
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        if (-not $pick.ContainsKey($n)) { $pick[$n] = $e; continue }
        $cur = $pick[$n]
        $better = $false
        if (([string]$e['状态']) -eq '已确认' -and ([string]$cur['状态']) -ne '已确认') { $better = $true }
        elseif (([string]$e['状态']) -eq ([string]$cur['状态']) -and (Ver-Num ([string]$e['版本'])) -gt (Ver-Num ([string]$cur['版本']))) { $better = $true }
        if ($better) { $pick[$n] = $e }
    }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($t.rel)
    $parts = $base -split '_'
    $fnCompany = if ($parts.Count -ge 1) { $parts[0] } else { '' }
    $fnJob = if ($parts.Count -ge 2) { $parts[1] } else { '' }
    $co = if ($pick.ContainsKey('公司') -and $pick['公司']['标准答案']) { [string]$pick['公司']['标准答案'] } else { $fnCompany }
    $job = if ($pick.ContainsKey('岗位') -and $pick['岗位']['标准答案']) { [string]$pick['岗位']['标准答案'] } else { $fnJob }
    if ([string]::IsNullOrWhiteSpace("$co$job")) { continue }
    $status = if ($pick.ContainsKey('投递状态')) { [string]$pick['投递状态']['标准答案'] } else { '' }
    $deadline = if ($pick.ContainsKey('截止时间')) { [string]$pick['截止时间']['标准答案'] } else { '' }
    $lastUpd = ''
    foreach ($e in $fileEntries) {
        $d = [string]$e['最后确认时间']
        if ($d -match '\d{4}-\d{2}-\d{2}' -and $d -gt $lastUpd) { $lastUpd = $Matches[0] }
    }
    $coLines += "| $(Cell $co) | $(Cell $job) | $(Cell $t.rel) | $(Cell $status) | $(Cell $deadline) | $(Cell $lastUpd) |"
    $coCount++
}

# 6. 写入（无变化则跳过）
$indexDir = Join-Path $ws $IndexDirName
New-Item -ItemType Directory -Path $indexDir -Force | Out-Null
$jobs = @(
    @{ name = "$IndexDirName/字段总索引.md";   path = (Join-Path $indexDir '字段总索引.md');   text = ($fieldLines -join "`r`n") }
    @{ name = "$IndexDirName/关键词倒排.md";   path = (Join-Path $indexDir '关键词倒排.md');   text = ($kwLines -join "`r`n") }
    @{ name = "$IndexDirName/公司岗位索引.md"; path = (Join-Path $indexDir '公司岗位索引.md'); text = ($coLines -join "`r`n") }
)
$changed = @(); $unchanged = @()
foreach ($j in $jobs) {
    if (Save-IfChanged $j.path ($j.text + "`r`n")) { $changed += $j.name } else { $unchanged += $j.name }
}

if ($Json) {
    $out = [ordered]@{
        workspace = $ws; generated_at = $stamp; entries = $entries.Count
        companies = $coCount; changed = $changed; unchanged = $unchanged
    }
    $out | ConvertTo-Json -Depth 6
    exit 0
}
Write-Output "[索引] $IndexDirName 重建完成：条目 $($entries.Count) 条，公司岗位 $coCount 个"
foreach ($n in $changed)   { Write-Output "  * $n（已更新）" }
foreach ($n in $unchanged) { Write-Output "  = $n（无变化，未重写）" }
exit 0
