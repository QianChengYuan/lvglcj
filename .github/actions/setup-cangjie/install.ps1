# install.ps1 — 仓颉 SDK 安装脚本（Windows）
# 由 .github/actions/setup-cangjie composite action 调用。
# 通过环境变量传参：INPUT_OS / INPUT_VERSION / INPUT_URL_OVERRIDE / INPUT_SHA_OVERRIDE。
#
# 安装目录固定为 %RUNNER_TEMP%\cangjie-sdk，由 composite action 中的 actions/cache 缓存；
# 缓存命中时跳过下载，直接复用已解压的 SDK。

$ErrorActionPreference = "Stop"

$InputOS      = if ($env:INPUT_OS)      { $env:INPUT_OS }      else { "windows" }
$InputVersion = if ($env:INPUT_VERSION) { $env:INPUT_VERSION } else { "1.2.0" }
$InputURL     = if ($env:INPUT_URL_OVERRIDE) { $env:INPUT_URL_OVERRIDE } else { "" }
$InputSHA     = if ($env:INPUT_SHA_OVERRIDE) { $env:INPUT_SHA_OVERRIDE } else { "" }

$runnerTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$sdkDir = Join-Path $runnerTemp "cangjie-sdk"
$marker = Join-Path $sdkDir ".installed"

# 内置下载源表：objectKey 与 SDK 版本一一对应，换版本必须换 key。
# SHA-256 同表硬编码，下载后强制校验。
# 覆盖方式：url-override / sha-override（CI 可传 vars.CANGJIE_SDK_URL_* / vars.CANGJIE_SDK_SHA_*）。
$defaultURLs = @{
  "windows_1.2.0" = "https://cangjie-lang.cn/v1/files/auth/downLoad?nsId=142267&fileName=cangjie-sdk-windows-x64-1.2.0.zip&objectKey=6ab1eafae4bd101f57762f5e"
}
$defaultSHAs = @{
  "windows_1.2.0" = "7BD5088AD56FB03C1214E73EA076DE5AC08580CC419A8CBD46A524EE1CA250BF"
}

$key = "${InputOS}_${InputVersion}"
$url = if ($InputURL) { $InputURL } else { $defaultURLs[$key] }
$sha = if ($InputSHA) { $InputSHA } else { $defaultSHAs[$key] }

$CANGJIE_HOME = $null
if (Test-Path $marker) {
  $envFile = Get-ChildItem $sdkDir -Recurse -Filter envsetup.ps1 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($envFile) {
    $CANGJIE_HOME = $envFile.DirectoryName
    Write-Host "==> 复用缓存的仓颉 SDK: $CANGJIE_HOME"
  }
}

if (-not $CANGJIE_HOME) {
  if (-not $url) {
    Write-Host "::error::未在内置表中找到 $InputOS / $InputVersion 的 SDK 下载地址；请用 url-override 覆盖，或在 install.ps1 的内置表中补充该组合"
    exit 1
  }

  if (Test-Path $sdkDir) { Remove-Item -Recurse -Force $sdkDir }
  New-Item -ItemType Directory -Force -Path $sdkDir | Out-Null

  $zip = Join-Path $sdkDir "sdk.zip"
  Write-Host "==> 下载仓颉 SDK: $url"
  curl.exe -fL --retry 3 --retry-delay 2 -o $zip $url
  if ($LASTEXITCODE -ne 0) {
    Write-Host "::error::仓颉 SDK 下载失败（exit=$LASTEXITCODE）"
    exit 1
  }

  if ($sha) {
    Write-Host "==> 校验 SHA-256: $sha"
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($actual -ne $sha) {
      Write-Host "::error::SDK SHA-256 校验失败: $actual（期望 $sha）"
      exit 1
    }
  } else {
    Write-Host "::warning::平台 $InputOS 未配置 SHA-256，跳过校验"
  }

  Write-Host "==> 解压到: $sdkDir"
  Expand-Archive -Path $zip -DestinationPath $sdkDir -Force
  Remove-Item $zip -Force

  $envFile = Get-ChildItem $sdkDir -Recurse -Filter envsetup.ps1 | Select-Object -First 1
  if (-not $envFile) {
    Write-Host "::error::解压后未找到 envsetup.ps1"
    exit 1
  }
  $CANGJIE_HOME = $envFile.DirectoryName
  New-Item -ItemType File -Path $marker -Force | Out-Null
}

"CANGJIE_HOME=$CANGJIE_HOME"                                       | Out-File -FilePath $env:GITHUB_ENV  -Append
"$CANGJIE_HOME\bin"                                                 | Out-File -FilePath $env:GITHUB_PATH -Append
"$CANGJIE_HOME\tools\bin"                                           | Out-File -FilePath $env:GITHUB_PATH -Append
# cjlint 依赖 libcjlint.dll（tools\lib），cjpm/cjc 依赖 libcangjie-runtime.dll（runtime\lib）
"$CANGJIE_HOME\tools\lib"                                           | Out-File -FilePath $env:GITHUB_PATH -Append
"$CANGJIE_HOME\runtime\lib\windows_x86_64_cjnative"                 | Out-File -FilePath $env:GITHUB_PATH -Append

# step output（供 composite 顶层 outputs 引用）
"cangjie-home=$CANGJIE_HOME" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
Write-Host "==> 已安装到: $CANGJIE_HOME"
