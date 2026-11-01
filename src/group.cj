/**
 * 友好 API 层：焦点组（`Group`）。
 *
 * 键盘 / 旋钮 / 遥控器这类「没有指针」的输入设备，靠焦点组在控件间移动焦点：
 *
 * ```cangjie
 * let g = Group.of()
 * g.add(btnA).add(btnB).add(slider)   // 加入顺序 = 焦点顺序
 * pad.setGroup(g)                     // 把键盘设备接到这个组
 * g.onFocus { w => tip.text(w.isSome() ? "已聚焦" : "无焦点") }
 * btnA.on(LV_EVENT_FOCUSED) {_ => ... }
 * g.close()                           // 页面销毁时
 * ```
 *
 * 被聚焦的控件会收到 `LV_EVENT_FOCUSED` / `LV_EVENT_DEFOCUSED`，
 * 按键则在 `LV_EVENT_KEY` 里（事件参数是按键码）。
 *
 * 组不拥有控件：控件的生命周期仍归创建者，`Group.close()` 只解散焦点关系。
 */
package lvglcj

import std.collection.*

/**
 * 焦点回调登记表：组句柄地址 → 仓颉闭包。
 *
 * 每组只有一个焦点回调（LVGL 的 `set_focus_cb` 就是单槽），后注册的覆盖前一个。
 */
private let GROUP_FOCUS_CBS: HashMap<UIntNative, (CPointer<lv_obj_t>) -> Unit> = HashMap<UIntNative, (CPointer<lv_obj_t>) -> Unit>()

/** 清空焦点回调表（`App.shutdown()` 调用） */
internal func clearGroupFocusCbs(): Unit {
    GROUP_FOCUS_CBS.clear()
}

/** LVGL 的焦点变化入口：把当前焦点控件转成借用视图交给仓颉闭包 */
@C
func cjGroupFocusCb(group: CPointer<lv_group_t>): Unit {
    match (GROUP_FOCUS_CBS.get(group.toUIntNative())) {
        case Some(cb) => try {
            cb(unsafe { lv_group_get_focused(group) })
        } catch (e: Exception) {
            App.reportCallbackError(e)
        }
        case None => ()
    }
}

public class Group {
    private var handle: CPointer<lv_group_t>

    private init(handle: CPointer<lv_group_t>) {
        this.handle = handle
    }

    /**
     * 新建焦点组。
     * @return 焦点组
     * @throws[LvglException] 分配失败时
     */
    public static func of(): Group {
        App.assertUIThread("Group.of")
        let h = unsafe { lv_group_create() }
        if (h.isNull()) {
            throw LvglException("lv_group_t 分配失败（通常是 LVGL 内存池耗尽）")
        }
        Group(h)
    }

    /** 默认焦点组（LVGL 的 `indev` 在没显式设组时会用它）；没有则返回 None */
    public static func defaultGroup(): ?Group {
        let h = unsafe { lv_group_get_default() }
        if (h.isNull()) {
            None
        } else {
            Some(Group(h))
        }
    }

    /**
     * 设为默认焦点组（新建的输入设备会自动挂上）。
     * @return this
     */
    public func setDefault(): Group {
        App.assertUIThread("Group.setDefault")
        ensureAlive("Group.setDefault")
        unsafe { lv_group_set_default(handle) }
        this
    }

    /**
     * 把控件加入组（加入顺序即焦点顺序）。
     * @param w 控件
     * @return this
     */
    public func add(w: Widget): Group {
        App.assertUIThread("Group.add")
        ensureAlive("Group.add")
        unsafe { lv_group_add_obj(handle, w.raw()) }
        this
    }

    /**
     * 把控件移出它所在的组（LVGL 按控件查组，不需要指明是哪个组）。
     * @param w 控件
     * @return this
     */
    public func remove(w: Widget): Group {
        App.assertUIThread("Group.remove")
        unsafe { lv_group_remove_obj(w.raw()) }
        this
    }

    /**
     * 清空组内所有控件（不删除控件本身）。
     * @return this
     */
    public func clear(): Group {
        App.assertUIThread("Group.clear")
        ensureAlive("Group.clear")
        unsafe { lv_group_remove_all_objs(handle) }
        this
    }

    /**
     * 聚焦到某个控件（控件须已在组里）。
     * @param w 控件
     * @return this
     */
    public func focus(w: Widget): Group {
        App.assertUIThread("Group.focus")
        ensureAlive("Group.focus")
        unsafe { lv_group_focus_obj(w.raw()) }
        this
    }

    /** 焦点移到下一个（到末尾后行为受 `setWrap` 影响） @return this */
    public func focusNext(): Group {
        App.assertUIThread("Group.focusNext")
        ensureAlive("Group.focusNext")
        unsafe { lv_group_focus_next(handle) }
        this
    }

    /** 焦点移到上一个 @return this */
    public func focusPrev(): Group {
        App.assertUIThread("Group.focusPrev")
        ensureAlive("Group.focusPrev")
        unsafe { lv_group_focus_prev(handle) }
        this
    }

    /**
     * 冻结 / 解冻焦点移动（`true` 时 focusNext/focusPrev 无效）。
     * @param on 是否冻结
     * @return this
     */
    public func freeze(on: Bool): Group {
        App.assertUIThread("Group.freeze")
        ensureAlive("Group.freeze")
        unsafe { lv_group_focus_freeze(handle, on) }
        this
    }

    /**
     * 当前焦点控件；没有焦点时返回 None。
     *
     * 返回的是**借用视图**（`owned: false`）：不要对它调 `delete()`/`finalize()`。
     * @return 焦点控件
     */
    public func focused(): ?Widget {
        let obj = unsafe { lv_group_get_focused(handle) }
        if (obj.isNull()) {
            None
        } else {
            Some(Widget(obj, owned: false))
        }
    }

    /**
     * 按索引取组内控件（0 起）；越界返回 None。
     * @param index 索引
     * @return 控件借用视图
     */
    public func objAt(index: UInt32): ?Widget {
        let obj = unsafe { lv_group_get_obj_by_index(handle, index) }
        if (obj.isNull()) {
            None
        } else {
            Some(Widget(obj, owned: false))
        }
    }

    /**
     * 焦点变化回调：焦点控件变化时回调一次，参数是新焦点（无焦点时 None）。
     *
     * 每组只有一个槽位，后注册的覆盖前一个；回调异常走 `App.onCallbackError`。
     * @param cb 回调
     * @return this
     */
    public func onFocus(cb: (Option<Widget>) -> Unit): Group {
        App.assertUIThread("Group.onFocus")
        ensureAlive("Group.onFocus")
        let key = handle.toUIntNative()
        GROUP_FOCUS_CBS.add(key, {
            obj => if (obj.isNull()) {
                cb(None)
            } else {
                cb(Some(Widget(obj, owned: false)))
            }
        })
        unsafe { lv_group_set_focus_cb(handle, cjGroupFocusCb) }
        this
    }

    /** 是否处于编辑态（文本框这类控件在编辑器场景用） */
    public func editing(): Bool {
        if (handle.isNull()) {
            return false
        }
        unsafe { lv_group_get_editing(handle) }
    }

    /**
     * 设置编辑态。
     * @param on 是否进入编辑态
     * @return this
     */
    public func setEditing(on: Bool): Group {
        App.assertUIThread("Group.setEditing")
        ensureAlive("Group.setEditing")
        unsafe { lv_group_set_editing(handle, on) }
        this
    }

    /** 焦点到末尾后是否环绕回第一个 */
    public func wrap(): Bool {
        if (handle.isNull()) {
            return false
        }
        unsafe { lv_group_get_wrap(handle) }
    }

    /**
     * 设置焦点环绕。
     * @param on 是否环绕
     * @return this
     */
    public func setWrap(on: Bool): Group {
        App.assertUIThread("Group.setWrap")
        ensureAlive("Group.setWrap")
        unsafe { lv_group_set_wrap(handle, on) }
        this
    }

    /** 挂一个调用方上下文（仅存地址，不接管生命周期） @param data 上下文地址 @return this */
    public func setUserData(data: CPointer<Unit>): Group {
        App.assertUIThread("Group.setUserData")
        ensureAlive("Group.setUserData")
        unsafe { lv_group_set_user_data(handle, data) }
        this
    }

    /** 取之前挂的上下文；没挂过返回空指针 */
    public func userData(): CPointer<Unit> {
        if (handle.isNull()) {
            return CPointer<Unit>()
        }
        unsafe { lv_group_get_user_data(handle) }
    }

    /** 是否已释放 */
    public func isClosed(): Bool {
        handle.isNull()
    }

    /**
     * 解散焦点组（幂等）。
     *
     * LVGL 会顺带：给当前焦点控件发 `LV_EVENT_DEFOCUSED`、把组从所有输入设备上摘掉、
     * 若它是默认组则清空默认组指针。**不会**删除组内控件。
     */
    public func close(): Unit {
        if (handle.isNull()) {
            return
        }
        App.assertUIThread("Group.close")
        GROUP_FOCUS_CBS.remove(handle.toUIntNative())
        unsafe { lv_group_delete(handle) }
        handle = CPointer<lv_group_t>()
    }

    /** 底层句柄（供 `Input.setGroup` 使用） */
    internal func raw(): CPointer<lv_group_t> {
        handle
    }

    private func ensureAlive(what: String): Unit {
        if (handle.isNull()) {
            throw LvglException("${what}：焦点组已释放")
        }
    }
}
