/**
 * FFI 层：布局引擎（flex / grid）。
 *
 * 对应 LVGL 的 `src/layouts/`。这些 API 有个共同点：**改父对象的属性**，
 * 子对象的位置由父对象在布局更新时统一计算，所以子对象的 `x()`/`y()`
 * 在 `Widget.updateLayout()` 之前读到的是旧值。
 *
 * 注意 `LV_STYLE_GRID_COLUMN_DSC_ARRAY` 一类的描述符是 `const int32_t *`，
 * LVGL **只保存指针不拷贝**，因此必须用 `Widget.keepBuf()` 把数组所有权交给控件。
 */
package lvglcj

/* ==================== flex（lv_flex.h） ==================== */

foreign func lv_obj_set_flex_flow(obj: CPointer<lv_obj_t>, flow: UInt32): Unit

foreign func lv_obj_set_flex_align(obj: CPointer<lv_obj_t>, mainPlace: UInt32, crossPlace: UInt32,
    trackCrossPlace: UInt32): Unit

foreign func lv_obj_set_flex_grow(obj: CPointer<lv_obj_t>, grow: UInt8): Unit

/* flex 的间距就是 style 的 pad_row / pad_column */
foreign func lv_obj_set_style_pad_row(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_pad_column(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

/**
 * `LV_FLEX_FLOW_*`（lv_flex.h:44，**不是** 0..7 顺序：ROW_WRAP 是 COLUMN|WRAP 之类的位组合）。
 * 写错不会有编译错误，只会让布局方向静默不对，所以这里逐条对照头文件。
 */
public const LV_FLEX_FLOW_ROW: UInt32 = 0x00
public const LV_FLEX_FLOW_COLUMN: UInt32 = 0x01
public const LV_FLEX_FLOW_ROW_WRAP: UInt32 = 0x04
public const LV_FLEX_FLOW_ROW_REVERSE: UInt32 = 0x08
public const LV_FLEX_FLOW_ROW_WRAP_REVERSE: UInt32 = 0x0C
public const LV_FLEX_FLOW_COLUMN_WRAP: UInt32 = 0x05
public const LV_FLEX_FLOW_COLUMN_REVERSE: UInt32 = 0x09
public const LV_FLEX_FLOW_COLUMN_WRAP_REVERSE: UInt32 = 0x0D

/** `LV_FLEX_ALIGN_*`（lv_flex.h:35） */
public const LV_FLEX_ALIGN_START: UInt32 = 0
public const LV_FLEX_ALIGN_END: UInt32 = 1
public const LV_FLEX_ALIGN_CENTER: UInt32 = 2
public const LV_FLEX_ALIGN_SPACE_EVENLY: UInt32 = 3
public const LV_FLEX_ALIGN_SPACE_AROUND: UInt32 = 4
public const LV_FLEX_ALIGN_SPACE_BETWEEN: UInt32 = 5

/* ==================== grid（lv_grid.h） ==================== */

/**
 * 一次设置列/行描述符（等价 `lv_obj_set_grid_dsc_array`）。
 *
 * 两个数组都是 `const int32_t *`，LVGL **不拷贝**，必须以 `keepBuf` 交给控件保管；
 * 且数组必须以 `LV_GRID_TEMPLATE_LAST` 结尾。
 */
foreign func lv_obj_set_grid_dsc_array(obj: CPointer<lv_obj_t>, colDsc: CPointer<Int32>, rowDsc: CPointer<Int32>): Unit

foreign func lv_obj_set_grid_align(obj: CPointer<lv_obj_t>, columnAlign: UInt32, rowAlign: UInt32): Unit

foreign func lv_obj_set_grid_cell(obj: CPointer<lv_obj_t>, columnAlign: UInt32, colPos: Int32, colSpan: Int32,
    rowAlign: UInt32, rowPos: Int32, rowSpan: Int32): Unit

/** `LV_GRID_FR(x)` 是宏（`LV_COORD_MAX - 100 + x`），仓颉侧走这个官方绑定入口，别自己重算常量 */
foreign func lv_grid_fr(x: UInt8): Int32

/* LV_LAYOUT_*（lv_layout.h:37，NONE=0 / FLEX=1 / GRID=2） */
public const LV_LAYOUT_NONE: UInt32 = 0
public const LV_LAYOUT_FLEX: UInt32 = 1
public const LV_LAYOUT_GRID: UInt32 = 2

/* LV_COORD_MAX = (1 << LV_COORD_TYPE_SHIFT) - 1 = (1 << 29) - 1 */
public const LV_GRID_TEMPLATE_LAST: Int32 = 0x1FFFFFFF
public const LV_GRID_CONTENT: Int32 = 0x1FFFFFFF - 101

/**
 * `LV_GRID_ALIGN_*`（lv_grid.h:43）。
 * 注意：顺序与 flex 不同，grid 是 START / **CENTER** / END，
 * flex 是 START / **END** / CENTER —— 照 flex 的顺序写会得到错误的对齐。
 */
public const LV_GRID_ALIGN_START: UInt32 = 0
public const LV_GRID_ALIGN_CENTER: UInt32 = 1
public const LV_GRID_ALIGN_END: UInt32 = 2
public const LV_GRID_ALIGN_STRETCH: UInt32 = 3
public const LV_GRID_ALIGN_SPACE_EVENLY: UInt32 = 4
public const LV_GRID_ALIGN_SPACE_AROUND: UInt32 = 5
public const LV_GRID_ALIGN_SPACE_BETWEEN: UInt32 = 6
