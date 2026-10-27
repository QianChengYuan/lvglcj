# lib/linux-arm64 —— 预编译静态库溯源（DRM + evdev）

> **用途有限**：这是 DRM/KMS 直出（tty 独占）版本，在 labwc/Wayland 桌面里会抢 DRM master。
> 桌面里跑请改用 `lib/linux-arm64-sdl`。

| 项 | 值 |
|---|---|
| 目标平台 | Linux aarch64（ELF 64-bit LSB, AArch64） |
| LVGL 版本 | **v9.5.0**（tag，源码来自 `gitcode.com/gh_mirrors/lvgl/lvgl`） |
| 配置源 | `native/config/pi/lv_conf.h` |
| 配置快照 SHA-256 | `f4983b3c66d28d7fb4d84048847f866e693a4fe7765f77adffcd16fc63642027` |
| 构建脚本 | `scripts/build-lvgl-pi.sh`（工具链 `cmake/toolchain-aarch64.cmake`） |
| 编译器 | `aarch64-linux-gnu-gcc` 13.x（Ubuntu 交叉包）+ cmake/ninja |
| 产物 | `liblvgl.a`、`liblvglcjshim.a`（校验和见同目录 `SHA256SUMS`） |

关键开关（以 `lv_conf.h` 为准）：

```
LV_COLOR_DEPTH 16           LV_USE_LINUX_DRM 1          LV_USE_LINUX_FBDEV 0
LV_USE_SDL 0                LV_USE_EVDEV 1              LV_MEM_SIZE 128KB
LV_USE_LODEPNG 1            LV_USE_FS_STDIO 1           LV_USE_IME_PINYIN 1
```

**能力缺口（`nm` 实测）**：本目录产物**未开 FreeType，也没有内置 CJK 字体**
（`native/config/pi/lv_conf.h` 只有 55 行）→ Pi 上走 DRM 时没有落地中文的手段。
需要中文请用 `lib/linux-arm64-sdl`（开了 FreeType）或给本配置补开关后重编。

**更新规则**：改 `native/config/pi/lv_conf.h` 或垫片后必须重编本目录产物，
并同步更新本文件的「配置快照 SHA-256」与 `SHA256SUMS`。
