# route.ps1 —— applykit 路由中枢：由 registry.json（单一事实源）驱动的意图识别、上下文装配、脚本链输出与一致性自检
# 用法：route.ps1 [-Guess "<用户原话>"] [-Intent <id>] [-List] [-Check] [-Json]
# 退出码：0 成功；1 registry 缺失/解析失败或参数错误；2 无法识别意图；4 发现漂移
param(
    [string]$Guess,
    [string]$Intent,
    [switch]$List,
    [switch]$Check,
    [switch]$Json
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path $PSScriptRoot -Parent
$regPath   = Join-Path $skillRoot 'registry.json'
$tmplDir   = Join-Path $skillRoot 'assets\templates'
$skillFile = Join-Path $skillRoot 'SKILL.md'
$verFile   = Join-Path $skillRoot 'VERSION'

if (-not (Test-Path $regPath)) { Write-Output "[错误] 缺少路由注册文件：$regPath"; exit 1 }
try {
    $reg = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($regPath, [System.Text.Encoding]::UTF8))
} catch {
    Write-Output "[错误] registry.json 解析失败：$_"
    exit 1
}
$scripts = @{}
foreach ($s in $reg.scripts) { $scripts[$s.id] = $s }
$intents = @($reg.intents | Sort-Object { [int]$_.priority })

function Cmd-Line($step) {
    if ([string]::IsNullOrWhiteSpace($step.script)) { return $step.args }
    $s = $scripts[$step.script]
    $exe = if ($s) { Split-Path $s.cmd -Leaf } else { "$($step.script).cmd" }
    return "$exe $($step.args)"
}

# ---------- -Check：一致性自检 ----------
if ($Check) {
    $drift = @()
    foreach ($s in $reg.scripts) {
        foreach ($rel in @($s.ps1, $s.cmd)) {
            if (-not (Test-Path (Join-Path $skillRoot ($rel -replace '/', '\')))) { $drift += "脚本缺失：$rel" }
        }
    }
    foreach ($w in $reg.workspace) {
        $p = Join-Path $tmplDir ($w.name -replace '/', '\')
        if ($w.kind -eq 'derived') {
            # 派生产物由 reindex 生成，只校验已在 template 中登记为 generated_by 的脚本存在
            if ($w.write_by -and $w.write_by -match 'scripts/([a-z_]+)\.cmd' -and -not $scripts.ContainsKey($Matches[1])) {
                $drift += "派生文件 $($w.name) 的生成脚本未注册：$($w.write_by)"
            }
            continue
        }
        if ($w.kind -eq 'dir') {
            if (-not (Test-Path $p -PathType Container)) { $drift += "模板目录缺失：assets/templates/$($w.name)" }
            continue
        }
        if (-not (Test-Path $p)) { $drift += "模板缺失：assets/templates/$($w.name)" }
    }
    if (Test-Path $verFile) {
        $v = ([System.IO.File]::ReadAllText($verFile, [System.Text.Encoding]::UTF8)).Trim()
        if ($v -ne [string]$reg.version) { $drift += "VERSION($v) 与 registry.json version($($reg.version)) 不一致" }
    } else { $drift += '根目录 VERSION 缺失' }
    if (Test-Path $skillFile) {
        $skillText = [System.IO.File]::ReadAllText($skillFile, [System.Text.Encoding]::UTF8)
        foreach ($s in $reg.scripts) {
            $leaf = Split-Path $s.cmd -Leaf
            if (-not $skillText.Contains($leaf)) { $drift += "SKILL.md 未登记脚本：$leaf" }
        }
        foreach ($i in $intents) {
            if (-not $skillText.Contains($i.name)) { $drift += "SKILL.md 未登记意图：$($i.name)" }
        }
    } else { $drift += 'SKILL.md 缺失' }
    foreach ($i in $intents) {
        foreach ($step in $i.chain) {
            if ($step.script -and -not $scripts.ContainsKey($step.script)) { $drift += "意图 $($i.id) 的执行链引用了未注册脚本：$($step.script)" }
        }
    }

    if ($Json) {
        [ordered]@{ status = $(if ($drift.Count) { 'drift' } else { 'ok' }); checked_at = (Get-Date -Format 'yyyy-MM-dd HH:mm'); scripts = $reg.scripts.Count; intents = $intents.Count; workspace_files = $reg.workspace.Count; drift = $drift } | ConvertTo-Json -Depth 6
    } elseif ($drift.Count -eq 0) {
        Write-Output "[自检通过] registry.json 与项目一致：脚本 $($reg.scripts.Count) 个 / 意图 $($intents.Count) 个 / 文件登记 $($reg.workspace.Count) 项"
    } else {
        Write-Output "[发现漂移] $($drift.Count) 项（registry.json 是唯一事实源，请按实际项目修正）："
        foreach ($d in $drift) { Write-Output "  · $d" }
    }
    if ($drift.Count) { exit 4 }
    exit 0
}

# ---------- -List：列出已注册的功能与脚本 ----------
if ($List) {
    if ($Json) {
        [ordered]@{ intents = $intents; scripts = $reg.scripts } | ConvertTo-Json -Depth 8
        exit 0
    }
    Write-Output "[已注册功能] $($intents.Count) 个（按优先级）："
    foreach ($i in $intents) {
        Write-Output "  $($i.priority). $($i.id)  $($i.name)  → 流程 $($i.flow)   触发词：$($i.triggers -join ' / ')"
    }
    Write-Output "[已注册脚本] $($reg.scripts.Count) 个："
    foreach ($s in $reg.scripts) {
        $codes = ($s.exit_codes.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '，'
        Write-Output "  · $(Split-Path $s.cmd -Leaf)  —— $($s.purpose)"
        Write-Output "      用法：$($s.usage)"
        Write-Output "      退出码：$codes"
    }
    exit 0
}

# ---------- -Intent <id>：输出该功能装配与执行链 ----------
if ($Intent) {
    $hit = @($intents | Where-Object { $_.id -eq $Intent })
    if ($hit.Count -eq 0) { Write-Output "[错误] 未注册的意图：$Intent（可用 -List 查看）"; exit 1 }
    $i = $hit[0]
    if ($Json) { $i | ConvertTo-Json -Depth 8; exit 0 }
    Write-Output "[意图] $($i.name)（id=$($i.id)，走 SKILL §5 流程 $($i.flow)）"
    if ($i.params.Count) { Write-Output "[必须抽取] $($i.params -join ' / ')" }
    Write-Output '[装配上下文]'
    foreach ($c in $i.context) { Write-Output "  - $c" }
    Write-Output '[执行链]'
    foreach ($step in $i.chain) {
        Write-Output "  $($step.step). $(Cmd-Line $step)"
        if ($step.expect -ne '-') { Write-Output "       期望退出码：$($step.expect)   异常：$($step.on_fail)" }
    }
    Write-Output "[输出骨架] $($i.output)"
    exit 0
}

# ---------- -Guess：按用户原话识别意图 ----------
if ($Guess) {
    $scored = @()
    foreach ($i in $intents) {
        $score = 0; $hits = @()
        foreach ($t in $i.triggers) {
            if ($Guess -like "*$t*") { $score += $t.Length; $hits += $t }
        }
        if ($score -gt 0) { $scored += [ordered]@{ intent = $i; score = $score; hits = $hits } }
    }
    if ($scored.Count -eq 0) {
        Write-Output "[无法识别] 未能从「$Guess」中判定功能。"
        Write-Output '请反问用户一次并给出三个选项：① 信息录入 / ② 信息查询 / ③ 信息修改；不猜测、不默认执行查询。'
        exit 2
    }
    $best = @($scored | Sort-Object -Property @{ Expression = { -$_.score } }, @{ Expression = { [int]$_.intent.priority } })[0]
    $i = $best.intent
    if ($Json) {
        [ordered]@{
            guess = $Guess; intent = $i.id; name = $i.name; flow = $i.flow
            score = $best.score; hits = $best.hits
            params = $i.params; context = $i.context
            chain = @($i.chain | ForEach-Object { [ordered]@{ step = $_.step; run = (Cmd-Line $_); expect = $_.expect; on_fail = $_.on_fail } })
            alternatives = @(@($scored | Where-Object { $_.intent.id -ne $i.id } | ForEach-Object { "$($_.intent.id)($($_.score))" }))
            output = $i.output
        } | ConvertTo-Json -Depth 8
        exit 0
    }
    Write-Output "[意图] $($i.name)（id=$($i.id)，流程 $($i.flow)：命中触发词 $($best.hits -join '、')）"
    Write-Output "[下一步] 先跑 resolve_workspace.cmd -Cwd <当前项目目录> 确认固定工作目录 W（唯一定位步骤）"
    if ($i.params.Count) { Write-Output "[必须抽取] $($i.params -join ' / ')" }
    Write-Output '[装配上下文]'
    foreach ($c in $i.context) { Write-Output "  - $c" }
    Write-Output '[执行链]'
    foreach ($step in $i.chain) {
        Write-Output "  $($step.step). $(Cmd-Line $step)"
        if ($step.expect -ne '-') { Write-Output "       期望退出码：$($step.expect)   异常：$($step.on_fail)" }
    }
    $alt = @($scored | Where-Object { $_.intent.id -ne $i.id })
    if ($alt.Count) { Write-Output "[备选（一句话含多功能时按 SKILL §4.2 串行）] $(($alt | ForEach-Object { "$($_.intent.name)($($_.score))" }) -join '，')" }
    Write-Output "[输出骨架] $($i.output)"
    exit 0
}

Write-Output '[用法] route.cmd -Guess "<用户原话>" | -Intent <id> | -List | -Check [-Json]'
exit 1
