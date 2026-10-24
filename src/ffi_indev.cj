/**
 * FFI 层：输入设备（lv_indev_*）与 evdev 驱动（lv_evdev_*）。
 */
package lvglcj

/* ---- indev 生命周期 ---- */
foreign func lv_indev_create(): CPointer<lv_indev_t>
foreign func lv_indev_delete(indev: CPointer<lv_indev_t>): Unit

/* ---- 配置 ---- */
foreign func lv_indev_set_type(indev: CPointer<lv_indev_t>, indevType: UInt32): Unit
foreign func lv_indev_set_read_cb(indev: CPointer<lv_indev_t>, readCb: CFunc<(CPointer<lv_indev_t>, CPointer<lv_indev_data_t>) -> Unit>): Unit
foreign func lv_indev_set_display(indev: CPointer<lv_indev_t>, disp: CPointer<lv_display_t>): Unit
foreign func lv_indev_set_cursor(indev: CPointer<lv_indev_t>, curObj: CPointer<lv_obj_t>): Unit
foreign func lv_indev_set_group(indev: CPointer<lv_indev_t>, group: CPointer<lv_group_t>): Unit
foreign func lv_indev_get_point(indev: CPointer<lv_indev_t>, point: CPointer<lv_point_t>): Unit
foreign func lv_indev_active(): CPointer<lv_indev_t>

/* ---- evdev 驱动（经 C 垫片；LV_USE_EVDEV=0 的构建里垫片返回空/失败） ---- */
foreign func lvglcj_evdev_create_cjbindwrapper(indevType: UInt32, devPath: CString): CPointer<lv_indev_t>
foreign func lvglcj_evdev_create_fd_cjbindwrapper(indevType: UInt32, fd: Int32): CPointer<lv_indev_t>
foreign func lvglcj_evdev_delete_cjbindwrapper(indev: CPointer<lv_indev_t>): Unit
foreign func lvglcj_evdev_set_calibration_cjbindwrapper(indev: CPointer<lv_indev_t>, minX: Int32, minY: Int32, maxX: Int32, maxY: Int32): Unit
foreign func lvglcj_evdev_set_swap_axes_cjbindwrapper(indev: CPointer<lv_indev_t>, swapAxes: Bool): Unit
foreign func lvglcj_evdev_discovery_start_cjbindwrapper(cb: CFunc<(CPointer<lv_indev_t>, UInt32, CPointer<Unit>) -> Unit>, userData: CPointer<Unit>): Int32
foreign func lvglcj_evdev_discovery_stop_cjbindwrapper(): Int32
