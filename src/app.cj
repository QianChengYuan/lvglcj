/**
 * 友好 API 层：生命周期与主循环（App）、定时器（Timer）。
 *
 * 线程模型硬约束（README「一.3」）：LVGL 不是线程安全的，全部 lv_* 调用
 * 必须在主线程完成。Timer 回调与事件回调均在主线程（lv_timer_handler）执行。
 */
package lvglcj

import std.collection.*
import std.time.*

/* ==================== tick 源 ==================== */

private var tickBase: Option<MonoTime> = None

/**
 * LVGL tick 源：挂到 lv_tick_set_cb 的单调时钟。
 * 不挂时间基准，画面会在第一帧后卡死（LVGL 认为时间从未流逝）。
 */
@C
func cjTickCb(): UInt32 {
    match (tickBase) {
        case None =>
            tickBase = Some(MonoTime.now())
            0
        case Some(base) => UInt32((MonoTime.now() - base).toMilliseconds())
    }
}

/* ==================== 性能采样 ==================== */

/*
 * LVGL 9.5 未导出 perf monitor 的查询 API（数据在私有结构体内），
 * 因此这里在主循环内自行采样，口径与 LVGL 一致：
 * - cpu：1 秒窗口内 lv_timer_handler 繁忙时间占墙钟时间的比例；
 * - fps：1 秒窗口内发生真实渲染调度（繁忙 >= 1ms）的次数。
 */
private var perfBusyMs: Float64 = 0.0
private var perfFrames: Int64 = 0
private var perfWindowStart: Option<MonoTime> = None
private var perfCpuPct: Int32 = 0
private var perfFps: Float64 = 0.0

private func perfSample(busyMs: Int64): Unit {
    match (perfWindowStart) {
        case None => perfWindowStart = Some(MonoTime.now())
        case Some(start) =>
            let elapsed = (MonoTime.now() - start).toMilliseconds()
            perfBusyMs += Float64(busyMs)
            if (busyMs >= 1) {
                perfFrames += 1
            }
            if (elapsed >= 1000) {
                perfCpuPct = Int32(perfBusyMs * 100.0 / Float64(elapsed))
                perfFps = Float64(perfFrames) * 1000.0 / Float64(elapsed)
                perfBusyMs = 0.0
                perfFrames = 0
                perfWindowStart = Some(MonoTime.now())
            }
    }
}

/* ==================== App ==================== */

private var running: Bool = false

public class App {
    private init() {}

    /** lv_init + 挂接单调时钟 tick 源。须在任何 LVGL 调用之前执行 */
    public static func setup(): Unit {
        unsafe { lv_init() }
        unsafe { lv_tick_set_cb(cjTickCb) }
    }

    /** lv_deinit 与资源回收 */
    public static func shutdown(): Unit {
        unsafe { lv_deinit() }
    }

    /** 默认 display 的友好包装 */
    public static func mainDisplay(): Display {
        Display(unsafe { lv_display_get_default() })
    }

    /** 请求退出主循环（run 的下次迭代后返回） */
    public static func stop(): Unit {
        running = false
    }

    /**
     * 主循环：lv_timer_handler + lv_sleep_ms，直到 App.stop()。
     * @param idleMs 每轮空闲休眠毫秒数（默认 5）
     */
    public static func run(idleMs!: UInt32 = 5): Unit {
        running = true
        while (running) {
            runOnce()
            unsafe { lv_sleep_ms(idleMs) }
        }
    }

    /**
     * 手动泵一次：lv_timer_handler + 性能采样。
     * @return 距下次定时器的毫秒数（便于与业务线程协作）
     */
    public static func runOnce(): UInt32 {
        let t0 = MonoTime.now()
        let idle = unsafe { lv_timer_handler() }
        perfSample((MonoTime.now() - t0).toMilliseconds())
        idle
    }
}

/** 性能诊断（口径见文件头 perfSample 注释） */
public class Perf {
    private init() {}

    /** 主循环繁忙时间占比（%，近似 CPU 占用） */
    public static func cpu(): Int32 {
        perfCpuPct
    }

    /** 渲染帧率（次/秒） */
    public static func fps(): Float64 {
        perfFps
    }

    /**
     * 打开 LVGL 自带的监视器（右下角 FPS/CPU 小字）。
     * `LV_USE_PERF_MONITOR=1` 时 `lv_display_create` 会自动显示它，本方法用于事后重开。
     * @param disp 目标 display，None = 当前默认 display
     */
    public static func showMonitor(disp!: Option<Display> = None): Unit {
        unsafe { lv_sysmon_show_performance(monitorTarget(disp)) }
    }

    /**
     * 关掉 LVGL 自带的监视器（右下角 FPS/CPU 小字），只是隐藏，采样照常。
     * 注意这只是隐藏悬浮标签；想完全省掉这部分开销，把 `lv_conf.h` 的
     * `LV_USE_PERF_MONITOR` 设为 0 并重编静态库。
     * @param disp 目标 display，None = 当前默认 display
     */
    public static func hideMonitor(disp!: Option<Display> = None): Unit {
        unsafe { lv_sysmon_hide_performance(monitorTarget(disp)) }
    }

    /** None → 空指针，表示 LVGL 的默认 display */
    private static func monitorTarget(disp: Option<Display>): CPointer<lv_display_t> {
        match (disp) {
            case Some(d) => d.raw()
            case None => CPointer<lv_display_t>()
        }
    }
}

/* ==================== Timer ==================== */

private class TimerEntry {
    var handle: CPointer<lv_timer_t>
    let cb: () -> Unit
    let repeat: Bool

    init(handle: CPointer<lv_timer_t>, cb: () -> Unit, repeat: Bool) {
        this.handle = handle
        this.cb = cb
        this.repeat = repeat
    }
}

// 定时器注册表必须是模块级：C 侧只认静态分发函数，闭包状态不能跟着对象走。
private let TIMER_ENTRIES: ArrayList<TimerEntry> = ArrayList<TimerEntry>()

/**
 * LVGL 定时器分发器：C 侧只见这个静态函数，仓颉闭包查注册表执行。
 * 注意：闭包内抛出的异常不能跨 C 边界传播，回调代码须自行兜底。
 */
@C
func cjTimerDispatch(timer: CPointer<lv_timer_t>): Unit {
    let addr = timer.toUIntNative()
    let finished: ArrayList<TimerEntry> = ArrayList<TimerEntry>()
    for (entry in TIMER_ENTRIES) {
        if (entry.handle.toUIntNative() == addr) {
            entry.cb()
            if (!entry.repeat) {
                finished.add(entry)
            }
        }
    }
    for (entry in finished) {
        unsafe { lv_timer_delete(entry.handle) }
        var i: Int64 = 0
        while (i < TIMER_ENTRIES.size) {
            if (TIMER_ENTRIES[i].handle.toUIntNative() == addr) {
                TIMER_ENTRIES.remove(at: i)
            } else {
                i += 1
            }
        }
    }
}

/** 定时器：把仓颉闭包注册到 LVGL 定时器（cb 在主线程执行，可直接操作控件） */
public class Timer {
    private init() {}

    /** 每 period 毫秒执行一次 */
    public static func every(period: UInt32, cb: () -> Unit): Unit {
        register(period, cb, true)
    }

    /** 延时 delay 毫秒执行一次 */
    public static func once(delay: UInt32, cb: () -> Unit): Unit {
        register(delay, cb, false)
    }

    private static func register(period: UInt32, cb: () -> Unit, repeat: Bool): Unit {
        TIMER_ENTRIES.add(TimerEntry(CPointer<lv_timer_t>(), cb, repeat))
        let idx = TIMER_ENTRIES.size - 1
        let handle = unsafe { lv_timer_create(cjTimerDispatch, period, CPointer<Unit>()) }
        TIMER_ENTRIES[idx].handle = handle
    }
}
