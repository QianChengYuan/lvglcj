/**
 * 友好 API 层：基础对象（Widget）与常用控件。
 *
 * 每个控件一个仓颉 class，链式风格，内部只持 lv_obj_t 句柄；
 * 析构由 finalize()/delete() 显式触发（LVGL 对象树由 C 侧管理）。
 */
package lvglcj

import std.collection.*
import std.fs.*

/* ==================== 事件桥接 ==================== */

private class EventEntry {
    let objAddr: UIntNative
    let mask: UInt32
    let cb: (Event) -> Unit

    init(objAddr: UIntNative, mask: UInt32, cb: (Event) -> Unit) {
        this.objAddr = objAddr
        this.mask = mask
        this.cb = cb
    }
}

// 事件注册表必须是模块级：C 侧只认静态分发函数，闭包状态不能跟着控件对象走。
private let EVENT_ENTRIES: ArrayList<EventEntry> = ArrayList<EventEntry>() // cjlint-ignore !G.VAR.02 回调注册表必须全局存活

/**
 * LVGL 事件分发器：C 侧只见这个静态函数。
 * 注意：闭包内抛出的异常不能跨 C 边界传播，回调代码须自行兜底。
 */
@C
func cjEventDispatch(e: CPointer<lv_event_t>): Unit {
    let code = unsafe { lv_event_get_code(e) }
    let target = unsafe { lv_event_get_target(e) }
    let addr = target.toUIntNative()
    for (entry in EVENT_ENTRIES) {
        if (entry.objAddr == addr && (entry.mask == LV_EVENT_ALL || entry.mask == code)) {
            entry.cb(Event(e))
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

    /** 事件目标控件。返回的 Widget 与源控件共享句柄，**不要**对其调用 finalize() */
    public func target(): Widget {
        Widget(unsafe { lv_event_get_target(handle) })
    }
}

/* ==================== Widget 基类 ==================== */

public open class Widget {
    protected var handle: CPointer<lv_obj_t>

    internal init(handle: CPointer<lv_obj_t>) {
        this.handle = handle
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

    /** 订阅事件（mask 为 LV_EVENT_*；LV_EVENT_ALL 收全部） */
    public func onEvent(mask: UInt32, cb: (Event) -> Unit): Unit {
        EVENT_ENTRIES.add(EventEntry(handle.toUIntNative(), mask, cb))
        unsafe {
            lv_obj_add_event_cb(handle, cjEventDispatch, mask, CPointer<Unit>())
        }
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

    /** 释放控件（从父对象上删除并销毁） */
    public func finalize(): Unit {
        unsafe { lv_obj_delete(handle) }
    }

    /** 同 finalize()：异步删除更安全（在定时器上下文中调用时用） */
    public func delete(): Unit {
        finalize()
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

/* ==================== 文本类 ==================== */

public class Label <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_label_create(parent.raw()) })
    }

    /** 包装既有 lv_obj_t（如 lv_win_add_title 的返回值） */
    internal init(handle: CPointer<lv_obj_t>) {
        super(handle)
    }

    public func text(s: String): Unit {
        withCString(s) {cs => unsafe { lv_label_set_text(handle, cs) }}
    }

    /** 顺序替换 %d 后设置文本（仓颉侧完成格式化；等价于 LVGL 的 set_text_fmt） */
    public func setTextFmt(fmt: String, args: Array<Int32>): Unit {
        let parts = fmt.split("%d")
        var result = ""
        var i: Int64 = 0
        while (i < Int64(parts.size)) {
            result += parts[i]
            if (i < Int64(args.size)) {
                result += "${args[i]}"
            }
            i += 1
        }
        text(result)
    }

    public func color(r: UInt8, g: UInt8, b: UInt8): Unit {
        unsafe { lv_obj_set_style_text_color(handle, Color.of(r, g, b), LV_PART_MAIN) }
    }

    public func longMode(mode: UInt32): Unit {
        unsafe { lv_label_set_long_mode(handle, mode) }
    }
}

public class TextArea <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_textarea_create(parent.raw()) })
    }

    public func text(s: String): Unit {
        withCString(s) {cs => unsafe { lv_textarea_set_text(handle, cs) }}
    }

    public func oneLine(on: Bool): Unit {
        unsafe { lv_textarea_set_one_line(handle, on) }
    }

    public func password(on: Bool): Unit {
        unsafe { lv_textarea_set_password_mode(handle, on) }
    }
}

public class Keyboard <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_keyboard_create(parent.raw()) })
    }

    public func target(ta: TextArea): Unit {
        unsafe { lv_keyboard_set_textarea(handle, ta.raw()) }
    }
}

/* ==================== 按钮 / 开关 ==================== */

public class Button <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_button_create(parent.raw()) })
    }

    /** 包装既有 lv_obj_t（如 lv_list_add_button 的返回值） */
    internal init(handle: CPointer<lv_obj_t>) {
        super(handle)
    }

    /** 点击回调（LV_EVENT_CLICKED，主线程执行） */
    public func onClick(cb: () -> Unit): Unit {
        onEvent(LV_EVENT_CLICKED) {_ => cb()}
    }

    /** 可勾选模式（状态用 LV_STATE_CHECKED） */
    public func checkable(): Unit {
        addFlag(LV_OBJ_FLAG_CHECKABLE)
    }
}

public class Switch <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_switch_create(parent.raw()) })
    }

    public func setChecked(on: Bool): Unit {
        if (on) {
            addState(LV_STATE_CHECKED)
        } else {
            removeState(LV_STATE_CHECKED)
        }
    }

    public func isChecked(): Bool {
        (unsafe { lv_obj_get_state(handle) } & LV_STATE_CHECKED) != 0
    }
}

public class Checkbox <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_checkbox_create(parent.raw()) })
    }

    public func text(s: String): Unit {
        withCString(s) {cs => unsafe { lv_checkbox_set_text(handle, cs) }}
    }

    public func setChecked(on: Bool): Unit {
        if (on) {
            addState(LV_STATE_CHECKED)
        } else {
            removeState(LV_STATE_CHECKED)
        }
    }

    public func isChecked(): Bool {
        (unsafe { lv_obj_get_state(handle) } & LV_STATE_CHECKED) != 0
    }
}

/* ==================== 值类 ==================== */

public class Slider <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_slider_create(parent.raw()) })
    }

    public func value(v: Int32, anim!: Bool = true): Unit {
        unsafe { lv_slider_set_value(handle, v, if (anim) {
            LV_ANIM_ON
        } else {
            LV_ANIM_OFF
        }) }
    }

    public func valueGet(): Int32 {
        unsafe { lv_slider_get_value(handle) }
    }

    public func range(min: Int32, max: Int32): Unit {
        unsafe { lv_slider_set_range(handle, min, max) }
    }
}

public class Arc <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_arc_create(parent.raw()) })
    }

    public func value(v: Int32): Unit {
        unsafe { lv_arc_set_value(handle, v) }
    }

    /** 背景弧角度范围（0..360） */
    public func angles(start: Int32, end: Int32): Unit {
        unsafe { lv_arc_set_bg_angles(handle, start, end) }
    }

    public func rotation(deg: Int32): Unit {
        unsafe { lv_arc_set_rotation(handle, deg) }
    }
}

public class Bar <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_bar_create(parent.raw()) })
    }

    public func value(v: Int32, anim!: Bool = true): Unit {
        unsafe { lv_bar_set_value(handle, v, if (anim) {
            LV_ANIM_ON
        } else {
            LV_ANIM_OFF
        }) }
    }

    public func range(min: Int32, max: Int32): Unit {
        unsafe { lv_bar_set_range(handle, min, max) }
    }
}

public class Spinbox <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_spinbox_create(parent.raw()) })
    }

    public func value(v: Int32): Unit {
        unsafe { lv_spinbox_set_value(handle, v) }
    }

    public func range(min: Int32, max: Int32): Unit {
        unsafe { lv_spinbox_set_range(handle, min, max) }
    }
}

/* ==================== 选择类 ==================== */

public class Dropdown <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_dropdown_create(parent.raw()) })
    }

    /** 选项串，各项以 \n 分隔 */
    public func options(s: String): Unit {
        withCString(s) {cs => unsafe { lv_dropdown_set_options(handle, cs) }}
    }
}

public class Roller <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_roller_create(parent.raw()) })
    }

    public func options(s: String, mode!: UInt32 = LV_ROLLER_MODE_NORMAL): Unit {
        withCString(s) {cs => unsafe { lv_roller_set_options(handle, cs, mode) }}
    }

    public func selected(i: UInt32): Unit {
        unsafe { lv_roller_set_selected(handle, i, LV_ANIM_OFF) }
    }
}

/* ==================== 列表 / 表格 / 标签页 ==================== */

public class List <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_list_create(parent.raw()) })
    }

    public func addText(s: String): Widget {
        withCString(s) {cs => unsafe { Widget(lv_list_add_text(handle, cs)) }}
    }

    public func addButton(s: String): Button {
        withCString(s) {cs => unsafe { Button(lv_list_add_button(handle, CPointer<Unit>(), cs)) }}
    }
}

public class Table <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_table_create(parent.raw()) })
    }

    public func cellValue(row: UInt32, col: UInt32, s: String): Unit {
        withCString(s) {cs => unsafe { lv_table_set_cell_value(handle, row, col, cs) }}
    }
}

public class TabView <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_tabview_create(parent.raw()) })
    }

    public func addTab(name: String): Widget {
        withCString(name) {cs => unsafe { Widget(lv_tabview_add_tab(handle, cs)) }}
    }
}

/* ==================== 容器类 ==================== */

public class Menu <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_menu_create(parent.raw()) })
    }
}

public class MsgBox <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_msgbox_create(parent.raw()) })
    }
}

public class Win <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_win_create(parent.raw()) })
    }

    public func addTitle(s: String): Label {
        withCString(s) {cs => unsafe { Label(lv_win_add_title(handle, cs)) }}
    }
}

/* ==================== 图像 ==================== */

public class Image <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_image_create(parent.raw()) })
    }

    /** 设置图像源（ImageBuffer.toImageDsc() 的产物） */
    public func setSource(dsc: ImageDsc): Unit {
        unsafe { lv_image_set_src(handle, CPointer<Unit>(dsc.raw())) }
    }

    /**
     * 从图片文件创建图像控件。
     * 前置：静态库编入了 `LV_USE_LODEPNG` + `LV_USE_FS_STDIO`（本仓库三平台产物都已打开）；
     * JPG/GIF/WebP 还需在 `lv_conf.h` 另开 `LV_USE_TJPGD` / `LV_USE_GIF` / `LV_USE_LIBWEBP` 并重编。
     */
    public static func fromFile(parent: Widget, path: String): Image {
        let img = Image(parent)
        img.setFile(path)
        img
    }

    /**
     * 换成图片文件（路径不存在直接抛异常）。
     *
     * 注意：`lv_image_set_src` 返回 void，解码失败时 LVGL 只打 WARN 日志、控件显示空白，
     * 仓颉侧无法区分"文件在但格式不支持"——这种情况请检查 lv_conf.h 的解码器开关。
     * @param path 图片文件路径（系统路径，垫片负责补驱动器字母）
     * @throws[LvglException] `path` 不存在，或当前构建未启用 LV_USE_FS_STDIO 时
     */
    public func setFile(path: String): Unit {
        if (!exists(path)) {
            throw LvglException("图片文件不存在：${path}")
        }
        let r = withCString(path) {cs => unsafe { lvglcj_image_set_file_cjbindwrapper(handle, cs) }}
        if (r != LV_RESULT_OK) {
            throw LvglException("图片加载失败：${path}（确认 lv_conf.h 已开 LV_USE_FS_STDIO 并重编了 liblvgl.a）")
        }
    }

    public func rotate(deg: Int32): Unit {
        unsafe { lv_image_set_rotation(handle, deg) }
    }

    /** 缩放（1.0 为原始大小） */
    public func scale(factor: Float64): Unit {
        unsafe { lv_image_set_scale(handle, UInt32(factor * 256.0)) }
    }
}

/* ==================== 图表 / 曲线 / LED ==================== */

/** 图表数据系列（lv_chart_series_t 的友好包装） */
public class ChartSeries {
    private var handle: CPointer<Unit>

    internal init(handle: CPointer<Unit>) {
        this.handle = handle
    }

    internal func raw(): CPointer<Unit> {
        handle
    }
}

public class Chart <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_chart_create(parent.raw()) })
    }

    public func pointCount(n: UInt32): Unit {
        unsafe { lv_chart_set_point_count(handle, n) }
    }

    /** axis: 0 = 主 Y 轴，1 = 次 Y 轴 */
    public func range(axis: UInt32, min: Int32, max: Int32): Unit {
        unsafe { lv_chart_set_axis_range(handle, axis, min, max) }
    }

    public func addSeries(r: UInt8, g: UInt8, b: UInt8): ChartSeries {
        ChartSeries(unsafe { lv_chart_add_series(handle, Color.of(r, g, b), 0) })
    }

    public func setNextValue(series: ChartSeries, v: Int32): Unit {
        unsafe { lv_chart_set_next_value(handle, series.raw(), v) }
    }
}

public class Line <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_line_create(parent.raw()) })
    }

    /**
     * 设置折线顶点（至少 2 个点）
     * @param points 顶点坐标数组
     * @throws[LvglException] 顶点少于 2 个，或顶点缓冲分配失败时
     */
    public func setPoints(points: Array<(Int32, Int32)>): Unit {
        if (points.size < 2) {
            throw LvglException("Line.setPoints 至少需要 2 个点")
        }
        let buf = unsafe { LibC.malloc<lv_point_t>(count: Int64(points.size)) }
        if (buf.isNull()) {
            throw LvglException("Line.setPoints 顶点数组分配失败")
        }
        unsafe {
            var i: Int64 = 0
            for (p in points) {
                var pt = lv_point_t()
                pt.x = p[0]
                pt.y = p[1]
                buf.write(i, pt)
                i += 1
            }
            lv_line_set_points(handle, buf, UInt32(points.size))
            LibC.free(buf)
        }
    }
}

public class Scale <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_scale_create(parent.raw()) })
    }

    public func range(min: Int32, max: Int32): Unit {
        unsafe { lv_scale_set_range(handle, min, max) }
    }
}

public class Led <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_led_create(parent.raw()) })
    }

    public func color(r: UInt8, g: UInt8, b: UInt8): Unit {
        unsafe { lv_led_set_color(handle, Color.of(r, g, b)) }
    }

    public func brightness(v: UInt8): Unit {
        unsafe { lv_led_set_brightness(handle, v) }
    }

    public func on(): Unit {
        unsafe { lv_led_on(handle) }
    }

    public func off(): Unit {
        unsafe { lv_led_off(handle) }
    }
}

/* ==================== 富文本（span） ==================== */

/**
 * 富文本片段（lv_span_t）。只能由 SpanGroup.add() 创建，不要自行构造。
 * 修改文本/样式后内部会自动调用 lv_spangroup_refresh() 触发重排。
 */
public class SpanPart {
    private var owner: CPointer<lv_obj_t>
    private var handle: CPointer<lv_span_t>

    internal init(owner: CPointer<lv_obj_t>, handle: CPointer<lv_span_t>) {
        this.owner = owner
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
     * 注意：LVGL 只保存 style 指针，**Style 对象必须比片段活得久**，不要传临时对象。
     */
    public func style(st: Style): SpanPart {
        unsafe { lv_spangroup_set_span_style(owner, handle, st.raw()) }
        unsafe { lv_spangroup_refresh(owner) }
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
        SpanPart(handle, unsafe { lv_spangroup_add_span(handle) })
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
 * 高亮日期数组在 C 侧**只保存指针、不拷贝**，因此本类内部保活，
 * 直到下一次 highlight() 或对象销毁。
 */
public class Calendar <: Widget {
    private var highlighted: CPointer<lv_calendar_date_t> = CPointer<lv_calendar_date_t>()

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
        if (!highlighted.isNull()) {
            unsafe { LibC.free(highlighted) }
        }
        highlighted = buf
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

    /** 点击日期回调（点击某日时 LVGL 抛 LV_EVENT_VALUE_CHANGED） */
    public func onPressed(cb: (UInt32, UInt32, UInt32) -> Unit): Unit {
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

    ~init() {
        if (!highlighted.isNull()) {
            unsafe { LibC.free(highlighted) }
        }
    }
}

/* ==================== 帧动画 ==================== */

/**
 * 帧动画（lv_animimg）。
 *
 * LVGL 只保存帧指针数组的地址、**不拷贝内容**，所以本类同时保活
 * 指针数组与每个 ImageDsc；调用方不要让 ImageBuffer/ImageDsc 提前失效。
 */
public class AnimImage <: Widget {
    private var framesBuf: CPointer<CPointer<Unit>> = CPointer<CPointer<Unit>>()
    private var keptDscs: ArrayList<ImageDsc> = ArrayList<ImageDsc>()

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
        if (!framesBuf.isNull()) {
            unsafe { LibC.free(framesBuf) }
        }
        framesBuf = buf
        let keep = ArrayList<ImageDsc>()
        for (d in list) {
            keep.add(d)
        }
        keptDscs = keep
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

    ~init() {
        if (!framesBuf.isNull()) {
            unsafe { LibC.free(framesBuf) }
        }
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
