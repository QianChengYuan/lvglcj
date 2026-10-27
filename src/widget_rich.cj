/**
 * 友好 API 层：富文本（span）、日历、帧动画、拼音输入法。
 *
 * 原 widget.cj 按主题拆分而来（同属 package lvglcj，对外 API 不变）。
 */
package lvglcj

import std.collection.*

/* ==================== 富文本（span） ==================== */

/**
 * 富文本片段（lv_span_t）。只能由 SpanGroup.add() 创建，不要自行构造。
 * 修改文本/样式后内部会自动调用 lv_spangroup_refresh() 触发重排。
 */
public class SpanPart {
    // 持有 SpanGroup 引用：既拿到 owner 指针，也让 style() 能把样式登记到 group 上保活
    private let group: SpanGroup
    private var owner: CPointer<lv_obj_t>
    private var handle: CPointer<lv_span_t>

    internal init(group: SpanGroup, handle: CPointer<lv_span_t>) {
        this.group = group
        this.owner = group.raw()
        this.handle = handle
    }

    /** 设置本片段文本（C 侧内部拷贝，调用返回后可释放临时串） */
    public func text(s: String): SpanPart {
        withCString(s) {cs => unsafe { lv_spangroup_set_span_text(owner, handle, cs) }}
        unsafe { lv_spangroup_refresh(owner) }
        this
    }

    /**
     * 设置本片段样式（字体/颜色/字号）。
     *
     * @lifetime 借用：`lv_spangroup_set_span_style` 只保存 `lv_style_t*`。本方法会把该
     *           Style 登记到所属 SpanGroup 上，所以 `sg.add("x").style(Style().textColor(...))`
     *           这种临时对象写法也安全 —— 样式会活到 SpanGroup 销毁。
     */
    public func style(st: Style): SpanPart {
        unsafe { lv_spangroup_set_span_style(owner, handle, st.raw()) }
        unsafe { lv_spangroup_refresh(owner) }
        group.keepStyle(st)
        this
    }
}

/**
 * 富文本组（lv_spangroup）：同一行文本里混排不同颜色/字号的片段。
 *
 * ```cangjie
 * let sg = SpanGroup(scr)
 * sg.add("警告：").style(Style().textColor(255, 80, 80))
 * sg.add("磁盘剩余 12%")
 * sg.size(300, LV_SIZE_CONTENT)
 * ```
 */
public class SpanGroup <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_spangroup_create(parent.raw()) })
    }

    /** 追加一个空片段，随后链式调用 .text(...) / .style(...) */
    public func add(): SpanPart {
        SpanPart(this, unsafe { lv_spangroup_add_span(handle) })
    }

    /** 追加一个带文本的片段 */
    public func add(text: String): SpanPart {
        add().text(text)
    }

    /** 当前片段数 */
    public func spanCount(): UInt32 {
        unsafe { lv_spangroup_get_span_count(handle) }
    }

    /** 文本对齐（LV_TEXT_ALIGN_*）。注意与 Widget.align（相对父容器对齐）不是一回事 */
    public func textAlign(a: UInt32): Unit {
        unsafe { lv_spangroup_set_align(handle, a) }
        unsafe { lv_spangroup_refresh(handle) }
    }

    /** 溢出处理：LV_SPAN_OVERFLOW_CLIP / LV_SPAN_OVERFLOW_ELLIPSIS */
    public func overflow(o: UInt32): Unit {
        unsafe { lv_spangroup_set_overflow(handle, o) }
        unsafe { lv_spangroup_refresh(handle) }
    }

    /** 首行缩进（像素） */
    public func indent(px: Int32): Unit {
        unsafe { lv_spangroup_set_indent(handle, px) }
        unsafe { lv_spangroup_refresh(handle) }
    }

    /** 宽度模式：LV_SPAN_MODE_FIXED（定宽）/ EXPAND（按文本撑开）/ BREAK（定宽换行） */
    public func mode(m: UInt32): Unit {
        unsafe { lv_spangroup_set_mode(handle, m) }
        unsafe { lv_spangroup_refresh(handle) }
    }

    /** 最大行数（-1 表示不限制） */
    public func maxLines(n: Int32): Unit {
        unsafe { lv_spangroup_set_max_lines(handle, n) }
        unsafe { lv_spangroup_refresh(handle) }
    }

    /** 手动触发重排（直接改过 C 侧数据后使用） */
    public func refresh(): Unit {
        unsafe { lv_spangroup_refresh(handle) }
    }
}

/* ==================== 日历 ==================== */

/**
 * 日历（lv_calendar）。
 *
 * 高亮日期数组在 C 侧**只保存指针、不拷贝**，因此缓冲登记在保活表里，
 * 活到下一次 highlight() 或**控件被删除**为止。
 */
public class Calendar <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_calendar_create(parent.raw()) })
    }

    /** 设置"今天"（该日以 today 样式高亮） */
    public func today(year: UInt32, month: UInt32, day: UInt32): Unit {
        unsafe { lv_calendar_set_today_date(handle, year, month, day) }
    }

    /** 当前显示的月份（day 固定为 1） */
    public func showMonth(year: UInt32, month: UInt32): Unit {
        unsafe { lv_calendar_set_month_shown(handle, year, month) }
    }

    /** 加上「年月 + 左右箭头」头部（9.5 的日历默认没有头部，需要显式创建） */
    public func headerArrow(): Unit {
        unsafe { lv_calendar_add_header_arrow(handle) }
    }

    /** 加上「年/月下拉框」头部（依赖 lv_conf.h 的 LV_USE_DROPDOWN） */
    public func headerDropdown(): Unit {
        unsafe { lv_calendar_add_header_dropdown(handle) }
    }

    /** 读回已设置的"今天"；同时可用于验证 lv_calendar_date_t 的字段布局 */
    public func todayDate(): Option<(UInt32, UInt32, UInt32)> {
        let p = unsafe { lv_calendar_get_today_date(handle) }
        if (p.isNull()) {
            return None
        }
        let d = unsafe { p.read() }
        Some((UInt32(d.year), UInt32(d.month), UInt32(d.day)))
    }

    /**
     * 高亮一组日期（year, month, day）
     * @param dates 待高亮日期；空数组直接返回，不清除已有高亮
     * @throws[LvglException] 日期缓冲分配失败时
     */
    public func highlight(dates: Array<(UInt32, UInt32, UInt32)>): Unit {
        if (dates.size == 0) {
            return
        }
        let buf = unsafe { LibC.malloc<lv_calendar_date_t>(count: Int64(dates.size)) }
        if (buf.isNull()) {
            throw LvglException("日历高亮日期数组分配失败")
        }
        unsafe {
            var i: Int64 = 0
            for (d in dates) {
                var item = lv_calendar_date_t()
                item.year = UInt16(d[0])
                item.month = UInt8(d[1])
                item.day = UInt8(d[2])
                buf.write(i, item)
                i += 1
            }
            lv_calendar_set_highlighted_dates(handle, buf, UIntNative(dates.size))
        }
        // 登记后旧缓冲由保活表释放；控件删除时连新缓冲一起释放。
        keepBuf(CPointer<Unit>(buf))
    }

    /** 用户点击选中的日期；未选中时返回 None */
    public func pressedDate(): Option<(UInt32, UInt32, UInt32)> {
        var d = lv_calendar_date_t() // cjlint-ignore !G.VAR.01 inout 出参必须是可变变量
        let r = unsafe { lv_calendar_get_pressed_date(handle, inout d) }
        if (r != LV_RESULT_OK) {
            return None
        }
        Some((UInt32(d.year), UInt32(d.month), UInt32(d.day)))
    }

    /** 点击日期回调（点击某日时 LVGL 抛 LV_EVENT_VALUE_CHANGED），返回可取消的订阅句柄 */
    public func onPressed(cb: (UInt32, UInt32, UInt32) -> Unit): EventSubscription {
        let selfHandle = handle
        onEvent(LV_EVENT_VALUE_CHANGED) {
            _ =>
                var d = lv_calendar_date_t() // cjlint-ignore !G.VAR.01 inout 出参必须是可变变量
                let r = unsafe { lv_calendar_get_pressed_date(selfHandle, inout d) }
                if (r == LV_RESULT_OK) {
                    cb(UInt32(d.year), UInt32(d.month), UInt32(d.day))
                }
        }
    }
}

/* ==================== 帧动画 ==================== */

/**
 * 帧动画（lv_animimg）。
 *
 * LVGL 只保存帧指针数组的地址、**不拷贝内容**，所以指针数组与每个 ImageDsc
 * 都登记进保活表，活到下一次 frames() 或**控件被删除**为止。
 * 调用方因此可以把临时 ImageDsc 直接传进来。
 */
public class AnimImage <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_animimg_create(parent.raw()) })
    }

    /**
     * 设置帧序列（至少 2 帧）。
     * @param list       每帧的图像描述符（ImageBuffer.toImageDsc() 的产物）
     * @param durationMs 一整轮播放的时长
     * @throws[LvglException] 帧数少于 2，或帧指针数组分配失败时
     */
    public func frames(list: Array<ImageDsc>, durationMs!: UInt32 = 1000): Unit {
        if (list.size < 2) {
            throw LvglException("AnimImage.frames 至少需要 2 帧")
        }
        let buf = unsafe { LibC.malloc<CPointer<Unit>>(count: Int64(list.size)) }
        if (buf.isNull()) {
            throw LvglException("帧指针数组分配失败")
        }
        unsafe {
            var i: Int64 = 0
            for (d in list) {
                buf.write(i, CPointer<Unit>(d.raw()))
                i += 1
            }
            lv_animimg_set_src(handle, buf, UIntNative(list.size))
            lv_animimg_set_duration(handle, durationMs)
        }
        // 帧指针数组与每个 ImageDsc 都交给保活表：旧的一批在登记新的一批时释放。
        keepBuf(CPointer<Unit>(buf))
        let keep = ArrayList<Object>()
        for (d in list) {
            keep.add(d)
        }
        keepOnly(keep)
    }

    /** 开始播放 */
    public func start(): Unit {
        unsafe { lv_animimg_start(handle) }
    }

    /** 循环次数（LV_ANIM_REPEAT_INFINITE 为无限） */
    public func repeatCount(n: UInt32): Unit {
        unsafe { lv_animimg_set_repeat_count(handle, n) }
    }

    /** 当前帧数 */
    public func srcCount(): UInt8 {
        unsafe { lv_animimg_get_src_count(handle) }
    }
}

/* ==================== 中文拼音输入法 ==================== */

/**
 * 拼音输入法（lv_ime_pinyin）：给 Keyboard 加中文候选词面板。
 *
 * 需要 `lv_conf.h` 里 `LV_USE_IME_PINYIN 1` 并重编静态库，
 * 否则链接期会报 `lv_ime_pinyin_*` 未定义。
 */
public class ImePinyin <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_ime_pinyin_create(parent.raw()) })
    }

    /** 绑定要输入的键盘（候选词面板会挂在该键盘上） */
    public func bindKeyboard(kb: Keyboard): Unit {
        unsafe { lv_ime_pinyin_set_keyboard(handle, kb.raw()) }
    }

    /** 键盘布局：LV_IME_PINYIN_MODE_K26 / K9 / K9_NUMBER */
    public func mode(m: UInt32): Unit {
        unsafe { lv_ime_pinyin_set_mode(handle, m) }
    }
}
