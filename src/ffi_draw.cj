/**
 * FFI 层：样式 / 主题 / 画布高层绘制 / 内存诊断 / 字体 / 垫片桥接。
 *
 * 颜色参数统一传 lv_color_t（9.5 起为 3 字节 BGR 值结构，@C struct 可直接映射），
 * 不再需要按值传颜色的 u32 垫片。
 */
package lvglcj

/* ---- 样式生命周期 ---- */
foreign func lv_style_init(style: CPointer<lv_style_t>): Unit
foreign func lv_style_reset(style: CPointer<lv_style_t>): Unit

/* ---- 样式属性（bg/border/text/shadow 族） ---- */
foreign func lv_style_set_bg_color(style: CPointer<lv_style_t>, value: lv_color_t): Unit
foreign func lv_style_set_bg_opa(style: CPointer<lv_style_t>, value: UInt8): Unit
foreign func lv_style_set_border_color(style: CPointer<lv_style_t>, value: lv_color_t): Unit
foreign func lv_style_set_border_width(style: CPointer<lv_style_t>, value: Int32): Unit
foreign func lv_style_set_text_color(style: CPointer<lv_style_t>, value: lv_color_t): Unit
foreign func lv_style_set_text_font(style: CPointer<lv_style_t>, value: CPointer<lv_font_t>): Unit
foreign func lv_style_set_radius(style: CPointer<lv_style_t>, value: Int32): Unit
foreign func lv_style_set_shadow_width(style: CPointer<lv_style_t>, value: Int32): Unit
foreign func lv_style_set_shadow_opa(style: CPointer<lv_style_t>, value: UInt8): Unit
foreign func lv_style_set_blur_radius(style: CPointer<lv_style_t>, value: Int32): Unit

/* ---- 对象局部样式（selector = part | state，0 即 MAIN|DEFAULT） ---- */
foreign func lv_obj_set_style_bg_color(obj: CPointer<lv_obj_t>, value: lv_color_t, selector: UInt32): Unit
foreign func lv_obj_set_style_bg_opa(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit
foreign func lv_obj_set_style_border_width(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit
foreign func lv_obj_set_style_text_color(obj: CPointer<lv_obj_t>, value: lv_color_t, selector: UInt32): Unit
foreign func lv_obj_set_style_text_font(obj: CPointer<lv_obj_t>, value: CPointer<lv_font_t>, selector: UInt32): Unit
foreign func lv_obj_set_style_radius(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

/* ---- 垫片：static inline 的 pad_all ---- */
foreign func lv_style_set_pad_all_cjbindwrapper(style: CPointer<lv_style_t>, value: Int32): Unit

/* ---- 主题 ---- */
foreign func lv_theme_default_init(disp: CPointer<lv_display_t>, colorPrimary: lv_color_t, colorSecondary: lv_color_t, dark: Bool, font: CPointer<lv_font_t>): CPointer<lv_theme_t>
foreign func lv_theme_apply(obj: CPointer<lv_obj_t>): Unit
foreign func lv_theme_delete(theme: CPointer<lv_theme_t>): Unit

/* ---- 内存诊断 ---- */
foreign func lv_mem_monitor(monP: CPointer<lv_mem_monitor_t>): Unit

/* ---- 颜色格式查询 ---- */
foreign func lv_color_format_get_bpp(cf: UInt32): UInt8
foreign func lv_color_format_get_size(cf: UInt32): UInt8

/* ---- 垫片：不透明类型分配 / 位域填充 / 画布高层绘制 / 字体指针 ---- */
foreign func lv_style_new_cjbindwrapper(): CPointer<lv_style_t>
foreign func lv_style_delete_cjbindwrapper(style: CPointer<lv_style_t>): Unit
foreign func lv_image_dsc_new_cjbindwrapper(): CPointer<lv_image_dsc_t>
foreign func lv_image_dsc_delete_cjbindwrapper(dsc: CPointer<lv_image_dsc_t>): Unit
foreign func lv_image_dsc_fill_cjbindwrapper(dsc: CPointer<lv_image_dsc_t>, cf: UInt32, w: UInt32, h: UInt32, stride: UInt32, data: CPointer<UInt8>, dataSize: UInt32): Unit
foreign func lv_sizeof_image_dsc_cjbindwrapper(): UIntNative
foreign func lv_offsetof_image_dsc_data_cjbindwrapper(): UIntNative
foreign func lv_canvas_draw_rect_cjbindwrapper(canvas: CPointer<lv_obj_t>, x: Int32, y: Int32, w: Int32, h: Int32, radius: Int32, color: lv_color_t, opa: UInt8): Unit
foreign func lv_canvas_draw_text_cjbindwrapper(canvas: CPointer<lv_obj_t>, x: Int32, y: Int32, w: Int32, text: CString, font: CPointer<lv_font_t>, color: lv_color_t, opa: UInt8): Unit
foreign func lv_font_montserrat_cjbindwrapper(size: Int32): CPointer<lv_font_t>
foreign func lv_font_default_cjbindwrapper(): CPointer<lv_font_t>
/* FreeType：按路径加载字体（LV_USE_FREETYPE=0 的构建返回 NULL）。style: 0=Normal 1=Italic 2=Bold */
foreign func lvglcj_freetype_font_create_cjbindwrapper(path: CString, size: UInt32, style: UInt32): CPointer<lv_font_t>
foreign func lvglcj_freetype_font_delete_cjbindwrapper(font: CPointer<lv_font_t>): Unit
