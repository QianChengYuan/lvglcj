/**
 * @file lvgl_shim.h
 * @brief lvglcj C 垫片层：把 LVGL 头文件里的宏 / static inline / 按值结构体参数
 *        包装成可链接的真函数，统一以 _cjbindwrapper 结尾。
 *
 * 规则（见 README「一.2 为什么必须有一层 C 垫片」）：
 *   凡是头文件里没有独立可链接符号的（宏、static inline、导出常量），一律先进本层。
 */
#ifndef LVGL_SHIM_H
#define LVGL_SHIM_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* 版本号：LVGL_VERSION_* 是 CMake 生成的编译期宏，没有可链接符号        */
/* ------------------------------------------------------------------ */
uint32_t lv_version_major_cjbindwrapper(void);
uint32_t lv_version_minor_cjbindwrapper(void);
uint32_t lv_version_patch_cjbindwrapper(void);

/* ------------------------------------------------------------------ */
/* 宏 / static inline 包装                                            */
/* ------------------------------------------------------------------ */
int32_t  lv_pct_cjbindwrapper(int32_t x);                       /* LV_PCT(x) 宏 */
lv_color_t lv_color_hex_cjbindwrapper(uint32_t hex);            /* 真函数，此处仅为统一入口 */
void     lv_style_set_pad_all_cjbindwrapper(lv_style_t * style, int32_t value); /* static inline */

/* ------------------------------------------------------------------ */
/* 不透明类型的堆分配 / 释放（仓颉侧只持 CPointer）                     */
/* ------------------------------------------------------------------ */
lv_style_t     * lv_style_new_cjbindwrapper(void);              /* malloc + lv_style_init */
void            lv_style_delete_cjbindwrapper(lv_style_t * style); /* lv_style_reset + free */
lv_image_dsc_t * lv_image_dsc_new_cjbindwrapper(void);          /* malloc + 清零 */
void            lv_image_dsc_delete_cjbindwrapper(lv_image_dsc_t * dsc);

/* lv_image_dsc_t 头部是位域结构，仓颉 @C struct 无法表达，统一在 C 侧填充 */
void   lv_image_dsc_fill_cjbindwrapper(lv_image_dsc_t * dsc, uint32_t cf,
                                       uint32_t w, uint32_t h, uint32_t stride,
                                       const uint8_t * data, uint32_t data_size);
size_t lv_sizeof_image_dsc_cjbindwrapper(void);
size_t lv_offsetof_image_dsc_data_cjbindwrapper(void);

/* ------------------------------------------------------------------ */
/* 画布高层绘制：9.5 起 canvas 的 draw_rect/draw_text 走                */
/* lv_canvas_init_layer + lv_draw_rect/lv_draw_label + finish_layer，  */
/* 涉及 lv_layer_t / dsc 内部结构，封装成本层一个函数                    */
/* ------------------------------------------------------------------ */
void lv_canvas_draw_rect_cjbindwrapper(lv_obj_t * canvas, int32_t x, int32_t y,
                                       int32_t w, int32_t h, int32_t radius,
                                       lv_color_t color, lv_opa_t opa);
void lv_canvas_draw_text_cjbindwrapper(lv_obj_t * canvas, int32_t x, int32_t y,
                                       int32_t w, const char * text,
                                       const lv_font_t * font, lv_color_t color,
                                       lv_opa_t opa);

/* ------------------------------------------------------------------ */
/* 字体：lv_font_montserrat_N 是数据符号（无函数入口），这里交出指针     */
/* ------------------------------------------------------------------ */
const lv_font_t * lv_font_montserrat_cjbindwrapper(int32_t size);
const lv_font_t * lv_font_default_cjbindwrapper(void);

/* ------------------------------------------------------------------ */
/* Linux 显示后端（DRM / fbdev）                                        */
/*                                                                     */
/* lv_conf.h 关闭对应开关时，liblvgl.a 中不存在这些符号；垫片按平台给出  */
/* 转发或空实现，保证仓颉侧 API 在所有平台都能链接。                     */
/* 返回 NULL / LV_RESULT_INVALID 表示该后端在当前构建不可用。            */
/* ------------------------------------------------------------------ */
lv_display_t * lvglcj_linux_drm_create_cjbindwrapper(void);
int32_t        lvglcj_linux_drm_set_file_cjbindwrapper(lv_display_t * disp, const char * file,
                                                       int64_t connector_id);

lv_display_t * lvglcj_linux_fbdev_create_cjbindwrapper(void);
int32_t        lvglcj_linux_fbdev_set_file_cjbindwrapper(lv_display_t * disp, const char * file);
void           lvglcj_linux_fbdev_set_force_refresh_cjbindwrapper(lv_display_t * disp, bool enabled);

/* ------------------------------------------------------------------ */
/* evdev 输入驱动（同上：关闭 LV_USE_EVDEV 时给空实现）                  */
/* discovery 回调的枚举参数统一按 uint32_t 传，具体类型在 .c 内强转       */
/* ------------------------------------------------------------------ */
typedef void (* lvglcj_evdev_discovery_cb_t)(lv_indev_t * indev, uint32_t type, void * user_data);

lv_indev_t * lvglcj_evdev_create_cjbindwrapper(uint32_t indev_type, const char * dev_path);
lv_indev_t * lvglcj_evdev_create_fd_cjbindwrapper(uint32_t indev_type, int fd);
void         lvglcj_evdev_delete_cjbindwrapper(lv_indev_t * indev);
void         lvglcj_evdev_set_calibration_cjbindwrapper(lv_indev_t * indev, int32_t min_x,
                                                        int32_t min_y, int32_t max_x, int32_t max_y);
void         lvglcj_evdev_set_swap_axes_cjbindwrapper(lv_indev_t * indev, bool swap_axes);
int32_t      lvglcj_evdev_discovery_start_cjbindwrapper(lvglcj_evdev_discovery_cb_t cb, void * user_data);
int32_t      lvglcj_evdev_discovery_stop_cjbindwrapper(void);

/* ------------------------------------------------------------------ */
/* FreeType 字体（LV_USE_FREETYPE=0 时返回 NULL，字体回落 LV_FONT_DEFAULT） */
/* style: 0=Normal, 1=Italic, 2=Bold                                       */
/* ------------------------------------------------------------------ */
lv_font_t * lvglcj_freetype_font_create_cjbindwrapper(const char * pathname, uint32_t size,
                                                      uint32_t style);
void        lvglcj_freetype_font_delete_cjbindwrapper(lv_font_t * font);

/* ------------------------------------------------------------------ */
/* 字体缺字回退链（LVGL 9.5 lv_font_t::fallback）                      */
/* 例如系统 CJK 字体不含拉丁字形时，缺的字会去 fallback 字体里找。      */
/* fallback 传 NULL 表示清空回退链。                                    */
/* ------------------------------------------------------------------ */
void            lvglcj_font_set_fallback_cjbindwrapper(lv_font_t * font, const lv_font_t * fallback);
const lv_font_t * lvglcj_font_get_fallback_cjbindwrapper(const lv_font_t * font);

/* ------------------------------------------------------------------ */
/* 图像文件加载                                                        */
/* LVGL 的 lv_image_set_src() 只认带驱动器字母的路径（"A:/xxx.png"），   */
/* 本函数在 C 侧补上前缀，仓颉侧直接传系统路径即可。                     */
/* LV_USE_FS_STDIO=0 时返回 LV_RESULT_INVALID。返回 OK 只表示已交给     */
/* LVGL，**不保证解码成功**（解不出来 LVGL 会打 WARN 日志）。            */
/* ------------------------------------------------------------------ */
int32_t lvglcj_image_set_file_cjbindwrapper(lv_obj_t * img, const char * path);

/* ------------------------------------------------------------------ */
/* 动画                                                                */
/*                                                                     */
/* lv_anim_t 是**完整结构**（不是不透明句柄），仓颉侧既不知道 sizeof 也  */
/* 不该去猜，因此由本层分配 / 释放。                                     */
/*                                                                     */
/* lv_anim_path_linear / ease_out 等是**函数**而不是数据符号，仓颉的     */
/* `foreign func` 只能调用、取不到函数地址，所以按枚举号换函数指针。      */
/* easing 编号与仓颉侧 `Easing` 枚举一一对应：                           */
/*   0=linear 1=ease_in 2=ease_out 3=ease_in_out                          */
/*   4=overshoot 5=bounce 6=step                                          */
/* ------------------------------------------------------------------ */
lv_anim_t * lvglcj_anim_new_cjbindwrapper(void);
void        lvglcj_anim_free_cjbindwrapper(lv_anim_t * a);
void        lvglcj_anim_set_easing_cjbindwrapper(lv_anim_t * a, uint32_t easing);

#ifdef __cplusplus
}
#endif

#endif /* LVGL_SHIM_H */
