/**
 * @file lv_conf.h
 * @brief lvglcj 目标机（Raspberry Pi Zero 2 W, aarch64）配置
 *
 * 与 lib/sdl/lv_conf.h 的差异即 README「二、lv_conf.h 关键开关」表中的
 * Pi 列。未显式设置的项沿用 LVGL 9.5 lv_conf_internal.h 的默认值。
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

/* ---- 内存池 ---- */
#define LV_MEM_SIZE (128 * 1024U)   /* 复杂 UI 可提到 256 KB */
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

/* ---- 字体：v1 只带内置 Montserrat，中文方案见 README Roadmap ---- */
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_DEFAULT &lv_font_montserrat_14

/* ---- 图像文件解码 / 文件系统（Image.fromFile）
   lodepng 是 LVGL 内置解码器，不引入外部依赖；文件访问走 STDIO（fopen），
   垫片会把系统路径拼成 "A:<path>"。 ---- */
#define LV_USE_LODEPNG 1
#define LV_USE_FS_STDIO 1
#define LV_FS_STDIO_LETTER 'A'
#define LV_FS_STDIO_PATH ""
#define LV_FS_STDIO_CACHE_SIZE 0

/* ---- 中文拼音输入法（lv_ime_pinyin）：LVGL 9.5 默认关闭，这里与 sdl 配置保持一致。
   注意：候选词是中文，Pi 上要正常显示仍需中文字形（当前 Pi 配置未开
   FreeType / 内置 CJK 子集，字形方案见 README Roadmap）。 ---- */
#define LV_USE_IME_PINYIN 1
#define LV_IME_PINYIN_USE_DEFAULT_DICT 1
#define LV_IME_PINYIN_CAND_TEXT_NUM 6
#define LV_IME_PINYIN_USE_K9_MODE 1
#define LV_IME_PINYIN_K9_CAND_TEXT_NUM 3

#endif /* LV_CONF_H */
