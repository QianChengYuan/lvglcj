# 编译 LVGL 9.5.0 + lvglcj 垫片 → lib/sdl/（Windows x86_64，MSYS2 UCRT64 + SDL2）
#
# 前置（在 MSYS2 UCRT64 终端里执行一次）：
#   pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake `
#           mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-SDL2 `
#           mingw-w64-ucrt-x86_64-freetype mingw-w64-ucrt-x86_64-pkgconf
#
# 用法（PowerShell 7 / pwsh）：
#   ./scripts/build-lvgl-sdl.ps1                      # 自动找 LVGL 源码
#   ./scripts/build-lvgl-sdl.ps1 -LvglDir D:/lvgl     # 指定 LVGL 源码目录
#   ./scripts/build-lvgl-sdl.ps1 -Clean               # 先清掉 .build/win64/
#
# 产物：lib/windows-x64/liblvgl.a、liblvglcjshim.a（PE x86_64）
# 配置源：native/config/sdl/lv_conf.h（含 _WIN32 分支，Windows / WSL 共用同一份）
#
# 路径一律用正斜杠：MSYS2 的 gcc/cmake 对 Windows 反斜杠路径会当作转义符处理，
# 直接传 "C:\a\b" 会报 "No such file or directory"。

[CmdletBinding()]
param(
    # LVGL 上游源码目录（只读对照，勿改）。留空则自动探测。
    [string]$LvglDir = "",
    # MSYS2 根目录
    [string]$Msys2Root = "C:/msys64",
    # 是否先清理构建目录
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

function Join-P {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Parts)
    ($Parts | ForEach-Object { $_.TrimEnd('/', '\') }) -join '/'
}

$root = (Split-Path -Parent $PSScriptRoot).Replace('\', '/')
$Msys2Root = $Msys2Root.Replace('\', '/')
$bin = Join-P "$Msys2Root" "ucrt64/bin"
$inc = Join-P "$Msys2Root" "ucrt64/include"

if (-not $LvglDir) {
    # 依次尝试：环境变量 LVGL_DIR > 仓库内 lvgl/ > 仓库旁 lvgl-ref/ > 上两级旁 lvgl-ref/
    $candidates = @()
    if ($env:LVGL_DIR) { $candidates += $env:LVGL_DIR.Replace('\', '/') }
    $parent = Split-Path -Parent $root
    $candidates += (Join-P $root "lvgl")
    $candidates += (Join-P $parent "lvgl-ref")
    $candidates += (Join-P (Split-Path -Parent $parent) "lvgl-ref")
    $LvglDir = $candidates | Where-Object { Test-Path (Join-P $_ "lvgl.h") } | Select-Object -First 1
    if (-not $LvglDir) {
        throw "找不到 LVGL 源码，试过：`n  $($candidates -join "`n  ")`n请用 -LvglDir 或环境变量 LVGL_DIR 指定（目录下需有 lvgl.h）"
    }
}
$LvglDir = $LvglDir.Replace('\', '/')
if (-not (Test-Path (Join-P $LvglDir "lvgl.h"))) {
    throw "找不到 LVGL 源码：$LvglDir（用 -LvglDir 指定，需含 lvgl.h）"
}

foreach ($tool in @("gcc.exe", "cmake.exe", "ninja.exe", "ar.exe")) {
    if (-not (Test-Path (Join-P $bin $tool))) {
        throw "缺少 $tool：请先在 MSYS2 UCRT64 里安装工具链（见本脚本头部注释）"
    }
}

$env:PATH = "$bin;$env:PATH"

# 配置源：native/config/sdl/lv_conf.h（含 _WIN32 分支，Windows/Linux 共用）；
# 产物按平台分目录：lib/windows-x64（PE）、lib/linux-x64（ELF）、lib/linux-arm64（aarch64）
$confPath = Join-P $root "native/config/sdl/lv_conf.h"
$outDir = Join-P $root "lib/windows-x64"
$buildDir = Join-P $root ".build/win64"
$shimSrc = Join-P $root "native/shim/lvgl_shim.c"
$confDir = Split-Path -Parent $confPath
$shimObj = Join-P $root ".build/win64/shim/lvgl_shim.o"

if ($Clean -and (Test-Path $buildDir)) {
    Write-Host "==> 清理 $buildDir"
    Remove-Item -Recurse -Force $buildDir
}

# 注意顺序：$buildDir 可能刚被 -Clean 删掉，所以目录创建要放在清理之后
New-Item -ItemType Directory -Force $outDir, (Split-Path -Parent $shimObj) | Out-Null

Write-Host "==> cmake 配置（Windows x86_64 + SDL2）"
Write-Host "    LVGL 源码：$LvglDir"
Write-Host "    配置源  ：$confPath"
# LVGL 9.5 用 LV_BUILD_CONF_PATH；旧名 LV_CONF_PATH 会被静默忽略。
# FreeType 头文件要显式加进 include 路径（LVGL 的 CMake 不管 freetype 依赖）。
& cmake -B $buildDir -G Ninja -S $LvglDir `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ `
    "-DLV_BUILD_CONF_PATH=$confPath" `
    -DCONFIG_LV_BUILD_EXAMPLES=OFF -DCONFIG_LV_BUILD_DEMOS=OFF `
    -DCONFIG_LV_USE_THORVG_INTERNAL=OFF `
    "-DCMAKE_C_FLAGS=-I$inc -I$inc/freetype2" `
    "-DCMAKE_CXX_FLAGS=-I$inc -I$inc/freetype2"
if ($LASTEXITCODE -ne 0) { throw "cmake 配置失败" }

Write-Host "==> 编译 liblvgl.a"
& cmake --build $buildDir
if ($LASTEXITCODE -ne 0) { throw "LVGL 编译失败" }

Write-Host "==> 编译 C 垫片 liblvglcjshim.a"
# 垫片用 LV_CONF_INCLUDE_SIMPLE + -I 配置目录 找 lv_conf.h，避免路径引号转义
& gcc -c -O2 -Wall -Wextra `
    -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE `
    "-I$LvglDir" "-I$confDir" "-I$inc" "-I$inc/freetype2" `
    -o $shimObj $shimSrc
if ($LASTEXITCODE -ne 0) { throw "垫片编译失败" }

& ar rcs (Join-P $outDir "liblvglcjshim.a") $shimObj
if ($LASTEXITCODE -ne 0) { throw "垫片打包失败" }

$builtLib = Join-P $buildDir "lib/liblvgl.a"
if (-not (Test-Path $builtLib)) { throw "未找到产物 $builtLib" }
Copy-Item $builtLib (Join-P $outDir "liblvgl.a") -Force

Write-Host "==> 完成：$outDir"
Get-ChildItem $outDir -Filter "*.a" | ForEach-Object { "    $($_.Name)  $($_.Length) 字节" }
Write-Host ""
Write-Host "下一步："
Write-Host "    $env:LVGLCJ_LIB_DIR = 'lib/windows-x64'"
Write-Host "    cd examples; cjpm build --cfg"
Write-Host "运行前把 SDL2 / FreeType 的 DLL 目录加进 PATH："
Write-Host "    `$env:PATH = '$bin;' + `$env:PATH"
