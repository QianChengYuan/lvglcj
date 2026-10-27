/**
 * 友好 API 层：生命周期与主循环（App）、定时器（Timer）。
 *
 * 线程模型硬约束（README「一.3」）：LVGL 不是线程安全的，全部 lv_* 调用
 * 必须在主线程完成。Timer 回调与事件回调均在主线程（lv_timer_handler）执行。
 */
package lvglcj

import std.collection.*
import std.collection.concurrent.*
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

/* ==================== UI 线程调度 ==================== */

// 任意线程都可以 post；任务只在 UI 线程的 runOnce 中执行。
private let UI_TASKS: ConcurrentLinkedQueue<() -> Unit> = ConcurrentLinkedQueue<() -> Unit>()

// 回调异常处理器：事件、定时器、post 任务共用同一条兜底路径。
private var callbackErrorHandler: Option<(Exception) -> Unit> = None // cjlint-ignore !G.VAR.02 UI 线程全局错误钩子

/* ==================== App ==================== */

private var running: Bool = false
private var diagEnabled: Bool = false // cjlint-ignore !G.VAR.02 主循环诊断开关（默认关闭）
private var lvglInited: Bool = false // cjlint-ignore !G.VAR.02 lv_init/lv_deinit 成对且只执行一次

// UI 线程标识：App.setup() 所在的线程。仓颉的终结器（~init）跑在独立的 GC 线程上
// （实测：主线程 id=1、终结器线程 id=2），所以在终结器里调 lv_* 属于跨线程操作，
// 必须回投到本线程执行 —— 见 App.releaseStyle()。
private var uiThreadId: Int64 = -1 // cjlint-ignore !G.VAR.02 UI 线程标识，setup() 时记录
private var threadAssert: Bool = false // cjlint-ignore !G.VAR.02 跨线程断言开关（默认关闭）

public class App {
    private init() {}

    /**
     * lv_init + 挂接单调时钟 tick 源。须在任何 LVGL 调用之前执行。
     * 幂等：重复调用直接返回（lv_init 不可重入）。
     * 同时把当前线程登记为 UI 线程（供 `isUIThread()` / `enableThreadAssert()` 使用）。
     */
    public static func setup(): Unit {
        if (lvglInited) {
            return
        }
        unsafe { lv_init() }
        unsafe { lv_tick_set_cb(cjTickCb) }
        uiThreadId = Thread.currentThread.id
        lvglInited = true
    }

    /**
     * lv_deinit 与资源回收。幂等：未经 setup() 或已 shutdown() 时直接返回。
     * 注意 deinit 之后 LVGL 的全局状态（样式/字体/寄存器）都已释放，
     * 再次 setup() 虽会重新 lv_init，但此前持有的控件/样式句柄全部失效。
     */
    public static func shutdown(): Unit {
        if (!lvglInited) {
            return
        }
        unsafe { lv_deinit() }
        lvglInited = false
    }

    /**
     * 打开/关闭主循环诊断输出（默认关闭）。
     * 打开后每 2 秒打印一行 `[lvglcj] 2s N 轮，最慢一轮 Xms`，用于判断
     * 休眠是否生效、某轮是否卡住。串口/控制台带宽受限时保持关闭。
     */
    public static func setDiagnostics(enabled: Bool): Unit {
        diagEnabled = enabled
    }

    /** 当前诊断输出是否打开 */
    public static func diagnostics(): Bool {
        diagEnabled
    }

    /* ---- 线程归属 ---- */

    /**
     * 当前线程是否就是 `App.setup()` 所在的 UI 线程。
     * 尚未 setup 时恒为 true（此时还没有"哪个线程是 UI 线程"的约束）。
     */
    public static func isUIThread(): Bool {
        uiThreadId < 0 || Thread.currentThread.id == uiThreadId
    }

    /**
     * 打开/关闭跨线程断言（默认关闭）。
     *
     * 打开后，只在 UI 线程合法的注册类 API（`Widget.onEvent`、`Timer.every/once`、
     * `Style.applyTo` 等）在别的线程调用时会抛 `LvglException` —— 比事后排查堆损坏便宜得多。
     * 建议在调试构建里打开；发布构建关闭以免每帧的线程 id 读取开销。
     */
    public static func enableThreadAssert(enabled: Bool): Unit {
        threadAssert = enabled
    }

    /**
     * 断言当前在 UI 线程。业务侧在后台线程回调里要操作控件时，可以先用它做自检，
     * 或直接用 `App.post` 转交。
     * @param what 出错信息里显示的操作名
     * @throws[LvglException] 已 `enableThreadAssert(true)` 且当前不在 UI 线程时
     */
    public static func assertUIThread(what: String): Unit {
        if (threadAssert && !isUIThread()) {
            throw LvglException("${what} 必须在 UI 线程调用（当前 ${Thread.currentThread.id}，UI 线程 ${uiThreadId}）")
        }
    }

    /**
     * 已在 UI 线程则立即执行，否则投递到 UI 线程（下一轮 `runOnce()` 执行）。
     * 给终结器这类"执行线程不可选"的场景用。
     */
    internal static func runOnUIThread(task: () -> Unit): Unit {
        if (isUIThread()) {
            task()
        } else {
            UI_TASKS.add(task)
        }
    }

    /**
     * 释放一个 `lv_style_t`。
     *
     * 仓颉的终结器（`~init`）跑在独立的 GC 线程（实测与主线程 id 不同），
     * 而 `lv_style_delete` 会改 LVGL 的样式链表 —— 直接调就是跨线程写全局状态。
     * 因此不在 UI 线程时回投给主循环；主循环没跑时宁可泄漏这一小块内存，
     * 也不要在渲染中途动 LVGL 的内部结构。
     */
    internal static func releaseStyle(style: CPointer<lv_style_t>): Unit {
        runOnUIThread {
            unsafe { lv_style_delete_cjbindwrapper(style) }
        }
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
     * 立即同步渲染一帧（等价 `lv_refr_now(NULL)`，刷新所有 display），
     * 不等 33ms 的刷新定时器到期。
     *
     * 正常主循环不需要它；用于：截图前、改了 Canvas 要马上看到结果、
     * 以及**测试**里确保"这一帧真的画了"（否则 `runOnce()` 可能只是跑了一遍
     * 定时器而没到刷新时刻，绘制路径根本没被执行）。
     */
    public static func refreshNow(): Unit {
        unsafe { lv_refr_now(CPointer<lv_display_t>()) }
    }

    /**
     * 从任意线程投递 UI 任务。任务只会在调用 App.run()/App.runOnce() 的
     * UI 线程执行，因此可以安全地更新控件。任务内不要阻塞。
     */
    public static func post(task: () -> Unit): Unit {
        UI_TASKS.add(task)
    }

    /**
     * 注册回调异常处理器。事件、定时器和 post 任务里抛出的异常都会交给它，
     * 不会跨 C 边界传播导致进程 abort。handler 自身抛错时只打印，不再向外抛。
     */
    public static func onCallbackError(handler: (Exception) -> Unit): Unit {
        callbackErrorHandler = Some(handler)
    }

    /** 清除回调异常处理器，恢复默认的控制台输出 */
    public static func clearCallbackErrorHandler(): Unit {
        callbackErrorHandler = None
    }

    internal static func reportCallbackError(e: Exception): Unit {
        match (callbackErrorHandler) {
            case Some(handler) => try {
                handler(e)
            } catch (handlerError: Exception) {
                println("[lvglcj] 回调异常处理器自身抛错：${handlerError.message}；原始异常：${e.message}")
            }
            case None => println("[lvglcj] 回调异常：${e.message}")
        }
    }

    /**
     * 主循环：lv_timer_handler + 空闲休眠，直到 App.stop()。
     * 每轮休眠 min(idleMs, 距下一个定时器的毫秒数)，既让出 CPU 又不推迟定时器。
     * @param idleMs 每轮空闲休眠上限毫秒数（默认 5）
     */
    public static func run(idleMs!: UInt32 = 5): Unit {
        running = true
        var rounds: Int64 = 0
        var maxCost: Int64 = 0
        var windowStart = MonoTime.now()
        while (running) {
            let t0 = MonoTime.now()
            let idle = runOnce()
            let cost = (MonoTime.now() - t0).toMilliseconds()
            if (cost > maxCost) {
                maxCost = cost
            }
            rounds += 1
            let win = (MonoTime.now() - windowStart).toMilliseconds()
            if (win >= 2000) {
                // 诊断（App.setDiagnostics(true) 才输出）：sleep 生效时约 400 轮/2s
                // （1000/(5+渲染耗时) × 2）。轮次远高于此说明休眠没起作用；
                // maxCost 大说明某轮卡住了。
                if (diagEnabled) {
                    println("[lvglcj] 2s ${rounds} 轮，最慢一轮 ${maxCost}ms")
                }
                rounds = 0
                maxCost = 0
                windowStart = MonoTime.now()
            }
            // 不用 lv_sleep_ms：当构建里 LV_USE_OS == LV_OS_NONE 时它退化成
            // lv_delay_ms 的**忙等**（while 轮询 tick），主线程会白烧一个核。
            // 在 Pi 上实测主线程常驻 90% CPU，直接抢走音频解码的调度时间，
            // 表现就是声音断续 + 界面点不动。改用仓颉自己的 sleep，必定让出 CPU。
            // idle 为 0（定时器已到期）或无定时器（LV_NO_TIMER_READY）时退回 idleMs。
            let nap = if (idle > 0 && idle < idleMs) {
                idle
            } else {
                idleMs
            }
            if (nap > 0) {
                sleep(Duration.millisecond * Int64(nap))
            }
        }
    }

    /**
     * 手动泵一次：先执行 post 任务，再跑 lv_timer_handler 与性能采样。
     * @return 距下次定时器的毫秒数（便于与业务线程协作）
     */
    public static func runOnce(): UInt32 {
        drainPostedTasks()
        let t0 = MonoTime.now()
        let idle = unsafe { lv_timer_handler() }
        perfSample((MonoTime.now() - t0).toMilliseconds())
        idle
    }

    // 每帧最多执行 256 个任务，避免业务线程无限投递时卡死渲染循环。
    private static func drainPostedTasks(): Unit {
        var count: Int64 = 0
        while (count < 256) {
            match (UI_TASKS.remove()) {
                case Some(task) =>
                    try {
                        task()
                    } catch (e: Exception) {
                        App.reportCallbackError(e)
                    }
                    count += 1
                case None => break
            }
        }
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

internal class TimerEntry {
    var handle: CPointer<lv_timer_t>
    let cb: () -> Unit
    let repeat: Bool
    var active: Bool = true

    init(handle: CPointer<lv_timer_t>, cb: () -> Unit, repeat: Bool) {
        this.handle = handle
        this.cb = cb
        this.repeat = repeat
    }
}

// 定时器注册表必须是模块级：C 侧只认静态分发函数，闭包状态不能跟着对象走。
private let TIMER_ENTRIES: ArrayList<TimerEntry> = ArrayList<TimerEntry>()
private var timerDispatchDepth: Int64 = 0 // cjlint-ignore !G.VAR.02 定时器回调重入计数

private func removeTimerEntry(entry: TimerEntry): Unit {
    var i: Int64 = 0
    while (i < TIMER_ENTRIES.size) {
        if (TIMER_ENTRIES[i].handle.toUIntNative() == entry.handle.toUIntNative()) {
            TIMER_ENTRIES.remove(at: i)
            return
        }
        i += 1
    }
}

private func compactTimers(): Unit {
    var i: Int64 = 0
    while (i < TIMER_ENTRIES.size) {
        if (!TIMER_ENTRIES[i].active) {
            TIMER_ENTRIES.remove(at: i)
        } else {
            i += 1
        }
    }
}

/**
 * LVGL 定时器分发器：C 侧只见这个静态函数，仓颉闭包查注册表执行。
 * 回调异常在这里捕获，不能跨 C 边界传播。
 */
@C
func cjTimerDispatch(timer: CPointer<lv_timer_t>): Unit {
    let addr = timer.toUIntNative()
    timerDispatchDepth += 1
    var i: Int64 = 0
    while (i < TIMER_ENTRIES.size) {
        let entry = TIMER_ENTRIES[i]
        if (entry.handle.toUIntNative() == addr && entry.active) {
            let repeat = entry.repeat
            try {
                entry.cb()
            } catch (e: Exception) {
                App.reportCallbackError(e)
            }
            // 回调里可能已经 cancel()，此时 active=false，不能再 delete 一次。
            if (!repeat && entry.active) {
                entry.active = false
                unsafe { lv_timer_delete(entry.handle) }
            }
        }
        i += 1
    }
    timerDispatchDepth -= 1
    if (timerDispatchDepth == 0) {
        compactTimers()
    }
}

/**
 * 定时器句柄：用于取消、暂停、恢复或立即触发定时器。
 * 一次性定时器执行完后 isActive() 会变为 false。
 */
public class TimerHandle {
    private let entry: TimerEntry

    internal init(entry: TimerEntry) {
        this.entry = entry
    }

    public func isActive(): Bool {
        entry.active
    }

    /** 取消定时器；可重复调用，回调内部调用也安全 */
    public func cancel(): Unit {
        if (!entry.active) {
            return
        }
        entry.active = false
        unsafe { lv_timer_delete(entry.handle) }
        if (timerDispatchDepth == 0) {
            removeTimerEntry(entry)
        }
    }

    public func pause(): Unit {
        if (entry.active) {
            unsafe { lv_timer_pause(entry.handle) }
        }
    }

    public func resume(): Unit {
        if (entry.active) {
            unsafe { lv_timer_resume(entry.handle) }
        }
    }

    /** 让定时器在下一次 lv_timer_handler 中立即执行 */
    public func ready(): Unit {
        if (entry.active) {
            unsafe { lv_timer_ready(entry.handle) }
        }
    }

    public func setPeriod(period: UInt32): Unit {
        if (entry.active) {
            unsafe { lv_timer_set_period(entry.handle, period) }
        }
    }
}

/** 定时器：把仓颉闭包注册到 LVGL 定时器（cb 在主线程执行，可直接操作控件） */
public class Timer {
    private init() {}

    /**
     * 每 period 毫秒执行一次。
     * @param period 周期（毫秒），必须 > 0；0 会让 LVGL 每轮 handler 都触发（≈200Hz）
     * @throws[LvglException] `period` 为 0，或 lv_timer_create 返回空指针时
     */
    public static func every(period: UInt32, cb: () -> Unit): TimerHandle {
        if (period == 0) {
            throw LvglException("Timer.every 的周期必须大于 0（0 会变成每轮 handler 都触发）")
        }
        register(period, cb, true)
    }

    /**
     * 延时 delay 毫秒执行一次（delay 为 0 表示下一轮 handler 立即执行）。
     * @throws[LvglException] lv_timer_create 返回空指针时
     */
    public static func once(delay: UInt32, cb: () -> Unit): TimerHandle {
        register(delay, cb, false)
    }

    /**
     * @throws[LvglException] lv_timer_create 返回空指针时
     */
    private static func register(period: UInt32, cb: () -> Unit, repeat: Bool): TimerHandle {
        App.assertUIThread("Timer.every/once")
        let entry = TimerEntry(CPointer<lv_timer_t>(), cb, repeat)
        TIMER_ENTRIES.add(entry)
        let handle = unsafe { lv_timer_create(cjTimerDispatch, period, CPointer<Unit>()) }
        if (handle.isNull()) {
            TIMER_ENTRIES.remove(at: TIMER_ENTRIES.size - 1)
            throw LvglException("定时器创建失败（period=${period}ms）")
        }
        entry.handle = handle
        TimerHandle(entry)
    }
}

/**
 * `Timer` 的别名，避免同时 `import std.sync.*` 时与 `std.sync.Timer` 重名。
 * 用法：`LvglTimer.every(1000) { ... }`
 */
public type LvglTimer = Timer
