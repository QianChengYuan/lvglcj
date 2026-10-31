# lib/linux-x64 —— 预编译静态库溯源

| 项 | 值 |
|---|---|
| 目标平台 | Linux x86_64（ELF 64-bit LSB, ABI: UNIX - GNU） |
| LVGL 版本 | **v9.5.0**（tag，源码来自 `gitcode.com/gh_mirrors/lvgl/lvgl`） |
| 配置源 | `native/config/sdl/lv_conf.h`（与 Windows 共用，内含 `_WIN32` 分支） |
| 配置快照 SHA-256 | `7c66d8092fe8a987dbeff3fd6ede8e2a18790abb962c3aa32dc65156f8b9307b`（本目录产物即按此配置编译） |
| 构建脚本 | `scripts/build-lvgl-sdl.sh` |
| 编译器 | Ubuntu 24.04（WSL2）gcc 13.3.0 + g++ 13.3.0 + cmake 3.28.3 + ninja 1.11.1 |
| 产物 | `liblvgl.a`、`liblvglcjshim.a`（校验和见同目录 `SHA256SUMS`） |

关键开关（以 `lv_conf.h` 为准）：

```
LV_COLOR_DEPTH 32           LV_USE_SDL 1                LV_SDL_ACCELERATED 0
LV_MEM_SIZE 1MB             LV_USE_FREETYPE 1           LV_FREETYPE_CACHE_FT_GLYPH_CNT 192
LV_USE_LODEPNG 1            LV_USE_FS_STDIO 1           LV_USE_IME_PINYIN 1
LV_USE_EVDEV 1                                          LV_USE_LINUX_DRM 0
```

重建：

```bash
sudo apt install build-essential cmake ninja-build pkg-config \
                 libsdl2-dev libfreetype-dev libevdev-dev
./scripts/build-lvgl-sdl.sh
```

**注意**：静态库带不出 SDL2 / FreeType，使用方必须在 `cjpm.toml` 里补
`-lSDL2 -lfreetype`（本仓库的 `[target.x86_64-unknown-linux-gnu]` 已经配好）。

**更新规则**：改 `native/config/sdl/lv_conf.h` 或 `native/shim/lvgl_shim.c` 后必须重编本目录产物，
并同步更新本文件的「配置快照 SHA-256」与 `SHA256SUMS`；CI 会校验 `SHA256SUMS`。
