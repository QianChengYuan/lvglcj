/**
 * @file lv_conf.h
 * @brief lvglcj 目标机（Raspberry Pi Zero 2 W, aarch64）配置
 *
 * 与 native/config/sdl/lv_conf.h 的差异即 README「二、lv_conf.h 关键开关」表中的
 * Pi 列。未显式设置的项沿用 LVGL 9.5 lv_conf_internal.h 的默认值。
 *
 * 中文方案：内置思源黑体 16px 子集（1338 字）作默认字体兜底，
 * 完整中文/其它字号走 FreeType 加载系统字体（DroidSansFallbackFull / Noto CJK）。
 */
#ifndef LV_CONF_H
#define LV_CONF_H

/* 16 位色深：512 MB 内存 + 纯 CPU 软渲染下的带宽/内存最优解 */
#define LV_COLOR_DEPTH 16

/* ---- 显示 / 输入后端 ---- */
#define LV_USE_LINUX_DRM 1          /* 优先 DRM/KMS（vc4-kms-v3d） */
#define LV_USE_LINUX_FBDEV 0        /* 兜底时才开（/dev/fb0） */
#define LV_USE_SDL 0
#define LV_USE_EVDEV 1              /* 触摸/鼠标/键盘 */
#define LV_USE_LIBINPUT 0
#define LV_USE_WAYLAND 0
#define LV_USE_X11 0

/* ---- 渲染 ---- */
#define LV_DEF_REFR_PERIOD 33       /* ≈30 fps，按面板刷新率与算力定 */
#define LV_DRAW_SW_ASM LV_DRAW_SW_ASM_NEON   /* Cortex-A53 NEON 加速软渲染 */
#define LV_USE_THORVG_INTERNAL 0    /* Zero 2 W 上矢量图形性价比低 */
#define LV_USE_GSTREAMER 0          /* v1.1 再评估 */

/* ---- 断言：发布版全关（开着显著变慢；调试时可临时打开） ---- */
#define LV_USE_ASSERT_MEM_INTEGRITY 0
#define LV_USE_ASSERT_OBJ 0
#define LV_USE_ASSERT_STYLE 0
/* 默认 1，失败时走 LV_ASSERT_HANDLER（默认 `while(1);`）→ 界面永久卡死。
   FreeType 字形缓存吃满内存时 LVGL 会把 NULL 的 draw_buf 传进 destroy，
   一断言就自旋（2026-10-26 在 Pi 上踩过）。关掉后最坏只丢一帧字形。 */
#define LV_USE_ASSERT_NULL 0

/* ---- 内存池：开了 FreeType 就不能再是 128KB ----
   FreeType 每个字形位图是一个 lv_draw_buf（20px 汉字约 0.5KB），128 个缓存项
   就是 ~64KB，再叠对象/样式/控件树，128KB 池会直接见底 → 字形分配失败 →
   撞上面那条 NULL 断言。真机 415MB 可用内存，512KB 很宽松（与 pi-sdl 一致）。 */
#define LV_MEM_SIZE (512 * 1024U)
#define LV_MEM_ADR 0

/* ---- 诊断 ---- */
/* 9.5 起 PERF/MEM 监控挂在 SYSMON 下：SYSMON=0 时 LVGL 会把下面两个强改回 0
   （并在编译期报 "LV_USE_MEM_MONITOR redefined" 告警），所以必须先开 SYSMON。 */
#define LV_USE_SYSMON 1
#define LV_USE_PERF_MONITOR 1       /* FPS / CPU 占用；发布版改 0 */
#define LV_USE_MEM_MONITOR 1        /* 内存 / 碎片 */

/* ---- 日志（排障期开，发布版可关） ---- */
#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN

/* ---- 字体 ---- */
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_20 1
/* 内置思源黑体 16px 子集（1338 字，编进 .a 约 190KB）作默认字体：
   它自带中文字形，缺字才会落到下面的 FreeType。 */
#define LV_FONT_SOURCE_HAN_SANS_SC_16_CJK 1
#define LV_FONT_DEFAULT &lv_font_source_han_sans_sc_16_cjk

/* ---- FreeType：完整中文 + 任意字号（Pi OS 自带 DroidSansFallbackFull） ---- */
#define LV_USE_FREETYPE 1
/* 每个缓存项就是一个字形位图 draw_buf；配合 512KB 池，128 项（≈64KB）够
   常驻几行歌词 + 列表标题，超出的按 LRU 重建。 */
#define LV_FREETYPE_CACHE_FT_GLYPH_CNT 128

/* ---- 图像文件解码 / 文件系统（Image.fromFile）
   lodepng 是 LVGL 内置解码器，不引入外部依赖；文件访问走 STDIO（fopen），
   垫片会把系统路径拼成 "A:<path>"。 ---- */
#define LV_USE_LODEPNG 1
#define LV_USE_FS_STDIO 1
#define LV_FS_STDIO_LETTER 'A'
#define LV_FS_STDIO_PATH ""
#define LV_FS_STDIO_CACHE_SIZE 0

/* ---- 中文拼音输入法（lv_ime_pinyin）：LVGL 9.5 默认关闭，这里与 sdl 配置保持一致。
   候选词是中文，字形由上面的内置 16px 子集 + FreeType 提供。 ---- */
#define LV_USE_IME_PINYIN 1
#define LV_IME_PINYIN_USE_DEFAULT_DICT 1
#define LV_IME_PINYIN_CAND_TEXT_NUM 6
#define LV_IME_PINYIN_USE_K9_MODE 1
#define LV_IME_PINYIN_K9_CAND_TEXT_NUM 3

#endif /* LV_CONF_H */
