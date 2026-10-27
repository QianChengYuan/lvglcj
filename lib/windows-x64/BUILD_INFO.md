# lib/windows-x64 —— 预编译静态库溯源

| 项 | 值 |
|---|---|
| 目标平台 | Windows x64（PE，`x86_64-w64-mingw32`） |
| LVGL 版本 | **v9.5.0**（tag，源码来自 `gitcode.com/gh_mirrors/lvgl/lvgl`） |
| 配置源 | `native/config/sdl/lv_conf.h` |
| 配置快照 SHA-256 | `203a4e09a41a8d10da4030535d0cccc62ab297c9dcffa6627ee824c0d8d4b5c4` |
| 构建脚本 | `scripts/build-lvgl-sdl.ps1` |
| 编译器 | MSYS2 **UCRT64** gcc（mingw32 / clang64 与 cjc 目标不匹配，不可用） |
| 产物 | `liblvgl.a`、`liblvglcjshim.a`（校验和见同目录 `SHA256SUMS`） |

关键开关（以 `lv_conf.h` 为准，这里只列影响 ABI/能力的项）：

```
LV_COLOR_DEPTH 32           LV_USE_SDL 1                LV_SDL_ACCELERATED 0
LV_MEM_SIZE 1MB             LV_USE_FREETYPE 1           LV_FREETYPE_CACHE_FT_GLYPH_CNT 192
LV_USE_LODEPNG 1            LV_USE_FS_STDIO 1           LV_USE_IME_PINYIN 1
LV_FONT_SOURCE_HAN_SANS_SC_16_CJK 1                     LV_USE_LINUX_DRM 0
```

重建：

```powershell
# 需先把 C:\msys64\ucrt64\bin 放进 PATH（否则 gcc 静默 exit 1 且无输出）
./scripts/build-lvgl-sdl.ps1
```

与源码的对应关系：垫片源码是 `native/shim/lvgl_shim.c`，改了垫片要重编 `liblvglcjshim.a`
（不必重编 LVGL 本体）。

**更新规则**：改 `native/config/sdl/lv_conf.h` 或垫片后必须重编本目录产物，
并同步更新本文件的「配置快照 SHA-256」与 `SHA256SUMS`；CI 会校验 `SHA256SUMS`。
