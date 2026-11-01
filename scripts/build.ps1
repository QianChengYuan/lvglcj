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
#   ./scripts/build.ps1 -Target aarch64-unknown-linux-gnu -Backend sdl   # 按目标三元组选库
#   ./scripts/build.ps1 -NoMsys2Path        # 不自动把 MSYS2 UCRT64 加进 PATH
#
# 目标三元组 → 预编译库（与 -Target 一起用时生效，仍可用 -LibDir 手动覆盖）：
#   x86_64-w64-mingw32           → lib/windows-x64
#   x86_64-unknown-linux-gnu     → lib/linux-x64
#   aarch64-unknown-linux-gnu    → lib/linux-arm64-sdl（-Backend drm 时用 lib/linux-arm64）
#   aarch64-apple-darwin         → lib/macos-arm64
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
    # 预编译静态库目录（默认：-Target 映射 > 已有环境变量 > 按平台猜）
    [string]$LibDir = "",
    # 目标三元组（交叉编译用，如 aarch64-unknown-linux-gnu）；同时决定 lib 目录
    [string]$Target = "",
    # aarch64 用哪个后端产物：sdl（默认，桌面）| drm（tty 独占）
    [string]$Backend = "sdl",
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

# 按目标三元组映射到预编译库目录。cjpm 1.2.0 **不支持** [target.<triple>.ffi.c]
# （实测被忽略，仍读全局 [ffi.c]），所以三元组 → 库目录只能由脚本做。
function Resolve-LibDirForTarget([string]$triple, [string]$backend) {
    switch ($triple) {
        "x86_64-w64-mingw32" { return "lib/windows-x64" }
        "x86_64-unknown-linux-gnu" { return "lib/linux-x64" }
        "aarch64-unknown-linux-gnu" {
            if ($backend -eq "drm") { return "lib/linux-arm64" }
            return "lib/linux-arm64-sdl"
        }
        "aarch64-apple-darwin" { return "lib/macos-arm64" }
        "x86_64-apple-darwin" { return "lib/macos-x64" }
        default {
            throw "未知目标三元组 '$triple'。可用：x86_64-w64-mingw32 / x86_64-unknown-linux-gnu / aarch64-unknown-linux-gnu / aarch64-apple-darwin"
        }
    }
}

# 1) 决定库目录：-LibDir > -Target 映射 > 环境变量 > 平台猜测
if ($LibDir -ne "") {
    $libDir = $LibDir
} elseif ($Target -ne "") {
    $libDir = Resolve-LibDirForTarget $Target $Backend
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
# 目标三元组与宿主一致时不必传 --target（cjpm 会打一条 "will be ignored" 的告警）
$hostTriple = if ($env:OS -eq "Windows_NT") {
    "x86_64-w64-mingw32"
} elseif ($IsMacOS) {
    if ((& uname -m).Trim() -eq "arm64") { "aarch64-apple-darwin" } else { "x86_64-apple-darwin" }
} else {
    $m = (& uname -m).Trim()
    if ($m -eq "aarch64" -or $m -eq "arm64") { "aarch64-unknown-linux-gnu" } else { "x86_64-unknown-linux-gnu" }
}

# cjc 交叉编译要有对应平台的 stdlib 模块（$env:CANGJIE_HOME/modules/<arch>_<os>_cjnative），
# 官方 SDK 只带 linux_x86_64 / windows_x86_64；缺 aarch64 时 cjc 会报
#   error: failed to detect cangjie modules, reason: target library path is not exist
function Test-TargetModules([string]$triple) {
    $mod = switch ($triple) {
        "aarch64-unknown-linux-gnu" { "linux_aarch64_cjnative" }
        "x86_64-unknown-linux-gnu" { "linux_x86_64_cjnative" }
        "x86_64-w64-mingw32" { "windows_x86_64_cjnative" }
        default { "" }
    }
    if ($mod -eq "" -or -not $env:CANGJIE_HOME) { return }
    if (-not (Test-Path (Join-Path $env:CANGJIE_HOME "modules/$mod"))) {
        Write-Host "[build] 警告：$env:CANGJIE_HOME/modules/$mod 不存在，cjc 交叉编译会失败；需要带目标平台 stdlib 模块的 SDK" -ForegroundColor Yellow
    }
}

$cjpmArgs = @("build")
if ($Release) { $cjpmArgs += "--release" }
if ($Target -ne "" -and $Target -ne $hostTriple) {
    Test-TargetModules $Target
    $cjpmArgs += "--target"; $cjpmArgs += $Target
}
Write-Host "==> cjpm $($cjpmArgs -join ' ')"
& cjpm @cjpmArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 5) examples（独立模块，需 --cfg 打开自定义构建开关）
if ($Examples) {
    # 交给 build-example.ps1：它除了 cjpm build --cfg，还会把 SDL2/FreeType/
    # libstdc++/libwinpthread 与仓颉运行时的 DLL 拷到产物目录，省去运行前改 PATH。
    Write-Host "==> examples: build-example.ps1"
    & (Join-Path $PSScriptRoot "build-example.ps1") -LibDir $libDir -Target $Target -Backend $Backend
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
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
