/**
 * FFI 层：数据绑定（`lv_subject` / `lv_observer`）。
 *
 * 对应 LVGL 9 的 `src/core/lv_observer.h`。三类能力：
 *
 * 1. **主题**：`lv_subject_init_int` / `set_int` / `get_int` / `notify` / `deinit`；
 * 2. **观察者**：`lv_subject_add_observer`（通用）与 `..._obj`（带目标控件，
 *    控件删除时 LVGL 会自动移除它 —— 这是 `bind` 相对 `subscribe` 的安全来源）；
 * 3. **声明式绑定**：`lv_obj_bind_flag_if_*` / `lv_label_bind_text` / `lv_*_bind_value`
 *    这一族**完全不需要闭包**，观察者随控件销毁，是本层最省事的部分。
 *
 * `lv_subject_t` 是完整结构，仓颉侧不知道 sizeof，分配走垫片。
 */
package lvglcj

/* ==================== 主题 ==================== */

/** 分配 + `lv_subject_init_int`（垫片；仓颉不知道 lv_subject_t 的大小） */
foreign func lvglcj_subject_new_int_cjbindwrapper(value: Int32): CPointer<lv_subject_t>

/** `lv_subject_deinit` + free（deinit 只清观察者链表，不释放结构自身） */
foreign func lvglcj_subject_free_cjbindwrapper(subject: CPointer<lv_subject_t>): Unit

foreign func lv_subject_set_int(subject: CPointer<lv_subject_t>, value: Int32): Unit

foreign func lv_subject_get_int(subject: CPointer<lv_subject_t>): Int32

foreign func lv_subject_get_previous_int(subject: CPointer<lv_subject_t>): Int32

/** 值下限：`set_int` 小于它会被钳住 */
foreign func lv_subject_set_min_value_int(subject: CPointer<lv_subject_t>, value: Int32): Unit

/** 值上限 */
foreign func lv_subject_set_max_value_int(subject: CPointer<lv_subject_t>, value: Int32): Unit

/** 值没变也强制通知一次（等价「刷新」） */
foreign func lv_subject_notify(subject: CPointer<lv_subject_t>): Unit

foreign func lv_subject_deinit(subject: CPointer<lv_subject_t>): Unit

/* ==================== 观察者 ==================== */

/*
 * 回调签名 `void (*)(lv_observer_t *, lv_subject_t *)`。
 * user_data 存本库的 token；回调里也能用 `lv_observer_get_user_data(observer)` 取回。
 */
foreign func lv_subject_add_observer(subject: CPointer<lv_subject_t>,
    observerCb: CFunc<(CPointer<lv_observer_t>, CPointer<lv_subject_t>) -> Unit>, userData: CPointer<UInt8>): CPointer<lv_observer_t>

/** 带目标控件：控件被删除时 LVGL 自动移除该观察者（无需手工 unsubscribe） */
foreign func lv_subject_add_observer_obj(subject: CPointer<lv_subject_t>,
    observerCb: CFunc<(CPointer<lv_observer_t>, CPointer<lv_subject_t>) -> Unit>, obj: CPointer<lv_obj_t>,
    userData: CPointer<UInt8>): CPointer<lv_observer_t>

foreign func lv_observer_remove(observer: CPointer<lv_observer_t>): Unit

foreign func lv_observer_get_user_data(observer: CPointer<lv_observer_t>): CPointer<UInt8>

/* ==================== 声明式绑定（无闭包） ==================== */

foreign func lv_obj_bind_flag_if_eq(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, flag: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_flag_if_not_eq(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, flag: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_flag_if_gt(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, flag: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_flag_if_ge(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, flag: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_flag_if_lt(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, flag: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_flag_if_le(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, flag: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_state_if_eq(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, state: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_state_if_not_eq(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, state: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_state_if_gt(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, state: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_state_if_ge(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, state: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_state_if_lt(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, state: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

foreign func lv_obj_bind_state_if_le(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, state: UInt32,
    refValue: Int32): CPointer<lv_observer_t>

/** 勾选态 ↔ 主题（0 = 未选，非 0 = 已选），Switch / Checkbox 常用 */
foreign func lv_obj_bind_checked(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>): CPointer<lv_observer_t>

/**
 * 标签文本 ↔ 主题（`fmt` 是 printf 风格，如 `"室温 %d°C"`；传 NULL 等于 `"%d"`）。
 *
 * `fmt` 只存指针**不拷贝**（`lv_label.c:683` 直接把它当 user_data 塞进 observer），
 * 所以本库用 `CStringHolder` 分配寿命与控件一致的缓冲，再挂到 `Widget.keep` 上。
 * 参数类型写 `CPointer<UInt8>`（对应 C 的 `const char *`），
 * 这样能直接传 holder 里的裸指针，不必来回构造 `CString`。
 */
foreign func lv_label_bind_text(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>, fmt: CPointer<UInt8>): CPointer<lv_observer_t>

foreign func lv_bar_bind_value(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>): CPointer<lv_observer_t>

foreign func lv_slider_bind_value(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>): CPointer<lv_observer_t>

foreign func lv_arc_bind_value(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>): CPointer<lv_observer_t>

foreign func lv_roller_bind_value(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>): CPointer<lv_observer_t>

foreign func lv_dropdown_bind_value(obj: CPointer<lv_obj_t>, subject: CPointer<lv_subject_t>): CPointer<lv_observer_t>
