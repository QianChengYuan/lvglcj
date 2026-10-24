# 静态检查 + 格式检查（仓颉 1.2.0：cjlint / cjfmt）
#
# 用法（PowerShell 7 / pwsh）：
#   ./scripts/check.ps1                 # 检查 src/ 与 examples/，不改文件
#   ./scripts/check.ps1 -Fix            # 先用 cjfmt 就地格式化，再重新检查
#   ./scripts/check.ps1 -SkipExamples   # 只查库源码
#   ./scripts/check.ps1 -SkipLint       # 只查格式
#   ./scripts/check.ps1 -SkipFormat     # 只跑静态检查
#
# 说明：
# - cjfmt 没有 --check 模式，这里先格式化到 target/check/fmt/，再逐文件与原文比对，
#   因此行尾（LF/CRLF）和末尾换行的差异也能查出来。
# - 项目根存在 cangjie-format.toml 时显式传给 cjfmt，避免 SDK 默认配置变化导致判定漂移。
# - cjlint 的 -m 必须指向 CANGJIE_HOME 根目录（不是 modules/ 子目录），
#   否则会报 "Can not find modules"。
# - cjlint 的 SUGGESTIONS 不判定失败，只做汇总；ERROR / WARNING 才返回非零。
# - 报告与格式化副本都落在 target/check/ 下（target/ 已被 .gitignore 忽略）。
#
# 退出码：0 通过；1 格式不一致；2 静态检查有 ERROR/WARNING；3 两者都有。

[CmdletBinding()]
param(
    # 就地格式化（等价于对不一致文件执行 cjfmt -f）
    [switch]$Fix,
    # 跳过 examples/ 目录
    [switch]$SkipExamples,
    # 跳过格式检查
    [switch]$SkipFormat,
    # 跳过静态检查
    [switch]$SkipLint
)

$ErrorActionPreference = "Stop"

$root = (Split-Path -Parent $PSScriptRoot).Replace('\', '/')
$checkDir = "$root/target/check"
$fmtRoot = "$checkDir/fmt"
$lintRoot = "$checkDir/cjlint"

function Resolve-CjTool {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "找不到 $Name，请先把仓颉 SDK 的 tools/bin 加入 PATH（本地执行 envsetup.ps1 / source envsetup.sh，CI 由 setup-cangjie 处理）"
    }
    return $cmd.Source
}

$cjfmt = Resolve-CjTool "cjfmt"
$cjlint = Resolve-CjTool "cjlint"

# cjlint -m 要的是 CANGJIE_HOME 根目录：优先环境变量，否则由 <home>/tools/bin/cjlint.exe 反推
if ($env:CANGJIE_HOME -and (Test-Path (Join-Path $env:CANGJIE_HOME "modules"))) {
    $cjHome = $env:CANGJIE_HOME
} else {
    $cjHome = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $cjlint))
}
if (-not (Test-Path (Join-Path $cjHome "modules"))) {
    throw "无法定位 CANGJIE_HOME（需要其下有 modules/），请设置环境变量 CANGJIE_HOME"
}

$formatDirs = @("src")
if (-not $SkipExamples) { $formatDirs += "examples" }

# 项目级格式配置（显式指定，保证 CI 与本地使用同一套规则）
$formatConfig = Join-Path $root "cangjie-format.toml"
if (-not (Test-Path $formatConfig)) { $formatConfig = $null }

function Invoke-FormatCheck {
    param([string[]]$Dirs)

    $bad = @()
    foreach ($dir in $Dirs) {
        $srcDir = Join-Path $root $dir
        if (-not (Test-Path $srcDir)) { continue }

        $dstDir = Join-Path $fmtRoot $dir
        Remove-Item -Recurse -Force $dstDir -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        $fmtArgs = @("-d", $srcDir, "-o", $dstDir)
        if ($formatConfig) { $fmtArgs += @("-c", $formatConfig) }
        & $cjfmt @fmtArgs | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "cjfmt 执行失败：$dir" }

        $files = @(Get-ChildItem -Recurse -File -Filter *.cj $srcDir)
        # cjfmt -o 在部分路径形态下会把输入目录的最后一级再套一层，这里自动识别输出根
        $outRoot = $dstDir
        $nested = Join-Path $dstDir (Split-Path -Leaf $srcDir)
        if (Test-Path $nested) { $outRoot = $nested }

        foreach ($f in $files) {
            $rel = $f.FullName.Substring($srcDir.Length).TrimStart('\', '/')
            $dstFile = Join-Path $outRoot $rel
            if (-not (Test-Path $dstFile)) {
                $bad += $f.FullName
                continue
            }
            $actual = [IO.File]::ReadAllText($f.FullName)
            $expect = [IO.File]::ReadAllText($dstFile)
            if ($actual -cne $expect) {
                $bad += $f.FullName
            }
        }
        Write-Host ("  格式检查 {0}：{1} 个文件" -f $dir, $files.Count)
    }
    return $bad
}

function Invoke-Lint {
    $report = Join-Path $lintRoot "cjlint-report.json"
    New-Item -ItemType Directory -Force -Path $lintRoot | Out-Null
    Remove-Item $report -Force -ErrorAction SilentlyContinue

    # cjlint 只接受完整的 config 目录（cjlint_rule_list.json + 各规则参数文件），
    # 因此运行时从当前 SDK 复制一份，再用仓库里的豁免名单覆盖 exclude_lists.json：
    # 规则文件始终跟随 SDK，项目只维护豁免项。
    $cfgDir = Join-Path $lintRoot "config"
    Remove-Item -Recurse -Force $cfgDir -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    Copy-Item (Join-Path $cjHome "tools/config/*") $cfgDir -Recurse -Force

    $excludeFile = Join-Path $root "tools/cjlint/exclude_lists.json"
    if (Test-Path $excludeFile) {
        Copy-Item $excludeFile (Join-Path $cfgDir "exclude_lists.json") -Force
    } else {
        Write-Host "  未找到 tools/cjlint/exclude_lists.json，使用 SDK 默认豁免" -ForegroundColor Yellow
    }

    & $cjlint -f (Join-Path $root "src") -m $cjHome -c $lintRoot -o $report
    $lintExit = $LASTEXITCODE
    if (-not (Test-Path $report)) {
        throw "cjlint 执行失败（exit=$lintExit），未生成报告"
    }

    $items = @()
    if (Test-Path $report) {
        $raw = Get-Content $report -Raw
        if ($raw -and $raw.Trim()) {
            $parsed = $raw | ConvertFrom-Json
            if ($null -ne $parsed) { $items = @($parsed) }
        }
    }

    $errors = @($items | Where-Object { $_.defectLevel -eq 'ERROR' })
    $warnings = @($items | Where-Object { $_.defectLevel -eq 'WARNING' })
    $suggestions = @($items | Where-Object { $_.defectLevel -eq 'SUGGESTIONS' })

    Write-Host ("  静态检查：ERROR {0} / WARNING {1} / SUGGESTIONS {2}" -f `
            $errors.Count, $warnings.Count, $suggestions.Count)

    $problems = @($errors) + @($warnings)
    if ($problems.Count -gt 0) {
        Write-Host "  需要处理：" -ForegroundColor Red
        $problems | Select-Object -First 20 | ForEach-Object {
            $rel = $_.file.Substring($root.Length).TrimStart('\', '/')
            Write-Host ("    {0}:{1}:{2}  {3}" -f $rel, $_.line, $_.column, $_.description) `
                -ForegroundColor Red
        }
        if ($problems.Count -gt 20) {
            Write-Host ("    ……另有 {0} 条，见报告" -f ($problems.Count - 20)) -ForegroundColor Red
        }
    }

    if ($suggestions.Count -gt 0) {
        Write-Host "  按规则汇总（建议级）："
        $suggestions | Group-Object defectType | Sort-Object Count -Descending | ForEach-Object {
            Write-Host ("    {0,4}  {1}" -f $_.Count, $_.Name)
        }
    }

    Write-Host "  报告：$report"
    return ($problems.Count -gt 0)
}

Write-Host "CANGJIE_HOME = $cjHome"

$code = 0
if (-not $SkipFormat) {
    $bad = @(Invoke-FormatCheck $formatDirs)

    if ($bad.Count -gt 0 -and $Fix) {
        Write-Host ("  发现 {0} 个文件格式不一致，正在就地格式化……" -f $bad.Count)
        foreach ($f in $bad) {
            $fixArgs = @("-f", $f)
            if ($formatConfig) { $fixArgs += @("-c", $formatConfig) }
            & $cjfmt @fixArgs | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "cjfmt -f 执行失败：$f" }
        }
        $bad = @(Invoke-FormatCheck $formatDirs)
    }

    if ($bad.Count -eq 0) {
        Write-Host "格式检查通过" -ForegroundColor Green
    } else {
        Write-Host ("格式检查失败：{0} 个文件需要格式化（可加 -Fix 自动修复）" -f $bad.Count) `
            -ForegroundColor Yellow
        $bad | ForEach-Object { Write-Host ("    " + $_.Substring($root.Length).TrimStart('\', '/')) }
        $code = $code -bor 1
    }
}

if (-not $SkipLint) {
    $lintFailed = Invoke-Lint
    if ($lintFailed) {
        Write-Host "静态检查未通过（存在 ERROR/WARNING）" -ForegroundColor Red
        $code = $code -bor 2
    } else {
        Write-Host "静态检查通过（无 ERROR/WARNING）" -ForegroundColor Green
    }
}

if ($code -eq 0) {
    Write-Host "全部检查通过" -ForegroundColor Green
}
exit $code
