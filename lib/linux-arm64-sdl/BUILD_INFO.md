# lib/linux-arm64-sdl —— 预编译静态库溯源（aarch64 + SDL 桌面）

Pi Zero 2 W 上以 SDL 窗口显示（labwc / Wayland 桌面），不抢 DRM master；中文走 FreeType。

| 项 | 值 |
|---|---|
| 目标平台 | Linux aarch64（ELF 64-bit LSB, AArch64） |
| LVGL 版本 | **v9.5.0**（tag，源码来自 `gitcode.com/gh_mirrors/lvgl/lvgl`） |
| 配置源 | `native/config/pi-sdl/lv_conf.h` |
| 配置快照 SHA-256 | `2873a0b2e00b78b5288122a12a925206169b28ef417e744a856501042a2c624f`（本目录产物即按此配置编译） |
| 构建脚本 | `scripts/build-lvgl-pi-sdl.sh`（工具链 `cmake/toolchain-aarch64.cmake`） |
| 编译器 | `aarch64-linux-gnu-gcc` 13.x + cmake/ninja；SDL2/FreeType 头取自 Ubuntu noble arm64 包（架构无关头） |
| 产物 | `liblvgl.a`、`liblvglcjshim.a`（校验和见同目录 `SHA256SUMS`） |

关键开关（以 `lv_conf.h` 为准）：

```
LV_COLOR_DEPTH 16           LV_USE_SDL 1                LV_MEM_SIZE 512KB
LV_USE_FREETYPE 1           LV_FREETYPE_CACHE_FT_GLYPH_CNT 128
LV_FONT_SOURCE_HAN_SANS_SC_16_CJK 1                     LV_USE_ASSERT_NULL 0
LV_USE_LODEPNG 1            LV_USE_FS_STDIO 1           LV_USE_IME_PINYIN 1
```

`LV_MEM_SIZE` 512KB / 字形缓存 128 / `LV_USE_ASSERT_NULL 0` 是踩过坑后的取值：
128KB + 256 字形时，密集中文会把字形缓存池吃光，`lv_draw_buf_destroy(NULL)`
触发默认断言处理器 `while(1);`，表现为界面卡死（声音还在放）。

重建：

```bash
# 需先在 Pi 上装好 libsdl2-dev libfreetype-dev，并把头文件/库拷到 /root/aarch64-sdl
./scripts/build-lvgl-pi-sdl.sh
```

**更新规则**：改 `native/config/pi-sdl/lv_conf.h` 或垫片后必须重编本目录产物，
并同步更新本文件的「配置快照 SHA-256」与 `SHA256SUMS`。
