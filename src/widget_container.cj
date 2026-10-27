/**
 * 友好 API 层：列表 / 表格 / 标签页 / 菜单 / 窗口等容器类控件。
 *
 * 原 widget.cj 按主题拆分而来（同属 package lvglcj，对外 API 不变）。
 */
package lvglcj

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
