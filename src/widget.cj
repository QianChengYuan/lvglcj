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
            // LVGL 删除对象时会发 LV_EVENT_DELETE（父对象递归删除子对象时也会发），
            // 在这里回收整个 hub，避免长跑后订阅表只增不减。
            if (code == LV_EVENT_DELETE) {
                removeEventHub(addr)
            }
        case None => ()
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

public open class Widget {
    protected var handle: CPointer<lv_obj_t>
    private let owned: Bool
    private var alive: Bool = true
    private var deleteRequested: Bool = false
    // 借给本控件的样式。LVGL 的 lv_obj_add_style / lv_spangroup_set_span_style
    // 只保存 lv_style_t*，不持有仓颉对象；这里把 Style 强引用挂到控件上，
    // 保证「临时 Style」也不会在绘制前被 GC 回收（否则就是偶发花屏/UAF）。
    private var keptStyles: Option<ArrayList<Style>> = None

    internal init(handle: CPointer<lv_obj_t>, owned!: Bool = true) {
        this.handle = handle
        this.owned = owned
    }

    /**
     * 登记一个"LVGL 只存指针"的样式，让它活到本控件销毁为止。
     * 由 `Style.applyTo()` / `SpanPart.style()` 内部调用，业务侧不需要手动调。
     */
    internal func keepStyle(st: Style): Unit {
        match (keptStyles) {
            case Some(list) => list.add(st)
            case None =>
                let list = ArrayList<Style>()
                list.add(st)
                keptStyles = Some(list)
        }
    }

    /**
     * 当前被本控件保活的样式数量。
     * 业务侧一般不需要；用于排查「样式是否真的被挂上了」以及测试断言。
     */
    public func keptStyleCount(): Int64 {
        match (keptStyles) {
            case Some(list) => list.size
            case None => 0
        }
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
                unsafe {
                    lv_obj_add_event_cb(handle, cjEventDispatch, LV_EVENT_ALL, CPointer<Unit>())
                }
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
        unsafe { lv_obj_delete(handle) }
        removeEventHub(addr)
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
