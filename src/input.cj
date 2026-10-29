/**
 * 友好 API 层：输入设备（Input）。
 * 触摸 / 鼠标 / 键盘，经 LVGL evdev 驱动（/dev/input/eventX）接入。
 */
package lvglcj

import std.collection.*

/** 设备发现的仓颉侧观察者（须声明在分发函数之前：仓颉顶层声明顺序敏感） */
private let DISCOVERY_CALLBACKS: ArrayList<() -> Unit> = ArrayList<() -> Unit>() // cjlint-ignore !G.VAR.02 evdev 发现回调须全局存活

/** 清空设备发现回调（`App.shutdown()` 调用） */
internal func clearDiscoveryCallbacks(): Unit {
    DISCOVERY_CALLBACKS.clear()
}

/**
 * evdev 设备发现回调：通知仓颉侧注册的观察者。
 *
 * 先取快照再遍历：回调里可能继续 `discover()`（往表里 add）或 `stopDiscover()`（清表），
 * 直接遍历会被就地修改。回调异常也不能跨 C 边界传播。
 */
@C
func cjEvdevDiscoveryCb(_: CPointer<lv_indev_t>, _: UInt32, _: CPointer<Unit>): Unit {
    let snapshot = ArrayList<() -> Unit>(DISCOVERY_CALLBACKS.size)
    for (cb in DISCOVERY_CALLBACKS) {
        snapshot.add(cb)
    }
    for (cb in snapshot) {
        try {
            cb()
        } catch (e: Exception) {
            App.reportCallbackError(e)
        }
    }
}

public class Input {
    private var handle: CPointer<lv_indev_t>

    internal init(handle: CPointer<lv_indev_t>) {
        this.handle = handle
    }

    /**
     * 创建 evdev 输入设备。
     * @param indevType LV_INDEV_TYPE_POINTER（触摸/鼠标）或 LV_INDEV_TYPE_KEYPAD（键盘）
     * @param dev       设备节点，如 /dev/input/event0
     * @throws[LvglException] 当前构建未启用 LV_USE_EVDEV，或无法打开 `dev`（不存在 / 无权限）时
     */
    public static func evdev(indevType: UInt32, dev: String): Input {
        let indev = withCString(dev) {cs => unsafe { lvglcj_evdev_create_cjbindwrapper(indevType, cs) }}
        if (indev.isNull()) {
            throw LvglException("evdev 创建设备失败：$dev")
        }
        Input(indev)
    }

    /**
     * 扫描 /dev/input/ 自动创建 evdev 设备（支持热插拔）。
     * 发现新设备时回调 cb（cb 内可再调 Input.evdev 做精细配置）。
     * @param cb 发现新设备时的回调（在主循环里执行）
     * @throws[LvglException] 当前构建未启用 LV_USE_EVDEV，或发现服务已在运行/启动失败时
     */
    public static func discover(cb: () -> Unit): Unit {
        // 回调表是普通 ArrayList，只在 UI 线程（lv_timer_handler 里）遍历；
        // 从这里断言同线程，避免后台线程 add 与遍历并发。
        App.assertUIThread("Input.discover")
        // 发现回调经 user_data 不需要携带状态，这里用静态分发占位：
        // LVGL 的 discovery 是轮询式，回调参数只有 indev/type，仓颉侧只需感知"有新设备"
        let started = unsafe {
            lvglcj_evdev_discovery_start_cjbindwrapper(cjEvdevDiscoveryCb, CPointer<Unit>())
        }
        if (started != LV_RESULT_OK) {
            throw LvglException("evdev 设备发现启动失败")
        }
        DISCOVERY_CALLBACKS.add(cb)
    }

    /** 停止设备发现，并丢弃已登记的回调（再次 `discover()` 不会重复触发旧回调） */
    public static func stopDiscover(): Unit {
        App.assertUIThread("Input.stopDiscover")
        unsafe { lvglcj_evdev_discovery_stop_cjbindwrapper() }
        DISCOVERY_CALLBACKS.clear()
    }

    /* ==================== 实例配置 ==================== */

    /** 绑定到指定 display（默认已绑定默认 display） */
    public func attach(display: Display): Unit {
        unsafe { lv_indev_set_display(handle, display.raw()) }
    }

    /** 原始坐标 → 屏幕坐标映射（触摸校准） */
    public func calibrate(minX: Int32, minY: Int32, maxX: Int32, maxY: Int32): Unit {
        unsafe { lvglcj_evdev_set_calibration_cjbindwrapper(handle, minX, minY, maxX, maxY) }
    }

    /** 修正 X/Y 颠倒的面板 */
    public func swapAxes(on: Bool): Unit {
        unsafe { lvglcj_evdev_set_swap_axes_cjbindwrapper(handle, on) }
    }

    /** 为鼠标类设备挂光标对象 */
    public func setCursor(obj: Widget): Unit {
        unsafe { lv_indev_set_cursor(handle, obj.raw()) }
    }

    /**
     * 最近一次处理的指针设备坐标（轮询式查询，无指针设备时返回 None）。
     * lv_indev_active() 返回上一次处理的输入设备，其 point 为最新读到位置。
     */
    public static func activePoint(): Option<(Int32, Int32)> {
        let indev = unsafe { lv_indev_active() }
        if (indev.isNull()) {
            return None
        }
        // inout 出参必须是 var（cjlint 的 G.VAR.01 在这里是误报）
        var pt = lv_point_t() // cjlint-ignore !G.VAR.01 inout 出参必须是可变变量
        unsafe { lv_indev_get_point(indev, inout pt) }
        Some((pt.x, pt.y))
    }
}
