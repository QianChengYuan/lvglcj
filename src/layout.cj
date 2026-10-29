/**
 * 友好 API 层：布局（flex / grid）。
 *
 * 为什么布局必须走 `Style` 而不是一次性 setter：
 * flex / grid 的描述符在 LVGL 里**本身就是 style 属性**
 * （`lv_style_set_flex_flow`、`lv_style_set_grid_column_dsc_array`），
 * 子对象的位置由父对象在布局更新时统一计算。所以这组 API 都挂在「父对象」上，
 * 且改完之后要么等下一帧，要么显式 `updateLayout()`。
 *
 * ```cangjie
 * root.flex(FlexFlow.ROW, gap: 8)
 *     .flexAlign(FlexAlign.SPACE_BETWEEN, cross: FlexAlign.CENTER)
 *     .setStylePadAll(12)
 * item.flexGrow(1)      // 吃掉剩余空间
 * root.updateLayout()   // 只有测试需要立刻读位置
 * ```
 */
package lvglcj

/* ==================== 枚举 ==================== */

/** flex 主轴方向（对应 `LV_FLEX_FLOW_*`） */
public enum FlexFlow {
    | ROW
    | COLUMN
    | ROW_WRAP
    | ROW_REVERSE
    | ROW_WRAP_REVERSE
    | COLUMN_WRAP
    | COLUMN_REVERSE
    | COLUMN_WRAP_REVERSE

    /** 转成 LVGL 的 `lv_flex_flow_t` 值 */
    public func code(): UInt32 {
        match (this) {
            case ROW => LV_FLEX_FLOW_ROW
            case COLUMN => LV_FLEX_FLOW_COLUMN
            case ROW_WRAP => LV_FLEX_FLOW_ROW_WRAP
            case ROW_REVERSE => LV_FLEX_FLOW_ROW_REVERSE
            case ROW_WRAP_REVERSE => LV_FLEX_FLOW_ROW_WRAP_REVERSE
            case COLUMN_WRAP => LV_FLEX_FLOW_COLUMN_WRAP
            case COLUMN_REVERSE => LV_FLEX_FLOW_COLUMN_REVERSE
            case COLUMN_WRAP_REVERSE => LV_FLEX_FLOW_COLUMN_WRAP_REVERSE
        }
    }
}

/** flex 对齐方式（对应 `LV_FLEX_ALIGN_*`） */
public enum FlexAlign {
    | START
    | END
    | CENTER
    | SPACE_EVENLY
    | SPACE_AROUND
    | SPACE_BETWEEN

    /** 转成 LVGL 的 `lv_flex_align_t` 值 */
    public func code(): UInt32 {
        match (this) {
            case START => LV_FLEX_ALIGN_START
            case END => LV_FLEX_ALIGN_END
            case CENTER => LV_FLEX_ALIGN_CENTER
            case SPACE_EVENLY => LV_FLEX_ALIGN_SPACE_EVENLY
            case SPACE_AROUND => LV_FLEX_ALIGN_SPACE_AROUND
            case SPACE_BETWEEN => LV_FLEX_ALIGN_SPACE_BETWEEN
        }
    }
}

/** 一条 grid 轨道（列或行）的尺寸 */
public enum GridSize {
    /** 由内容撑开（`LV_GRID_CONTENT`） */
    | CONTENT
    /** 按权重分配剩余空间，例如 `Fr(1)` / `Fr(2)` 表示 1:2（`LV_GRID_FR`） */
    | Fr(UInt8)
    /** 固定像素 */
    | Px(Int32)

    /**
     * 转成 LVGL 的 `int32_t` 轨道描述符。
     *
     * `Fr` 走 LVGL 官方的 `lv_grid_fr()` 绑定入口，**不**在仓颉侧重算
     * `LV_COORD_MAX - 100 + x`：那个公式来自宏，随版本变化时不会有人发现。
     */
    internal func code(): Int32 {
        match (this) {
            case CONTENT => LV_GRID_CONTENT
            case Fr(n) => unsafe { lv_grid_fr(n) }
            case Px(v) => v
        }
    }
}

/**
 * grid 单元格内的对齐（`LV_GRID_ALIGN_*`）。
 *
 * 注意：顺序与 `FlexAlign` 不同：这里是 START / CENTER / END，flex 是 START / END / CENTER。
 * 用错不会编译失败，只会静默对齐到另一个位置。
 */
public enum GridAlign {
    | START
    | CENTER
    | END
    | STRETCH
    | SPACE_EVENLY
    | SPACE_AROUND
    | SPACE_BETWEEN

    /** 转成 LVGL 的 `lv_grid_align_t` 值 */
    public func code(): UInt32 {
        match (this) {
            case START => LV_GRID_ALIGN_START
            case CENTER => LV_GRID_ALIGN_CENTER
            case END => LV_GRID_ALIGN_END
            case STRETCH => LV_GRID_ALIGN_STRETCH
            case SPACE_EVENLY => LV_GRID_ALIGN_SPACE_EVENLY
            case SPACE_AROUND => LV_GRID_ALIGN_SPACE_AROUND
            case SPACE_BETWEEN => LV_GRID_ALIGN_SPACE_BETWEEN
        }
    }
}

/* ==================== Widget 上的布局入口 ==================== */

extend Widget {
    /**
     * 让**子对象**按 flex 排列（等价 `lv_obj_set_flex_flow` + 间距）。
     *
     * `gap` 同时设置行间距与列间距（`pad_row` / `pad_column`）——
     * LVGL 的 flex 间距就是这么表达的，主轴方向用哪一个由 flow 决定。
     *
     * ```cangjie
     * row.flex(FlexFlow.ROW, gap: 8)                  // 横排、间隔 8
     * col.flex(FlexFlow.COLUMN, gap: 4)               // 竖排
     * wrap.flex(FlexFlow.ROW_WRAP, gap: 6)            // 换行（子对象需给尺寸）
     * ```
     * @param flow 主轴方向与是否换行
     * @param gap 子对象间距（像素）
     * @return this，便于链式调用
     */
    public func flex(flow: FlexFlow, gap!: Int32 = 0): Widget {
        App.assertUIThread("Widget.flex")
        unsafe { lv_obj_set_flex_flow(raw(), flow.code()) }
        setStyleGap(gap)
        this
    }

    /**
     * 调整 flex 对齐（等价 `lv_obj_set_flex_align`）。
     *
     * 三个参数分别是：主轴上的分布方式、子对象在**轨道内**的交叉轴对齐、
     * **整条轨道**在容器交叉轴上的分布。
     *
     * 注意：想要「横向排列、垂直居中」用 **`trackCross: CENTER`**，而不是 `cross`：
     * flex 的轨道交叉尺寸取的是该行最高子对象的高度（`lv_flex.c` 的
     * `track_cross_size = LV_MAX(get_cross_size(item), ...)`），单行时轨道和子对象一样高，
     * `cross` 居中算出来仍是 0。`cross` 只在「一行里有高矮不一的子对象」时看得出差别。
     *
     * ```cangjie
     * row.flex(FlexFlow.ROW, gap: 8).flexAlign(FlexAlign.SPACE_BETWEEN, trackCross: FlexAlign.CENTER)
     * ```
     * @param mainPlace 主轴分布（SPACE_BETWEEN / CENTER / START …）
     * @param cross 子对象在轨道内的交叉轴对齐
     * @param trackCross 轨道整体在容器交叉轴上的分布（垂直居中用这个）
     * @return this，便于链式调用
     */
    public func flexAlign(mainPlace: FlexAlign, cross!: FlexAlign = FlexAlign.START,
        trackCross!: FlexAlign = FlexAlign.START): Widget {
        App.assertUIThread("Widget.flexAlign")
        unsafe { lv_obj_set_flex_align(raw(), mainPlace.code(), cross.code(), trackCross.code()) }
        this
    }

    /**
     * 让本子对象按比例吃掉父 flex 容器里的剩余空间（等价 `lv_obj_set_flex_grow`）。
     *
     * 只有**父对象是 flex 布局**时生效；所有子对象的 grow 值相同则等分剩余空间。
     * @param grow 权重（0 = 不生长；典型值 1）
     * @return this，便于链式调用
     */
    public func flexGrow(grow: UInt8): Widget {
        App.assertUIThread("Widget.flexGrow")
        unsafe { lv_obj_set_flex_grow(raw(), grow) }
        this
    }

    /**
     * 让**子对象**按 grid 排列（等价 `lv_obj_set_grid_dsc_array`，内部会切到 grid 布局）。
     *
     * 列与行必须**一起**给：LVGL 的 `lv_obj_set_grid_dsc_array` 是一次设置两个数组的，
     * 拆成 `colDsc()` / `rowDsc()` 两步调用时中间那一刻的描述符是不完整的
     * （另半边是 NULL），布局会算出空结果。所以这里刻意只提供一个入口。
     *
     * ```cangjie
     * grid.grid([GridSize.Fr(1), GridSize.Fr(2)], [GridSize.Content, GridSize.Px(40)])
     *     .gridAlign(col: GridAlign.STRETCH, row: GridAlign.STRETCH)
     * label.place(col: 0, row: 0)
     * wide.place(col: 0, row: 1, colSpan: 2)
     * ```
     * @param cols 列描述符（至少一项）
     * @param rows 行描述符（至少一项）
     * @return this，便于链式调用
     * @throws[LvglException] 描述符数组分配失败，或 cols/rows 为空时
     */
    public func grid(cols: Array<GridSize>, rows: Array<GridSize>): Widget {
        App.assertUIThread("Widget.grid")
        if (cols.size == 0 || rows.size == 0) {
            throw LvglException("Widget.grid 的列/行描述符不能为空")
        }
        let colBuf = toGridDsc(cols)
        let rowBuf = try {
            toGridDsc(rows)
        } catch (e: Exception) {
            // 行描述符分配失败时列描述符还没交给控件，必须就地 free，否则泄漏
            unsafe { LibC.free(CPointer<Unit>(colBuf)) }
            throw e
        }
        unsafe { lv_obj_set_grid_dsc_array(raw(), colBuf, rowBuf) }
        // 两个数组必须**同时**存活，所以占两个槽位（slot 0 / slot 1）
        keepBuf(CPointer<Unit>(colBuf), slot: 0)
        keepBuf(CPointer<Unit>(rowBuf), slot: 1)
        this
    }

    /**
     * 轨道整体在容器里的分布（等价 `lv_obj_set_grid_align`）。
     * @param col 列方向的分布方式
     * @param row 行方向的分布方式
     * @return this，便于链式调用
     */
    public func gridAlign(col!: GridAlign, row!: GridAlign = GridAlign.START): Widget {
        App.assertUIThread("Widget.gridAlign")
        unsafe { lv_obj_set_grid_align(raw(), col.code(), row.code()) }
        this
    }

    /**
     * 把本控件放进父 grid 的某个单元格（等价 `lv_obj_set_grid_cell`）。
     *
     * 只有**父对象是 grid 布局**时生效；`colSpan` / `rowSpan` 必须 >= 1。
     * @param col 起始列（0 起）
     * @param row 起始行（0 起）
     * @param colSpan 跨列数
     * @param rowSpan 跨行数
     * @param colAlign 单元格内的水平对齐（STRETCH 表示填满单元格）
     * @param rowAlign 单元格内的垂直对齐
     * @return this，便于链式调用
     */
    public func place(col!: Int32, row!: Int32, colSpan!: Int32 = 1i32, rowSpan!: Int32 = 1i32,
        colAlign!: GridAlign = GridAlign.STRETCH, rowAlign!: GridAlign = GridAlign.STRETCH): Widget {
        App.assertUIThread("Widget.place")
        let cs = if (colSpan < 1i32) {
            1i32
        } else {
            colSpan
        }
        let rs = if (rowSpan < 1i32) {
            1i32
        } else {
            rowSpan
        }
        unsafe {
            lv_obj_set_grid_cell(raw(), colAlign.code(), col, cs, rowAlign.code(), row, rs)
        }
        this
    }
}

/**
 * 把轨道尺寸数组转成 LVGL 要的 `int32_t[]`（末尾补 `LV_GRID_TEMPLATE_LAST`）。
 *
 * 这块内存的所有权交给 `Widget.keepBuf()`，由控件删除时统一 free。
 */
private func toGridDsc(sizes: Array<GridSize>): CPointer<Int32> {
    let buf = unsafe { LibC.malloc<Int32>(count: Int64(sizes.size) + 1) }
    if (buf.isNull()) {
        throw LvglException("grid 轨道描述符数组分配失败")
    }
    unsafe {
        var i: Int64 = 0
        for (s in sizes) {
            buf.write(i, s.code())
            i += 1
        }
        buf.write(i, LV_GRID_TEMPLATE_LAST)
    }
    buf
}
