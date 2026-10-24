# 编译指南

本指南覆盖三条构建路径：**Windows（MSYS2 UCRT64）**、**WSL（Ubuntu）**、**aarch64 交叉（Pi Zero 2 W）**。

## 0. 先搞清楚产物与选择方式

三份静态库的目标格式互不兼容，必须分目录存放；**配置源与产物分离**（配置在 `native/config/`，`lib/` 下只有 `.a`）：

```
native/config/
├── sdl/lv_conf.h                       配置源（SDL 后端，Windows + WSL 共用；内含 _WIN32 分支）
└── pi/lv_conf.h                        配置源（Pi：DRM + evdev + RGB565 + NEON）

lib/
├── windows-x64/   liblvgl.a  liblvglcjshim.a     PE x86_64     Windows（MSYS2 UCRT64）
├── linux-x64/     liblvgl.a  liblvglcjshim.a     ELF x86_64    WSL / Linux 桌面
└── linux-arm64/   liblvgl.a  liblvglcjshim.a     ELF aarch64   Raspberry Pi（DRM + evdev）
```

用哪个由环境变量 `LVGLCJ_LIB_DIR` 决定（`cjpm.toml` 里是 `[ffi.c] path = "${LVGLCJ_LIB_DIR}"`）：

```powershell
$env:LVGLCJ_LIB_DIR = "lib/windows-x64"        # Windows PowerShell
```
```bash
export LVGLCJ_LIB_DIR=lib/linux-x64        # WSL / Linux
```

> ⚠️ `cjpm` 支持 `${VAR}` 替换，但**不支持** `${VAR:-默认值}`。不设这个变量会直接报
> `can not find the library 'lvgl' which is listed in 'ffi.c' field`。

## 1. 前置：仓颉 SDK 1.2.0

```bash
cjc -v      # Cangjie Compiler: 1.2.0 (cjnative)
cjpm -v     # 1.2.0
```

SDK 未进 `PATH` 时，先按官方方式 `source` 其 `envsetup.sh`（Windows 是 `envsetup.bat`）。**`LD_LIBRARY_PATH` 必须包含 runtime 目录**，否则编译出的程序运行时报 `libcangjie-runtime.so` 缺失。

---

## 2. 路径 A：Windows（MSYS2 UCRT64）

> 需要 **64 位** `ucrt64` 环境（`cjc` 的目标是 `x86_64-w64-mingw32`）。`mingw32` 是 32 位、`clang64` 的 CRT 不同，链接必失败。

### 2.1 安装工具链（一次性）

在 **MSYS2 UCRT64** 终端里：

```bash
pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake \
        mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-SDL2 \
        mingw-w64-ucrt-x86_64-freetype mingw-w64-ucrt-x86_64-pkgconf
```

### 2.2 编 LVGL + 垫片

```powershell
# 默认自动探测 LVGL 源码：仓库内 lvgl/ 或同级 lvgl-ref/
./scripts/build-lvgl-sdl.ps1

# 指定源码目录 / 清理重建
./scripts/build-lvgl-sdl.ps1 -LvglDir D:/lvgl -Clean
```

产物落到 `lib/windows-x64/`。脚本做的事（等价于手工配方，见 [第 6 节](#6-手工构建配方不用脚本)）：

1. `cmake` 配置 LVGL（`LV_BUILD_CONF_PATH` 指向 `native/config/sdl/lv_conf.h`，关 examples/demos/thorvg）；
2. `cmake --build` 出 `liblvgl.a`；
3. `gcc -c` 编垫片，`ar rcs` 打 `liblvglcjshim.a`。

### 2.3 编仓颉工程并运行

```powershell
$env:LVGLCJ_LIB_DIR = "lib/windows-x64"
cd examples
cjpm build --cfg

$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH    # SDL2.dll / libfreetype-6.dll
./target/release/bin/main.exe widgets
```

> 运行期 DLL 必须在 `PATH` 里（或在 exe 同目录）：`SDL2.dll`、`libfreetype-6.dll`。

---

## 3. 路径 B：WSL（Ubuntu 24.04 + WSLg）

### 3.1 依赖（一次性）

```bash
sudo apt install build-essential cmake ninja-build pkg-config git curl \
                 libsdl2-dev libfreetype-dev libevdev-dev \
                 fonts-noto-cjk
```

- `libevdev-dev`：`lv_conf.h` 在非 Windows 分支开了 `LV_USE_EVDEV=1`，编垫片/LVGL 都要这个头文件；
- `fonts-noto-cjk`：WSL 默认没有中文字体，不装界面就是方框。

### 3.2 关闭 Windows PATH 注入（重要）

WSL 默认把 Windows 的 `PATH` 追加进 Linux，会把 `cjc.exe`、MSYS2 的 `ninja` 一起带进来，导致构建跑到 Windows 程序上。编辑 `/etc/wsl.conf`：

```ini
[interop]
appendWindowsPath = false
```

改完 `wsl --terminate <发行版名>` 再进。

### 3.3 编 LVGL + 垫片

```bash
export LVGL_DIR=/opt/lvgl-9.5.0        # 可选：复用已有源码，省一次克隆
export BUILD_DIR=/opt/build-sdl        # 可选：放原生盘，比 /mnt/c 快很多
./scripts/build-lvgl-sdl.sh
```

产物 → `lib/linux-x64/`。

### 3.4 编仓颉工程并运行

```bash
export LVGLCJ_LIB_DIR=lib/linux-x64
cd examples && cjpm build --cfg
./target/release/bin/main widgets      # WSLg 直接弹窗
```

若报 `error while loading shared libraries: libcangjie-runtime.so`，说明当前是**非登录 shell**，`/etc/profile.d/cangjie.sh` 没生效：

```bash
bash -lc '...'                       # 用登录 shell
# 或
source /etc/profile.d/cangjie.sh
```

---

## 4. 路径 C：aarch64 交叉编译（Pi Zero 2 W）

### 4.1 目标与现状

| 项 | 状态 |
|---|---|
| C 库（LVGL + 垫片）交叉编译 | ✅ 已实测，产物 `lib/linux-arm64/`，`readelf` 显示 `Machine: AArch64` |
| 仓颉侧产出 aarch64 可执行文件 | ⏳ **需要 linux-aarch64 版仓颉 SDK**（见 4.5） |

### 4.2 交叉工具链 + arm64 头文件

```bash
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
sudo dpkg --add-architecture arm64
sudo apt install libdrm-dev:arm64 libevdev-dev:arm64
```

> amd64 机器装 arm64 包需要 multiarch：主源标 `Architectures: amd64`，另加 `ubuntu-ports` 源标 `Architectures: arm64`，否则 `apt` 会报找不到包或架构冲突。

### 4.3 编 C 库

```bash
export LVGL_DIR=/opt/lvgl-9.5.0
export BUILD_DIR=/opt/build-pi
./scripts/build-lvgl-pi.sh
```

脚本会自动准备 `/opt/arm64-include`（把 `xf86drm*.h`、`libdrm/*.h`、`libevdev-1.0/` 扁平拷进去），因为**交叉 gcc 不会搜宿主机的 `/usr/include`**，而 `lv_linux_drm.c` 里 include 的是 `<xf86drm.h>` / `<drm_fourcc.h>`。

校验产物：

```bash
aarch64-linux-gnu-readelf -h lib/linux-arm64/liblvgl.a | grep Machine   # AArch64
aarch64-linux-gnu-nm -g --defined-only lib/linux-arm64/liblvgl.a | grep -c evdev
```

### 4.4 `native/config/pi/lv_conf.h` 与模拟器版的关键差异

| 宏 | `native/config/sdl/lv_conf.h` | `native/config/pi/lv_conf.h` |
|---|---|---|
| `LV_COLOR_DEPTH` | 32 | **16**（RGB565） |
| `LV_USE_SDL` | 1 | 0 |
| `LV_USE_LINUX_DRM` | 0 | **1** |
| `LV_USE_EVDEV` | Linux 1 / Windows 0 | **1** |
| `LV_USE_DRAW_SW_ASM` | 默认 | **NEON** |
| `LV_MEM_SIZE` | 256 KB | **128 KB**（复杂 UI 可提到 256 KB） |
| `LV_DEF_REFR_PERIOD` | 16 ms | **33 ms**（≈30 fps） |
| `LV_USE_FREETYPE` | 1 | 0（要完整中文就在 Pi 上开，并装 Noto CJK） |
| `LV_USE_LODEPNG` | **1** | **1**（`Image.fromFile` 的 PNG 解码；LVGL 内置，零外部依赖） |
| `LV_USE_FS_STDIO` | **1** | **1**（文件访问走 `fopen`，驱动器字母 `'A'`；垫片负责拼 `A:<path>`） |
| `LV_USE_IME_PINYIN` | **1** | **1**（`ImePinyin` 需它；LVGL 9.5 默认 0，改完要重编静态库） |

### 4.5 仓颉侧交叉（待办）

linux-x64 SDK 的 `runtime/lib` 里只有 `linux_x86_64_cjnative`，直接链 `lib/linux-arm64` 会得到：

```
/usr/bin/ld: skipping incompatible .../lib/linux-arm64/liblvgl.a when searching for -llvgl
/usr/bin/ld: cannot find -llvgl: No such file or directory
```

装上 **linux-aarch64 版 SDK** 后：

```bash
export CANGJIE_HOME=/opt/cangjie_1.2.0_aarch64/cangjie
export PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$PATH"
export LVGLCJ_LIB_DIR=lib/linux-arm64

cd examples
cjpm build --target=aarch64-unknown-linux-gnu --cfg
file target/release/bin/main        # ELF 64-bit LSB, ARM aarch64
```

若链接报 `Scrt1.o` / `crti.o` 找不到，是 cjc 没找到交叉 sysroot：

```bash
--sysroot /usr/aarch64-linux-gnu \
-L /usr/aarch64-linux-gnu/lib \
-L /usr/lib/gcc-cross/aarch64-linux-gnu/13
```

退路：直接在 Pi 上原生 `cjpm build`（慢但零坑）。

---

## 5. 构建你自己的工程（引用本库）

`examples/cjpm.toml` 是最小可用模板：

```toml
[package]
cjc-version = "1.2.0"
name = "myApp"
version = "0.1.0"
output-type = "executable"

# 静态库带不出依赖：SDL 后端要 -lSDL2，中文 FreeType 要 -lfreetype
link-option = "-lSDL2 -lfreetype"

[dependencies]
lvglcj = { path = ".." }        # 或 git 依赖

[profile.customized-option]
# cjpm 1.2.0 只接受 cfg / cfg_1 / cfg_2 … 作键名，且 --cfg 只匹配字面量 cfg
cfg = "--cfg=\"lv_backend=sdl\""
```

必读的三点：

1. **`link-option` 不能省**，否则 `undefined symbol: SDL_Init` / `FT_Init_FreeType`；
2. 依赖本库时**也要设 `LVGLCJ_LIB_DIR`**（它是库包 `cjpm.toml` 里的 `${...}`）；
3. `--cfg` 的键名必须是 `cfg`，用别的名字 cjpm 会报 `the customized key ... is wrong`。

---

## 5.1 运行单元测试（cjpm test）

测试源码在 `src/test/`（package `lvglcj.test`），不需要额外配置，设好 `LVGLCJ_LIB_DIR` 即可：

```bash
export LVGLCJ_LIB_DIR=lib/linux-x64      # Windows: $env:LVGLCJ_LIB_DIR = "lib/windows-x64"
cjpm test                                # 实测 29 passed / 11 skipped / 0 failed
# 含窗口用例（会真的弹 320x240 窗口）；注意 --include-tags 不会覆盖配置里的
# exclude-tags，必须用一个不存在的 tag 把它顶掉
cjpm test --include-tags=requires_display --exclude-tags=notag
```

三个注意点：

1. **测试二进制也要链接 `-lSDL2 -lfreetype`**：本库 `cjpm.toml` 已用 `[target.<triple>]` 的 `link-option` 声明，Windows 上还要保证 `SDL2.dll` / `libfreetype-6.dll` 在 `PATH`；
2. 依赖真实屏幕的用例打 `@Tag[requires_display]`，由 `[profile.test].exclude-tags` 默认排除，适合无头环境与 CI；
3. `@Tag` 的标签必须是**标识符**（`@Tag[requires_display]`），不能加引号；`@ExpectThrows` 用括号形式 `@ExpectThrows[LvglException](expr)`。

## 6. 手工构建配方（不用脚本）

脚本只是把下面的命令串起来。要改 `lv_conf.h` 或换编译选项时可直接照抄。

### 6.1 LVGL 本体

```bash
cmake -B build -G Ninja -S /path/to/lvgl \
  -DCMAKE_BUILD_TYPE=Release \
  -DLV_BUILD_CONF_PATH=/abs/path/to/lv_conf.h \
  -DCONFIG_LV_BUILD_EXAMPLES=OFF \
  -DCONFIG_LV_BUILD_DEMOS=OFF \
  -DCONFIG_LV_USE_THORVG_INTERNAL=OFF \
  -DCMAKE_C_FLAGS="-I/usr/include/freetype2"
cmake --build build
# → build/lib/liblvgl.a
```

| 参数 | 为什么必须 |
|---|---|
| `LV_BUILD_CONF_PATH` | **9.5 的配置项名**。老名 `LV_CONF_PATH` 不会报错，只会静默忽略 → 用默认配置，SDL/DRM 后端全关 |
| `CONFIG_LV_BUILD_EXAMPLES/DEMOS=OFF` | 不编 `lv_demo_*`，省几百个文件 |
| `CONFIG_LV_USE_THORVG_INTERNAL=OFF` | 不编 ThorVG，否则顺带编一堆 C++ 并把 libstdc++ 拖进静态库 |
| `-I.../freetype2` | LVGL 的 CMake 不处理 freetype 依赖，`LV_USE_FREETYPE=1` 时必须自己加 |

交叉编译再加 `-DCMAKE_TOOLCHAIN_FILE=../../cmake/toolchain-aarch64.cmake`，并把 `-I` 换成 `/opt/arm64-include`。

### 6.2 C 垫片

```bash
gcc -c -O2 -fPIC -Wall -Wextra \
  -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE \
  -I/path/to/lvgl -I/abs/path/to/          `# 后者是 lv_conf.h 所在目录` \
  -I/usr/include/freetype2 \
  -o lvgl_shim.o native/shim/lvgl_shim.c
ar rcs liblvglcjshim.a lvgl_shim.o
```

- `LV_CONF_INCLUDE_SIMPLE` + `-I<配置目录>` 是 `LV_CONF_PATH` 的等价写法，免去引号转义；
- `LV_LVGL_H_INCLUDE_SIMPLE` 让 LVGL 内部头文件按 `src/...` 找，配合 `-I<lvgl 根>`；
- 交叉时把 `gcc`/`ar` 换成 `aarch64-linux-gnu-gcc` / `aarch64-linux-gnu-ar`。

### 6.3 MSYS2 下的差异

- 路径一律**正斜杠**（`C:/msys64/...`），反斜杠会被当转义符；
- 追加 `-IC:/msys64/ucrt64/include -IC:/msys64/ucrt64/include/freetype2`；
- LVGL 的 CMake 需要 `-DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++`。

---

## 7. 编译期常见错误

| 报错 | 原因 | 解法 |
|---|---|---|
| `can not find the library 'lvgl' ... 'ffi.c' field` | 没设 `LVGLCJ_LIB_DIR` | 按第 0 节设置 |
| `the environment variable '${...:-...}' is wrong` | 用了 shell 默认值语法 | 只写 `${VAR}`，变量必须存在 |
| `the customized key 'xxx' is wrong, the example is 'cfg_1'` | 自定义选项键名不对 | 用 `cfg` / `cfg_1` / `cfg_2` |
| `undefined symbol: SDL_Init` / `FT_Init_FreeType` | 少 `link-option` | `link-option = "-lSDL2 -lfreetype"` |
| `skipping incompatible .../liblvgl.a` | 用了别的平台的库 | 换对 `LVGLCJ_LIB_DIR` |
| cmake 说 `Configuration file ... not found` | 配置路径错/没写绝对路径 | `LV_BUILD_CONF_PATH` 给绝对路径 |
| 配置成功但后端全被关掉 | 用了老参数名 `LV_CONF_PATH` | 改成 `LV_BUILD_CONF_PATH` |
| `drm.h: No such file or directory` | 交叉编译缺 libdrm 头路径 | 见 4.3，`-I/opt/arm64-include` |
| `LV_USE_MEM_MONITOR redefined` | `LV_USE_SYSMON=0` 把监控强改回 0 | `#define LV_USE_SYSMON 1` |
| `there is no '.cj' file in directory 'src/shim'` | C 垫片放错了目录 | 垫片放仓库根 `shim/`（`src-dir` 下的非仓颉目录会被警告） |

更多运行期问题见 [常见问题](faq.md)。
