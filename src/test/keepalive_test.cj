/**
 * 保活注册表 + Resource 释放 + 泄漏追踪 —— 需要 display 的用例。
 *
 * 这里的结论都建立在一条实测事实之上：仓颉的 GC 由分配压力驱动（UI 帧循环
 * 3 秒内一次都不触发），而 `Widget` 是 open 类、语言不允许带终结器。
 * 所以「保活」必须锚在 lv_obj 上，「释放」必须靠作用域或显式调用。
 *
 *   cjpm test --include-tags=requires_display --exclude-tags=notag
 *
 * 默认走 SDL dummy 驱动（不弹窗口，绘制照常执行）；想看画面加 LVGLCJ_TEST_REAL_WINDOW=1。
 */
package lvglcj.test

import lvglcj.*
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class KeepAliveTests {
    static var scr: Option<Screen> = None

    @BeforeAll
    static func setupDisplay() {
        ensureLvglInit()
        try {
            // 与 WidgetTests 共用同一个 display（各自建会并发初始化 SDL）
            scr = Some(ensureSdlScreen())
        } catch (e: LvglException) {
            let _ = e.message
        }
        // 追踪只统计"开启之后创建"的控件；关闭前创建的不会被补登记。
        App.enableWidgetTracking()
    }

    @AfterAll
    static func stopTracking() {
        App.disableWidgetTracking()
    }

    private static func screen(): Screen {
        match (scr) {
            case Some(s) => s
            case None => throw LvglException("测试屏幕未初始化")
        }
    }

    /** try-with-resources：作用域结束自动 close()，不依赖 GC */
    @Tag[requires_display]
    @TestCase
    func testTryWithResourcesClosesWidget() {
        let before = App.liveWidgetCount()
        try (lb = Label(screen())) {
            lb.text("确定")
            @Expect(lb.isClosed(), false)
        }
        @Expect(App.liveWidgetCount(), before)
    }

    /** close() 幂等；close 之后再 finalize 也不抛 */
    @Tag[requires_display]
    @TestCase
    func testCloseIsIdempotent() {
        let btn = Button(screen())
        @Expect(btn.isClosed(), false)
        btn.close()
        @Expect(btn.isClosed(), true)
        btn.close()
        btn.finalize()
        @Expect(true)
    }

    /** 借用视图（Screen）的 close 静默返回：try-with-resources 收尾不该抛异常 */
    @Tag[requires_display]
    @TestCase
    func testBorrowerViewCloseIsSilent() {
        let s = screen()
        s.close()
        @Expect(s.isClosed(), false)
    }

    /**
     * 同一个 Style 挂到两个控件上：删掉其中一个不得影响另一个的绘制。
     * 保活是按 lv_obj 分别登记的，两份引用互相独立。
     */
    @Tag[requires_display]
    @TestCase
    func testStyleSharedByTwoWidgetsSurvivesOneDelete() {
        let before = App.liveWidgetCount()
        let a = Label(screen())
        let b = Label(screen())
        let st = Style().radius(6).bgColor(10, 20, 30)
        st.applyTo(a)
        st.applyTo(b)
        a.finalize()
        // b 仍在用这个样式：真画一帧，ASan 下若是提前释放这里会报 heap-use-after-free
        App.refreshNow()
        b.text("仍可绘制")
        App.refreshNow()
        b.finalize()
        @Expect(App.liveWidgetCount(), before)
    }

    /** 追踪表随控件删除同步缩小；全部删完后报告应为 0 */
    @Tag[requires_display]
    @TestCase
    func testTrackingCountFollowsLifecycle() {
        let before = App.liveWidgetCount()
        let items = ArrayList<Widget>()
        var i = 0
        while (i < 5) {
            items.add(Button(screen()))
            i += 1
        }
        @Expect(App.liveWidgetCount(), before + 5)
        for (w in items) {
            w.finalize()
        }
        @Expect(App.liveWidgetCount(), before)
        @Expect(App.reportLiveWidgets(), before)
    }

    /** 删除控件时保活缓冲随之释放：连续 setPoints 后删除不应崩，且计数归零 */
    @Tag[requires_display]
    @TestCase
    func testLineBufferReleasedWithWidget() {
        let before = App.liveWidgetCount()
        let line = Line(screen())
        line.setPoints([(0, 0), (10, 10), (20, 0)])
        App.refreshNow()
        line.setPoints([(0, 0), (30, 30)]) // 换缓冲：旧的此时释放
        App.refreshNow()
        line.close()
        @Expect(App.liveWidgetCount(), before)
    }
}
