# init_workspace.ps1 —— 网申工作台幂等初始化：复制模板，已存在文件一律跳过，绝不覆盖用户数据
# 用法：init_workspace.ps1 <工作目录>     退出码：0 成功（含全部跳过）；1 错误
param([Parameter(Position = 0, Mandatory = $true)][string]$Workspace)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$templateDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\templates'
if (-not (Test-Path $templateDir -PathType Container)) {
    Write-Output "[错误] 找不到模板目录：$templateDir"
    exit 1
}

$ws = [System.IO.Path]::GetFullPath($Workspace)
New-Item -ItemType Directory -Path $ws -Force | Out-Null

$created = @(); $skipped = @()
Get-ChildItem $templateDir -Recurse -File | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($templateDir.Length).TrimStart('\', '/')
    $dst = Join-Path $ws $rel
    if (Test-Path $dst) {
        $skipped += $rel
    } else {
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
        Copy-Item $_.FullName $dst
        $created += $rel
    }
}

Write-Output "工作目录：$ws"
Write-Output "新建 $($created.Count) 个文件："
$created | ForEach-Object { Write-Output "  + $_" }
Write-Output "跳过 $($skipped.Count) 个已存在文件（未改动）："
$skipped | ForEach-Object { Write-Output "  = $_" }
if ($created.Count -eq 0) { Write-Output '工作目录已完整，无需新建。' }
Write-Output ''
Write-Output '下一步（必做）：运行 scripts\reindex.cmd "<工作目录>" 生成 12_索引（查询/修改/查重的检索入口）。'
exit 0
