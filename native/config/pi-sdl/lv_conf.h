/**
 * @file lv_conf.h
 * @brief lvglcj 真机（Raspberry Pi Zero 2 W, aarch64, Debian 13 + labwc 桌面）SDL 后端配置
 *
 * 与 native/config/pi/lv_conf.h（DRM + evdev 独占 TTY）的区别：
 *   - 走 SDL 窗口，在桌面（Wayland/XWayland）里跑，不抢 DRM master
 *   - 输入由 SDL 提供，关掉 evdev，省掉 libevdev 链接
 *   - 中文走 FreeType 加载系统字体（Pi 自带
 *     /usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf）
 *
 * 交叉编译：scripts/build-lvgl-pi-sdl.sh → lib/linux-arm64-sdl/
 */
#ifndef LV_CONF_H
#define LV_CONF_H

/* Zero 2 W 内存与带宽都紧张，用 RGB565 */
#define LV_COLOR_DEPTH 16

/* ---- 显示 / 输入后端 ---- */
#define LV_USE_SDL 1
#define LV_USE_LINUX_DRM 0
#define LV_USE_LINUX_FBDEV 0
#define LV_USE_EVDEV 0            /* SDL 已提供鼠标/键盘/触摸 */
#define LV_USE_LIBINPUT 0
#define LV_USE_WAYLAND 0
#define LV_USE_X11 0

/* ---- 渲染 ---- */
#define LV_DEF_REFR_PERIOD 33     /* Zero 2 W 用 30 fps 档，留出 CPU 余量 */
#define LV_DRAW_SW_ASM LV_DRAW_SW_ASM_NONE
#define LV_USE_THORVG_INTERNAL 0
#define LV_USE_GSTREAMER 0

/* ---- 断言：发布配置，关掉逐对象的开销 ---- */
#define LV_USE_ASSERT_MEM_INTEGRITY 0
#define LV_USE_ASSERT_OBJ 0
#define LV_USE_ASSERT_STYLE 0

/* ---- 内存池：SDL 后端 buffer 走系统堆，这里只放对象/样式 ---- */
#define LV_MEM_SIZE (128 * 1024U)
#define LV_MEM_ADR 0

/* ---- 诊断：保留 FPS 监控，关掉内存监控省一点开销 ---- */
#define LV_USE_SYSMON 1
#define LV_USE_PERF_MONITOR 1
#define LV_USE_MEM_MONITOR 0

/* ---- 日志：真机上只留 WARN ---- */
#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN

/* ---- 字体 ---- */
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_20 1
/* 内置思源黑体 16px 子集做兜底（1338 字），完整中文靠下面的 FreeType */
#define LV_FONT_SOURCE_HAN_SANS_SC_16_CJK 1
#define LV_FONT_DEFAULT &lv_font_source_han_sans_sc_16_cjk

/* ---- FreeType：加载 /usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf ---- */
#define LV_USE_FREETYPE 1
#define LV_FREETYPE_CACHE_FT_GLYPH_CNT 256

/* ---- 图像文件解码 / 文件系统（Image.fromFile） ---- */
#define LV_USE_LODEPNG 1
#define LV_USE_FS_STDIO 1
#define LV_FS_STDIO_LETTER 'A'
#define LV_FS_STDIO_PATH ""
#define LV_FS_STDIO_CACHE_SIZE 0

/* ---- 中文拼音输入法 ---- */
#define LV_USE_IME_PINYIN 1
#define LV_IME_PINYIN_USE_DEFAULT_DICT 1
#define LV_IME_PINYIN_CAND_TEXT_NUM 6
#define LV_IME_PINYIN_USE_K9_MODE 1
#define LV_IME_PINYIN_K9_CAND_TEXT_NUM 3

#endif /* LV_CONF_H */
