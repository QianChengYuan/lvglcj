/**
 * 友好 API 层：文本 / 按钮 / 值 / 选择类控件。
 *
 * 原 widget.cj 按主题拆分而来（同属 package lvglcj，对外 API 不变）。
 */
package lvglcj

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

    /** 点击回调（LV_EVENT_CLICKED，主线程执行），返回可取消的订阅句柄 */
    public func onClick(cb: () -> Unit): EventSubscription {
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

    /** 开关状态变化（闭包参数是变化后的状态） */
    public func onChanged(cb: (Bool) -> Unit): EventSubscription {
        let selfHandle = handle
        onEvent(LV_EVENT_VALUE_CHANGED) {
            _ => cb((unsafe { lv_obj_get_state(selfHandle) } & LV_STATE_CHECKED) != 0)
        }
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

    /** 勾选状态变化（闭包参数是变化后的状态） */
    public func onChanged(cb: (Bool) -> Unit): EventSubscription {
        let selfHandle = handle
        onEvent(LV_EVENT_VALUE_CHANGED) {
            _ => cb((unsafe { lv_obj_get_state(selfHandle) } & LV_STATE_CHECKED) != 0)
        }
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

    /** 数值变化（闭包参数是当前值） */
    public func onValueChanged(cb: (Int32) -> Unit): EventSubscription {
        let selfHandle = handle
        onEvent(LV_EVENT_VALUE_CHANGED) {
            _ => cb(unsafe { lv_slider_get_value(selfHandle) })
        }
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
