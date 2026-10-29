/**
 * 友好 API 层：数据绑定（`Subject` / `Observer`）。
 *
 * LVGL 9 的 subject 机制是为 C 设计的（`lv_subject` 只能存 int / float / string /
 * pointer 四种，取值要按类型分函数）。这里先只做 **int 主题** —— 覆盖进度、温度、
 * 计数这类绝大多数场景；字符串主题需要调用方提供 buffer 且不拷贝，等有真实需求再加。
 *
 * ## 三种用法，按「省事程度」排序
 *
 * 1. **声明式绑定**（推荐，零闭包、控件删除自动解绑）：
 *    ```cangjie
 *    let temp = Subject.of(20)
 *    label.bindText(temp, fmt: "室温 %d°C")   // lv_label_bind_text
 *    slider.bindValue(temp)                   // lv_slider_bind_value
 *    switch.bindChecked(temp)                 // lv_obj_bind_checked
 *    box.bindFlagIf(temp, LV_OBJ_FLAG_HIDDEN, 0)   // lv_obj_bind_flag_if_eq
 *    temp.set(26)                             // 上面四处同时更新
 *    ```
 *    这一族观察者由 LVGL 持有，随控件销毁，**不占本库的条目表**。
 *
 * 2. **绑定到控件（带闭包）**：`temp.bind(label) { v => ... }`
 *    —— 用 `lv_subject_add_observer_obj`，控件删除时 LVGL 会自动摘掉观察者；
 *    本库另外监听控件的 `LV_EVENT_DELETE` 来回收闭包与条目。
 *
 * 3. **纯订阅（无控件）**：`temp.subscribe { v => ... }`
 *    —— 用 `lv_subject_add_observer`，**必须**靠返回的 `Observer.cancel()` 或
 *    `Subject.close()` 释放，否则闭包一直挂在主题上。
 *
 * 2 与 3 在注册时都会**立即回调一次**（LVGL 建观察者时同步跑一遍），所以回调里
 * 直接写「拿值刷 UI」即可，不必另写初值分支。
 *
 * ## 生命周期
 *
 * `Subject` 同样不做终结器：`close()` 要调 `lv_subject_deinit`（动 LVGL 链表），
 * 而 `~init` 跑在 GC 线程。主题一般和页面同寿，`close()` 放在页面销毁处即可。
 * `Subject.liveCount()` 可用于验证「有没有漏关」。
 */
package lvglcj

import std.collection.*

/** 比较运算符（对应 `lv_obj_bind_flag_if_*` / `lv_obj_bind_state_if_*` 的六种变体） */
public enum CompareOp {
    | EQ
    | NOT_EQ
    | GT
    | GE
    | LT
    | LE
}

/**
 * 观察者条目：闭包 + token（token 存在 observer 的 user_data 里，用于回调回查）。
 *
 * `observer` 必须是 `var`：`lv_subject_add_observer_obj` 在**返回之前**就同步回调
 * 一次（`lv_observer.c:472`「Update Observer immediately」），所以条目得先入表、
 * 回调跑完才拿得到 observer 指针（否则首次通知会被丢掉）。
 *
 * `owner` 是所属主题的句柄地址：只有它有权清掉这条目，
 * 避免「token 地址被别的主题复用后误删别人条目」。
 */
private class ObserverEntry {
    let token: CPointer<UInt8>
    let cb: (Int32) -> Unit
    let owner: UIntNative
    var observer: CPointer<lv_observer_t>

    init(token: CPointer<UInt8>, cb: (Int32) -> Unit, owner: UIntNative) {
        this.token = token
        this.cb = cb
        this.owner = owner
        this.observer = CPointer<lv_observer_t>()
    }
}

/** token 地址 → 条目。只登记**带闭包**的观察者；声明式绑定不经过这里。 */
private let OBSERVER_ENTRIES: HashMap<UIntNative, ObserverEntry> = HashMap<UIntNative, ObserverEntry>()

private func allocObserverToken(): CPointer<UInt8> {
    let t = unsafe { LibC.malloc<UInt8>(count: 1) }
    if (t.isNull()) {
        throw LvglException("观察者 token 分配失败")
    }
    t
}

/**
 * 只清条目，**不 free token、不碰 observer 指针**。
 *
 * 用在「LVGL 已经替我们释放了观察者」的路径上：
 * 1. 控件被删除 —— LVGL 给 obj 挂的 `unsubscribe_on_delete_cb` 已 `lv_observer_remove`；
 * 2. 主题 `lv_subject_deinit` —— 逐个 `lv_observer_remove`；
 * 3. 用户主动取消 —— `cancelObserver` 已经 remove 过了。
 * 这三种情况再 remove 一次就是 double free。
 *
 * token 也不在这里释放：它只有 1 字节，统一在 `Subject.close()` 回收，
 * 这样在主题存活期间 token 地址**不会被复用**，条目的 key 始终可靠。
 * @param token 观察者 token
 * @param owner 调用方主题的句柄地址（不匹配则不动，防误删）
 */
private func releaseObserver(token: CPointer<UInt8>, owner: UIntNative): Unit {
    if (token.isNull()) {
        return
    }
    let addr = token.toUIntNative()
    match (OBSERVER_ENTRIES.get(addr)) {
        case Some(e) =>
            if (e.owner == owner) {
                OBSERVER_ENTRIES.remove(addr)
            }
        case None => ()
    }
}

/**
 * 清空观察者注册表（`App.shutdown()` 调用）：free 所有 token，不碰 LVGL 的观察者节点
 * （`lv_deinit` 会统一回收，此时再 `lv_observer_remove` 就是操作已释放内存）。
 *
 * 注意：`shutdown()` 之后所有 `Subject` / `Observer` 句柄都已失效，不得再调用其方法
 * （`close()` 也会对已失效的 `lv_subject_t` 动手）。
 */
internal func clearSubjectObservers(): Unit {
    let ts = ArrayList<CPointer<UInt8>>(OBSERVER_ENTRIES.size)
    for ((_, e) in OBSERVER_ENTRIES) {
        ts.add(e.token)
    }
    OBSERVER_ENTRIES.clear()
    for (t in ts) {
        if (!t.isNull()) {
            unsafe { LibC.free(t) }
        }
    }
}

/** 主动取消：先 `lv_observer_remove`（让 LVGL 释放自己的观察者节点），再清条目 */
private func cancelObserver(token: CPointer<UInt8>): Unit {
    if (token.isNull()) {
        return
    }
    let addr = token.toUIntNative()
    match (OBSERVER_ENTRIES.get(addr)) {
        case Some(e) =>
            if (!e.observer.isNull()) {
                unsafe { lv_observer_remove(e.observer) }
            }
            OBSERVER_ENTRIES.remove(addr)
        case None => ()
    }
}

/** LVGL 的通知入口：按 observer 的 user_data 回查闭包，再把主题当前值喂给它 */
@C
func cjSubjectObserver(observer: CPointer<lv_observer_t>, subject: CPointer<lv_subject_t>): Unit {
    let token = unsafe { lv_observer_get_user_data(observer) }
    match (OBSERVER_ENTRIES.get(token.toUIntNative())) {
        case Some(e) => try {
            e.cb(unsafe { lv_subject_get_int(subject) })
        } catch (err: Exception) {
            App.reportCallbackError(err)
        }
        case None => ()
    }
}

/**
 * 一棵「让 C 侧长期持有字符串」的辅助对象。
 *
 * `lv_label_bind_text` 只把 `fmt` 指针塞进 user_data、**不拷贝**，所以这块内存
 * 必须活到控件销毁。做法是把它交给 `Widget.keep`：控件删 → holder 不可达 →
 * GC 线程 free。`~init` 里只有 `LibC.free`，属纯内存操作，跨线程安全。
 */
private class CStringHolder {
    let ptr: CPointer<UInt8>

    init(s: String) {
        let bytes = s.toArray()
        let buf = unsafe { LibC.malloc<UInt8>(count: Int64(bytes.size) + 1) }
        if (buf.isNull()) {
            throw LvglException("字符串缓冲分配失败")
        }
        unsafe {
            var i: Int64 = 0
            for (b in bytes) {
                buf.write(i, b)
                i += 1
            }
            buf.write(i, 0)
        }
        ptr = buf
    }

    ~init() {
        unsafe { LibC.free(ptr) }
    }
}

/**
 * 整型数据主题（`lv_subject_init_int`）。
 *
 * ```cangjie
 * let progress = Subject.of(0)
 * bar.bindValue(progress)
 * label.bindText(progress, fmt: "%d%%")
 * progress.set(60)          // 两处同步刷新
 * progress.add(-10)         // 56 → 50
 * progress.close()          // 页面销毁时
 * ```
 *
 * 值有下限/上限（默认 int32 全范围）：`setRange(0, 100)` 后超出会被钳住，
 * 这样「进度条不会因为算错而越界」由主题统一保证，各个绑定处不用各写一遍。
 */
public class Subject {
    private var handle: CPointer<lv_subject_t>
    private let tokens: ArrayList<CPointer<UInt8>> = ArrayList<CPointer<UInt8>>()

    private init(handle: CPointer<lv_subject_t>) {
        this.handle = handle
    }

    /**
     * 新建整型主题。
     * @param initial 初始值
     * @return 主题
     * @throws[LvglException] 分配失败时
     */
    public static func of(initial: Int32): Subject {
        App.assertUIThread("Subject.of")
        let h = unsafe { lvglcj_subject_new_int_cjbindwrapper(initial) }
        if (h.isNull()) {
            throw LvglException("lv_subject_t 分配失败")
        }
        Subject(h)
    }

    /**
     * 当前值。
     *
     * 读取类方法在主题已释放时**返回 0**（宽容），写操作（`set`/`add`/`setRange`/
     * `notify`/`subscribe`/`bind`）则抛 `LvglException` —— 这条分界是全库一致的：
     * 「读已失效对象」不该让清理路径（如统一收尾时读一次状态）崩掉。
     */
    public func get(): Int32 {
        if (handle.isNull()) {
            0
        } else {
            unsafe { lv_subject_get_int(handle) }
        }
    }

    /** 上一次通知前的值；主题已释放时返回 0（同 `get()` 的读宽容约定） */
    public func previous(): Int32 {
        if (handle.isNull()) {
            0
        } else {
            unsafe { lv_subject_get_previous_int(handle) }
        }
    }

    /**
     * 设值并通知观察者。
     *
     * **只有值真正变化时才通知**（LVGL 走 `lv_subject_notify_if_changed`，
     * 先按 min/max 钳住再比新旧值）；需要「值没变也刷新一次」用 `notify()`。
     * @param v 新值（会被 min/max 钳住）
     */
    public func set(v: Int32): Unit {
        App.assertUIThread("Subject.set")
        if (handle.isNull()) {
            throw LvglException("主题已释放")
        }
        unsafe { lv_subject_set_int(handle, v) }
    }

    /**
     * 在当前值上加增量。
     *
     * 中间结果用 Int64 算，超出 int32 时按边界钳住——仓颉的 Int32 加法溢出是抛异常，
     * 而「进度加过头」不该让整个刷新链路崩掉。
     * @param delta 增量（可为负）
     */
    public func add(delta: Int32): Unit {
        let sum = Int64(get()) + Int64(delta)
        if (sum > Int64(Int32.Max)) {
            set(Int32.Max)
        } else if (sum < Int64(Int32.Min)) {
            set(Int32.Min)
        } else {
            set(Int32(sum))
        }
    }

    /**
     * 设置取值范围，之后的 `set` 超界会被钳住。
     *
     * 注意：**不会回写当前值**（LVGL 只改 min/max 字段），
     * 想把现有值也拉回范围请紧接着 `set(get())`。
     * @param min 下限
     * @param max 上限
     */
    public func setRange(min: Int32, max: Int32): Unit {
        App.assertUIThread("Subject.setRange")
        if (handle.isNull()) {
            throw LvglException("主题已释放")
        }
        unsafe {
            lv_subject_set_min_value_int(handle, min)
            lv_subject_set_max_value_int(handle, max)
        }
    }

    /**
     * 值没变也强制通知一次（用于「刷新」语义）。
     * @throws[LvglException] 主题已释放（`close()` 之后）时
     */
    public func notify(): Unit {
        App.assertUIThread("Subject.notify")
        if (handle.isNull()) {
            throw LvglException("主题已释放")
        }
        unsafe { lv_subject_notify(handle) }
    }

    /**
     * 纯订阅（无控件）：主题每次通知都调 `cb`。
     *
     * 注册时会**立即回调一次**（LVGL 建观察者时就同步跑一遍），所以 `cb` 里可以直接
     * 拿它初始化一次状态，不必另写初值分支。
     *
     * 必须用返回的 `Observer.cancel()` 或 `Subject.close()` 释放，
     * 否则闭包一直挂在主题上。
     * @param cb 回调，参数是主题当前值
     * @return 可取消的观察者
     * @throws[LvglException] 主题已释放，或注册失败时
     */
    public func subscribe(cb: (Int32) -> Unit): Observer {
        App.assertUIThread("Subject.subscribe")
        if (handle.isNull()) {
            throw LvglException("主题已释放")
        }
        let owner = handle.toUIntNative()
        let token = allocObserverToken()
        tokens.add(token)
        // 必须先入表再注册：add_observer 在返回前就同步回调，晚了首帧就丢了
        let entry = ObserverEntry(token, cb, owner)
        OBSERVER_ENTRIES.add(token.toUIntNative(), entry)
        let obs = unsafe { lv_subject_add_observer(handle, cjSubjectObserver, token) }
        if (obs.isNull()) {
            OBSERVER_ENTRIES.remove(token.toUIntNative())
            throw LvglException("观察者注册失败")
        }
        entry.observer = obs
        Observer(token)
    }

    /**
     * 绑定到某个控件：主题变化时调 `cb`，**控件被删除时自动解绑**。
     *
     * 与 `subscribe` 的区别就在这里：走的是 `lv_subject_add_observer_obj`，
     * LVGL 会给控件挂一个 `LV_EVENT_DELETE` 回调，在 `lv_obj_delete` 时把观察者摘掉，
     * 所以不会出现「控件没了回调还在」。本库再挂一个 DELETE 回调回收闭包与条目，
     * 它排在 LVGL 那个之后执行（注册更晚），此时观察者已被 LVGL 释放。
     * @param to 目标控件（观察者的生命周期与它绑定）
     * @param cb 回调，参数是主题当前值；注册时会立即回调一次
     * @return 可取消的观察者
     * @throws[LvglException] 主题已释放，或注册失败时
     */
    public func bind(to: Widget, cb: (Int32) -> Unit): Observer {
        App.assertUIThread("Subject.bind")
        if (handle.isNull()) {
            throw LvglException("主题已释放")
        }
        let owner = handle.toUIntNative()
        let token = allocObserverToken()
        tokens.add(token)
        let entry = ObserverEntry(token, cb, owner)
        OBSERVER_ENTRIES.add(token.toUIntNative(), entry)
        let obs = unsafe { lv_subject_add_observer_obj(handle, cjSubjectObserver, to.raw(), token) }
        if (obs.isNull()) {
            OBSERVER_ENTRIES.remove(token.toUIntNative())
            throw LvglException("观察者注册失败")
        }
        entry.observer = obs
        // 控件删除 → LVGL 已摘掉 observer，这里只回收闭包与条目
        to.onEvent(LV_EVENT_DELETE) {_ => releaseObserver(token, owner)}
        Observer(token)
    }

    /** 是否已释放 */
    public func isClosed(): Bool {
        handle.isNull()
    }

    /**
     * 释放主题（幂等）。
     *
     * 顺序很重要：先清本库条目（避免 deinit 过程中回调打到即将失效的闭包），
     * 再 `lv_subject_deinit`（LVGL 会逐个 free 掉观察者节点），
     * 最后连同 token 一起 free 结构自身。token 拖到最后才释放，
     * 是为了让它在本主题存活期间地址唯一（见 `releaseObserver`）。
     */
    public func close(): Unit {
        if (handle.isNull()) {
            return
        }
        App.assertUIThread("Subject.close")
        let owner = handle.toUIntNative()
        for (t in tokens) {
            releaseObserver(t, owner)
        }
        unsafe { lvglcj_subject_free_cjbindwrapper(handle) }
        for (t in tokens) {
            unsafe { LibC.free(t) }
        }
        tokens.clear()
        handle = CPointer<lv_subject_t>()
    }

    /** 当前登记中的带闭包观察者数（声明式绑定不计入；正常应回落到 0） */
    public static func liveCount(): Int64 {
        OBSERVER_ENTRIES.size
    }

    /** 底层句柄（供 `Widget.bind*` 这些声明式绑定使用） */
    internal func raw(): CPointer<lv_subject_t> {
        handle
    }
}

/**
 * 观察者句柄。不带终结器（同 `AnimHandle`）：取消要改 LVGL 链表，不能跑在 GC 线程。
 */
public class Observer {
    private var token: CPointer<UInt8>

    internal init(token: CPointer<UInt8>) {
        this.token = token
    }

    /** 是否仍有效（控件被删除也会让它失效） */
    public func isActive(): Bool {
        if (token.isNull()) {
            return false
        }
        OBSERVER_ENTRIES.contains(token.toUIntNative())
    }

    /** 取消订阅（幂等） */
    public func cancel(): Unit {
        if (token.isNull()) {
            return
        }
        App.assertUIThread("Observer.cancel")
        let t = token
        token = CPointer<UInt8>()
        cancelObserver(t)
    }
}

/* ==================== 声明式绑定（零闭包，随控件销毁） ==================== */

/**
 * 声明式绑定：观察者完全由 LVGL 持有，控件删除时自动摘除，
 * 因此**不需要**保存返回的句柄，也不占本库的条目表。
 */
extend Widget {
    /**
     * 值满足比较条件时给控件加 `flag`，否则移除。
     *
     * ```cangjie
     * // 值为 0 时隐藏（空列表提示）
     * tip.bindFlagIf(count, LV_OBJ_FLAG_HIDDEN, 0, op: CompareOp.NOT_EQ)
     * ```
     * @param sub 主题
     * @param flag `LV_OBJ_FLAG_*`
     * @param refValue 比较基准
     * @param op 比较运算符（默认等于）
     * @return this
     */
    public func bindFlagIf(sub: Subject, flag: UInt32, refValue: Int32, op!: CompareOp = CompareOp.EQ): Widget {
        App.assertUIThread("Widget.bindFlagIf")
        let s = sub.raw()
        unsafe {
            match (op) {
                case EQ => lv_obj_bind_flag_if_eq(raw(), s, flag, refValue)
                case NOT_EQ => lv_obj_bind_flag_if_not_eq(raw(), s, flag, refValue)
                case GT => lv_obj_bind_flag_if_gt(raw(), s, flag, refValue)
                case GE => lv_obj_bind_flag_if_ge(raw(), s, flag, refValue)
                case LT => lv_obj_bind_flag_if_lt(raw(), s, flag, refValue)
                case LE => lv_obj_bind_flag_if_le(raw(), s, flag, refValue)
            }
        }
        this
    }

    /**
     * 值满足比较条件时给控件加 `state`（按下态、禁用态这类外观开关）。
     * @param sub 主题
     * @param state `LV_STATE_*`
     * @param refValue 比较基准
     * @param op 比较运算符
     * @return this
     */
    public func bindStateIf(sub: Subject, state: UInt32, refValue: Int32, op!: CompareOp = CompareOp.EQ): Widget {
        App.assertUIThread("Widget.bindStateIf")
        let s = sub.raw()
        unsafe {
            match (op) {
                case EQ => lv_obj_bind_state_if_eq(raw(), s, state, refValue)
                case NOT_EQ => lv_obj_bind_state_if_not_eq(raw(), s, state, refValue)
                case GT => lv_obj_bind_state_if_gt(raw(), s, state, refValue)
                case GE => lv_obj_bind_state_if_ge(raw(), s, state, refValue)
                case LT => lv_obj_bind_state_if_lt(raw(), s, state, refValue)
                case LE => lv_obj_bind_state_if_le(raw(), s, state, refValue)
            }
        }
        this
    }

    /**
     * 勾选态 ↔ 主题（0 = 未选，非 0 = 已选）。Switch / Checkbox 用。
     * @param sub 主题
     * @return this
     */
    public func bindChecked(sub: Subject): Widget {
        App.assertUIThread("Widget.bindChecked")
        unsafe { lv_obj_bind_checked(raw(), sub.raw()) }
        this
    }
}

/** 标签文本绑定：`fmt` 是 printf 风格，用 `%d` 占主题值 */
extend Label {
    /**
     * 文本随主题变化。
     * @param sub 主题
     * @param fmt printf 风格格式串（如 `"室温 %d°C"`；`%d` 位置填主题值）
     * @return this
     * @throws[LvglException] 字符串缓冲分配失败时
     */
    public func bindText(sub: Subject, fmt!: String = "%d"): Label {
        App.assertUIThread("Label.bindText")
        let holder = CStringHolder(fmt)
        unsafe { lv_label_bind_text(raw(), sub.raw(), holder.ptr) }
        // lv_label_bind_text 只存指针，必须保活到控件销毁
        keep(holder)
        this
    }
}

/** 数值控件绑定：主题值直接写进控件（类型由 LVGL 的 bind 负责） */
extend Slider {
    /** 滑块位置随主题变化（拖动滑块也会回写主题） @param sub 主题 @return this */
    public func bindValue(sub: Subject): Slider {
        App.assertUIThread("Slider.bindValue")
        unsafe { lv_slider_bind_value(raw(), sub.raw()) }
        this
    }
}

extend Bar {
    /** 进度随主题变化 @param sub 主题 @return this */
    public func bindValue(sub: Subject): Bar {
        App.assertUIThread("Bar.bindValue")
        unsafe { lv_bar_bind_value(raw(), sub.raw()) }
        this
    }
}

extend Arc {
    /** 圆弧角度随主题变化 @param sub 主题 @return this */
    public func bindValue(sub: Subject): Arc {
        App.assertUIThread("Arc.bindValue")
        unsafe { lv_arc_bind_value(raw(), sub.raw()) }
        this
    }
}

extend Roller {
    /** 选中项随主题变化 @param sub 主题 @return this */
    public func bindValue(sub: Subject): Roller {
        App.assertUIThread("Roller.bindValue")
        unsafe { lv_roller_bind_value(raw(), sub.raw()) }
        this
    }
}

extend Dropdown {
    /** 选中项随主题变化 @param sub 主题 @return this */
    public func bindValue(sub: Subject): Dropdown {
        App.assertUIThread("Dropdown.bindValue")
        unsafe { lv_dropdown_bind_value(raw(), sub.raw()) }
        this
    }
}
