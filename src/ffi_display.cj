/**
 * FFI 层：显示（lv_display_*）、屏幕（lv_screen_*）、Linux 显示驱动。
 * 枚举参数一律映射为 UInt32（C 枚举 ABI 等价）。
 */
package lvglcj

/* ---- display 生命周期 ---- */
foreign func lv_display_create(horRes: Int32, verRes: Int32): CPointer<lv_display_t>

foreign func lv_display_delete(disp: CPointer<lv_display_t>): Unit

foreign func lv_display_set_default(disp: CPointer<lv_display_t>): Unit

foreign func lv_display_get_default(): CPointer<lv_display_t>

/* ---- 分辨率 / 旋转 / 偏移 ---- */
foreign func lv_display_set_resolution(disp: CPointer<lv_display_t>, horRes: Int32, verRes: Int32): Unit

foreign func lv_display_set_physical_resolution(disp: CPointer<lv_display_t>, horRes: Int32, verRes: Int32): Unit

foreign func lv_display_set_offset(disp: CPointer<lv_display_t>, x: Int32, y: Int32): Unit

foreign func lv_display_set_rotation(disp: CPointer<lv_display_t>, rotation: UInt32): Unit

foreign func lv_display_get_horizontal_resolution(disp: CPointer<lv_display_t>): Int32

foreign func lv_display_get_vertical_resolution(disp: CPointer<lv_display_t>): Int32

/* ---- 缓冲 / 渲染模式 / 色深 ---- */
foreign func lv_display_set_buffers(disp: CPointer<lv_display_t>, buf1: CPointer<Unit>, buf2: CPointer<Unit>,
    bufSize: UInt32, renderMode: UInt32): Unit

foreign func lv_display_set_render_mode(disp: CPointer<lv_display_t>, renderMode: UInt32): Unit

foreign func lv_display_get_render_mode(disp: CPointer<lv_display_t>): UInt32

foreign func lv_display_set_color_format(disp: CPointer<lv_display_t>, colorFormat: UInt32): Unit

foreign func lv_display_get_color_format(disp: CPointer<lv_display_t>): UInt32

/* ---- flush 回调（px_map 为 uint8_t*，非 const） ---- */
foreign func lv_display_set_flush_cb(disp: CPointer<lv_display_t>,
    flushCb: CFunc<(CPointer<lv_display_t>, CPointer<lv_area_t>, CPointer<UInt8>) -> Unit>): Unit

foreign func lv_display_flush_ready(disp: CPointer<lv_display_t>): Unit

foreign func lv_display_flush_is_last(disp: CPointer<lv_display_t>): Bool

/* ---- 屏幕 ---- */
foreign func lv_display_get_screen_active(disp: CPointer<lv_display_t>): CPointer<lv_obj_t>

foreign func lv_screen_load(scr: CPointer<lv_obj_t>): Unit

foreign func lv_screen_active(): CPointer<lv_obj_t>

/* ---- 层 ----
 * top  = 在 screen 内容之上（光标、悬浮按钮、通知条）
 * sys  = 在 top 之上（系统级弹层，一般不要往里塞普通控件）
 * bottom = 在 screen 内容之下（壁纸）
 */
foreign func lv_layer_top(): CPointer<lv_obj_t>

foreign func lv_layer_sys(): CPointer<lv_obj_t>

foreign func lv_layer_bottom(): CPointer<lv_obj_t>

/* ---- 屏幕刷新定时器（拿到后可用 lv_timer_set_period 调刷新率） ---- */
foreign func lv_display_get_refr_timer(disp: CPointer<lv_display_t>): CPointer<lv_timer_t>

/* ---- 系统监视器（右下角 FPS/CPU 悬浮标签）----
 * 9.5 起挂在 LV_USE_SYSMON + LV_USE_PERF_MONITOR 下；display 创建时 LVGL 会自动显示，
 * 这两个函数用于运行时显隐（disp 传空指针 = 默认 display）。
 * 注意：对应配置关掉时符号不存在，链接会报未定义。 */
foreign func lv_sysmon_show_performance(disp: CPointer<lv_display_t>): Unit

foreign func lv_sysmon_hide_performance(disp: CPointer<lv_display_t>): Unit

/* ---- Linux DRM/KMS 驱动（经 C 垫片转发；非 Linux 构建下垫片返回 NULL） ---- */
foreign func lvglcj_linux_drm_create_cjbindwrapper(): CPointer<lv_display_t>

foreign func lvglcj_linux_drm_set_file_cjbindwrapper(disp: CPointer<lv_display_t>, file: CString, connectorId: Int64): Int32

/* ---- Linux fbdev 驱动（同上） ---- */
foreign func lvglcj_linux_fbdev_create_cjbindwrapper(): CPointer<lv_display_t>

foreign func lvglcj_linux_fbdev_set_file_cjbindwrapper(disp: CPointer<lv_display_t>, file: CString): Int32

foreign func lvglcj_linux_fbdev_set_force_refresh_cjbindwrapper(disp: CPointer<lv_display_t>, enabled: Bool): Unit

/* ---- SDL 驱动（WSL/桌面模拟） ---- */
foreign func lv_sdl_window_create(horRes: Int32, verRes: Int32): CPointer<lv_display_t>

foreign func lv_sdl_mouse_create(): CPointer<lv_indev_t>

foreign func lv_sdl_keyboard_create(): CPointer<lv_indev_t>

/**
 * SDL 的 hint 设置（`SDL_SetHint`，来自 SDL2 而非 LVGL）。
 *
 * 只在 Windows 上声明：进程默认是 DPI-unaware，Windows 会把 800x480 的画面按
 * 显示缩放（本机 125%）整体做位图插值拉伸，整屏发虚；先声明 per-monitor 感知
 * 后窗口按物理像素直出，1:1 清晰。Linux/macOS 没有 DPI 虚拟化问题，
 * 且 DRM/fbdev 版根本不链接 SDL2 —— 用 `@When` 关掉，免得引入解不开的符号。
 *
 * 返回值是 `SDL_bool`（C 的 int）：false 只表示这个 SDL 版本不认识该 hint 名，
 * 不影响窗口创建。
 */
@When[os == "Windows"]
foreign func SDL_SetHint(name: CString, value: CString): Int32
