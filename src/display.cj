/**
 * 友好 API 层：显示（Display）与屏幕（Screen）。
 * 三个后端（DRM / fbdev / SDL）同一接口，自动读取设备真实分辨率与色深。
 */
package lvglcj

/** 屏幕：对 lv_screen_active 的友好包装，可作为控件的 parent */
public class Screen <: Widget {
    internal init(handle: CPointer<lv_obj_t>) {
        super(handle)
    }

    /** 把本屏幕设为活动屏幕（带默认加载动画时长 0） */
    public func load(): Unit {
        unsafe { lv_screen_load(handle) }
    }
}

public class Display {
    private var handle: CPointer<lv_display_t>

    internal init(handle: CPointer<lv_display_t>) {
        this.handle = handle
    }

    /* ==================== 三个后端 ==================== */

    /**
     * DRM/KMS 后端（优先）。
     * @param card DRM 设备节点，默认 /dev/dri/card0
     */
    public static func drm(card!: String = "/dev/dri/card0"): Display {
        let disp = unsafe { lvglcj_linux_drm_create_cjbindwrapper() }
        if (disp.isNull()) {
            throw LvglException("DRM 后端创建失败（$card，确认 vc4-kms-v3d 已启用，或当前构建未启用 LV_USE_LINUX_DRM）")
        }
        // connector_id = -1 表示自动选择第一个可用接口
        let r = withCString(card) { cs => unsafe { lvglcj_linux_drm_set_file_cjbindwrapper(disp, cs, -1) } }
        if (r != LV_RESULT_OK) {
            throw LvglException("DRM set_file 失败：$card")
        }
        Display(disp)
    }

    /**
     * fbdev 后端（无 DRM 时的兜底）。
     * @param dev 帧缓冲设备节点，默认 /dev/fb0
     */
    public static func fbdev(dev!: String = "/dev/fb0"): Display {
        let disp = unsafe { lvglcj_linux_fbdev_create_cjbindwrapper() }
        if (disp.isNull()) {
            throw LvglException("fbdev 后端创建失败（$dev，或当前构建未启用 LV_USE_LINUX_FBDEV）")
        }
        let r = withCString(dev) { cs => unsafe { lvglcj_linux_fbdev_set_file_cjbindwrapper(disp, cs) } }
        if (r != LV_RESULT_OK) {
            throw LvglException("fbdev set_file 失败：$dev")
        }
        Display(disp)
    }

    /**
     * SDL 后端（WSL/桌面模拟，WSLg 弹窗）。
     * 同时创建 SDL 鼠标与键盘输入设备，保证模拟环境下可直接交互。
     */
    public static func sdl(w: Int32, h: Int32): Display {
        let disp = unsafe { lv_sdl_window_create(w, h) }
        if (disp.isNull()) {
            throw LvglException("SDL 后端创建失败（${w}x${h}）")
        }
        // SDL 驱动自带的指针/键盘输入
        unsafe {
            lv_sdl_mouse_create()
            lv_sdl_keyboard_create()
        }
        Display(disp)
    }

    /* ==================== 查询 ==================== */

    public func width(): Int32 {
        unsafe { lv_display_get_horizontal_resolution(handle) }
    }

    public func height(): Int32 {
        unsafe { lv_display_get_vertical_resolution(handle) }
    }

    /** 实际生效色深（位），由显示当前 color format 决定 */
    public func colorDepth(): UInt32 {
        let cf = unsafe { lv_display_get_color_format(handle) }
        unsafe { UInt32(lv_color_format_get_bpp(cf)) }
    }

    /** 当前活动屏幕 */
    public func screen(): Screen {
        Screen(unsafe { lv_display_get_screen_active(handle) })
    }

    /* ==================== 调优 ==================== */

    /** 旋转（LV_DISPLAY_ROTATION_0/90/180/270，软旋转） */
    public func setRotation(rotation: UInt32): Unit {
        unsafe { lv_display_set_rotation(handle, rotation) }
    }

    /** 切换色深格式（LV_COLOR_FORMAT_RGB565 / RGB565_SWAPPED / XRGB8888 / L8 ...） */
    public func setColorFormat(cf: UInt32): Unit {
        unsafe { lv_display_set_color_format(handle, cf) }
    }

    /** 渲染模式（LV_DISPLAY_RENDER_MODE_PARTIAL/DIRECT/FULL） */
    public func setRenderMode(mode: UInt32): Unit {
        unsafe { lv_display_set_render_mode(handle, mode) }
    }

    /**
     * 每次 flush 强制整屏刷新（黑屏/花屏排障用，有性能代价）。
     * 仅 fbdev 驱动提供该能力（lv_linux_fbdev_set_force_refresh）。
     */
    public func setForceRefresh(on: Bool): Unit {
        unsafe { lvglcj_linux_fbdev_set_force_refresh_cjbindwrapper(handle, on) }
    }

    /** 底层句柄（仅供高级用户直穿 FFI 层使用） */
    internal func raw(): CPointer<lv_display_t> {
        handle
    }
}
