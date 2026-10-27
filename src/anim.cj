/**
 * 友好 API 层：动画（`Anim`）与时间线（`Timeline`）。
 *
 * ## 为什么不能把闭包直接交给 LVGL
 *
 * LVGL 的 `lv_anim_exec_xcb_t` 是 C 函数指针，签名 `void (*)(void * var, int32_t value)`。
 * 仓颉的 `@C` 顶层函数可以当函数指针用，但**拿不到闭包上下文**——所以本库的做法是：
 *
 * 1. 每次 `start()` 用 `LibC.malloc<UInt8>(1)` 要一个 1 字节的 **token** 当 `var`；
 * 2. 闭包登记到按 token 地址索引的条目表（`ANIM_ENTRIES`）；
 * 3. C 回调 `cjAnimExec` 拿到 var 就能回查闭包；
 * 4. 动画结束时 LVGL 调 `deleted_cb`（**完成和被打断都会调**，见 `lv_anim.c:701/824`），
 *    在那里统一「清条目 + free token」。
 *
 * 不用 `malloc<Unit>`：仓颉里 `sizeOf<Unit>() == 0`，`LibC.malloc<Unit>` 会在内部
 * 对齐除法上抛 `ArithmeticException: Divided by zero`（已实测）。
 *
 * ## 线程
 *
 * `start` / `cancel` / `cancelAll` 都要改 LVGL 的动画链表，必须在 UI 线程调用；
 * `exec_cb` / `completed_cb` / `deleted_cb` 由 LVGL 定时器在自己线程里调到，
 * 也就是 UI 线程，因此不需要回投。
 *
 * ## 值的类型
 *
 * LVGL 的动画值就是 `int32_t`（`lv_anim_set_values`），**不是浮点**。
 * 需要小数请自己做定点缩放，例如 `exec { v => bar.value(v * 10) }` 走 0..1000。
 */
package lvglcj

import std.collection.*

/** 缓动曲线（对应 `lv_anim_path_*`，编号与垫片里的 switch 一致） */
public enum Easing {
    | LINEAR
    | EASE_IN
    | EASE_OUT
    | EASE_IN_OUT
    | OVERSHOOT
    | BOUNCE
    | STEP

    internal func code(): UInt32 {
        match (this) {
            case LINEAR => 0
            case EASE_IN => 1
            case EASE_OUT => 2
            case EASE_IN_OUT => 3
            case OVERSHOOT => 4
            case BOUNCE => 5
            case STEP => 6
        }
    }
}

/** 一条正在运行的动画：闭包 + token（token 同时是 LVGL 侧的 `var` 与 `user_data`） */
private class AnimEntry {
    let token: CPointer<UInt8>
    let execCb: (Int32) -> Unit
    var completedCb: Option<() -> Unit>

    init(token: CPointer<UInt8>, execCb: (Int32) -> Unit, completedCb: Option<() -> Unit>) {
        this.token = token
        this.execCb = execCb
        this.completedCb = completedCb
    }
}

/** token 地址 → 条目。生命周期由 LVGL 的 `deleted_cb` 驱动（见文件头）。 */
private let ANIM_ENTRIES: HashMap<UIntNative, AnimEntry> = HashMap<UIntNative, AnimEntry>()

/** 要一块 1 字节内存只为了地址唯一（内容从不使用） */
private func allocAnimToken(): CPointer<UInt8> {
    let t = unsafe { LibC.malloc<UInt8>(count: 1) }
    if (t.isNull()) {
        throw LvglException("动画 token 分配失败")
    }
    t
}

/** 幂等：清条目 + free token。token 已被清过时什么也不做。 */
private func freeAnimEntry(token: CPointer<UInt8>): Unit {
    if (token.isNull()) {
        return
    }
    let addr = token.toUIntNative()
    match (ANIM_ENTRIES.get(addr)) {
        case Some(_) =>
            ANIM_ENTRIES.remove(addr)
            unsafe { LibC.free(token) }
        case None => ()
    }
}

/** LVGL 每帧调用：按 token 回查闭包 */
@C
func cjAnimExec(token: CPointer<UInt8>, value: Int32): Unit {
    match (ANIM_ENTRIES.get(token.toUIntNative())) {
        case Some(e) => try {
            e.execCb(value)
        } catch (err: Exception) {
            App.reportCallbackError(err)
        }
        case None => ()
    }
}

/** 播放完成（`repeat` 与 `reverse` 都结束后各调一次）；条目此时还没清，可以正常回调 */
@C
func cjAnimCompleted(a: CPointer<lv_anim_t>): Unit {
    let token = unsafe { lv_anim_get_user_data(a) }
    match (ANIM_ENTRIES.get(token.toUIntNative())) {
        case Some(e) => match (e.completedCb) {
            case Some(cb) => try {
                cb()
            } catch (err: Exception) {
                App.reportCallbackError(err)
            }
            case None => ()
        }
        case None => ()
    }
}

/** 生命周期终点（完成 / 被打断 / delete_all 都会走到）：在这里释放闭包与 token */
@C
func cjAnimDeleted(a: CPointer<lv_anim_t>): Unit {
    freeAnimEntry(unsafe { lv_anim_get_user_data(a) })
}

/**
 * 值动画构建器。
 *
 * ```cangjie
 * Anim.create()
 *     .exec { v => bar.value(v) }        // 每帧回调，参数是 int32
 *     .from(0).to(100)
 *     .duration(300).easing(Easing.EASE_OUT)
 *     .onCompleted { => println("到位") }
 *     .start()
 *
 * Anim.create().exec { v => box.setStyleBgOpa(UInt8(v)) }
 *     .from(0).to(255).duration(120).playback(120).loop().start()   // 呼吸灯
 * ```
 *
 * 一个 `Anim` 是**配置**，可以 `start()` 多次（每次生成独立的运行实例）。
 */
public class Anim {
    private var execCb: Option<(Int32) -> Unit> = None
    private var fromVal: Int32 = 0
    private var toVal: Int32 = 0
    private var durationMs: UInt32 = 300
    private var delayMs: UInt32 = 0
    private var easingKind: Easing = Easing.EASE_IN_OUT
    private var repeatCnt: UInt32 = 1
    private var repeatDelayMs: UInt32 = 0
    private var reverseMs: UInt32 = 0
    private var reverseDelayMs: UInt32 = 0
    private var completedCb: Option<() -> Unit> = None

    private init() {}

    /** 新建一个动画配置 */
    public static func create(): Anim {
        Anim()
    }

    /**
     * 值回调：动画每帧调用一次，参数是当前的整数值。
     * @param cb 回调（在 UI 线程执行；异常交给 `App.onCallbackError`）
     * @return this
     */
    public func exec(cb: (Int32) -> Unit): Anim {
        execCb = Some(cb)
        this
    }

    /** 起始值 @param v 整数 @return this */
    public func from(v: Int32): Anim {
        fromVal = v
        this
    }

    /** 结束值 @param v 整数 @return this */
    public func to(v: Int32): Anim {
        toVal = v
        this
    }

    /** 单程时长（毫秒） @param ms 毫秒 @return this */
    public func duration(ms: UInt32): Anim {
        durationMs = ms
        this
    }

    /** 开始前的延迟（毫秒） @param ms 毫秒 @return this */
    public func delay(ms: UInt32): Anim {
        delayMs = ms
        this
    }

    /** 缓动曲线 @param e 曲线 @return this */
    public func easing(e: Easing): Anim {
        easingKind = e
        this
    }

    /**
     * 总播放次数（LVGL 语义：**1 = 只播一次**，2 = 播两次…）。
     * 传 0 会被当成 1（LVGL 里 0 表示「不重复」，配合时长 0 会立即结束，容易误用）。
     * @param count 次数
     * @return this
     */
    public func repeat(count: UInt32): Anim {
        repeatCnt = if (count == 0) {
            1
        } else {
            count
        }
        this
    }

    /** 无限循环（等价 `repeat(LV_ANIM_REPEAT_INFINITE)`） @return this */
    public func loop(): Anim {
        repeatCnt = LV_ANIM_REPEAT_INFINITE
        this
    }

    /** 每轮之间的停顿（毫秒） @param ms 毫秒 @return this */
    public func repeatDelay(ms: UInt32): Anim {
        repeatDelayMs = ms
        this
    }

    /**
     * 回放时长：正向播完后再反向播一遍（0 = 不回放）。
     * 呼吸灯、开关滑块这类「去而复返」用它，不需要自己拼两个动画。
     * @param ms 毫秒
     * @return this
     */
    public func playback(ms: UInt32): Anim {
        reverseMs = ms
        this
    }

    /** 回放前的停顿（毫秒） @param ms 毫秒 @return this */
    public func playbackDelay(ms: UInt32): Anim {
        reverseDelayMs = ms
        this
    }

    /**
     * 播放完成回调（`repeat` / `playback` 全部结束后触发一次）。
     * @param cb 回调
     * @return this
     */
    public func onCompleted(cb: () -> Unit): Anim {
        completedCb = Some(cb)
        this
    }

    /**
     * 启动动画。
     * @return 运行句柄（`cancel()` 停止；自然结束后条目会自动回收）
     * @throws[LvglException] 没调用过 `exec(...)`，或 token / lv_anim_t 分配失败时
     */
    public func start(): AnimHandle {
        App.assertUIThread("Anim.start")
        let cb = match (execCb) {
            case Some(c) => c
            case None => throw LvglException("Anim 需要先 exec(...) 提供值回调")
        }
        let token = allocAnimToken()
        let a = try {
            buildAnim(token)
        } catch (e: LvglException) {
            freeAnimEntry(token)
            throw e
        }
        ANIM_ENTRIES.add(token.toUIntNative(), AnimEntry(token, cb, completedCb))
        unsafe { lv_anim_start(a) }
        // lv_anim_start 内部已 memcpy 一份，传入的这份可以立刻释放
        unsafe { lvglcj_anim_free_cjbindwrapper(a) }
        AnimHandle(token)
    }

    /**
     * 把配置好的动画挂到时间线上（不启动）。
     *
     * 与 `start()` 的差别：时间线**不会**触发各片段的 `deleted_cb`
     * （它只是逐帧调 `exec_cb`，见 `lv_anim_timeline.c` 的 `anim_timeline_set_act_time`），
     * 所以 token 由 `Timeline` 自己记账、在 `close()` 时统一释放。
     * @param tl 目标时间线
     * @param startTime 在时间线上的起始时刻（毫秒）
     * @return 该片段的 token
     * @throws[LvglException] 没调用过 `exec(...)` 时
     */
    internal func appendTo(tl: CPointer<lv_anim_timeline_t>, startTime: UInt32): CPointer<UInt8> {
        let cb = match (execCb) {
            case Some(c) => c
            case None => throw LvglException("动画片段需要先 exec(...) 提供值回调")
        }
        let token = allocAnimToken()
        let a = try {
            buildAnim(token)
        } catch (e: LvglException) {
            freeAnimEntry(token)
            throw e
        }
        ANIM_ENTRIES.add(token.toUIntNative(), AnimEntry(token, cb, completedCb))
        unsafe { lv_anim_timeline_add(tl, startTime, a) }
        unsafe { lvglcj_anim_free_cjbindwrapper(a) }
        token
    }

    private func buildAnim(token: CPointer<UInt8>): CPointer<lv_anim_t> {
        let a = unsafe { lvglcj_anim_new_cjbindwrapper() }
        if (a.isNull()) {
            throw LvglException("lv_anim_t 分配失败")
        }
        unsafe {
            lv_anim_set_var(a, token)
            // user_data 也存同一个 token：deleted_cb / completed_cb 只拿到 lv_anim_t*，
            // 靠它才能回查条目表
            lv_anim_set_user_data(a, token)
            lv_anim_set_exec_cb(a, cjAnimExec)
            lv_anim_set_values(a, fromVal, toVal)
            lv_anim_set_duration(a, durationMs)
            lv_anim_set_delay(a, delayMs)
            lvglcj_anim_set_easing_cjbindwrapper(a, easingKind.code())
            lv_anim_set_repeat_count(a, repeatCnt)
            lv_anim_set_repeat_delay(a, repeatDelayMs)
            if (reverseMs > 0) {
                lv_anim_set_reverse_duration(a, reverseMs)
            }
            if (reverseDelayMs > 0) {
                lv_anim_set_reverse_delay(a, reverseDelayMs)
            }
            lv_anim_set_completed_cb(a, cjAnimCompleted)
            lv_anim_set_deleted_cb(a, cjAnimDeleted)
        }
        a
    }

    /** 当前登记中的动画条目数（调试 / 泄漏排查；正常应回落到 0） */
    public static func liveCount(): Int64 {
        ANIM_ENTRIES.size
    }

    /**
     * 立刻停掉**所有**动画（场景切换时用）。
     * LVGL 会逐个触发 `deleted_cb`，条目表随之清空；这里再兜底扫一遍残留。
     */
    public static func cancelAll(): Unit {
        App.assertUIThread("Anim.cancelAll")
        unsafe { lv_anim_delete_all() }
        // 正常情况下 deleted_cb 已经把表清空了；这里兜底处理没有挂到 C 侧的残留条目
        let leftovers = ArrayList<CPointer<UInt8>>()
        for ((_, e) in ANIM_ENTRIES) {
            leftovers.add(e.token)
        }
        for (t in leftovers) {
            freeAnimEntry(t)
        }
    }
}

/**
 * 运行中的动画句柄。
 *
 * **不做终结器**：`~init` 跑在 GC 线程，而取消动画要改 LVGL 的动画链表。
 * 动画自然结束（含只播一次的常见情况）时条目会自动回收，不需要你管；
 * 只有「无限循环且不打算停」的动画才必须显式 `cancel()`。
 */
public class AnimHandle {
    private var token: CPointer<UInt8>

    internal init(token: CPointer<UInt8>) {
        this.token = token
    }

    /** 是否还在跑（自然结束后返回 false） */
    public func isRunning(): Bool {
        if (token.isNull()) {
            return false
        }
        let a = unsafe { lv_anim_get(token, cjAnimExec) }
        !a.isNull()
    }

    /** 暂停（保留进度，可 `resume()`） */
    public func pause(): Unit {
        let a = unsafe { lv_anim_get(token, cjAnimExec) }
        if (!a.isNull()) {
            unsafe { lv_anim_pause(a) }
        }
    }

    /** 继续播放 */
    public func resume(): Unit {
        let a = unsafe { lv_anim_get(token, cjAnimExec) }
        if (!a.isNull()) {
            unsafe { lv_anim_resume(a) }
        }
    }

    /** 是否已暂停 */
    public func isPaused(): Bool {
        let a = unsafe { lv_anim_get(token, cjAnimExec) }
        !a.isNull() && unsafe { lv_anim_is_paused(a) }
    }

    /**
     * 立刻停止（幂等）。会触发 `deleted_cb`，条目与 token 随之释放。
     */
    public func cancel(): Unit {
        if (token.isNull()) {
            return
        }
        App.assertUIThread("AnimHandle.cancel")
        let t = token
        token = CPointer<UInt8>()
        unsafe { lv_anim_delete(t, cjAnimExec) }
    }
}

/**
 * 动画时间线：让多个动画按各自起始时刻跑在同一条时间轴上。
 *
 * ```cangjie
 * let tl = Timeline.create()
 *     .add(Anim.create().exec { v => box.pos(Int32(v), 0) }.to(100).duration(300), at: 0)
 *     .add(Anim.create().exec { v => box.setStyleBgOpa(UInt8(v)) }.to(255).duration(200), at: 200)
 * tl.start()
 * // 切场景：
 * tl.close()
 * ```
 *
 * **必须 `close()`**：LVGL 的 `lv_anim_timeline_delete` 只释放自己的描述符数组，
 * 不会触发各片段动画的 `deleted_cb`，所以条目和 token 得由这里负责回收。
 */
public class Timeline {
    private var handle: CPointer<lv_anim_timeline_t>
    private let tokens: ArrayList<CPointer<UInt8>> = ArrayList<CPointer<UInt8>>()

    private init(handle: CPointer<lv_anim_timeline_t>) {
        this.handle = handle
    }

    /**
     * 创建时间线。
     * @return 新时间线
     * @throws[LvglException] 分配失败时
     */
    public static func create(): Timeline {
        App.assertUIThread("Timeline.create")
        let h = unsafe { lv_anim_timeline_create() }
        if (h.isNull()) {
            throw LvglException("lv_anim_timeline_create 失败")
        }
        Timeline(h)
    }

    /**
     * 追加一个片段。
     * @param anim 未启动的动画配置
     * @param at 在时间线上的起始时刻（毫秒；会覆盖动画自己的 `delay`）
     * @return this
     * @throws[LvglException] 时间线已关闭，或动画没配置 `exec(...)` 时
     */
    public func add(anim: Anim, at!: UInt32): Timeline {
        App.assertUIThread("Timeline.add")
        if (handle.isNull()) {
            throw LvglException("时间线已释放")
        }
        tokens.add(anim.appendTo(handle, at))
        this
    }

    /** 从头开始播放 @return 整条时间线总时长（毫秒） */
    public func start(): UInt32 {
        App.assertUIThread("Timeline.start")
        if (handle.isNull()) {
            throw LvglException("时间线已释放")
        }
        unsafe { lv_anim_timeline_start(handle) }
    }

    /** 暂停（可再次 `start()` 继续） */
    public func pause(): Unit {
        if (!handle.isNull()) {
            unsafe { lv_anim_timeline_pause(handle) }
        }
    }

    /** 直接跳到某个进度（0..65535），用于跟手势/滑块联动 @param progress 进度 */
    public func setProgress(progress: UInt16): Unit {
        if (!handle.isNull()) {
            unsafe { lv_anim_timeline_set_progress(handle, progress) }
        }
    }

    /** 当前进度（0..65535） */
    public func progress(): UInt16 {
        if (handle.isNull()) {
            0
        } else {
            unsafe { lv_anim_timeline_get_progress(handle) }
        }
    }

    /** 整条时间线总时长（毫秒） */
    public func playTime(): UInt32 {
        if (handle.isNull()) {
            0
        } else {
            unsafe { lv_anim_timeline_get_playtime(handle) }
        }
    }

    /** 是否已关闭 */
    public func isClosed(): Bool {
        handle.isNull()
    }

    /**
     * 释放时间线（幂等）。会先停掉正在跑的播放，再回收所有片段的闭包与 token。
     *
     * **必须显式调用**：本类不提供终结器。`~init` 跑在 GC 线程，而
     * `lv_anim_timeline_delete` 要动 LVGL 的链表，跨线程调用就是竞态；
     * 退一步只 free token 也不行 —— 条目表（HashMap）同样会被 GC 线程与 UI 线程并发改。
     */
    public func close(): Unit {
        if (handle.isNull()) {
            return
        }
        App.assertUIThread("Timeline.close")
        unsafe { lv_anim_timeline_delete(handle) }
        handle = CPointer<lv_anim_timeline_t>()
        for (t in tokens) {
            freeAnimEntry(t)
        }
        tokens.clear()
    }
}

/* ==================== 滚动（Widget 扩展） ==================== */

/**
 * 滚动相关方法。它们和动画共用 `lv_anim`：`anim: true` 时 LVGL 内部会为
 * `(obj, 内部 exec_cb)` 建一条动画，所以**不需要**本库的 `Anim`，也不会占用条目表。
 *
 * 前置条件：目标控件要带 `LV_OBJ_FLAG_SCROLLABLE`（LVGL 的 `lv_obj` 默认带，
 * 但 `Screen` 与部分控件模板可能没有，用 `scrollable()` 显式打开），
 * 且内容尺寸要**大于**控件尺寸 —— 否则滚不动是正常的，不是 bug。
 *
 * ```cangjie
 * list.scrollable().scrollDir(LV_DIR_VER)          // 只允许纵向滚
 * list.scrollBy(0, 120, anim: true)                // 下滑 120，带动画
 * list.scrollToY(0)                                // 回到顶部
 * item.scrollToView(anim: true)                    // 把某个子项滚进可视区
 * ```
 */
extend Widget {
    /**
     * 开关滚动能力（`LV_OBJ_FLAG_SCROLLABLE`）。
     *
     * 注意它**只约束用户输入**（拖动/滚轮）和 `scrollToView()`；
     * 程序化的 `scrollBy` / `scrollTo` 不受影响 —— LVGL 的 `lv_obj_scroll_by`
     * 压根不检查这个 flag（实测确认）。想禁止代码滚动只能在调用侧控制。
     * @param on true 打开
     * @return this
     */
    public func scrollable(on!: Bool = true): Widget {
        if (on) {
            addFlag(LV_OBJ_FLAG_SCROLLABLE)
        } else {
            removeFlag(LV_OBJ_FLAG_SCROLLABLE)
        }
        this
    }

    /**
     * 相对滚动。
     *
     * 注意 `dx` / `dy` 是「**内容**相对视口的位移」，方向与 `scrollX()` / `scrollY()` **相反**：
     * `scrollBy(0, -120)` 会让 `scrollY()` 增加 120（看到更靠下的内容）。
     * 想按「向下滚 120」的直觉写，用 `scrollToY(scrollY() + 120)`。
     *
     * 这个符号来自 LVGL：`lv_obj_scroll_to_y(y)` 内部就是
     * `scroll_by(-y + scrollY())`（`lv_obj_scroll.c`）。
     * @param dx 内容横向位移（正数 = 内容右移，`scrollX()` 减小）
     * @param dy 内容纵向位移（正数 = 内容下移，`scrollY()` 减小）
     * @param anim 是否用动画过渡
     * @return this
     */
    public func scrollBy(dx: Int32, dy: Int32, anim!: Bool = false): Widget {
        App.assertUIThread("Widget.scrollBy")
        unsafe { lv_obj_scroll_by(raw(), dx, dy, anim) }
        this
    }

    /**
     * 滚动到绝对位置（相对可滚动内容的左上角，正数表示已滚过多少）。
     * @param x 横向偏移
     * @param y 纵向偏移
     * @param anim 是否用动画过渡
     * @return this
     */
    public func scrollTo(x: Int32, y: Int32, anim!: Bool = false): Widget {
        App.assertUIThread("Widget.scrollTo")
        unsafe { lv_obj_scroll_to(raw(), x, y, anim) }
        this
    }

    /** 只改横向偏移 @param x 偏移 @param anim 是否动画 @return this */
    public func scrollToX(x: Int32, anim!: Bool = false): Widget {
        App.assertUIThread("Widget.scrollToX")
        unsafe { lv_obj_scroll_to_x(raw(), x, anim) }
        this
    }

    /** 只改纵向偏移 @param y 偏移 @param anim 是否动画 @return this */
    public func scrollToY(y: Int32, anim!: Bool = false): Widget {
        App.assertUIThread("Widget.scrollToY")
        unsafe { lv_obj_scroll_to_y(raw(), y, anim) }
        this
    }

    /** 当前横向滚动偏移 */
    public func scrollX(): Int32 {
        unsafe { lv_obj_get_scroll_x(raw()) }
    }

    /** 当前纵向滚动偏移 */
    public func scrollY(): Int32 {
        unsafe { lv_obj_get_scroll_y(raw()) }
    }

    /**
     * 把自己滚进父容器的可视区（长列表里定位某一项）。
     * @param anim 是否用动画过渡
     * @return this
     */
    public func scrollToView(anim!: Bool = false): Widget {
        App.assertUIThread("Widget.scrollToView")
        unsafe { lv_obj_scroll_to_view(raw(), anim) }
        this
    }

    /**
     * 滚动条显示策略。
     * @param mode `LV_SCROLLBAR_MODE_OFF` / `ON` / `ACTIVE` / `AUTO`
     * @return this
     */
    public func scrollbarMode(mode: UInt32): Widget {
        unsafe { lv_obj_set_scrollbar_mode(raw(), mode) }
        this
    }

    /**
     * 允许的滚动方向（`LV_DIR_HOR` / `LV_DIR_VER` / `LV_DIR_ALL` …，位标志）。
     * @param dir 方向
     * @return this
     */
    public func scrollDir(dir: UInt32): Widget {
        unsafe { lv_obj_set_scroll_dir(raw(), dir) }
        this
    }

    /** 立刻停住正在进行的滚动动画（用户开始拖动时常用） */
    public func stopScrollAnim(): Unit {
        unsafe { lv_obj_stop_scroll_anim(raw()) }
    }

    /** 是否正在滚动（含惯性 / 动画阶段） */
    public func isScrolling(): Bool {
        unsafe { lv_obj_is_scrolling(raw()) }
    }
}
