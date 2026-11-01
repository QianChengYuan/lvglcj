#!/usr/bin/env pwsh
# 一键构建并「自包含」运行 examples：
#   1) 自动挑预编译库目录并注入 LVGLCJ_LIB_DIR（不设这个变量 cjpm 会报
#      can not find the library 'lvgl' which is listed in 'ffi.c' field）
#   2) cjpm build --cfg
#   3) 把 SDL2 / FreeType 及其依赖 DLL 拷到产物目录，省去每次改 PATH
#
# 用法：
#   pwsh scripts/build-example.ps1                  # 构建 + 拷 DLL
#   pwsh scripts/build-example.ps1 -Run all         # 构建后直接跑 `main all`
#   pwsh scripts/build-example.ps1 -LibDir lib/windows-x64
#   pwsh scripts/build-example.ps1 -Target aarch64-unknown-linux-gnu -Backend sdl
#
# -Target 按目标三元组选库目录（cjpm 1.2.0 不支持 [target.<triple>.ffi.c]，只能脚本做）：
#   x86_64-w64-mingw32 → lib/windows-x64
#   x86_64-unknown-linux-gnu → lib/linux-x64
#   aarch64-unknown-linux-gnu → lib/linux-arm64-sdl（-Backend drm 时 lib/linux-arm64）
param(
    [string]$LibDir = "",
    [string]$Run = "",
    [string]$Target = "",
    [string]$Backend = "sdl"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Examples = Join-Path $Root "examples"

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
        default { throw "未知目标三元组 '$triple'" }
    }
}

if ($LibDir -eq "" -and $Target -ne "") {
    $LibDir = Resolve-LibDirForTarget $Target $Backend
}
if ($LibDir -eq "") {
    if ($IsWindows) {
        $LibDir = "lib/windows-x64"
    } elseif ($IsMacOS) {
        $LibDir = "lib/macos-arm64"
    } else {
        $LibDir = "lib/linux-x64"
    }
}
$LibAbs = (Resolve-Path (Join-Path $Root $LibDir)).Path
$env:LVGLCJ_LIB_DIR = $LibAbs
Write-Host "[build-example] LVGLCJ_LIB_DIR=$LibAbs"

Push-Location $Examples
try {
    $hostTriple = if ($IsWindows) {
        "x86_64-w64-mingw32"
    } elseif ($IsMacOS) {
        if ((& uname -m).Trim() -eq "arm64") { "aarch64-apple-darwin" } else { "x86_64-apple-darwin" }
    } else {
        $m = (& uname -m).Trim()
        if ($m -eq "aarch64" -or $m -eq "arm64") { "aarch64-unknown-linux-gnu" } else { "x86_64-unknown-linux-gnu" }
    }
    if ($Target -ne "" -and $Target -ne $hostTriple) {
        if ($Target -eq "aarch64-unknown-linux-gnu" -and -not $env:LVGLCJ_AARCH64_SDL_LIB) {
            Write-Host "[build-example] 交叉到 aarch64 需要 LVGLCJ_AARCH64_SDL_LIB（aarch64 的 SDL2/FreeType 库目录）"
        }
        if ($Target -eq "aarch64-unknown-linux-gnu" -and $env:CANGJIE_HOME `
            -and -not (Test-Path (Join-Path $env:CANGJIE_HOME "modules/linux_aarch64_cjnative"))) {
            Write-Host "[build-example] 警告：$env:CANGJIE_HOME/modules/linux_aarch64_cjnative 不存在，cjc 交叉编译会失败" -ForegroundColor Yellow
        }
        cjpm build --cfg --target $Target
    } else {
        cjpm build --cfg
    }
    if ($LASTEXITCODE -ne 0) {
        throw "cjpm build 失败（exit $LASTEXITCODE）"
    }

    $BinDir = Join-Path $Examples "target/release/bin"
    if ($IsWindows) {
        # liblvgl.a 带不出 SDL2 / FreeType；而 MSYS2 的 libfreetype-6.dll 自己又依赖
        # libstdc++-6.dll、libgcc_s_seh-1.dll、libbrotli*、libpng16-16、zlib1，
        # 全拷到 exe 旁边，双击/在任意目录下都能直接跑。
        $Msys = "C:\msys64\ucrt64\bin"
        $Dlls = @(
            "SDL2.dll",
            "libfreetype-6.dll",
            "libstdc++-6.dll",
            "libgcc_s_seh-1.dll",
            # libstdc++-6.dll / libgcc_s_seh-1.dll 自己又依赖 libwinpthread-1.dll，
            # 少了它会在启动时直接 0xC0000139（entry point not found）。
            "libwinpthread-1.dll",
            "libbrotlidec.dll",
            "libbrotlicommon.dll",
            "libpng16-16.dll",
            "zlib1.dll",
            "libbz2-1.dll",
            "libharfbuzz-0.dll",
            "libglib-2.0-0.dll",
            "libgraphite2.dll",
            "libintl-8.dll",
            "libpcre2-8-0.dll",
            "libiconv-2.dll"
        )
        foreach ($d in $Dlls) {
            $src = Join-Path $Msys $d
            if (Test-Path $src) {
                Copy-Item $src $BinDir -Force
            }
        }
        # 仓颉运行时的两个 DLL 也要在 exe 旁边（否则要 cjc 的 runtime 目录在 PATH）
        $CjRuntime = Join-Path $env:CANGJIE_HOME "runtime/lib/windows_x86_64_cjnative"
        if (Test-Path $CjRuntime) {
            foreach ($d in @("libboundscheck.dll", "libcangjie-runtime.dll")) {
                $src = Join-Path $CjRuntime $d
                if (Test-Path $src) { Copy-Item $src $BinDir -Force }
            }
        }
        $Exe = Join-Path $BinDir "main.exe"
        Write-Host "[build-example] 产物：$Exe"
        if ($Run -ne "") { & $Exe $Run }
        else { Write-Host "[build-example] 直接运行：`"$Exe`" all" }
    } else {
        $Exe = Join-Path $BinDir "main"
        Write-Host "[build-example] 产物：$Exe"
        if ($Run -ne "") { & $Exe $Run }
        else { Write-Host "[build-example] 直接运行：`"$Exe`" all" }
    }
} finally {
    Pop-Location
}
