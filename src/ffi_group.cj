/**
 * FFI 层：焦点组（`lv_group`）。
 *
 * 对应 LVGL 9 的 `src/core/lv_group.h`。焦点组把「一组可聚焦控件」和「一个输入设备」
 * 连起来：键盘 / 编码器滚动时，焦点在组内控件间移动，被聚焦的控件收到
 * `LV_EVENT_FOCUSED` / `LV_EVENT_DEFOCUSED`（以及 `LV_EVENT_KEY`）。
 *
 * 注意两个容易记错的签名：
 * 1. **`lv_group_remove_obj(obj)` 收的是控件**，不是组 —— 从一个组摘一个控件；
 * 2. `lv_group_focus_obj(obj)` 同理，也是按控件聚焦。
 *
 * `lv_group_t` 是完整结构，仓颉侧不知道 sizeof，分配走 `lv_group_create`。
 */
package lvglcj

/* ---- 生命周期 ---- */

foreign func lv_group_create(): CPointer<lv_group_t>

/** 删除组；LVGL 会一并从所有输入设备上摘掉它，并清掉默认组指针 */
foreign func lv_group_delete(group: CPointer<lv_group_t>): Unit

foreign func lv_group_get_default(): CPointer<lv_group_t>

foreign func lv_group_set_default(group: CPointer<lv_group_t>): Unit

/* ---- 成员 ---- */

foreign func lv_group_add_obj(group: CPointer<lv_group_t>, obj: CPointer<lv_obj_t>): Unit

/** 摘掉单个控件（参数是控件！） */
foreign func lv_group_remove_obj(obj: CPointer<lv_obj_t>): Unit

foreign func lv_group_remove_all_objs(group: CPointer<lv_group_t>): Unit

foreign func lv_group_get_obj_by_index(group: CPointer<lv_group_t>, index: UInt32): CPointer<lv_obj_t>

/* ---- 焦点 ---- */

/** 聚焦到某个控件（参数是控件！） */
foreign func lv_group_focus_obj(obj: CPointer<lv_obj_t>): Unit

foreign func lv_group_focus_next(group: CPointer<lv_group_t>): Unit

foreign func lv_group_focus_prev(group: CPointer<lv_group_t>): Unit

/** 冻结焦点（`true` 时 focus_next/prev 不再移动） */
foreign func lv_group_focus_freeze(group: CPointer<lv_group_t>, en: Bool): Unit

/**
 * 焦点变化回调，签名 `void (*)(lv_group_t *)`。
 * 回调里用 `lv_group_get_focused` 取新的焦点控件。
 */
foreign func lv_group_set_focus_cb(group: CPointer<lv_group_t>, focusCb: CFunc<(CPointer<lv_group_t>) -> Unit>): Unit

foreign func lv_group_get_focused(group: CPointer<lv_group_t>): CPointer<lv_obj_t>

/* ---- 编辑态 / 环绕 ---- */

foreign func lv_group_set_editing(group: CPointer<lv_group_t>, edit: Bool): Unit

foreign func lv_group_get_editing(group: CPointer<lv_group_t>): Bool

foreign func lv_group_set_wrap(group: CPointer<lv_group_t>, en: Bool): Unit

foreign func lv_group_get_wrap(group: CPointer<lv_group_t>): Bool

/* ---- 用户数据（本库不用，留给调用方挂自己的上下文） ---- */

foreign func lv_group_set_user_data(group: CPointer<lv_group_t>, userData: CPointer<Unit>): Unit

foreign func lv_group_get_user_data(group: CPointer<lv_group_t>): CPointer<Unit>
