# lib/linux-arm64 —— 预编译静态库溯源（DRM + evdev）

> **用途有限**：这是 DRM/KMS 直出（tty 独占）版本，在 labwc/Wayland 桌面里会抢 DRM master。
> 桌面里跑请改用 `lib/linux-arm64-sdl`。

| 项 | 值 |
|---|---|
| 目标平台 | Linux aarch64（ELF 64-bit LSB, AArch64） |
| LVGL 版本 | **v9.5.0**（tag，源码来自 `gitcode.com/gh_mirrors/lvgl/lvgl`） |
| 配置源 | `native/config/pi/lv_conf.h` |
| 配置快照 SHA-256 | `f4983b3c66d28d7fb4d84048847f866e693a4fe7765f77adffcd16fc63642027`（**旧**） |
| 构建脚本 | `scripts/build-lvgl-pi.sh`（工具链 `cmake/toolchain-aarch64.cmake`） |
| 编译器 | `aarch64-linux-gnu-gcc` 13.x（Ubuntu 交叉包）+ cmake/ninja |
| 产物 | `liblvgl.a`、`liblvglcjshim.a`（校验和见同目录 `SHA256SUMS`） |

> ⚠️ **本目录产物已过期**：`native/config/pi/lv_conf.h` 之后又改过
> （现为 91 行，SHA-256 `dfb1d25147c6ed8506684b5d9b74280f1a65830af274a4a7635b09079f3e9d66`），
> 新增了内置 CJK 子集、`LV_USE_FREETYPE=1`、`LV_MEM_SIZE=512KB` 等。
> 下面的开关表只描述**已提交的旧产物**，重跑 `scripts/build-lvgl-pi.sh` 后需整体更新。

旧产物的关键开关（对应上面的旧快照）：

```
LV_COLOR_DEPTH 16           LV_USE_LINUX_DRM 1          LV_USE_LINUX_FBDEV 0
LV_USE_SDL 0                LV_USE_EVDEV 1              LV_MEM_SIZE 128KB
LV_USE_LODEPNG 1            LV_USE_FS_STDIO 1           LV_USE_IME_PINYIN 1
```

**旧产物的能力缺口（`nm` 实测）**：**未开 FreeType，也没有内置 CJK 字体** → Pi 上走 DRM 时没有落地中文的手段。
需要中文请用 `lib/linux-arm64-sdl`（开了 FreeType），或按当前配置重编本目录。

重编后预期：`LV_USE_FREETYPE=1` + `LV_FONT_SOURCE_HAN_SANS_SC_16_CJK=1`，
中文由「内置 16px 子集兜底 + FreeType 载系统字体」提供；编译期需 arm64 的
`freetype2` 头（脚本 `FT_INC`），链接期由使用方补 `-lfreetype`。

**更新规则**：改 `native/config/pi/lv_conf.h` 或垫片后必须重编本目录产物，
并同步更新本文件的「配置快照 SHA-256」与 `SHA256SUMS`。
