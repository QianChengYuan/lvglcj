/**
 * FFI 层：动画（lv_anim / lv_anim_timeline）与滚动（lv_obj_scroll）。
 *
 * 三组放一起是因为它们共享同一个底层：`lv_anim`。滚动动画（`scroll_by(anim: true)`）
 * 和 `lv_anim` 是同一套定时器，只是 var/exec_cb 由 LVGL 内部持有。
 *
 * **两个类型陷阱**：
 * 1. `lv_anim_t` 是完整结构（不是不透明句柄），仓颉侧不知道 sizeof，
 *    分配一律走垫片 `lvglcj_anim_new_cjbindwrapper()`；
 * 2. `lv_anim_*_path_*` 是**函数**而非数据符号，仓颉的 `foreign` 取不到函数地址，
 *    因此 easing 也走垫片（按枚举号在 C 侧选函数指针）。
 */
package lvglcj

/* ==================== 动画：句柄与配置 ==================== */

/** 分配并 `lv_anim_init` 一个 lv_anim_t（垫片；仓颉侧不知道结构大小） */
foreign func lvglcj_anim_new_cjbindwrapper(): CPointer<lv_anim_t>

/** 释放由 `lvglcj_anim_new_cjbindwrapper` 分配的 lv_anim_t */
foreign func lvglcj_anim_free_cjbindwrapper(a: CPointer<lv_anim_t>): Unit

/** 按 easing 编号设置路径曲线（垫片；`lv_anim_path_*` 是函数不是数据） */
foreign func lvglcj_anim_set_easing_cjbindwrapper(a: CPointer<lv_anim_t>, easing: UInt32): Unit

/*
 * var / user_data 在 C 侧是 `void *`。这里声明成 `uint8_t *`：
 * 仓颉侧用 `LibC.malloc<UInt8>` 取唯一 token，指针宽度与 ABI 完全一致，
 * 省掉 CPointer 之间的强转（`CPointer<Unit>` 的 malloc 会因 sizeOf 为 0 而除零）。
 */
foreign func lv_anim_set_var(a: CPointer<lv_anim_t>, animVar: CPointer<UInt8>): Unit

foreign func lv_anim_set_exec_cb(a: CPointer<lv_anim_t>, cb: CFunc<(CPointer<UInt8>, Int32) -> Unit>): Unit

foreign func lv_anim_set_values(a: CPointer<lv_anim_t>, start: Int32, end: Int32): Unit

foreign func lv_anim_set_duration(a: CPointer<lv_anim_t>, duration: UInt32): Unit

foreign func lv_anim_set_delay(a: CPointer<lv_anim_t>, delay: UInt32): Unit

foreign func lv_anim_set_repeat_count(a: CPointer<lv_anim_t>, cnt: UInt32): Unit

foreign func lv_anim_set_repeat_delay(a: CPointer<lv_anim_t>, delay: UInt32): Unit

/** 反向（回放）时长：0 表示不回放 */
foreign func lv_anim_set_reverse_duration(a: CPointer<lv_anim_t>, duration: UInt32): Unit

foreign func lv_anim_set_reverse_delay(a: CPointer<lv_anim_t>, delay: UInt32): Unit

foreign func lv_anim_set_completed_cb(a: CPointer<lv_anim_t>, cb: CFunc<(CPointer<lv_anim_t>) -> Unit>): Unit

/**
 * 动画生命周期结束回调（**完成和被打断都会触发**，lv_anim.c:701 / 824）。
 * 本库用它做「条目表 + token 内存」的统一释放点，不要删掉。
 */
foreign func lv_anim_set_deleted_cb(a: CPointer<lv_anim_t>, cb: CFunc<(CPointer<lv_anim_t>) -> Unit>): Unit

foreign func lv_anim_set_user_data(a: CPointer<lv_anim_t>, data: CPointer<UInt8>): Unit

foreign func lv_anim_get_user_data(a: CPointer<lv_anim_t>): CPointer<UInt8>

/** 启动动画（内部会 memcpy 一份 lv_anim_t，调用后即可释放传入的那份） */
foreign func lv_anim_start(a: CPointer<lv_anim_t>): CPointer<lv_anim_t>

/** 删除 var + exec_cb 匹配的动画（会触发 deleted_cb） */
foreign func lv_anim_delete(animVar: CPointer<UInt8>, cb: CFunc<(CPointer<UInt8>, Int32) -> Unit>): Bool

/** 查找 var + exec_cb 匹配的动画；未找到返回 NULL */
foreign func lv_anim_get(animVar: CPointer<UInt8>, cb: CFunc<(CPointer<UInt8>, Int32) -> Unit>): CPointer<lv_anim_t>

foreign func lv_anim_delete_all(): Unit

foreign func lv_anim_pause(a: CPointer<lv_anim_t>): Unit

foreign func lv_anim_resume(a: CPointer<lv_anim_t>): Unit

foreign func lv_anim_is_paused(a: CPointer<lv_anim_t>): Bool

/* ==================== 时间线 ==================== */

foreign func lv_anim_timeline_create(): CPointer<lv_anim_timeline_t>

/** 删除时间线。**注意它不会触发各片段动画的 deleted_cb**（见 anim.cj 的说明） */
foreign func lv_anim_timeline_delete(at: CPointer<lv_anim_timeline_t>): Unit

foreign func lv_anim_timeline_add(at: CPointer<lv_anim_timeline_t>, startTime: UInt32, a: CPointer<lv_anim_t>): Unit

foreign func lv_anim_timeline_start(at: CPointer<lv_anim_timeline_t>): UInt32

foreign func lv_anim_timeline_pause(at: CPointer<lv_anim_timeline_t>): Unit

foreign func lv_anim_timeline_set_progress(at: CPointer<lv_anim_timeline_t>, progress: UInt16): Unit

foreign func lv_anim_timeline_get_progress(at: CPointer<lv_anim_timeline_t>): UInt16

foreign func lv_anim_timeline_get_playtime(at: CPointer<lv_anim_timeline_t>): UInt32

foreign func lv_anim_timeline_set_reverse(at: CPointer<lv_anim_timeline_t>, reverse: Bool): Unit

foreign func lv_anim_timeline_set_repeat_count(at: CPointer<lv_anim_timeline_t>, cnt: UInt32): Unit

foreign func lv_anim_timeline_set_repeat_delay(at: CPointer<lv_anim_timeline_t>, delay: UInt32): Unit

/* ==================== 滚动（lv_obj_scroll.h） ==================== */

/* lv_anim_enable_t 就是 bool：true = 带动画，false = 立即到位 */
foreign func lv_obj_scroll_by(obj: CPointer<lv_obj_t>, dx: Int32, dy: Int32, animEn: Bool): Unit

foreign func lv_obj_scroll_to(obj: CPointer<lv_obj_t>, x: Int32, y: Int32, animEn: Bool): Unit

foreign func lv_obj_scroll_to_x(obj: CPointer<lv_obj_t>, x: Int32, animEn: Bool): Unit

foreign func lv_obj_scroll_to_y(obj: CPointer<lv_obj_t>, y: Int32, animEn: Bool): Unit

foreign func lv_obj_scroll_to_view(obj: CPointer<lv_obj_t>, animEn: Bool): Unit

foreign func lv_obj_scroll_to_view_recursive(obj: CPointer<lv_obj_t>, animEn: Bool): Unit

foreign func lv_obj_get_scroll_x(obj: CPointer<lv_obj_t>): Int32

foreign func lv_obj_get_scroll_y(obj: CPointer<lv_obj_t>): Int32

foreign func lv_obj_set_scrollbar_mode(obj: CPointer<lv_obj_t>, mode: UInt32): Unit

foreign func lv_obj_set_scroll_dir(obj: CPointer<lv_obj_t>, dir: UInt32): Unit

foreign func lv_obj_stop_scroll_anim(obj: CPointer<lv_obj_t>): Unit

foreign func lv_obj_is_scrolling(obj: CPointer<lv_obj_t>): Bool

/* `LV_SCROLLBAR_MODE_*`（lv_obj_scroll.h:31） */
public const LV_SCROLLBAR_MODE_OFF: UInt32 = 0
public const LV_SCROLLBAR_MODE_ON: UInt32 = 1
public const LV_SCROLLBAR_MODE_ACTIVE: UInt32 = 2
public const LV_SCROLLBAR_MODE_AUTO: UInt32 = 3

/* `LV_DIR_*`（lv_area.h:77，注意是位标志） */
public const LV_DIR_NONE: UInt32 = 0
public const LV_DIR_LEFT: UInt32 = 1
public const LV_DIR_RIGHT: UInt32 = 2
public const LV_DIR_TOP: UInt32 = 4
public const LV_DIR_BOTTOM: UInt32 = 8
public const LV_DIR_HOR: UInt32 = 3
public const LV_DIR_VER: UInt32 = 12
public const LV_DIR_ALL: UInt32 = 15
