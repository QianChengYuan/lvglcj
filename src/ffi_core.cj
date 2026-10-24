/**
 * FFI 层：核心（初始化 / tick / 定时器 / 延时 / 版本）
 * 版本号经垫片读取 CMake 生成的 lv_version.h 宏（编译期常量无链接符号）。
 */
package lvglcj

/* ---- 初始化 ---- */
foreign func lv_init(): Unit

foreign func lv_deinit(): Unit

/* ---- tick（LVGL 的时间基准，缺了它画面会在第一帧后卡死） ---- */
foreign func lv_tick_inc(tickPeriod: UInt32): Unit

foreign func lv_tick_get(): UInt32

foreign func lv_tick_set_cb(cb: CFunc<() -> UInt32>): Unit

/* ---- 延时 / 睡眠 ---- */
foreign func lv_delay_ms(ms: UInt32): Unit

foreign func lv_sleep_ms(ms: UInt32): Unit

/* ---- 主循环 ---- */
/** 泵一次定时器与渲染，返回距下次定时器的毫秒数 */
foreign func lv_timer_handler(): UInt32

foreign func lv_timer_get_idle(): UInt32

foreign func lv_timer_get_time_until_next(): UInt32

/* ---- 定时器 ---- */
foreign func lv_timer_create(cb: CFunc<(CPointer<lv_timer_t>) -> Unit>, period: UInt32, userData: CPointer<Unit>): CPointer<lv_timer_t>

foreign func lv_timer_delete(timer: CPointer<lv_timer_t>): Unit

foreign func lv_timer_pause(timer: CPointer<lv_timer_t>): Unit

foreign func lv_timer_resume(timer: CPointer<lv_timer_t>): Unit

foreign func lv_timer_set_cb(timer: CPointer<lv_timer_t>, cb: CFunc<(CPointer<lv_timer_t>) -> Unit>): Unit

foreign func lv_timer_set_period(timer: CPointer<lv_timer_t>, period: UInt32): Unit

foreign func lv_timer_ready(timer: CPointer<lv_timer_t>): Unit

foreign func lv_timer_reset(timer: CPointer<lv_timer_t>): Unit

foreign func lv_timer_set_repeat_count(timer: CPointer<lv_timer_t>, repeatCount: Int32): Unit

foreign func lv_timer_set_auto_delete(timer: CPointer<lv_timer_t>, autoDelete: Bool): Unit

foreign func lv_timer_set_user_data(timer: CPointer<lv_timer_t>, userData: CPointer<Unit>): Unit

/* ---- 版本（垫片读取 LVGL_VERSION_* 宏） ---- */
foreign func lv_version_major_cjbindwrapper(): UInt32

foreign func lv_version_minor_cjbindwrapper(): UInt32

foreign func lv_version_patch_cjbindwrapper(): UInt32
