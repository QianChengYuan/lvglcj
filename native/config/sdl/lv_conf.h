/**
 * @file lv_conf.h
 * @brief lvglcj 模拟器（WSL, x86_64, SDL2 + WSLg）配置
 *
 * 与 lib/pi/lv_conf.h 的差异即 README「二、lv_conf.h 关键开关」表中的
 * WSL 列：32 位色深、SDL 后端、断言全开（开发期尽早发现问题）。
 */
#ifndef LV_CONF_H
#define LV_CONF_H

/* WSL 模拟验证用 32 位色深（真机是 16，见 lib/pi/lv_conf.h） */
#define LV_COLOR_DEPTH 32

/* ---- 显示 / 输入后端 ---- */
#define LV_USE_SDL 1                /* 桌面窗口验证（WSLg / Windows MSYS2 通用） */
/* 0 = SDL 软件渲染器。默认的 SDL_RENDERER_ACCELERATED 需要 GL/GPU 上下文：
   WSL 没有 WSLg 时（SDL_VIDEODRIVER=dummy / offscreen）创建渲染器会直接失败，
   而这个机器的 WSLg 一直是坏的。LVGL 本来就是 CPU 画图，SDL 只负责把纹理贴到窗口，
   软件渲染没有实际损失，Windows/WSL 都能跑。 */
#define LV_SDL_ACCELERATED 0
#define LV_USE_LINUX_DRM 0
#define LV_USE_LINUX_FBDEV 0
/* evdev 驱动依赖 <linux/input.h>、<sys/epoll.h>，MinGW 下不存在；
   Windows 的输入由 SDL 驱动（lv_sdl_mouse/keyboard）提供，故按平台关闭 */
#if defined(_WIN32)
#define LV_USE_EVDEV 0
#else
#define LV_USE_EVDEV 1              /* 触摸/鼠标/键盘 */
#endif
#define LV_USE_LIBINPUT 0
#define LV_USE_WAYLAND 0
#define LV_USE_X11 0

/* ---- 渲染 ---- */
#define LV_DEF_REFR_PERIOD 16       /* 60 fps 档 */
#define LV_DRAW_SW_ASM LV_DRAW_SW_ASM_NONE
#define LV_USE_THORVG_INTERNAL 0
#define LV_USE_GSTREAMER 0

/* ---- 断言：开发期全开（每次对象/样式访问都校验） ---- */
#define LV_USE_ASSERT_MEM_INTEGRITY 1
#define LV_USE_ASSERT_OBJ 1
#define LV_USE_ASSERT_STYLE 1
/* 断言失败要"炸出来"。LVGL 默认 LV_ASSERT_HANDLER 是 `while(1);`，在 Pi 上实测过
   一次 FreeType 字形缓存分配失败 → lv_draw_buf_destroy(NULL) → LV_ASSERT_NULL →
   永久自旋，界面全停但其它线程还在跑（声音继续），从外面看就是"界面卡死"。
   开发配置改成 abort()：同样的问题会立刻带栈崩掉，一眼能看见。 */
#define LV_ASSERT_HANDLER_INCLUDE <stdlib.h>
#define LV_ASSERT_HANDLER abort();

/* ---- 内存池 ---- */
/* 1MB：这块只放 LVGL 对象/样式/字形缓存。原来 256KB 时，FreeType 字形缓存上限
   512 项（每项一个 glyph 位图 draw_buf）就能把池子吃光 → 分配失败 → 见上面断言说明，
   Pi 上《大鱼》卡死就是这么来的。 */
#define LV_MEM_SIZE (1024 * 1024U)
#define LV_MEM_ADR 0

/* ---- 诊断 ---- */
/* 9.5 起 PERF/MEM 监控挂在 SYSMON 下：LV_USE_SYSMON 为 0 时
   lv_conf_internal.h 会把下面两个强行改回 0，故必须同时打开 */
#define LV_USE_SYSMON 1
#define LV_USE_PERF_MONITOR 1
#define LV_USE_MEM_MONITOR 1

/* ---- 日志：开发期开到 INFO ---- */
#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_INFO

/* ---- 字体 ---- */
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_20 1
/* 思源黑体 SC 16px 中文子集（LVGL 内置，无外部依赖）：
   Montserrat 不含 CJK 字形，示例里的中文会显示成方框，故默认字体用它 */
#define LV_FONT_SOURCE_HAN_SANS_SC_16_CJK 1
#define LV_FONT_DEFAULT &lv_font_source_han_sans_sc_16_cjk

/* ---- FreeType：运行时加载系统 CJK 字体（内置子集只有 1338 字，覆盖不全） ---- */
#define LV_USE_FREETYPE 1
/* 192 项 ≈ 100KB 字形位图，够 5 行中文歌词 + 列表标题常驻；超出按 LRU 重建 */
#define LV_FREETYPE_CACHE_FT_GLYPH_CNT 192

/* ---- 图像文件解码 / 文件系统（Image.fromFile）
   lodepng 是 LVGL 内置、零外部依赖的解码器，PNG 足以覆盖图标与截图场景；
   JPG/GIF/WebP 需要时自行打开 LV_USE_TJPGD / LV_USE_GIF / LV_USE_LIBWEBP。
   文件访问走 STDIO 驱动（fopen），垫片会把系统路径拼成 "A:<path>" 再交给 LVGL。 ---- */
#define LV_USE_LODEPNG 1
#define LV_USE_FS_STDIO 1
#define LV_FS_STDIO_LETTER 'A'
#define LV_FS_STDIO_PATH ""
#define LV_FS_STDIO_CACHE_SIZE 0

/* ---- 中文拼音输入法（lv_ime_pinyin）：需要中文输入时由 ImePinyin 绑定 Keyboard。
   LVGL 9.5 默认 LV_USE_IME_PINYIN=0，此处显式打开并编入内置词典，
   否则 ImePinyin 的 lv_ime_pinyin_* 符号在静态库里不存在，链接期会报未定义。 ---- */
#define LV_USE_IME_PINYIN 1
#define LV_IME_PINYIN_USE_DEFAULT_DICT 1
#define LV_IME_PINYIN_CAND_TEXT_NUM 6
#define LV_IME_PINYIN_USE_K9_MODE 1
#define LV_IME_PINYIN_K9_CAND_TEXT_NUM 3

#endif /* LV_CONF_H */
