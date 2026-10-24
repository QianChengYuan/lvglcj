/**
 * FFI 层：控件（label / button / image / slider / arc / bar / switch /
 * checkbox / dropdown / roller / textarea / keyboard / list / table /
 * tabview / menu / msgbox / spinbox / scale / line / led / canvas / win / chart）。
 *
 * 注意（9.5 起的变化）：
 * - 已无 lv_label_set_font：字体经样式设置（lv_obj_set_style_text_font，见 ffi_draw.cj）
 * - canvas 已无 draw_rect/draw_text：走垫片 lv_canvas_draw_*_cjbindwrapper（见 ffi_draw.cj）
 */
package lvglcj

/* ---- label ---- */
foreign func lv_label_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_label_set_text(obj: CPointer<lv_obj_t>, text: CString): Unit
foreign func lv_label_set_text_fmt(obj: CPointer<lv_obj_t>, fmt: CString, ...): Unit
foreign func lv_label_set_long_mode(obj: CPointer<lv_obj_t>, longMode: UInt32): Unit

/* ---- button ---- */
foreign func lv_button_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>

/* ---- image ---- */
foreign func lv_image_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_image_set_src(obj: CPointer<lv_obj_t>, src: CPointer<Unit>): Unit
/* 图像文件加载（C 侧补 "A:" 前缀后调 lv_image_set_src；LV_USE_FS_STDIO=0 返回 INVALID） */
foreign func lvglcj_image_set_file_cjbindwrapper(img: CPointer<lv_obj_t>, path: CString): Int32
foreign func lv_image_set_rotation(obj: CPointer<lv_obj_t>, angle: Int32): Unit
foreign func lv_image_set_scale(obj: CPointer<lv_obj_t>, zoom: UInt32): Unit
foreign func lv_image_set_pivot(obj: CPointer<lv_obj_t>, x: Int32, y: Int32): Unit
foreign func lv_image_set_inner_align(obj: CPointer<lv_obj_t>, align: UInt32): Unit

/* ---- slider / arc / bar ---- */
foreign func lv_slider_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_slider_set_value(obj: CPointer<lv_obj_t>, value: Int32, anim: UInt32): Unit
foreign func lv_slider_get_value(obj: CPointer<lv_obj_t>): Int32
foreign func lv_slider_set_range(obj: CPointer<lv_obj_t>, min: Int32, max: Int32): Unit
foreign func lv_arc_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_arc_set_value(obj: CPointer<lv_obj_t>, value: Int32): Unit
foreign func lv_arc_set_bg_angles(obj: CPointer<lv_obj_t>, start: Int32, end: Int32): Unit
foreign func lv_arc_set_rotation(obj: CPointer<lv_obj_t>, rotation: Int32): Unit
foreign func lv_bar_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_bar_set_value(obj: CPointer<lv_obj_t>, value: Int32, anim: UInt32): Unit
foreign func lv_bar_set_range(obj: CPointer<lv_obj_t>, min: Int32, max: Int32): Unit

/* ---- switch / checkbox ---- */
foreign func lv_switch_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_checkbox_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_checkbox_set_text(obj: CPointer<lv_obj_t>, txt: CString): Unit

/* ---- dropdown / roller ---- */
foreign func lv_dropdown_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_dropdown_set_options(obj: CPointer<lv_obj_t>, options: CString): Unit
foreign func lv_roller_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_roller_set_options(obj: CPointer<lv_obj_t>, options: CString, mode: UInt32): Unit
foreign func lv_roller_set_selected(obj: CPointer<lv_obj_t>, selOpt: UInt32, anim: UInt32): Unit

/* ---- textarea / keyboard ---- */
foreign func lv_textarea_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_textarea_set_text(obj: CPointer<lv_obj_t>, txt: CString): Unit
foreign func lv_textarea_set_one_line(obj: CPointer<lv_obj_t>, en: Bool): Unit
foreign func lv_textarea_set_password_mode(obj: CPointer<lv_obj_t>, en: Bool): Unit
foreign func lv_keyboard_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_keyboard_set_textarea(kb: CPointer<lv_obj_t>, ta: CPointer<lv_obj_t>): Unit

/* ---- list / table / tabview ---- */
foreign func lv_list_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_list_add_text(list: CPointer<lv_obj_t>, txt: CString): CPointer<lv_obj_t>
foreign func lv_list_add_button(list: CPointer<lv_obj_t>, icon: CPointer<Unit>, txt: CString): CPointer<lv_obj_t>
foreign func lv_table_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_table_set_cell_value(obj: CPointer<lv_obj_t>, row: UInt32, col: UInt32, txt: CString): Unit
foreign func lv_tabview_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_tabview_add_tab(obj: CPointer<lv_obj_t>, name: CString): CPointer<lv_obj_t>

/* ---- menu / msgbox / win ---- */
foreign func lv_menu_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_msgbox_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_win_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_win_add_title(win: CPointer<lv_obj_t>, txt: CString): CPointer<lv_obj_t>

/* ---- spinbox / scale ---- */
foreign func lv_spinbox_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_spinbox_set_value(obj: CPointer<lv_obj_t>, v: Int32): Unit
foreign func lv_spinbox_set_range(obj: CPointer<lv_obj_t>, minValue: Int32, maxValue: Int32): Unit
foreign func lv_scale_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_scale_set_range(obj: CPointer<lv_obj_t>, min: Int32, max: Int32): Unit

/* ---- line / led / chart ---- */
foreign func lv_line_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_line_set_points(obj: CPointer<lv_obj_t>, points: CPointer<lv_point_t>, pointNum: UInt32): Unit
foreign func lv_led_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_led_set_color(led: CPointer<lv_obj_t>, color: lv_color_t): Unit
foreign func lv_led_set_brightness(led: CPointer<lv_obj_t>, bright: UInt8): Unit
foreign func lv_led_on(led: CPointer<lv_obj_t>): Unit
foreign func lv_led_off(led: CPointer<lv_obj_t>): Unit
foreign func lv_chart_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_chart_set_point_count(obj: CPointer<lv_obj_t>, cnt: UInt32): Unit
/* 9.5 已把 lv_chart_set_range 改名为 lv_chart_set_axis_range(obj, axis, min, max) */
foreign func lv_chart_set_axis_range(obj: CPointer<lv_obj_t>, axis: UInt32, min: Int32, max: Int32): Unit
foreign func lv_chart_set_next_value(obj: CPointer<lv_obj_t>, ser: CPointer<Unit>, value: Int32): Unit
foreign func lv_chart_add_series(obj: CPointer<lv_obj_t>, color: lv_color_t, axis: UInt32): CPointer<Unit>

/* ---- canvas（高层绘制经垫片，见 ffi_draw.cj） ---- */
foreign func lv_canvas_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_canvas_set_buffer(obj: CPointer<lv_obj_t>, buf: CPointer<Unit>, w: Int32, h: Int32, cf: UInt32): Unit
foreign func lv_canvas_set_draw_buf(obj: CPointer<lv_obj_t>, drawBuf: CPointer<lv_draw_buf_t>): Unit
foreign func lv_canvas_set_px(obj: CPointer<lv_obj_t>, x: Int32, y: Int32, color: lv_color_t, opa: UInt8): Unit
foreign func lv_canvas_fill_bg(obj: CPointer<lv_obj_t>, color: lv_color_t, opa: UInt8): Unit
foreign func lv_canvas_buf_size(w: Int32, h: Int32, bpp: UInt8, stride: UInt8): UInt32

/* ---- 绘制缓冲 ---- */
foreign func lv_draw_buf_create(w: UInt32, h: UInt32, cf: UInt32, stride: UInt32): CPointer<lv_draw_buf_t>
foreign func lv_draw_buf_destroy(drawBuf: CPointer<lv_draw_buf_t>): Unit

/* LV_LABEL_LONG_MODE_*（lv_label.h） */
public const LV_LABEL_LONG_MODE_WRAP: UInt32 = 0
public const LV_LABEL_LONG_MODE_DOTS: UInt32 = 1

/* LV_ROLLER_MODE_*（lv_roller.h） */
public const LV_ROLLER_MODE_NORMAL: UInt32 = 0
public const LV_ROLLER_MODE_INFINITE: UInt32 = 1

/* LV_ANIM_*（lv_anim.h） */
public const LV_ANIM_OFF: UInt32 = 0
public const LV_ANIM_ON: UInt32 = 1
/** 无限循环（lv_anim.h: LV_ANIM_REPEAT_INFINITE） */
public const LV_ANIM_REPEAT_INFINITE: UInt32 = 0xFFFFFFFF

/* LV_IMAGE_ALIGN_*（lv_image.h） */
public const LV_IMAGE_ALIGN_DEFAULT: UInt32 = 0
public const LV_IMAGE_ALIGN_TOP_LEFT: UInt32 = 1
public const LV_IMAGE_ALIGN_CENTER: UInt32 = 9

/* ---- span（富文本片段组；9.5 的控件是 lv_spangroup，lv_span 是其中的片段） ---- */
foreign func lv_spangroup_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_spangroup_add_span(obj: CPointer<lv_obj_t>): CPointer<lv_span_t>
foreign func lv_spangroup_set_span_text(obj: CPointer<lv_obj_t>, span: CPointer<lv_span_t>, text: CString): Unit
foreign func lv_spangroup_set_span_style(obj: CPointer<lv_obj_t>, span: CPointer<lv_span_t>, style: CPointer<lv_style_t>): Unit
foreign func lv_spangroup_set_align(obj: CPointer<lv_obj_t>, align: UInt32): Unit
foreign func lv_spangroup_set_overflow(obj: CPointer<lv_obj_t>, overflow: UInt32): Unit
foreign func lv_spangroup_set_indent(obj: CPointer<lv_obj_t>, indent: Int32): Unit
foreign func lv_spangroup_set_mode(obj: CPointer<lv_obj_t>, mode: UInt32): Unit
foreign func lv_spangroup_set_max_lines(obj: CPointer<lv_obj_t>, lines: Int32): Unit
foreign func lv_spangroup_get_span_count(obj: CPointer<lv_obj_t>): UInt32
foreign func lv_spangroup_refresh(obj: CPointer<lv_obj_t>): Unit

/* ---- calendar ---- */
foreign func lv_calendar_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_calendar_set_today_date(obj: CPointer<lv_obj_t>, year: UInt32, month: UInt32, day: UInt32): Unit
foreign func lv_calendar_set_month_shown(obj: CPointer<lv_obj_t>, year: UInt32, month: UInt32): Unit
foreign func lv_calendar_set_highlighted_dates(obj: CPointer<lv_obj_t>, dates: CPointer<lv_calendar_date_t>, num: UIntNative): Unit
foreign func lv_calendar_get_today_date(obj: CPointer<lv_obj_t>): CPointer<lv_calendar_date_t>
/* 返回 lv_result_t（C 枚举，4 字节），对齐本库既有的 LV_RESULT_OK: Int32 写法 */
foreign func lv_calendar_get_pressed_date(obj: CPointer<lv_obj_t>, date: CPointer<lv_calendar_date_t>): Int32
/* 9.5 的日历默认**不带**年月头部，需显式创建（arrow：左右箭头 / dropdown：年月下拉） */
foreign func lv_calendar_add_header_arrow(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_calendar_add_header_dropdown(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>

/* ---- animimg（帧动画） ---- */
foreign func lv_animimg_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_animimg_set_src(obj: CPointer<lv_obj_t>, dsc: CPointer<CPointer<Unit>>, num: UIntNative): Unit
foreign func lv_animimg_set_duration(obj: CPointer<lv_obj_t>, duration: UInt32): Unit
foreign func lv_animimg_set_repeat_count(obj: CPointer<lv_obj_t>, count: UInt32): Unit
foreign func lv_animimg_get_src_count(obj: CPointer<lv_obj_t>): UInt8
foreign func lv_animimg_start(obj: CPointer<lv_obj_t>): Unit

/* ---- ime_pinyin（中文拼音输入法，需 LV_USE_IME_PINYIN=1） ---- */
foreign func lv_ime_pinyin_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>
foreign func lv_ime_pinyin_set_keyboard(obj: CPointer<lv_obj_t>, kb: CPointer<lv_obj_t>): Unit
foreign func lv_ime_pinyin_set_mode(obj: CPointer<lv_obj_t>, mode: UInt32): Unit

/* LV_SPAN_OVERFLOW_*（lv_span.h） */
public const LV_SPAN_OVERFLOW_CLIP: UInt32 = 0
public const LV_SPAN_OVERFLOW_ELLIPSIS: UInt32 = 1

/* LV_SPAN_MODE_*（lv_span.h） */
public const LV_SPAN_MODE_FIXED: UInt32 = 0
public const LV_SPAN_MODE_EXPAND: UInt32 = 1
public const LV_SPAN_MODE_BREAK: UInt32 = 2

/* LV_TEXT_ALIGN_*（lv_text.h） */
public const LV_TEXT_ALIGN_AUTO: UInt32 = 0
public const LV_TEXT_ALIGN_LEFT: UInt32 = 1
public const LV_TEXT_ALIGN_CENTER: UInt32 = 2
public const LV_TEXT_ALIGN_RIGHT: UInt32 = 3

/* LV_IME_PINYIN_MODE_*（lv_ime_pinyin.h） */
public const LV_IME_PINYIN_MODE_K26: UInt32 = 0
public const LV_IME_PINYIN_MODE_K9: UInt32 = 1
public const LV_IME_PINYIN_MODE_K9_NUMBER: UInt32 = 2
