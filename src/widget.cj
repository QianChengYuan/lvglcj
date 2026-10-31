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
    /**
     * true  = 只接收「子孙冒泡上来」的事件（`lv_event_get_target != current_target`）；
     * false = 只接收本对象自己发出的（两者相等）。
     * 两种互斥，因此同一个控件上可以安全地同时挂 `on` 与 `onBubbled`。
     */
    let bubble: Bool
    let cb: (Event) -> Unit
    var active: Bool = true

    init(id: UInt64, mask: UInt32, bubble: Bool, cb: (Event) -> Unit) {
        this.id = id
        this.mask = mask
        this.bubble = bubble
        this.cb = cb
    }
}

// 每个对象一个 hub、一个 C 回调；订阅条目在对象删除时随 hub 一起释放。
private class EventHub {
    let entries: ArrayList<EventEntry> = ArrayList<EventEntry>()
    var dispatchDepth: Int64 = 0

    func add(id: UInt64, mask: UInt32, bubble: Bool, cb: (Event) -> Unit): Unit {
        entries.add(EventEntry(id, mask, bubble, cb))
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
 * `lv_calendar_set_highlighted_dates`、`lv_animimg_set_src`、`lv_image_set_src`、
 * `lv_style_set_grid_column_dsc_array` …），这些数据的存活**必须锚在 lv_obj 上**，
 * 不能锚在仓颉包装对象上：仓颉的 GC 由分配压力驱动（实测 UI 帧循环 3 秒内一次都不触发），
 * 包装对象何时被回收与 lv_obj 是否还在屏上毫无关系。
 *
 * 四种语义（对外见 `Widget.keep` / `keepOnly` / `keepBuf`，样式由库内部登记）：
 * - `refs`   **追加式**：`keep()` 登记的对象，多个并存、各自独立；
 * - `refs`   **替换式**（keepOnly）：帧序列这种「一次换一整套」的对象；
 * - `styles` **只追加的样式表**：`Style.applyTo` / `SpanPart.style` 登记，
 *   **不受 keepOnly 影响** —— 样式是逐个 `lv_obj_add_style` 挂上去的，
 *   LVGL 的 `obj->styles[]` 里每个槽各自指向一个 `lv_style_t`，
 *   「换图源」不该把之前挂的样式一起解引用掉；
 * - `cBufs`  **按槽位替换**：我们 malloc 出来交给 LVGL 的裸缓冲。同一槽位只留最新一个，
 *   登记新的一定 free 旧的；不同槽位并存（grid 的列描述符与行描述符就需要两个槽）。
 *
 * 四种都不锚在包装对象上，全部由 `LV_EVENT_DELETE` 统一回收。
 */
private class KeepSlot {
    /// 需要强引用的仓颉对象（ImageDsc / 自定义 keep 的对象），随 lv_obj 删除一起释放
    let refs: ArrayList<Object> = ArrayList<Object>()
    /// 样式单独一张表：只追加，不会被 keepOnly 清掉（见类注释）
    let styles: ArrayList<Object> = ArrayList<Object>()
    /// 需要 free 的 C 侧裸缓冲，下标即槽位号
    let cBufs: ArrayList<CPointer<Unit>> = ArrayList<CPointer<Unit>>()

    /** 写入指定槽位，返回被顶替下来的旧缓冲（由调用方 free，可能为空） */
    func putBuf(slot: UInt32, buf: CPointer<Unit>): CPointer<Unit> {
        let i = Int64(slot)
        while (cBufs.size <= i) {
            cBufs.add(CPointer<Unit>())
        }
        let old = cBufs[i]
        cBufs[i] = buf
        old
    }
}

private let KEEPS: HashMap<UIntNative, KeepSlot> = HashMap<UIntNative, KeepSlot>()
/// 已经给该 lv_obj 挂过 cjEventDispatch 的地址，避免重复注册 C 回调
private let HOOKED: HashSet<UIntNative> = HashSet<UIntNative>()

private func freeKeepSlot(addr: UIntNative): Unit {
    match (KEEPS.get(addr)) {
        case Some(slot) =>
            for (buf in slot.cBufs) {
                if (!buf.isNull()) {
                    unsafe { LibC.free(buf) }
                }
            }
            slot.cBufs.clear()
            slot.refs.clear()
            slot.styles.clear()
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
 *
 * **按 current_target 索引而不是 target**：冒泡时 LVGL 会拿祖先的 cb 再调一次，
 * 这时 current_target 是祖先、target 仍是原始对象。用 current_target 才能命中祖先的 hub，
 * 并用「两者是否相等」区分「自己发出的」与「子对象冒泡上来的」两类订阅。
 */
@C
func cjEventDispatch(e: CPointer<lv_event_t>): Unit {
    let code = unsafe { lv_event_get_code(e) }
    let target = unsafe { lv_event_get_target(e) }
    let current = unsafe { lv_event_get_current_target_obj(e) }
    let targetAddr = target.toUIntNative()
    let addr = current.toUIntNative()
    let bubbled = addr != targetAddr
    match (EVENT_HUBS.get(addr)) {
        case Some(hub) =>
            hub.dispatchDepth += 1
            var i: Int64 = 0
            while (i < hub.entries.size) {
                let entry = hub.entries[i]
                if (entry.active && entry.bubble == bubbled && (entry.mask == LV_EVENT_ALL || entry.mask == code)) {
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
        removeEventHub(targetAddr)
        freeKeepSlot(targetAddr)
        untrackWidget(targetAddr)
        HOOKED.remove(targetAddr)
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

/** 追加式：`obj` 活到 lv_obj 被删除为止（多个对象各自独立并存） */
internal func keepRef(handle: CPointer<lv_obj_t>, obj: Object): Unit {
    keepSlotOf(handle).refs.add(obj)
}

/** 替换式：用 `objs` 顶掉此前登记的全部对象（换帧 / 换源时用） */
internal func keepOnlyRefs(handle: CPointer<lv_obj_t>, objs: ArrayList<Object>): Unit {
    let slot = keepSlotOf(handle)
    slot.refs.clear()
    for (o in objs) {
        slot.refs.add(o)
    }
}

/**
 * 按槽位登记一块**所有权转移**给控件的 C 缓冲：同一槽位的旧缓冲立即 free。
 *
 * grid 的列/行描述符是两块同时存活的数组，所以槽位是必需的——
 * 早先「一个控件只留一块缓冲」的写法在这里会直接用掉前一块。
 */
internal func keepBufOf(handle: CPointer<lv_obj_t>, buf: CPointer<Unit>, slot: UInt32): Unit {
    let old = keepSlotOf(handle).putBuf(slot, buf)
    if (!old.isNull() && old.toUIntNative() != buf.toUIntNative()) {
        unsafe { LibC.free(old) }
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

/** 当前保活的仓颉对象个数（含样式；调试/测试用） */
internal func keptRefCount(handle: CPointer<lv_obj_t>): Int64 {
    match (KEEPS.get(handle.toUIntNative())) {
        case Some(slot) => slot.refs.size + slot.styles.size
        case None => 0
    }
}

/** 当前保活的非空 C 缓冲个数（调试/测试用） */
internal func keptBufCount(handle: CPointer<lv_obj_t>): Int64 {
    match (KEEPS.get(handle.toUIntNative())) {
        case Some(slot) =>
            var n: Int64 = 0
            for (buf in slot.cBufs) {
                if (!buf.isNull()) {
                    n += 1
                }
            }
            n
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
        App.assertUIThread("EventSubscription.cancel")
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

    /**
     * 事件最初的目标控件（冒泡时始终是那个真正被点击/修改的控件）。
     * 返回的是借用视图，**不要**对其调用 finalize()/delete()
     */
    public func target(): Widget {
        Widget(unsafe { lv_event_get_target(handle) }, owned: false)
    }

    /**
     * 当前回调所属的控件。与 `target()` 相同表示「事件由本控件发出」，
     * 不同则表示「事件从子对象冒泡上来」。
     */
    public func currentTarget(): Widget {
        Widget(unsafe { lv_event_get_current_target_obj(handle) }, owned: false)
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

    /**
     * @param handle lv_obj_t 句柄
     * @param owned  true = 本对象拥有该 lv_obj（负责释放）；false = 借用视图
     * @throws[LvglException] owned 且句柄为空时（`lv_*_create` 失败，通常是 LVGL 内存池耗尽）
     */
    internal init(handle: CPointer<lv_obj_t>, owned!: Bool = true) {
        // 所有控件的构造函数都是 `super(unsafe { lv_x_create(...) })`，
        // 这里统一兜住创建失败：否则后续任何链式调用都会解引用空指针。
        // 借用视图（Screen / Event.target()）允许为空语义，不在此校验。
        if (owned && handle.isNull()) {
            throw LvglException("控件创建失败：lv_obj_t 为空（通常是 LVGL 内存池耗尽）")
        }
        this.handle = handle
        this.owned = owned
        if (owned) {
            trackWidget(handle)
        }
    }

    /* ---- 保活：LVGL「只存指针」类 API 的公共契约 ---- */

    /**
     * 追加保活一个仓颉对象，直到本控件**被 LVGL 删除**为止。
     *
     * 凡是「LVGL 只存指针、不拷贝内容」的能力，数据存活都得锚在 lv_obj 上：
     * `lv_obj_add_style`、`lv_image_set_src`、`lv_spangroup_set_span_style`、
     * `lv_style_set_grid_column_dsc_array` … 库内部已对样式与图像描述符自动登记，
     * 自定义控件碰到同类 API 时用它，**不要**把引用挂在包装对象字段上。
     *
     * 为什么不挂包装对象上：仓颉 GC 由分配压力驱动（实测 UI 帧循环 3 秒内一次都不触发），
     * 包装对象可能先于 lv_obj 被回收，而 lv_obj 还在屏上。
     * @param obj 需要保活的对象
     * @return this，便于链式调用
     */
    public func keep(obj: Object): Widget {
        App.assertUIThread("Widget.keep")
        keepRef(handle, obj)
        this
    }

    /**
     * 替换式保活：用 `objs` 顶掉此前由 `keep()` 登记的**全部**对象（帧序列换源、图像换源）。
     *
     * 与 `keep()` 的差别是**先清空再登记**，适合「一次换一整套」的场景，
     * 避免旧帧一直留到控件删除。
     *
     * 注意：`Style.applyTo` / `SpanPart.style` 登记的样式在**独立的表**里，
     * 不受本方法影响 —— 否则换图源会把已经挂在 lv_obj 上的样式一起放开。
     * @param objs 新的保活对象列表
     * @return this，便于链式调用
     */
    public func keepOnly(objs: ArrayList<Object>): Widget {
        App.assertUIThread("Widget.keepOnly")
        keepOnlyRefs(handle, objs)
        this
    }

    /**
     * 按槽位接管一块 C 缓冲的**所有权**：本控件被删除时 free 它。
     *
     * 给「LVGL 直接引用一块我们 malloc 出来的数组」的 API 用：
     * `lv_line_set_points`、`lv_calendar_set_highlighted_dates`、
     * `lv_style_set_grid_column_dsc_array` / `..._row_...`。
     *
     * **必须是 `LibC.malloc` 系列分配的指针**，且登记之后调用方不能再 free（会重复释放）。
     * 同一 `slot` 再次调用会立刻 free 旧缓冲；不同槽位并存——grid 的列描述符用
     * `slot: 0`、行描述符用 `slot: 1`。
     * @param buf 交由控件接管的缓冲
     * @param slot 槽位号（默认 0）
     * @return this，便于链式调用
     */
    public func keepBuf(buf: CPointer<Unit>, slot!: UInt32 = 0): Widget {
        App.assertUIThread("Widget.keepBuf")
        keepBufOf(handle, buf, slot)
        this
    }

    /**
     * 当前被本控件保活的仓颉对象个数（样式、图像描述符、自定义保活累加）。
     * 业务侧一般不需要；用于排查「保活是否真的挂上了」以及测试断言。
     */
    public func keptCount(): Int64 {
        keptRefCount(handle)
    }

    /** 当前被本控件接管的非空 C 缓冲个数（按槽位计） */
    public func keptBufs(): Int64 {
        keptBufCount(handle)
    }

    /**
     * 追加保活一个样式；由 `Style.applyTo()` / `SpanPart.style()` 内部调用。
     *
     * 与 `keep()` 不同，样式登记在**独立**的 styles 表里：`keepOnly()`（换图源、换帧）
     * 只清 refs，不会把已挂在 lv_obj 上的 lv_style_t 一起放开 —— 否则 LVGL 的
     * `obj->styles[]` 会指向已释放的样式。
     */
    internal func keepStyle(st: Style): Unit {
        keepSlotOf(handle).styles.add(st)
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

    /**
     * 相对父对象**内容区**的左上角 x 坐标。
     *
     * flex/grid 的子对象位置是惰性计算的：改完布局属性后必须等布局更新，
     * 在此之前读到的还是旧值 —— 需要立即读请先调 `updateLayout()`。
     */
    public func x(): Int32 {
        unsafe { lv_obj_get_x(handle) }
    }

    /** 相对父对象内容区的左上角 y 坐标（同 `x()` 的惰性说明） */
    public func y(): Int32 {
        unsafe { lv_obj_get_y(handle) }
    }

    /** 内容区宽度（去掉 padding / 边框后的可布局宽度） */
    public func contentWidth(): Int32 {
        unsafe { lv_obj_get_content_width(handle) }
    }

    /** 内容区高度（去掉 padding / 边框后的可布局高度） */
    public func contentHeight(): Int32 {
        unsafe { lv_obj_get_content_height(handle) }
    }

    /**
     * 立即重算本对象子树的布局（等价 `lv_obj_update_layout`）。
     *
     * 正常界面里下一帧会自动算；**测试里必须显式调**，否则刚设好的 flex/grid
     * 布局还没落到子对象的 x/y/size 上，断言读到的是旧值。
     */
    public func updateLayout(): Unit {
        unsafe { lv_obj_update_layout(handle) }
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
     * 等价于 `on(mask, cb)`；保留此名是为了与「我确实要收全量」的意图区分。
     * @throws[LvglException] 控件已释放或已请求删除时
     */
    public func onEvent(mask: UInt32, cb: (Event) -> Unit): EventSubscription {
        subscribe(mask, cb)
    }

    /**
     * 精确订阅一个事件码（`EventCode.CLICKED` 等），只收**本控件自己发出的**。
     *
     * 与 `onEvent(LV_EVENT_ALL)` 相比，过滤放在仓颉侧的分发表里就完成了，
     * 回调不会再被无关事件唤醒 —— 滑动列表这类高频控件差别明显。
     * @param code LV_EVENT_* 事件码
     * @param cb 回调（在 UI 线程执行；异常由 `App.onCallbackError` 接管）
     * @return 可取消的订阅句柄
     * @throws[LvglException] 控件已释放或已请求删除时
     */
    public func on(code: UInt32, cb: (Event) -> Unit): EventSubscription {
        subscribe(code, cb)
    }

    /**
     * 订阅**子孙冒泡上来**的事件（只收 target != 本控件的），常用于「一屏一个处理器」。
     *
     * 前置条件：发出事件的那个子孙必须带 `LV_OBJ_FLAG_EVENT_BUBBLE`，
     * 否则事件根本不会向上传播 —— 用 `child.bubble()` 打开。为了少踩坑，
     * 本方法会给**自己**也打开该标志（作为中间层继续向上传递时是必需的）。
     *
     * ```cangjie
     * root.onBubbled(EventCode.CLICKED) { e => ... }  // e.target() 是真正被点的控件
     * btn.bubble()
     * ```
     * @param code LV_EVENT_* 事件码（或 LV_EVENT_ALL）
     * @param cb 回调
     * @return 可取消的订阅句柄
     * @throws[LvglException] 控件已释放或已请求删除时
     */
    public func onBubbled(code: UInt32, cb: (Event) -> Unit): EventSubscription {
        bubble()
        subscribe(code, cb, bubble: true)
    }

    /**
     * 打开/关闭事件冒泡（`LV_OBJ_FLAG_EVENT_BUBBLE`）：打开后本控件发出的事件
     * 会继续传给父对象，父对象上的 `onBubbled` 才能收到。
     * @param on true 打开，false 关闭
     * @return this，便于链式调用
     */
    public func bubble(on!: Bool = true): Widget {
        if (on) {
            addFlag(LV_OBJ_FLAG_EVENT_BUBBLE)
        } else {
            removeFlag(LV_OBJ_FLAG_EVENT_BUBBLE)
        }
        this
    }

    private func subscribe(mask: UInt32, cb: (Event) -> Unit, bubble!: Bool = false): EventSubscription {
        App.assertUIThread("Widget.on")
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
        hub.add(id, mask, bubble, cb)
        EventSubscription(addr, id)
    }

    /** 取消一个事件订阅，等价于 sub.cancel() */
    public func offEvent(sub: EventSubscription): Unit {
        sub.cancel()
    }

    /** 主动向控件发送事件（测试、自定义事件或模拟输入时使用）；控件已释放时静默返回 */
    public func sendEvent(code: UInt32): Unit {
        if (!alive || deleteRequested) {
            return
        }
        let _ = unsafe { lv_obj_send_event(handle, code, CPointer<Unit>()) }
    }

    /* ---- 局部样式快捷（selector = part | state） ---- */

    /**
     * 一次性改单个属性，不产生可复用的 `Style` 对象。
     *
     * 与 `Style().xxx().applyTo()` 的分工：要复用到多个控件（尤其常态/按下态成对）
     * 请用 `Style`；只调一处就改的目标用这组 setter 更直接，也不用操心保活。
     * 所有 setter 都支持 `part` 与 `state`，例如：
     * ```cangjie
     * btn.setStyleBgColor(0xD0, 0xD0, 0xD0, state: LV_STATE_PRESSED)
     * slider.setStyleBgColor(0x21, 0x96, 0xF3, part: LV_PART_INDICATOR)
     * ```
     * @param r 红
     * @param g 绿
     * @param b 蓝
     * @param part 目标部件（LV_PART_*）
     * @param state 目标状态（LV_STATE_*，默认 DEFAULT）
     */
    public func setStyleBgColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN,
        state!: UInt32 = LV_STATE_DEFAULT): Unit {
        unsafe { lv_obj_set_style_bg_color(handle, Color.of(r, g, b), part | state) }
    }

    /** 背景不透明度（0 透明，255 不透明；`LV_OPA_COVER` 即 255） */
    public func setStyleBgOpa(opa: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Unit {
        unsafe { lv_obj_set_style_bg_opa(handle, opa, part | state) }
    }

    /** 文字颜色 */
    public func setStyleTextColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN,
        state!: UInt32 = LV_STATE_DEFAULT): Unit {
        unsafe { lv_obj_set_style_text_color(handle, Color.of(r, g, b), part | state) }
    }

    /** 圆角半径（像素） */
    public func setStyleRadius(radius: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Unit {
        unsafe { lv_obj_set_style_radius(handle, radius, part | state) }
    }

    /** 边框宽度（像素，0 即无边框） */
    public func setStyleBorderWidth(w: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Unit {
        unsafe { lv_obj_set_style_border_width(handle, w, part | state) }
    }

    /** 边框颜色 */
    public func setStyleBorderColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN,
        state!: UInt32 = LV_STATE_DEFAULT): Unit {
        unsafe { lv_obj_set_style_border_color(handle, Color.of(r, g, b), part | state) }
    }

    /**
     * 四边统一内边距。
     *
     * 分别设四条边：`lv_obj_set_style_pad_all` 在 LVGL 里是 `static inline`，
     * 静态库里没有这个符号，直接 FFI 绑定会链接失败（`Style.padAll` 走的是垫片包装）。
     */
    public func setStylePadAll(pad: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Unit {
        let sel = part | state
        unsafe {
            lv_obj_set_style_pad_left(handle, pad, sel)
            lv_obj_set_style_pad_right(handle, pad, sel)
            lv_obj_set_style_pad_top(handle, pad, sel)
            lv_obj_set_style_pad_bottom(handle, pad, sel)
        }
    }

    /** 阴影宽度（像素，0 即无阴影） */
    public func setStyleShadowWidth(w: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Unit {
        unsafe { lv_obj_set_style_shadow_width(handle, w, part | state) }
    }

    /**
     * 设置 flex / grid 的子对象间距（`pad_row` 与 `pad_column` 同时设）。
     *
     * 注意这两个属性**不受 `setStylePadAll` / `padAll` 影响**：它们是独立的
     * 「子对象之间的间距」，而 pad_all 是「内容与边框之间的留白」。
     * 布局间距没归零时，flex / grid 的轨道尺寸会算得比预期小 —— 这点很容易漏。
     * @param gap 间距（像素）
     * @param part 目标部件
     * @param state 目标状态
     */
    public func setStyleGap(gap: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Unit {
        let sel = part | state
        unsafe {
            lv_obj_set_style_pad_row(handle, gap, sel)
            lv_obj_set_style_pad_column(handle, gap, sel)
        }
    }

    /**
     * 设置字体。text_font 是可继承属性：设在 Screen / 容器上即对该子树全部生效，
     * 因此全局换字体只需 `disp.screen().setFont(f)`。
     *
     * @param f 字体
     * @param part 目标部件
     * @param state 目标状态
     */
    public func setFont(f: Font, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Unit {
        // 字体指针存进 LVGL 的对象样式里，这里标记"已被引用"，
        // 防止调用方随后 Font.close() 把仍在渲染的字形缓存删掉。
        f.attach()
        unsafe { lv_obj_set_style_text_font(handle, f.raw(), part | state) }
    }

    /* ---- 生命周期 ---- */

    /**
     * 立即释放控件（从父对象上删除并销毁）；重复调用安全。
     *
     * @throws[LvglException] 对 Screen / Event.target() 等借用视图调用时
     */
    public func finalize(): Unit {
        App.assertUIThread("Widget.finalize")
        if (!owned) {
            throw LvglException("该 Widget 是借用视图，不能释放")
        }
        if (!alive || deleteRequested) {
            return
        }
        alive = false
        deleteRequested = true
        let addr = handle.toUIntNative()
        // 先确认对象还在树上：LVGL 拥有子对象，父对象被删除时子对象一起消失，
        // 但包装对象不会因此变成 isDeleted()==true。此时地址已归还内存池，
        // 再调 lv_obj_delete 就是往池链表里写脏数据（父对象先删的常见用法）。
        if (unsafe { lv_obj_is_valid(handle) }) {
            // lv_obj_delete 内部会同步派发 LV_EVENT_DELETE：
            // 订阅表与保活槽都由 cjEventDispatch 收尾，这里再做一次只是兜底（幂等）。
            unsafe { lv_obj_delete(handle) }
        }
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
        App.assertUIThread("Widget.delete")
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
        App.assertUIThread("Widget.close")
        if (!owned || !alive || deleteRequested) {
            return
        }
        alive = false
        deleteRequested = true
        let addr = handle.toUIntNative()
        if (unsafe { lv_obj_is_valid(handle) }) {
            unsafe { lv_obj_delete(handle) }
        }
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
