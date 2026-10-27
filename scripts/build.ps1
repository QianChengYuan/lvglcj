# 一键构建（Windows / PowerShell 7）
#
# 目的：`cjpm.toml` 里 `[ffi.c] path = "${LVGLCJ_LIB_DIR}"` 不支持默认值
# （cjpm 1.2.0 没有 ${VAR:-默认} 语法），新克隆的仓库不设变量就构建失败。
# 本脚本自动选预编译库目录、注入环境变量，再交给 cjpm。
#
# 用法：
#   ./scripts/build.ps1                     # 库，debug
#   ./scripts/build.ps1 -Release            # 库，release
#   ./scripts/build.ps1 -Examples           # 库 + examples（--cfg）
#   ./scripts/build.ps1 -Test               # 库 + 单元测试
#   ./scripts/build.ps1 -LibDir lib/linux-x64
#   ./scripts/build.ps1 -NoMsys2Path        # 不自动把 MSYS2 UCRT64 加进 PATH
#
# 说明：
# - 已有的 $env:LVGLCJ_LIB_DIR 会被沿用（显式传 -LibDir 可覆盖）；两者都没有才按平台猜。
# - 注入的是**绝对路径**：examples 是独立模块，cjpm 会拿相对路径去根模块解析，
#   写 "lib/windows-x64" 时从 examples 里构建会找不到库。
# - Windows 上 gcc 找不到 UCRT64 的 bin 时会静默 exit 1 且无任何输出，
#   所以这里默认把 C:\msys64\ucrt64\bin 前置到 PATH（不存在则跳过）。
#
# 退出码：0 成功；1 参数/环境问题；其余为 cjpm 的退出码。

[CmdletBinding()]
param(
    # 预编译静态库目录（默认：已有环境变量 > 按平台猜）
    [string]$LibDir = "",
    # 同时构建 examples（cjpm build --cfg）
    [switch]$Examples,
    # release 构建
    [switch]$Release,
    # 构建后跑单元测试（默认排除 requires_display 用例）
    [switch]$Test,
    # 构建后跑 requires_display 用例（无头环境靠 SDL dummy 驱动）
    [switch]$DisplayTests,
    # 不自动把 MSYS2 UCRT64 加进 PATH
    [switch]$NoMsys2Path
)

$ErrorActionPreference = "Stop"

$root = (Split-Path -Parent $PSScriptRoot).Replace('\', '/')

function Resolve-DefaultLibDir {
    if ($env:OS -eq "Windows_NT") {
        return "lib/windows-x64"
    }
    $arch = (& uname -m).Trim()
    if ($arch -eq "aarch64" -or $arch -eq "arm64") {
        # 桌面上跑用 SDL 版；只有 DRM 版时才退回
        if (Test-Path (Join-Path $root "lib/linux-arm64-sdl/liblvgl.a")) {
            return "lib/linux-arm64-sdl"
        }
        return "lib/linux-arm64"
    }
    return "lib/linux-x64"
}

# 1) 决定库目录：显式参数 > 环境变量 > 平台猜测
if ($LibDir -ne "") {
    $libDir = $LibDir
} elseif ($env:LVGLCJ_LIB_DIR) {
    $libDir = $env:LVGLCJ_LIB_DIR
} else {
    $libDir = Resolve-DefaultLibDir
}

# 2) 转绝对路径并校验产物
$libAbs = if ([System.IO.Path]::IsPathRooted($libDir)) {
    $libDir.Replace('\', '/')
} else {
    (Join-Path $root $libDir).Replace('\', '/')
}
foreach ($f in @("liblvgl.a", "liblvglcjshim.a")) {
    $p = Join-Path $libAbs $f
    if (-not (Test-Path $p)) {
        throw "缺少 $p`n可选目录：" + ((Get-ChildItem (Join-Path $root "lib") -Directory | ForEach-Object { "lib/" + $_.Name }) -join "、")
    }
}
$env:LVGLCJ_LIB_DIR = $libAbs
Write-Host "LVGLCJ_LIB_DIR = $libAbs"

# 3) Windows：把 MSYS2 UCRT64 挪到 PATH **最前面**
#    不只是"加进去"：仓颉 SDK 的 tools\bin 里也有 libwinpthread-1.dll 等运行库，
#    顺序反了会加载到不匹配的 DLL（症状：unittest 启动即 0xC0000139 入口点找不到，
#    或 gcc 静默 exit 1 且无输出）。
if (-not $NoMsys2Path -and $env:OS -eq "Windows_NT") {
    $ucrt = "C:\msys64\ucrt64\bin"
    if (Test-Path $ucrt) {
        $rest = $env:PATH -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $ucrt) }
        $env:PATH = ($ucrt, ($rest -join ';')) -join ';'
        Write-Host "PATH 首位已设为 $ucrt"
    }
}

# 4) 构建
$cjpmArgs = @("build")
if ($Release) { $cjpmArgs += "--release" }
Write-Host "==> cjpm $($cjpmArgs -join ' ')"
& cjpm @cjpmArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 5) examples（独立模块，需 --cfg 打开自定义构建开关）
if ($Examples) {
    Write-Host "==> examples: cjpm build --cfg"
    Push-Location (Join-Path $root "examples")
    try {
        & cjpm build --cfg
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally {
        Pop-Location
    }
}

# 6) 测试
if ($Test) {
    Write-Host "==> cjpm test"
    & cjpm test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# requires_display 用例单独一轮：dummy 视频驱动让无头环境也能建出 display，
# 注意要同时 --exclude-tags=notag 顶掉 [profile.test] 里默认的排除项。
if ($DisplayTests) {
    if (-not $env:SDL_VIDEODRIVER) { $env:SDL_VIDEODRIVER = "dummy" }
    Write-Host "==> cjpm test --include-tags=requires_display --exclude-tags=notag"
    & cjpm test --include-tags=requires_display --exclude-tags=notag
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "全部完成"
