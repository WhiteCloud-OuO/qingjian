<#
.SYNOPSIS
  把青简项目指定目录导出成单文件 TXT：先目录树，再按路径拼接每个文本文件内容。
  输出为 UTF-8 无 BOM，方便直接上传。

.EXAMPLE
  # 导出整个项目（不含 target/.git 等）
  .\Export-Source.ps1

  # 只导出跟本次改动相关的三块
  .\Export-Source.ps1 -Include "crates\qingjian-platform","apps\settings","apps\windows\server"

  # 自定义输出文件名
  .\Export-Source.ps1 -Out "qingjian-config-dump.txt"
#>
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,

    [string]$Out = "qingjian-dump.txt",

    # 只导出这些子目录（相对 Root）；为空则导出整个 Root
    [string[]]$Include = @(),

    # 跳过这些目录名（任意层级匹配）
    [string[]]$ExcludeDir = @('.git', 'target', 'node_modules', 'dist', 'build', '.idea', '.vscode', 'bin', 'obj', '.vs'),

    # 只拼接这些扩展名的文件
    [string[]]$Extensions = @('.rs', '.toml', '.md', '.json', '.txt', '.ps1', '.bat', '.yml', '.yaml'),

    # 单文件超过这个大小（KB）就跳过内容，只在目录树里列出
    [int]$MaxFileKB = 512
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path -LiteralPath $Root).Path
$OutPath = [System.IO.Path]::GetFullPath((Join-Path $Root $Out))

# 计算实际扫描的起点
$scanRoots = if ($Include.Count -gt 0) {
    $Include | ForEach-Object {
        $p = Join-Path $Root $_
        if (-not (Test-Path -LiteralPath $p)) {
            Write-Warning "跳过不存在的路径: $p"
            return
        }
        (Resolve-Path -LiteralPath $p).Path
    }
} else {
    @($Root)
}
$scanRoots = @($scanRoots)

# ---------- 收集文件 ----------
function Get-ProjectFiles {
    param([string[]]$Roots, [string[]]$ExcludeDir, [string[]]$Extensions, [string]$OutPath)

    foreach ($r in $Roots) {
        Get-ChildItem -LiteralPath $r -Recurse -File -Force | Where-Object {
            $path = $_.FullName
            if ($path -eq $OutPath) { return $false }
            $parts = $path -split '[\\/]'
            foreach ($d in $ExcludeDir) {
                if ($parts -contains $d) { return $false }
            }
            if ($Extensions.Count -gt 0 -and ($Extensions -notcontains $_.Extension.ToLower())) {
                return $false
            }
            return $true
        }
    }
}

$allFiles = @(Get-ProjectFiles -Roots $scanRoots -ExcludeDir $ExcludeDir -Extensions $Extensions -OutPath $OutPath |
    Sort-Object FullName)

Write-Host ("扫描到 {0} 个文件" -f $allFiles.Count) -ForegroundColor Cyan

# ---------- 组装输出 ----------
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine("# 青简源码导出")
$null = $sb.AppendLine("# Root: $Root")
$null = $sb.AppendLine("# 导出时间: $(Get-Date -Format o)")
$null = $sb.AppendLine("# 文件数: $($allFiles.Count)")
$null = $sb.AppendLine()

# ---------- 目录树 ----------
$null = $sb.AppendLine("=" * 80)
$null = $sb.AppendLine("## 目录结构")
$null = $sb.AppendLine("=" * 80)
$null = $sb.AppendLine()

function Write-Tree {
    param([string]$Path, [string]$Prefix, [System.Text.StringBuilder]$Sb,
          [string[]]$ExcludeDir, [string[]]$Extensions)

    $items = @(Get-ChildItem -LiteralPath $Path -Force | Where-Object {
        if ($_.PSIsContainer -and ($ExcludeDir -contains $_.Name)) { return $false }
        if ((-not $_.PSIsContainer) -and $Extensions.Count -gt 0 -and ($Extensions -notcontains $_.Extension.ToLower())) { return $false }
        return $true
    } | Sort-Object @{Expression={$_.PSIsContainer}; Descending=$true}, Name)

    $count = $items.Count
    for ($i = 0; $i -lt $count; $i++) {
        $item = $items[$i]
        $isLast = ($i -eq $count - 1)
        $branch = if ($isLast) { '└── ' } else { '├── ' }
        $nextPrefix = $Prefix + $(if ($isLast) { '    ' } else { '│   ' })

        if ($item.PSIsContainer) {
            $null = $Sb.AppendLine("$Prefix$branch$($item.Name)/")
            Write-Tree -Path $item.FullName -Prefix $nextPrefix -Sb $Sb -ExcludeDir $ExcludeDir -Extensions $Extensions
        } else {
            $null = $Sb.AppendLine("$Prefix$branch$($item.Name)")
        }
    }
}

foreach ($r in $scanRoots) {
    $name = if ($r -eq $Root) { '.' } else { $r.Substring($Root.Length).TrimStart('\') }
    $null = $sb.AppendLine("$name/")
    Write-Tree -Path $r -Prefix '' -Sb $sb -ExcludeDir $ExcludeDir -Extensions $Extensions
    $null = $sb.AppendLine()
}

# ---------- 文件内容 ----------
$null = $sb.AppendLine("=" * 80)
$null = $sb.AppendLine("## 文件内容")
$null = $sb.AppendLine("=" * 80)
$null = $sb.AppendLine()

$skipped = 0
$written = 0
foreach ($f in $allFiles) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
    $sizeKB = [math]::Round($f.Length / 1KB, 1)

    $null = $sb.AppendLine()
    $null = $sb.AppendLine("=" * 80)
    $null = $sb.AppendLine("### FILE: $rel  ($sizeKB KB)")
    $null = $sb.AppendLine("=" * 80)

    if ($sizeKB -gt $MaxFileKB) {
        $null = $sb.AppendLine("[跳过：文件过大，$sizeKB KB > $MaxFileKB KB]")
        $skipped++
        continue
    }

    try {
        $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop
        if ($null -eq $text) { $text = "" }
        $null = $sb.Append($text)
        if (-not $text.EndsWith("`n")) { $null = $sb.AppendLine() }
        $written++
    } catch {
        $null = $sb.AppendLine("[读取失败: $($_.Exception.Message)]")
    }
}

$null = $sb.AppendLine()
$null = $sb.AppendLine("=" * 80)
$null = $sb.AppendLine("# 结束：写入 $written 个文件，跳过 $skipped 个（超过 $MaxFileKB KB）")
$null = $sb.AppendLine("=" * 80)

# ---------- 写文件（UTF-8 无 BOM） ----------
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutPath, $sb.ToString(), $utf8NoBom)

$finalKB = [math]::Round((Get-Item -LiteralPath $OutPath).Length / 1KB, 1)
Write-Host "已写出: $OutPath ($finalKB KB)" -ForegroundColor Green