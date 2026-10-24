/**
 * FFI 层：类型定义（与友好层同属根包 lvglcj）
 *
 * 背景：仓颉 1.2.0 的 foreign 声明不允许任何访问修饰符、且不可跨包导入
 * （实测：public/protected 均报 "modifiers conflict"，跨包导入报 not accessible），
 * 因此 FFI 层与友好层必须位于同一包内，目录上即 src/ 根目录。
 *
 * 两类 C 类型在仓颉侧的落法：
 * 1. 不透明句柄（lv_display_t/lv_obj_t/...）——空 `@C struct` 占位，只持地址、从不解引用；
 * 2. 按值结构体（lv_area_t/lv_point_t/...）——`@C struct` 逐一映射，字段顺序与 C 一致。
 *
 * 位域结构（lv_image_header_t）无法用 @C struct 表达，统一由垫片
 * lv_image_dsc_fill_cjbindwrapper 在 C 侧填充，仓颉侧只持 lv_image_dsc_t 句柄。
 */
package lvglcj

/* ==================== 不透明句柄 ==================== */

/** 显示设备（DRM/KMS、fbdev、SDL 后端各一份） */
@C
public struct lv_display_t {}

/** 基础对象 / 屏幕 / 控件共用句柄 */
@C
public struct lv_obj_t {}

/** 输入设备 */
@C
public struct lv_indev_t {}

/** 样式（lv_style_t 内部含联合体，仓颉侧视为不透明） */
@C
public struct lv_style_t {}

/** 主题 */
@C
public struct lv_theme_t {}

/** LVGL 定时器 */
@C
public struct lv_timer_t {}

/** 字体（数据符号，指针由垫片 lv_font_*_cjbindwrapper 交出） */
@C
public struct lv_font_t {}

/** 绘制缓冲（9.5 起 canvas / display 均使用） */
@C
public struct lv_draw_buf_t {}

/** 图像描述符（头部为位域，由垫片填充） */
@C
public struct lv_image_dsc_t {}

/** 事件对象 */
@C
public struct lv_event_t {}

/** 输入设备组（键盘焦点管理） */
@C
public struct lv_group_t {}

/** 动画 */
@C
public struct lv_anim_t {}

/** 图像解码器 */
@C
public struct lv_image_decoder_t {}

/** 富文本片段（lv_span_t）：由 lv_spangroup_add_span 交出，仓颉侧只持地址 */
@C
public struct lv_span_t {}

/* ==================== 按值结构体 ==================== */

/** 矩形区域（与 C 布局一致：int32 x1/y1/x2/y2） */
@C
public struct lv_area_t {
    public var x1: Int32 = 0
    public var y1: Int32 = 0
    public var x2: Int32 = 0
    public var y2: Int32 = 0
}

/** 点（int32 x/y） */
@C
public struct lv_point_t {
    public var x: Int32 = 0
    public var y: Int32 = 0
}

/**
 * 颜色。LVGL 9.5 起 lv_color_t 恒为 3 字节 BGR 结构（与 LV_COLOR_DEPTH 无关，
 * 深度只影响渲染时选用的 LV_COLOR_FORMAT_NATIVE）。
 */
@C
public struct lv_color_t {
    public var blue: UInt8 = 0
    public var green: UInt8 = 0
    public var red: UInt8 = 0
}

/** 32 位颜色（含 alpha），用于 I1/2/4/8 调色板等场景 */
@C
public struct lv_color32_t {
    public var blue: UInt8 = 0
    public var green: UInt8 = 0
    public var red: UInt8 = 0
    public var alpha: UInt8 = 0
}

/**
 * 输入设备读取回调的填充结构（lv_indev_data_t）。
 * 字段与 C 侧一致：gesture_type[6] / gesture_data[6] / state / point / key /
 * btn_id / enc_diff / timestamp / continue_reading。
 */
@C
public struct lv_indev_data_t {
    public var gestureType: VArray<UInt32, $6> = VArray<UInt32, $6>(repeat: 0)
    public var gestureData: VArray<CPointer<Unit>, $6> = VArray<CPointer<Unit>, $6>(repeat: CPointer<Unit>())
    public var state: UInt32 = 0
    public var point: lv_point_t = lv_point_t()
    public var key: UInt32 = 0
    public var btnId: UInt32 = 0
    public var encDiff: Int16 = 0
    public var timestamp: UInt32 = 0
    public var continueReading: Bool = false
}

/**
 * 日历日期（lv_calendar_date_t）。
 * 注意 C 侧是 **uint16 year + uint8 month + uint8 day**（共 4 字节），
 * 不是三个 uint32——按 v8 记忆写成同宽会导致布局错位、读写日期全乱。
 */
@C
public struct lv_calendar_date_t {
    public var year: UInt16 = 0
    public var month: UInt8 = 0
    public var day: UInt8 = 0
}

/** 内存监控（lv_mem_monitor_t，size_t 字段映射为 UIntNative） */
@C
public struct lv_mem_monitor_t {
    public var totalSize: UIntNative = 0
    public var freeCnt: UIntNative = 0
    public var freeSize: UIntNative = 0
    public var freeBiggestSize: UIntNative = 0
    public var usedCnt: UIntNative = 0
    public var maxUsed: UIntNative = 0
    public var usedPct: UInt8 = 0
    public var fragPct: UInt8 = 0
}
