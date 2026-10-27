/**
 * 布局引擎（flex / grid）—— 需要 display 的用例。
 *
 * 全部是**真断言**：在 SDL dummy 驱动下建 display，`updateLayout()` 之后
 * 读子对象的 `x()/y()/width()/height()`，断言布局确实按预期算过。
 * 没有这类断言时，「flex 生效了吗」只能靠人眼看截图。
 *
 *   cjpm test --include-tags=requires_display --exclude-tags=notag
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class LayoutTests {
    static var scr: Option<Screen> = None

    @BeforeAll
    static func setupDisplay() {
        ensureLvglInit()
        try {
            scr = Some(ensureSdlScreen())
        } catch (e: LvglException) {
            let _ = e.message
        }
    }

    private static func screen(): Screen {
        match (scr) {
            case Some(s) => s
            case None => throw LvglException("测试屏幕未初始化")
        }
    }

    /**
     * 一个 padding / 边框 / 布局间距都归零的容器：让断言不受主题默认样式干扰。
     *
     * `setStyleGap(0)` 不能省：主题给对象留了 pad_row / pad_column（实测 8），
     * 它们**不受 padAll 影响**，留着会让 grid 的轨道算窄 8px。
     */
    private static func bareBox(parent: Widget, w: Int32, h: Int32): Container {
        let box = Container(parent)
        box.size(w, h)
        box.setStylePadAll(0)
        box.setStyleBorderWidth(0)
        box.setStyleGap(0)
        box
    }

    /** flex 横排：三个定宽子对象按 flow 依次排开，间距等于 gap */
    @Tag[requires_display]
    @TestCase
    func testFlexRowPlacesChildrenInOrder() {
        let root = bareBox(screen(), 240, 60)
        root.flex(FlexFlow.ROW, gap: 10)
        let a = bareBox(root, 60, 30)
        let b = bareBox(root, 60, 30)
        let c = bareBox(root, 60, 30)
        root.updateLayout()

        @Expect(a.x(), 0)
        @Expect(b.x(), 70) // 60 + gap 10
        @Expect(c.x(), 140)
        @Expect(b.y(), a.y()) // 单行，交叉轴位置一致
        root.close()
    }

    /** flex 竖排：y 递增，x 不变 */
    @Tag[requires_display]
    @TestCase
    func testFlexColumnStacksVertically() {
        let root = bareBox(screen(), 120, 200)
        root.flex(FlexFlow.COLUMN, gap: 5)
        let a = bareBox(root, 40, 30)
        let b = bareBox(root, 40, 30)
        root.updateLayout()

        @Expect(a.x(), 0)
        @Expect(b.x(), 0)
        @Expect(b.y(), 35) // 30 + gap 5
        root.close()
    }

    /** flexGrow：定宽兄弟占住固定部分，grow 的那个吃掉剩余宽度 */
    @Tag[requires_display]
    @TestCase
    func testFlexGrowFillsRemainingSpace() {
        let root = bareBox(screen(), 200, 40)
        root.flex(FlexFlow.ROW, gap: 0)
        let fixed = bareBox(root, 50, 40)
        let grow = bareBox(root, 10, 40)
        grow.flexGrow(1)
        root.updateLayout()

        @Expect(fixed.width(), 50)
        @Expect(grow.width(), 150) // 200 - 50
        @Expect(fixed.width() + grow.width(), root.contentWidth())
        root.close()
    }

    /**
     * 垂直居中必须用 trackCross：轨道的交叉尺寸取的是行内最高子对象，
     * 单行时 cross 居中算出来仍是 0（实测确认，见 lv_flex.c 的 track_cross_size）。
     */
    @Tag[requires_display]
    @TestCase
    func testFlexTrackCrossCentersVertically() {
        let root = bareBox(screen(), 200, 100)
        root.flex(FlexFlow.ROW).flexAlign(FlexAlign.START, trackCross: FlexAlign.CENTER)
        let item = bareBox(root, 40, 20)
        root.updateLayout()

        @Expect(item.x(), 0)
        @Expect(item.y(), 40) // (100 - 20) / 2
        root.close()
    }

    /** 主轴 SPACE_BETWEEN：首尾贴边，中间均分剩余空间 */
    @Tag[requires_display]
    @TestCase
    func testFlexMainPlaceSpaceBetween() {
        let root = bareBox(screen(), 200, 40)
        root.flex(FlexFlow.ROW, gap: 0).flexAlign(FlexAlign.SPACE_BETWEEN)
        let a = bareBox(root, 40, 40)
        let b = bareBox(root, 40, 40)
        let c = bareBox(root, 40, 40)
        root.updateLayout()

        @Expect(a.x(), 0)
        @Expect(c.x(), 160) // 200 - 40
        @Expect(b.x(), 80) // 中间均分
        root.close()
    }

    /** 换行：三个 90 宽的方块放进 200 宽，第三个必须落到第二行 */
    @Tag[requires_display]
    @TestCase
    func testFlexRowWrapBreaksIntoSecondTrack() {
        let root = bareBox(screen(), 200, 100)
        root.flex(FlexFlow.ROW_WRAP, gap: 5)
        let a = bareBox(root, 90, 20)
        let b = bareBox(root, 90, 20)
        let c = bareBox(root, 90, 20)
        root.updateLayout()

        @Expect(a.y(), b.y())
        @Expect(c.y() > a.y(), true) // 第二行
        @Expect(c.x(), 0) // 回到行首
        root.close()
    }

    /** grid 列宽按 Fr 权重分配：1:2 分 300 宽 → 100 / 200 */
    @Tag[requires_display]
    @TestCase
    func testGridColumnFrRatio() {
        let root = bareBox(screen(), 300, 100)
        root.grid([GridSize.Fr(1), GridSize.Fr(2)], [GridSize.Fr(1)])
        let a = bareBox(root, 10, 10)
        a.place(col: 0, row: 0)
        let b = bareBox(root, 10, 10)
        b.place(col: 1, row: 0)
        root.updateLayout()

        @Expect(a.x(), 0)
        @Expect(a.width(), 100)
        @Expect(b.x(), 100)
        @Expect(b.width(), 200)
        root.close()
    }

    /** grid 固定像素行：行高按 Px 描述符走 */
    @Tag[requires_display]
    @TestCase
    func testGridRowPixels() {
        let root = bareBox(screen(), 100, 200)
        root.grid([GridSize.Fr(1)], [GridSize.Px(40), GridSize.Px(60)])
        let a = bareBox(root, 10, 10)
        a.place(col: 0, row: 0)
        let b = bareBox(root, 10, 10)
        b.place(col: 0, row: 1)
        root.updateLayout()

        @Expect(a.y(), 0)
        @Expect(a.height(), 40)
        @Expect(b.y(), 40)
        @Expect(b.height(), 60)
        root.close()
    }

    /** colSpan 跨列：占满两列 */
    @Tag[requires_display]
    @TestCase
    func testGridSpanAcrossColumns() {
        let root = bareBox(screen(), 300, 100)
        root.grid([GridSize.Fr(1), GridSize.Fr(1)], [GridSize.Px(50)])
        let wide = bareBox(root, 10, 10)
        wide.place(col: 0, row: 0, colSpan: 2)
        root.updateLayout()

        @Expect(wide.x(), 0)
        @Expect(wide.width(), 300)
        root.close()
    }

    /**
     * grid 需要两块描述符数组**同时**存活（列 + 行）：
     * 这正是 KeepSlot 从「单个缓冲」改成「按槽位」的原因 ——
     * 换一次 grid 时两块旧缓冲都要被释放，槽位数不变。
     */
    @Tag[requires_display]
    @TestCase
    func testGridKeepsColumnAndRowBuffers() {
        let root = bareBox(screen(), 300, 100)
        root.grid([GridSize.Fr(1), GridSize.Fr(1)], [GridSize.Px(50), GridSize.Px(20)])
        @Expect(root.keptBufs(), 2)

        root.grid([GridSize.Fr(1)], [GridSize.Px(30)]) // 换一套：两块旧缓冲都释放
        @Expect(root.keptBufs(), 2)
        let cell = bareBox(root, 10, 10)
        cell.place(col: 0, row: 0)
        root.updateLayout()
        @Expect(cell.height(), 30)
        root.close()
    }
}
