/**
 * @file lvgl_shim.c
 * @brief lvglcj C 垫片层实现。编译方式见 scripts/build_lvgl_{pi,sdl}.sh：
 *        与 LVGL 同工具链、同 lv_conf.h 编译，产物 liblvglcjshim.a。
 */
#include "lvgl_shim.h"

#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* 版本号（读取 CMake 生成的 lv_version.h 宏）                          */
/* ------------------------------------------------------------------ */
uint32_t lv_version_major_cjbindwrapper(void) { return (uint32_t)LVGL_VERSION_MAJOR; }
uint32_t lv_version_minor_cjbindwrapper(void) { return (uint32_t)LVGL_VERSION_MINOR; }
uint32_t lv_version_patch_cjbindwrapper(void) { return (uint32_t)LVGL_VERSION_PATCH; }

/* ------------------------------------------------------------------ */
/* 宏 / static inline 包装                                            */
/* ------------------------------------------------------------------ */
int32_t lv_pct_cjbindwrapper(int32_t x)
{
    return LV_PCT(x);
}

lv_color_t lv_color_hex_cjbindwrapper(uint32_t hex)
{
    return lv_color_hex(hex);
}

void lv_style_set_pad_all_cjbindwrapper(lv_style_t * style, int32_t value)
{
    lv_style_set_pad_all(style, value);
}

/* ------------------------------------------------------------------ */
/* 不透明类型分配 / 释放                                                */
/* ------------------------------------------------------------------ */
lv_style_t * lv_style_new_cjbindwrapper(void)
{
    lv_style_t * style = (lv_style_t *)malloc(sizeof(lv_style_t));
    if(style == NULL) return NULL;
    lv_style_init(style);
    return style;
}

void lv_style_delete_cjbindwrapper(lv_style_t * style)
{
    if(style == NULL) return;
    lv_style_reset(style);
    free(style);
}

lv_image_dsc_t * lv_image_dsc_new_cjbindwrapper(void)
{
    return (lv_image_dsc_t *)calloc(1, sizeof(lv_image_dsc_t));
}

void lv_image_dsc_delete_cjbindwrapper(lv_image_dsc_t * dsc)
{
    free(dsc);
}

void lv_image_dsc_fill_cjbindwrapper(lv_image_dsc_t * dsc, uint32_t cf,
                                     uint32_t w, uint32_t h, uint32_t stride,
                                     const uint8_t * data, uint32_t data_size)
{
    if(dsc == NULL) return;
    memset(dsc, 0, sizeof(*dsc));
    /* header 为位域结构（magic:8/cf:8/flags:16 + w:16/h:16/stride:16/reserved_2:16），
     * 只能整体赋值，无法按字节拼装 —— 这是必须放在 C 侧填充的原因。 */
    dsc->header.magic = LV_IMAGE_HEADER_MAGIC;
    dsc->header.cf = (uint8_t)cf;
    dsc->header.flags = 0;
    dsc->header.w = (uint16_t)w;
    dsc->header.h = (uint16_t)h;
    dsc->header.stride = (uint16_t)stride;
    dsc->data_size = data_size;
    dsc->data = data;
}

size_t lv_sizeof_image_dsc_cjbindwrapper(void)
{
    return sizeof(lv_image_dsc_t);
}

size_t lv_offsetof_image_dsc_data_cjbindwrapper(void)
{
    return offsetof(lv_image_dsc_t, data);
}

/* ------------------------------------------------------------------ */
/* 画布高层绘制（layer API 封装）                                       */
/* ------------------------------------------------------------------ */
void lv_canvas_draw_rect_cjbindwrapper(lv_obj_t * canvas, int32_t x, int32_t y,
                                       int32_t w, int32_t h, int32_t radius,
                                       lv_color_t color, lv_opa_t opa)
{
    lv_layer_t layer;
    lv_canvas_init_layer(canvas, &layer);

    lv_draw_rect_dsc_t dsc;
    lv_draw_rect_dsc_init(&dsc);
    dsc.bg_color = color;
    dsc.bg_opa = opa;
    dsc.radius = radius;

    lv_area_t coords = {
        .x1 = x, .y1 = y,
        .x2 = x + w - 1, .y2 = y + h - 1
    };
    lv_draw_rect(&layer, &dsc, &coords);
    lv_canvas_finish_layer(canvas, &layer);
}

void lv_canvas_draw_text_cjbindwrapper(lv_obj_t * canvas, int32_t x, int32_t y,
                                       int32_t w, const char * text,
                                       const lv_font_t * font, lv_color_t color,
                                       lv_opa_t opa)
{
    const lv_font_t * f = (font != NULL) ? font : LV_FONT_DEFAULT;
    int32_t line_h = lv_font_get_line_height(f);

    lv_layer_t layer;
    lv_canvas_init_layer(canvas, &layer);

    lv_draw_label_dsc_t dsc;
    lv_draw_label_dsc_init(&dsc);
    dsc.text = text;
    dsc.font = f;
    dsc.color = color;
    dsc.opa = opa;

    lv_area_t coords = {
        .x1 = x, .y1 = y,
        .x2 = x + w - 1, .y2 = y + line_h - 1
    };
    lv_draw_label(&layer, &dsc, &coords);
    lv_canvas_finish_layer(canvas, &layer);
}

/* ------------------------------------------------------------------ */
/* 字体指针（lv_font_montserrat_N 为数据符号，按 lv_conf.h 开关裁剪）    */
/* ------------------------------------------------------------------ */
const lv_font_t * lv_font_montserrat_cjbindwrapper(int32_t size)
{
    switch(size) {
#if LV_FONT_MONTSERRAT_8
        case 8:   return &lv_font_montserrat_8;
#endif
#if LV_FONT_MONTSERRAT_10
        case 10:  return &lv_font_montserrat_10;
#endif
#if LV_FONT_MONTSERRAT_12
        case 12:  return &lv_font_montserrat_12;
#endif
#if LV_FONT_MONTSERRAT_14
        case 14:  return &lv_font_montserrat_14;
#endif
#if LV_FONT_MONTSERRAT_16
        case 16:  return &lv_font_montserrat_16;
#endif
#if LV_FONT_MONTSERRAT_18
        case 18:  return &lv_font_montserrat_18;
#endif
#if LV_FONT_MONTSERRAT_20
        case 20:  return &lv_font_montserrat_20;
#endif
#if LV_FONT_MONTSERRAT_22
        case 22:  return &lv_font_montserrat_22;
#endif
#if LV_FONT_MONTSERRAT_24
        case 24:  return &lv_font_montserrat_24;
#endif
#if LV_FONT_MONTSERRAT_28
        case 28:  return &lv_font_montserrat_28;
#endif
#if LV_FONT_MONTSERRAT_32
        case 32:  return &lv_font_montserrat_32;
#endif
#if LV_FONT_MONTSERRAT_40
        case 40:  return &lv_font_montserrat_40;
#endif
#if LV_FONT_MONTSERRAT_48
        case 48:  return &lv_font_montserrat_48;
#endif
        default:  return LV_FONT_DEFAULT;
    }
}

const lv_font_t * lv_font_default_cjbindwrapper(void)
{
    return LV_FONT_DEFAULT;
}

/* ------------------------------------------------------------------ */
/* Linux 显示后端（DRM / fbdev）                                        */
/*                                                                     */
/* lv_conf.h 里关掉 LV_USE_LINUX_DRM / LV_USE_LINUX_FBDEV 时（Windows、 */
/* 无 DRM 的桌面模拟构建），liblvgl.a 里根本不存在同名符号，仓颉侧若直  */
/* 接 foreign 声明这些函数会在链接期报 undefined symbol。这里统一经垫片 */
/* 转发：开启则直连真函数，关闭则给空实现（返回 NULL / LV_RESULT_INVALID），*/
/* 让 Display.drm()/fbdev() 在非 Linux 平台抛可读异常而不是链接失败。   */
/* ------------------------------------------------------------------ */
#if LV_USE_LINUX_DRM
lv_display_t * lvglcj_linux_drm_create_cjbindwrapper(void)
{
    return lv_linux_drm_create();
}

int32_t lvglcj_linux_drm_set_file_cjbindwrapper(lv_display_t * disp, const char * file,
                                                int64_t connector_id)
{
    return (int32_t)lv_linux_drm_set_file(disp, file, connector_id);
}
#else
lv_display_t * lvglcj_linux_drm_create_cjbindwrapper(void)
{
    return NULL;
}

int32_t lvglcj_linux_drm_set_file_cjbindwrapper(lv_display_t * disp, const char * file,
                                                int64_t connector_id)
{
    (void)disp;
    (void)file;
    (void)connector_id;
    return (int32_t)LV_RESULT_INVALID;
}
#endif /* LV_USE_LINUX_DRM */

#if LV_USE_LINUX_FBDEV
lv_display_t * lvglcj_linux_fbdev_create_cjbindwrapper(void)
{
    return lv_linux_fbdev_create();
}

int32_t lvglcj_linux_fbdev_set_file_cjbindwrapper(lv_display_t * disp, const char * file)
{
    return (int32_t)lv_linux_fbdev_set_file(disp, file);
}

void lvglcj_linux_fbdev_set_force_refresh_cjbindwrapper(lv_display_t * disp, bool enabled)
{
    lv_linux_fbdev_set_force_refresh(disp, enabled);
}
#else
lv_display_t * lvglcj_linux_fbdev_create_cjbindwrapper(void)
{
    return NULL;
}

int32_t lvglcj_linux_fbdev_set_file_cjbindwrapper(lv_display_t * disp, const char * file)
{
    (void)disp;
    (void)file;
    return (int32_t)LV_RESULT_INVALID;
}

void lvglcj_linux_fbdev_set_force_refresh_cjbindwrapper(lv_display_t * disp, bool enabled)
{
    (void)disp;
    (void)enabled;
}
#endif /* LV_USE_LINUX_FBDEV */

/* ------------------------------------------------------------------ */
/* evdev 输入驱动                                                       */
/*                                                                     */
/* 同上：LV_USE_EVDEV=0（如 Windows/MinGW）时 liblvgl.a 无这些符号，此处  */
/* 给空实现，保证 Input.evdev() 系列 API 在所有平台可链接、可抛异常。     */
/* ------------------------------------------------------------------ */
#if LV_USE_EVDEV
lv_indev_t * lvglcj_evdev_create_cjbindwrapper(uint32_t indev_type, const char * dev_path)
{
    return lv_evdev_create((lv_indev_type_t)indev_type, dev_path);
}

lv_indev_t * lvglcj_evdev_create_fd_cjbindwrapper(uint32_t indev_type, int fd)
{
    return lv_evdev_create_fd((lv_indev_type_t)indev_type, fd);
}

void lvglcj_evdev_delete_cjbindwrapper(lv_indev_t * indev)
{
    lv_evdev_delete(indev);
}

void lvglcj_evdev_set_calibration_cjbindwrapper(lv_indev_t * indev, int32_t min_x, int32_t min_y,
                                                int32_t max_x, int32_t max_y)
{
    lv_evdev_set_calibration(indev, (int)min_x, (int)min_y, (int)max_x, (int)max_y);
}

void lvglcj_evdev_set_swap_axes_cjbindwrapper(lv_indev_t * indev, bool swap_axes)
{
    lv_evdev_set_swap_axes(indev, swap_axes);
}

int32_t lvglcj_evdev_discovery_start_cjbindwrapper(lvglcj_evdev_discovery_cb_t cb, void * user_data)
{
    return (int32_t)lv_evdev_discovery_start((lv_evdev_discovery_cb_t)cb, user_data);
}

int32_t lvglcj_evdev_discovery_stop_cjbindwrapper(void)
{
    return (int32_t)lv_evdev_discovery_stop();
}
#else
lv_indev_t * lvglcj_evdev_create_cjbindwrapper(uint32_t indev_type, const char * dev_path)
{
    (void)indev_type;
    (void)dev_path;
    return NULL;
}

lv_indev_t * lvglcj_evdev_create_fd_cjbindwrapper(uint32_t indev_type, int fd)
{
    (void)indev_type;
    (void)fd;
    return NULL;
}

void lvglcj_evdev_delete_cjbindwrapper(lv_indev_t * indev)
{
    (void)indev;
}

void lvglcj_evdev_set_calibration_cjbindwrapper(lv_indev_t * indev, int32_t min_x, int32_t min_y,
                                                int32_t max_x, int32_t max_y)
{
    (void)indev;
    (void)min_x;
    (void)min_y;
    (void)max_x;
    (void)max_y;
}

void lvglcj_evdev_set_swap_axes_cjbindwrapper(lv_indev_t * indev, bool swap_axes)
{
    (void)indev;
    (void)swap_axes;
}

int32_t lvglcj_evdev_discovery_start_cjbindwrapper(lvglcj_evdev_discovery_cb_t cb, void * user_data)
{
    (void)cb;
    (void)user_data;
    return (int32_t)LV_RESULT_INVALID;
}

int32_t lvglcj_evdev_discovery_stop_cjbindwrapper(void)
{
    return (int32_t)LV_RESULT_INVALID;
}
#endif /* LV_USE_EVDEV */

/* ------------------------------------------------------------------ */
/* FreeType 字体：运行时按路径加载系统 TTF/TTC（完整 CJK 字形）          */
/*                                                                     */
/* 注意：9.5 的 lv_init() 内部已经调用过 lv_freetype_init()，这里再调会  */
/* 返回 "freetype already initialized"(LV_RESULT_INVALID)，因此绝不重复 */
/* 初始化，直接创建字体即可；LV_USE_FREETYPE=0 的构建返回 NULL。         */
/* ------------------------------------------------------------------ */
#if LV_USE_FREETYPE
lv_font_t * lvglcj_freetype_font_create_cjbindwrapper(const char * pathname, uint32_t size,
                                                      uint32_t style)
{
    return lv_freetype_font_create(pathname, LV_FREETYPE_FONT_RENDER_MODE_BITMAP, size,
                                   (lv_freetype_font_style_t)style);
}

void lvglcj_freetype_font_delete_cjbindwrapper(lv_font_t * font)
{
    if(font == NULL) return;
    lv_freetype_font_delete(font);
}
#else
lv_font_t * lvglcj_freetype_font_create_cjbindwrapper(const char * pathname, uint32_t size,
                                                      uint32_t style)
{
    (void)pathname;
    (void)size;
    (void)style;
    return NULL;
}

void lvglcj_freetype_font_delete_cjbindwrapper(lv_font_t * font)
{
    (void)font;
}
#endif /* LV_USE_FREETYPE */

/* ------------------------------------------------------------------ */
/* 字体缺字回退链：本字体没有的字形交给 fallback 继续找                  */
/*                                                                     */
/* 典型场景：树莓派的 DroidSansFallbackFull.ttf 只有汉字/假名，没有基本  */
/* 拉丁字母（U+0021..U+007E），直接拿来当主题字体时 "LVGL 9.5" 会全变方框。*/
/* LVGL 9.5 的 lv_font_t 自带 fallback 字段，lv_font_get_glyph_dsc 会沿   */
/* 链逐个尝试（本字体返回的 is_placeholder 会继续往下一级找）。          */
/* ------------------------------------------------------------------ */
void lvglcj_font_set_fallback_cjbindwrapper(lv_font_t * font, const lv_font_t * fallback)
{
    if(font == NULL) return;
    font->fallback = fallback;
}

const lv_font_t * lvglcj_font_get_fallback_cjbindwrapper(const lv_font_t * font)
{
    if(font == NULL) return NULL;
    return font->fallback;
}

/* ------------------------------------------------------------------ */
/* 图像文件加载                                                        */
/*                                                                     */
/* lv_image_set_src() 用 lv_image_src_get_type() 判断来源：以已注册驱动 */
/* 字母 + ':' 开头才算 "文件"，否则会被当成 SYMBOL 去查字库。所以必须先  */
/* 拼出 "A:<path>"（A = LV_FS_STDIO_LETTER）。                          */
/*                                                                     */
/* 路径字符串由 LVGL 内部 lv_strdup() 复制（见 lv_image.c 的 Save the   */
/* source 段），而解码探测也发生在 set_src 内部、buf 仍然有效，因此这里  */
/* 调用完即可释放临时缓冲。                                             */
/* ------------------------------------------------------------------ */
int32_t lvglcj_image_set_file_cjbindwrapper(lv_obj_t * img, const char * path)
{
#if LV_USE_FS_STDIO
    if(img == NULL || path == NULL) return LV_RESULT_INVALID;

    size_t len = strlen(path);
    char * buf = (char *)malloc(len + 3); /* "A:" + path + '\0' */
    if(buf == NULL) return LV_RESULT_INVALID;

    buf[0] = (char)LV_FS_STDIO_LETTER;
    buf[1] = ':';
    memcpy(buf + 2, path, len + 1);

    lv_image_set_src(img, buf);
    free(buf);
    return LV_RESULT_OK;
#else
    (void)img;
    (void)path;
    return LV_RESULT_INVALID;
#endif
}
