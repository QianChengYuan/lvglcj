# lib/linux-arm64 —— 预编译静态库溯源（DRM + evdev）

> **用途有限**：这是 DRM/KMS 直出（tty 独占）版本，在 labwc/Wayland 桌面里会抢 DRM master。
> 桌面里跑请改用 `lib/linux-arm64-sdl`。

| 项 | 值 |
|---|---|
| 目标平台 | Linux aarch64（ELF 64-bit LSB, AArch64） |
| LVGL 版本 | **v9.5.0**（tag，源码来自 `gitcode.com/gh_mirrors/lvgl/lvgl`） |
| 配置源 | `native/config/pi/lv_conf.h`（91 行） |
| 配置快照 SHA-256 | `dfb1d25147c6ed8506684b5d9b74280f1a65830af274a4a7635b09079f3e9d66` |
| 构建脚本 | `scripts/build-lvgl-pi.sh`（工具链 `cmake/toolchain-aarch64.cmake`） |
| 编译器 | `aarch64-linux-gnu-gcc` 13.3（Ubuntu 交叉包）+ cmake/ninja |
| 产物 | `liblvgl.a`、`liblvglcjshim.a`（校验和见同目录 `SHA256SUMS`） |

关键开关（以 `lv_conf.h` 为准）：

```
LV_COLOR_DEPTH 16           LV_USE_LINUX_DRM 1         LV_USE_LINUX_FBDEV 0
LV_USE_SDL 0                LV_USE_EVDEV 1             LV_MEM_SIZE 512KB
LV_USE_FREETYPE 1           LV_FREETYPE_CACHE_FT_GLYPH_CNT 128
LV_FONT_SOURCE_HAN_SANS_SC_16_CJK 1                     LV_USE_ASSERT_NULL 0
LV_USE_LODEPNG 1            LV_USE_FS_STDIO 1           LV_USE_IME_PINYIN 1
```

`nm` 实测能力（2026-10-29 重编）：`lv_freetype_init`、`lv_font_source_han_sans_sc_16_cjk`、
`lv_ime_pinyin_create`、`lv_spangroup_create`、`lv_calendar_add_header_arrow`、
`lv_animimg_set_src`、`lv_subject_init_int`、`lv_label_bind_text`、`lv_linux_drm_create`、
`lv_evdev_create` 均在；**无** `lv_sdl_window_create`（符合 SDL=0）。
中文由「内置 16px 子集兜底 + FreeType 载系统字体」提供。

重建（WSL，复用已有 LVGL 源码与独立构建目录）：

```bash
LVGL_DIR=/root/lvgl-build/lvgl-src \
BUILD_DIR=/root/lvgl-build/pi-fresh \
FT_INC=/root/aarch64-sdl/include \
./scripts/build-lvgl-pi.sh
```

> 与 `lib/linux-arm64-sdl` 的差别：本目录走 DRM 直出 + evdev 输入，不依赖 SDL2；
> 最终链接需要额外补 `-ldrm -levdev`（FreeType 仍需 `-lfreetype`），
> 而 SDL 版补的是 `-lSDL2 -lfreetype`。

**更新规则**：改 `native/config/pi/lv_conf.h` 或垫片后必须重编本目录产物，
并同步更新本文件的「配置快照 SHA-256」与 `SHA256SUMS`。
