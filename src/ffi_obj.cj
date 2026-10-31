/**
 * FFI 层：基础对象（lv_obj_*）。
 * 枚举值见文件末尾的常量区（与 C 头文件逐一核对，无需链接）。
 */
package lvglcj

/* ---- 生命周期 ---- */
foreign func lv_obj_create(parent: CPointer<lv_obj_t>): CPointer<lv_obj_t>

foreign func lv_obj_delete(obj: CPointer<lv_obj_t>): Unit

foreign func lv_obj_delete_async(obj: CPointer<lv_obj_t>): Unit

foreign func lv_obj_clean(obj: CPointer<lv_obj_t>): Unit

foreign func lv_obj_get_parent(obj: CPointer<lv_obj_t>): CPointer<lv_obj_t>

/**
 * 对象是否仍在某个 display 的对象树上（9.5 提供，遍历屏幕树比较地址、不解引用入参）。
 *
 * 给「包装对象不知道自己已经随父对象被删」兜底：对 `lv_obj_delete` 一个已回收的
 * 地址会直接踩内存池，删前先问一句能把它降级成「什么都不做」。
 */
foreign func lv_obj_is_valid(obj: CPointer<lv_obj_t>): Bool

foreign func lv_obj_get_display(obj: CPointer<lv_obj_t>): CPointer<lv_display_t>

foreign func lv_obj_invalidate(obj: CPointer<lv_obj_t>): Unit

/* ---- 位置 / 尺寸 ---- */
foreign func lv_obj_set_pos(obj: CPointer<lv_obj_t>, x: Int32, y: Int32): Unit

foreign func lv_obj_set_x(obj: CPointer<lv_obj_t>, x: Int32): Unit

foreign func lv_obj_set_y(obj: CPointer<lv_obj_t>, y: Int32): Unit

foreign func lv_obj_set_size(obj: CPointer<lv_obj_t>, w: Int32, h: Int32): Unit

foreign func lv_obj_set_width(obj: CPointer<lv_obj_t>, w: Int32): Unit

foreign func lv_obj_set_height(obj: CPointer<lv_obj_t>, h: Int32): Unit

foreign func lv_obj_get_width(obj: CPointer<lv_obj_t>): Int32

foreign func lv_obj_get_height(obj: CPointer<lv_obj_t>): Int32

foreign func lv_obj_get_x(obj: CPointer<lv_obj_t>): Int32

foreign func lv_obj_get_y(obj: CPointer<lv_obj_t>): Int32

foreign func lv_obj_get_content_width(obj: CPointer<lv_obj_t>): Int32

foreign func lv_obj_get_content_height(obj: CPointer<lv_obj_t>): Int32

foreign func lv_obj_align(obj: CPointer<lv_obj_t>, align: UInt32, xOfs: Int32, yOfs: Int32): Unit

foreign func lv_obj_set_align(obj: CPointer<lv_obj_t>, align: UInt32): Unit

foreign func lv_obj_center(obj: CPointer<lv_obj_t>): Unit

foreign func lv_obj_update_layout(obj: CPointer<lv_obj_t>): Unit

/* ---- 标志 / 状态 ---- */
foreign func lv_obj_add_flag(obj: CPointer<lv_obj_t>, f: UInt32): Unit

foreign func lv_obj_remove_flag(obj: CPointer<lv_obj_t>, f: UInt32): Unit

foreign func lv_obj_has_flag(obj: CPointer<lv_obj_t>, f: UInt32): Bool

foreign func lv_obj_get_state(obj: CPointer<lv_obj_t>): UInt32

foreign func lv_obj_add_state(obj: CPointer<lv_obj_t>, state: UInt32): Unit

foreign func lv_obj_remove_state(obj: CPointer<lv_obj_t>, state: UInt32): Unit

/* ---- 样式 ---- */
foreign func lv_obj_add_style(obj: CPointer<lv_obj_t>, style: CPointer<lv_style_t>, selector: UInt32): Unit

foreign func lv_obj_remove_style(obj: CPointer<lv_obj_t>, style: CPointer<lv_style_t>, selector: UInt32): Unit

foreign func lv_obj_remove_theme(obj: CPointer<lv_obj_t>, selector: UInt32): Unit

foreign func lv_obj_refresh_style(obj: CPointer<lv_obj_t>, selector: UInt32): Unit

/* ---- 事件 ---- */
foreign func lv_obj_add_event_cb(obj: CPointer<lv_obj_t>, eventCb: CFunc<(CPointer<lv_event_t>) -> Unit>,
    filter: UInt32, userData: CPointer<Unit>): CPointer<Unit>

foreign func lv_obj_send_event(obj: CPointer<lv_obj_t>, eventCode: UInt32, param: CPointer<Unit>): Int32

/* ---- 用户数据 ---- */
foreign func lv_obj_set_user_data(obj: CPointer<lv_obj_t>, userData: CPointer<Unit>): Unit

foreign func lv_obj_get_user_data(obj: CPointer<lv_obj_t>): CPointer<Unit>

/* ---- 事件查询 ---- */
foreign func lv_event_get_code(e: CPointer<lv_event_t>): UInt32

foreign func lv_event_get_target(e: CPointer<lv_event_t>): CPointer<lv_obj_t>

/**
 * 当前被调用的对象（冒泡时是**祖先**，不是最初的目标）。
 * 与 `lv_event_get_target` 比较即可判断这次回调是「自己发出」还是「子对象冒泡上来」。
 */
foreign func lv_event_get_current_target_obj(e: CPointer<lv_event_t>): CPointer<lv_obj_t>

foreign func lv_event_get_param(e: CPointer<lv_event_t>): CPointer<Unit>

/* ==================== 常量（与 C 头文件核对，编译期值） ==================== */

/* LV_OBJ_FLAG_*（lv_obj.h，9.5 实测值：0x1/0x2/0x4/0x8/0x10/0x20/0x300） */
public const LV_OBJ_FLAG_HIDDEN: UInt32 = 1 << 0
public const LV_OBJ_FLAG_CLICKABLE: UInt32 = 1 << 1
public const LV_OBJ_FLAG_CLICK_FOCUSABLE: UInt32 = 1 << 2
public const LV_OBJ_FLAG_CHECKABLE: UInt32 = 1 << 3
public const LV_OBJ_FLAG_SCROLLABLE: UInt32 = 1 << 4
/* CHAIN 是 HOR|VER 两位的组合（0x300），不是单个位 */
public const LV_OBJ_FLAG_SCROLL_CHAIN: UInt32 = (1 << 8) | (1 << 9)
public const LV_OBJ_FLAG_SCROLL_ELASTIC: UInt32 = 1 << 5
/* 事件冒泡：只有**发出事件的对象**带这一位，父对象才会收到（lv_obj.h:64，1u<<14） */
public const LV_OBJ_FLAG_EVENT_BUBBLE: UInt32 = 1 << 14

/* LV_STATE_*（lv_obj_style.h，selector = part | state，0 即 MAIN|DEFAULT） */
public const LV_STATE_DEFAULT: UInt32 = 0
public const LV_STATE_CHECKED: UInt32 = 1 << 2
public const LV_STATE_FOCUSED: UInt32 = 1 << 3
public const LV_STATE_PRESSED: UInt32 = 1 << 7
public const LV_STATE_DISABLED: UInt32 = 1 << 9
public const LV_STATE_ANY: UInt32 = 0xFFFF

/* LV_PART_*（lv_obj_style.h，9.5 起 part 位于 selector 高 16 位之上的偏移量） */
public const LV_PART_MAIN: UInt32 = 0
public const LV_PART_SCROLLBAR: UInt32 = 0x010000
public const LV_PART_INDICATOR: UInt32 = 0x020000
public const LV_PART_KNOB: UInt32 = 0x030000
public const LV_PART_CURSOR: UInt32 = 0x060000
public const LV_PART_ANY: UInt32 = 0x0F0000

/* LV_ALIGN_*（lv_area.h） */
public const LV_ALIGN_DEFAULT: UInt32 = 0
public const LV_ALIGN_TOP_LEFT: UInt32 = 1
public const LV_ALIGN_TOP_MID: UInt32 = 2
public const LV_ALIGN_TOP_RIGHT: UInt32 = 3
public const LV_ALIGN_BOTTOM_LEFT: UInt32 = 4
public const LV_ALIGN_BOTTOM_MID: UInt32 = 5
public const LV_ALIGN_BOTTOM_RIGHT: UInt32 = 6
public const LV_ALIGN_LEFT_MID: UInt32 = 7
public const LV_ALIGN_RIGHT_MID: UInt32 = 8
public const LV_ALIGN_CENTER: UInt32 = 9

/* LV_EVENT_*（lv_event.h） */
public const LV_EVENT_ALL: UInt32 = 0
public const LV_EVENT_PRESSED: UInt32 = 1
public const LV_EVENT_PRESSING: UInt32 = 2
public const LV_EVENT_PRESS_LOST: UInt32 = 3
public const LV_EVENT_SHORT_CLICKED: UInt32 = 4
public const LV_EVENT_SINGLE_CLICKED: UInt32 = 5
public const LV_EVENT_DOUBLE_CLICKED: UInt32 = 6
public const LV_EVENT_TRIPLE_CLICKED: UInt32 = 7
public const LV_EVENT_LONG_PRESSED: UInt32 = 8
public const LV_EVENT_LONG_PRESSED_REPEAT: UInt32 = 9
public const LV_EVENT_CLICKED: UInt32 = 10
public const LV_EVENT_RELEASED: UInt32 = 11
public const LV_EVENT_VALUE_CHANGED: UInt32 = 35
public const LV_EVENT_DELETE: UInt32 = 42

/* LV_INDEV_TYPE_*（lv_indev.h） */
public const LV_INDEV_TYPE_NONE: UInt32 = 0
public const LV_INDEV_TYPE_POINTER: UInt32 = 1
public const LV_INDEV_TYPE_KEYPAD: UInt32 = 2
public const LV_INDEV_TYPE_BUTTON: UInt32 = 3
public const LV_INDEV_TYPE_ENCODER: UInt32 = 4

/* LV_INDEV_STATE_*（lv_indev.h） */
public const LV_INDEV_STATE_RELEASED: UInt32 = 0
public const LV_INDEV_STATE_PRESSED: UInt32 = 1

/* LV_DISPLAY_ROTATION_*（lv_display.h） */
public const LV_DISPLAY_ROTATION_0: UInt32 = 0
public const LV_DISPLAY_ROTATION_90: UInt32 = 1
public const LV_DISPLAY_ROTATION_180: UInt32 = 2
public const LV_DISPLAY_ROTATION_270: UInt32 = 3

/* LV_DISPLAY_RENDER_MODE_*（lv_display.h） */
public const LV_DISPLAY_RENDER_MODE_PARTIAL: UInt32 = 0
public const LV_DISPLAY_RENDER_MODE_DIRECT: UInt32 = 1
public const LV_DISPLAY_RENDER_MODE_FULL: UInt32 = 2

/* LV_COLOR_FORMAT_*（lv_color.h） */
public const LV_COLOR_FORMAT_RGB565: UInt32 = 0x12
public const LV_COLOR_FORMAT_RGB565_SWAPPED: UInt32 = 0x1B
public const LV_COLOR_FORMAT_RGB888: UInt32 = 0x0F
public const LV_COLOR_FORMAT_XRGB8888: UInt32 = 0x11
public const LV_COLOR_FORMAT_ARGB8888: UInt32 = 0x10
public const LV_COLOR_FORMAT_L8: UInt32 = 0x06
public const LV_COLOR_FORMAT_I1: UInt32 = 0x07
public const LV_COLOR_FORMAT_I8: UInt32 = 0x0A

/* LV_RESULT_*（lv_types.h）：注意 INVALID 在前，故 INVALID=0、OK=1，别写反 */
public const LV_RESULT_OK: Int32 = 1
public const LV_RESULT_INVALID: Int32 = 0
