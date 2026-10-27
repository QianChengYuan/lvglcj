/**
 * 友好 API 层：事件桥接 + 基础对象（Widget）+ 基础容器。
 *
 * 每个控件一个仓颉 class，链式风格，内部只持 lv_obj_t 句柄；
 * 析构由 finalize()/delete() 显式触发（LVGL 对象树由 C 侧管理）。
 *
 * 控件按主题拆在同包的其它文件里（原先都挤在本文件，1100+ 行）：
 * - widget_basic.cj      文本 / 按钮 / 值 / 选择类
 * - widget_container.cj  列表 / 表格 / 标签页 / 菜单 / 窗口
 * - widget_media.cj      图像 / 图表 / 曲线 / 刻度 / LED
 * - widget_rich.cj       富文本 span / 日历 / 帧动画 / 拼音输入法
 */
package lvglcj

import std.collection.*

/* ==================== 事件桥接 ==================== */

private class EventEntry {
    let id: UInt64
    let mask: UInt32
    let cb: (Event) -> Unit
    var active: Bool = true

    init(id: UInt64, mask: UInt32, cb: (Event) -> Unit) {
        this.id = id
        this.mask = mask
        this.cb = cb
    }
}

// 每个对象一个 hub、一个 C 回调；订阅条目在对象删除时随 hub 一起释放。
private class EventHub {
    let entries: ArrayList<EventEntry> = ArrayList<EventEntry>()
    var dispatchDepth: Int64 = 0

    func add(id: UInt64, mask: UInt32, cb: (Event) -> Unit): Unit {
        entries.add(EventEntry(id, mask, cb))
    }

    func contains(id: UInt64): Bool {
        for (entry in entries) {
            if (entry.id == id) {
                return true
            }
        }
        false
    }

    func cancel(id: UInt64): Unit {
        for (entry in entries) {
            if (entry.id == id) {
                entry.active = false
            }
        }
        // 回调内部取消时先标记，等分发结束再压实，避免遍历中删元素。
        if (dispatchDepth == 0) {
            compact()
        }
    }

    func compact(): Unit {
        var i: Int64 = 0
        while (i < entries.size) {
            if (!entries[i].active) {
                entries.remove(at: i)
            } else {
                i += 1
            }
        }
    }

    func deactivateAll(): Unit {
        for (entry in entries) {
            entry.active = false
        }
        entries.clear()
    }
}

// 事件注册表必须是模块级：C 侧只认静态分发函数，闭包状态不能跟着控件对象走。
private let EVENT_HUBS: HashMap<UIntNative, EventHub> = HashMap<UIntNative, EventHub>()
private var nextEventId: UInt64 = 0 // cjlint-ignore !G.VAR.02 UI 线程事件订阅计数

private func removeEventHub(addr: UIntNative): Unit {
    match (EVENT_HUBS.get(addr)) {
        case Some(hub) =>
            hub.deactivateAll()
            EVENT_HUBS.remove(addr)
        case None => ()
    }
}

/* ==================== 保活注册表 ==================== */

/**
 * 单个 lv_obj 的「保活槽」。
 *
 * 有些 LVGL API 只保存指针、不拷贝内容（`lv_line_set_points`、`lv_obj_add_style`、
 * `lv_calendar_set_highlighted_dates`、`lv_animimg_set_src`、`lv_image_set_src` …），
 * 这些数据的存活**必须锚在 lv_obj 上**，不能锚在仓颉包装对象上：
 * 仓颉的 GC 由分配压力驱动（实测 UI 帧循环 3 秒内一次都不触发），
 * 包装对象何时被回收与 lv_obj 是否还在屏上毫无关系。
 */
private class KeepSlot {
    /// 需要 free 的 C 侧裸缓冲（同一槽只保留最新的一个，替换时释放旧的）
    var cBuf: CPointer<Unit> = CPointer<Unit>()
    /// 需要强引用的仓颉对象（Style / ImageDsc …），随 lv_obj 删除一起释放
    let refs: ArrayList<Object> = ArrayList<Object>()
}

private let KEEPS: HashMap<UIntNative, KeepSlot> = HashMap<UIntNative, KeepSlot>()
/// 已经给该 lv_obj 挂过 cjEventDispatch 的地址，避免重复注册 C 回调
private let HOOKED: HashSet<UIntNative> = HashSet<UIntNative>()

private func freeKeepSlot(addr: UIntNative): Unit {
    match (KEEPS.get(addr)) {
        case Some(slot) =>
            if (!slot.cBuf.isNull()) {
                unsafe { LibC.free(slot.cBuf) }
                slot.cBuf = CPointer<Unit>()
            }
            slot.refs.clear()
            KEEPS.remove(addr)
        case None => ()
    }
}

/* ==================== 控件泄漏追踪（可选，默认关闭） ==================== */

/**
 * 已创建但尚未删除的 owned 控件（地址 → 创建序号）。
 *
 * 为什么需要它：`Widget` 是 open 类，语言不允许带终结器（cjc 实测报
 * `finalizer is forbidden in class ... that is open`），而 GC 又只在分配压力下触发，
 * 「忘记 finalize」没有任何兜底。所以这里提供**可检测**而不是**可兜底**：
 * 开发期打开追踪，跑完场景用 `App.reportLiveWidgets()` 看还有谁没释放。
 * 关闭时零开销（只多一次布尔判断）。
 */
private let LIVE_WIDGETS: HashMap<UIntNative, Int64> = HashMap<UIntNative, Int64>()
private var trackingOn: Bool = false // cjlint-ignore !G.VAR.02 只由 UI 线程读写
private var nextLiveSeq: Int64 = 0 // cjlint-ignore !G.VAR.02 只由 UI 线程递增

internal func setWidgetTracking(on: Bool): Unit {
    trackingOn = on
}

internal func widgetTrackingEnabled(): Bool {
    trackingOn
}

internal func untrackWidget(addr: UIntNative): Unit {
    if (LIVE_WIDGETS.contains(addr)) {
        LIVE_WIDGETS.remove(addr)
    }
}

internal func trackedWidgetCount(): Int64 {
    LIVE_WIDGETS.size
}

/** 未释放控件的创建序号（升序），用于报告里指出"早于谁创建" */
internal func trackedWidgetSeqs(): Array<Int64> {
    let seqs = ArrayList<Int64>(LIVE_WIDGETS.size)
    for ((_, seq) in LIVE_WIDGETS) {
        seqs.add(seq)
    }
    let arr = Array<Int64>(seqs.size, repeat: 0)
    var i: Int64 = 0
    for (s in seqs) {
        arr[i] = s
        i += 1
    }
    // 数量是"泄漏的控件数"，通常个位数；直接插入排序，省掉 std.sort 依赖
    var k: Int64 = 1
    while (k < arr.size) {
        let v = arr[k]
        var j = k - 1
        while (j >= 0 && arr[j] > v) {
            arr[j + 1] = arr[j]
            j -= 1
        }
        arr[j + 1] = v
        k += 1
    }
    arr
}

/**
 * LVGL 事件分发器：C 侧只见这个静态函数。
 * 回调异常在这里捕获，不能跨 C 边界传播。
 */
@C
func cjEventDispatch(e: CPointer<lv_event_t>): Unit {
    let code = unsafe { lv_event_get_code(e) }
    let target = unsafe { lv_event_get_target(e) }
    let addr = target.toUIntNative()
    match (EVENT_HUBS.get(addr)) {
        case Some(hub) =>
            hub.dispatchDepth += 1
            var i: Int64 = 0
            while (i < hub.entries.size) {
                let entry = hub.entries[i]
                if (entry.active && (entry.mask == LV_EVENT_ALL || entry.mask == code)) {
                    try {
                        entry.cb(Event(e))
                    } catch (err: Exception) {
                        App.reportCallbackError(err)
                    }
                }
                i += 1
            }
            hub.dispatchDepth -= 1
            if (hub.dispatchDepth == 0) {
                hub.compact()
            }
        case None => ()
    }
    // LVGL 删除对象时会发 LV_EVENT_DELETE（父对象递归删除子对象时也会发）。
    // 这里做与「有没有订阅者」无关的收尾：回收订阅表 + 释放保活的缓冲/引用，
    // 避免长跑后注册表只增不减，也避免保活数据跟着已死的包装对象一起烂在内存里。
    if (code == LV_EVENT_DELETE) {
        removeEventHub(addr)
        freeKeepSlot(addr)
        untrackWidget(addr)
        HOOKED.remove(addr)
    }
}

/**
 * 确保该 lv_obj 挂着 cjEventDispatch（没有订阅者也要挂）：
 * 保活数据要靠 LV_EVENT_DELETE 这个唯一的「对象即将消失」时机来释放。
 */
private func ensureHook(handle: CPointer<lv_obj_t>): Unit {
    let addr = handle.toUIntNative()
    if (HOOKED.contains(addr)) {
        return
    }
    HOOKED.add(addr)
    unsafe {
        lv_obj_add_event_cb(handle, cjEventDispatch, LV_EVENT_ALL, CPointer<Unit>())
    }
}

/**
 * 登记一个 owned 控件（仅追踪开启时生效）。
 * 同时确保挂上 cjEventDispatch：控件可能从不订阅事件，但如果它被父对象
 * 递归删除，只有挂着回调才能收到 LV_EVENT_DELETE 并在这里注销。
 */
private func trackWidget(handle: CPointer<lv_obj_t>): Unit {
    if (!trackingOn) {
        return
    }
    LIVE_WIDGETS.add(handle.toUIntNative(), nextLiveSeq)
    nextLiveSeq += 1
    ensureHook(handle)
}

private func keepSlotOf(handle: CPointer<lv_obj_t>): KeepSlot {
    let addr = handle.toUIntNative()
    match (KEEPS.get(addr)) {
        case Some(slot) => slot
        case None =>
            let slot = KeepSlot()
            KEEPS.add(addr, slot)
            ensureHook(handle)
            slot
    }
}

/** 让某个仓颉对象（Style / ImageDsc …）活到 lv_obj 被删除为止（追加式） */
internal func keepRef(handle: CPointer<lv_obj_t>, obj: Object): Unit {
    keepSlotOf(handle).refs.add(obj)
}

/** 替换保活的 C 侧裸缓冲：登记新缓冲并释放旧的（替换式，同一时刻只留一个） */
internal func replaceKeepBuf(handle: CPointer<lv_obj_t>, buf: CPointer<Unit>): Unit {
    let slot = keepSlotOf(handle)
    if (!slot.cBuf.isNull()) {
        unsafe { LibC.free(slot.cBuf) }
    }
    slot.cBuf = buf
}

/** 替换保活的仓颉对象列表（替换式，用于换帧/换源时清掉上一批） */
internal func replaceKeepRefs(handle: CPointer<lv_obj_t>, objs: ArrayList<Object>): Unit {
    let slot = keepSlotOf(handle)
    slot.refs.clear()
    for (o in objs) {
        slot.refs.add(o)
    }
}

/**
 * 清空所有保活槽（`App.shutdown()` 调用）。
 *
 * `lv_deinit()` 直接释放 LVGL 内存池，不会为每个对象派发 `LV_EVENT_DELETE`，
 * 所以必须在这里主动把我们 `malloc` 的缓冲 free 掉，并清空各张按地址索引的表 ——
 * 否则下次 `App.setup()` 后地址复用会撞上上一轮的残留条目。
 */
internal func releaseAllKeeps(): Unit {
    let addrs = ArrayList<UIntNative>(KEEPS.size)
    for ((addr, _) in KEEPS) {
        addrs.add(addr)
    }
    for (a in addrs) {
        freeKeepSlot(a)
        removeEventHub(a)
    }
    KEEPS.clear()
    EVENT_HUBS.clear()
    HOOKED.clear()
    LIVE_WIDGETS.clear()
}

/** 当前保活的仓颉对象个数（调试/测试用） */
internal func keptRefCount(handle: CPointer<lv_obj_t>): Int64 {
    match (KEEPS.get(handle.toUIntNative())) {
        case Some(slot) => slot.refs.size
        case None => 0
    }
}

/** 事件订阅句柄；cancel() 后不再触发，可重复取消 */
public class EventSubscription {
    private let objAddr: UIntNative
    private let id: UInt64
    private var active: Bool = true

    internal init(objAddr: UIntNative, id: UInt64) {
        this.objAddr = objAddr
        this.id = id
    }

    public func isActive(): Bool {
        if (!active) {
            return false
        }
        match (EVENT_HUBS.get(objAddr)) {
            case Some(hub) => hub.contains(id)
            case None => false
        }
    }

    public func cancel(): Unit {
        if (!active) {
            return
        }
        active = false
        match (EVENT_HUBS.get(objAddr)) {
            case Some(hub) => hub.cancel(id)
            case None => ()
        }
    }
}

/** 事件对象：code() 取事件码（LV_EVENT_*），target() 取目标控件（非拥有视图） */
public class Event {
    private var handle: CPointer<lv_event_t>

    internal init(handle: CPointer<lv_event_t>) {
        this.handle = handle
    }

    public func code(): UInt32 {
        unsafe { lv_event_get_code(handle) }
    }

    /** 事件目标控件。返回的是借用视图，**不要**对其调用 finalize()/delete() */
    public func target(): Widget {
        Widget(unsafe { lv_event_get_target(handle) }, owned: false)
    }
}

/* ==================== Widget 基类 ==================== */

/**
 * 控件基类。同时实现 `Resource`，因此可以用 try-with-resources 让释放跟着作用域走：
 *
 * ```cangjie
 * try (btn = Button(scr)) {
 *     btn.text("确定")
 *     ...
 * }   // 作用域结束（含异常路径）自动 close()，不依赖 GC
 * ```
 */
public open class Widget <: Resource {
    protected var handle: CPointer<lv_obj_t>
    private let owned: Bool
    private var alive: Bool = true
    private var deleteRequested: Bool = false

    internal init(handle: CPointer<lv_obj_t>, owned!: Bool = true) {
        this.handle = handle
        this.owned = owned
        if (owned) {
            trackWidget(handle)
        }
    }

    /**
     * 登记一个"LVGL 只存指针"的样式，让它活到本控件**被 LVGL 删除**为止。
     * 由 `Style.applyTo()` / `SpanPart.style()` 内部调用，业务侧不需要手动调。
     *
     * 注意这里不挂在包装对象上，而是登记到按 lv_obj 地址索引的保活表：
     * 包装对象可能先被 GC（时机不可控），而 lv_obj 还在屏上。
     */
    internal func keepStyle(st: Style): Unit {
        keepRef(handle, st)
    }

    /**
     * 当前被本控件保活的仓颉对象数量（样式、图像描述符等累加）。
     * 业务侧一般不需要；用于排查「保活是否真的挂上了」以及测试断言。
     */
    public func keptStyleCount(): Int64 {
        keptRefCount(handle)
    }

    /* ---- 几何 ---- */

    public func size(w: Int32, h: Int32): Unit {
        unsafe { lv_obj_set_size(handle, w, h) }
    }

    public func pos(x: Int32, y: Int32): Unit {
        unsafe { lv_obj_set_pos(handle, x, y) }
    }

    /** 相对父容器对齐（LV_ALIGN_*），dx/dy 为偏移 */
    public func align(a: UInt32, dx!: Int32 = 0, dy!: Int32 = 0): Unit {
        unsafe { lv_obj_align(handle, a, dx, dy) }
    }

    public func center(): Unit {
        unsafe { lv_obj_center(handle) }
    }

    public func width(): Int32 {
        unsafe { lv_obj_get_width(handle) }
    }

    public func height(): Int32 {
        unsafe { lv_obj_get_height(handle) }
    }

    /* ---- 标志 / 状态 ---- */

    public func addFlag(f: UInt32): Unit {
        unsafe { lv_obj_add_flag(handle, f) }
    }

    public func removeFlag(f: UInt32): Unit {
        unsafe { lv_obj_remove_flag(handle, f) }
    }

    public func hasFlag(f: UInt32): Bool {
        unsafe { lv_obj_has_flag(handle, f) }
    }

    public func addState(s: UInt32): Unit {
        unsafe { lv_obj_add_state(handle, s) }
    }

    public func removeState(s: UInt32): Unit {
        unsafe { lv_obj_remove_state(handle, s) }
    }

    /* ---- 事件 ---- */

    /**
     * 订阅事件（mask 为 LV_EVENT_*；LV_EVENT_ALL 收全部）。
     * 返回订阅句柄，可用 cancel() 取消；控件删除时订阅会自动失效。
     *
     * @throws[LvglException] 控件已释放或已请求删除时
     */
    public func onEvent(mask: UInt32, cb: (Event) -> Unit): EventSubscription {
        App.assertUIThread("Widget.onEvent")
        if (!alive || deleteRequested) {
            throw LvglException("控件已释放，不能注册事件")
        }
        let addr = handle.toUIntNative()
        let hub = match (EVENT_HUBS.get(addr)) {
            case Some(existing) => existing
            case None =>
                let created = EventHub()
                EVENT_HUBS.add(addr, created)
                // 每个对象只注册一个 C 回调，事件过滤在仓颉侧完成。
                ensureHook(handle)
                created
        }
        let id = nextEventId
        nextEventId += 1
        hub.add(id, mask, cb)
        EventSubscription(addr, id)
    }

    /** 取消一个事件订阅，等价于 sub.cancel() */
    public func offEvent(sub: EventSubscription): Unit {
        sub.cancel()
    }

    /** 主动向控件发送事件（测试、自定义事件或模拟输入时使用） */
    public func sendEvent(code: UInt32): Unit {
        let _ = unsafe { lv_obj_send_event(handle, code, CPointer<Unit>()) }
    }

    /* ---- 局部样式快捷 ---- */

    public func setStyleBgColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN): Unit {
        unsafe { lv_obj_set_style_bg_color(handle, Color.of(r, g, b), part) }
    }

    public func setStyleTextColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN): Unit {
        unsafe { lv_obj_set_style_text_color(handle, Color.of(r, g, b), part) }
    }

    public func setStyleRadius(radius: Int32, part!: UInt32 = LV_PART_MAIN): Unit {
        unsafe { lv_obj_set_style_radius(handle, radius, part) }
    }

    /**
     * 设置字体。text_font 是可继承属性：设在 Screen / 容器上即对该子树全部生效，
     * 因此全局换字体只需 `disp.screen().setFont(f)`。
     */
    public func setFont(f: Font, part!: UInt32 = LV_PART_MAIN): Unit {
        unsafe { lv_obj_set_style_text_font(handle, f.raw(), part) }
    }

    /* ---- 生命周期 ---- */

    /**
     * 立即释放控件（从父对象上删除并销毁）；重复调用安全。
     *
     * @throws[LvglException] 对 Screen / Event.target() 等借用视图调用时
     */
    public func finalize(): Unit {
        if (!owned) {
            throw LvglException("该 Widget 是借用视图，不能释放")
        }
        if (!alive || deleteRequested) {
            return
        }
        alive = false
        deleteRequested = true
        let addr = handle.toUIntNative()
        // lv_obj_delete 内部会同步派发 LV_EVENT_DELETE：
        // 订阅表与保活槽都由 cjEventDispatch 收尾，这里再做一次只是兜底（幂等）。
        unsafe { lv_obj_delete(handle) }
        removeEventHub(addr)
        freeKeepSlot(addr)
        untrackWidget(addr)
        HOOKED.remove(addr)
    }

    /**
     * 请求异步删除控件；在定时器/事件回调里调用更安全。重复调用安全。
     *
     * @throws[LvglException] 对 Screen / Event.target() 等借用视图调用时
     */
    public func delete(): Unit {
        if (!owned) {
            throw LvglException("该 Widget 是借用视图，不能释放")
        }
        if (!alive || deleteRequested) {
            return
        }
        deleteRequested = true
        unsafe { lv_obj_delete_async(handle) }
    }

    /** 是否已经请求删除（异步删除完成前也会返回 true） */
    public func isDeleted(): Bool {
        !alive || deleteRequested
    }

    /** `Resource` 接口：控件是否已释放（供 try-with-resources 判断要不要 close） */
    public func isClosed(): Bool {
        isDeleted()
    }

    /**
     * `Resource` 接口：立即释放控件，等价于 `finalize()`，但**不抛异常**。
     *
     * 与 `finalize()` 的差别只有两点，都是为了适配 try-with-resources：
     * ① 借用视图（`Screen`/`Event.target()`）静默返回，避免作用域结束时抛异常打断业务；
     * ② 重复调用安全（不抛）。
     * 需要「误用时立刻发现」请继续用 `finalize()`。
     */
    public func close(): Unit {
        if (!owned || !alive || deleteRequested) {
            return
        }
        alive = false
        deleteRequested = true
        let addr = handle.toUIntNative()
        unsafe { lv_obj_delete(handle) }
        removeEventHub(addr)
        freeKeepSlot(addr)
        untrackWidget(addr)
        HOOKED.remove(addr)
    }

    /** 内容变化后触发重绘 */
    public func invalidate(): Unit {
        unsafe { lv_obj_invalidate(handle) }
    }

    /** 底层句柄（内部使用：作为子控件的 parent / 样式目标） */
    internal func raw(): CPointer<lv_obj_t> {
        handle
    }
}

/* ==================== 基础容器 ==================== */

/** 基础容器控件（透明、可布局） */
public class Container <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_obj_create(parent.raw()) })
    }
}
