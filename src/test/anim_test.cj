/**
 * 动画 / 时间线 / 滚动 —— 需要 display 的用例。
 *
 * 动画靠 LVGL 的定时器推进，测试里没有真实事件循环，所以用
 * 「sleep 一小段 + `App.runOnce()`」手动泵帧，并在等待超时后断言最终值。
 * 时长都取 40~60ms，整组用例控制在 1 秒内。
 *
 *   cjpm test --include-tags=requires_display --exclude-tags=notag
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class AnimTests {
    static var scr: Option<Screen> = None
    static var valueA: Int32 = -1
    static var valueB: Int32 = -1
    static var completedCount: Int32 = 0

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

    /** 泵帧直到 `done()` 为真或超时；返回是否在超时前达成 */
    private static func pumpUntil(done: () -> Bool, rounds!: Int64 = 20): Bool {
        var i: Int64 = 0
        while (i < rounds) {
            if (done()) {
                return true
            }
            sleep(Duration.millisecond * 20)
            App.runOnce()
            i += 1
        }
        done()
    }

    /** 值动画跑到底：末值正确、句柄失效、条目表回到 0 */
    @Tag[requires_display]
    @TestCase
    func testAnimRunsToEndValue() {
        valueA = -1
        Anim.cancelAll()
        let h = Anim.create().exec {v => valueA = v}.from(0).to(100).duration(40).easing(Easing.LINEAR).start()
        @Expect(h.isRunning(), true)

        @Expect(pumpUntil({=> valueA == 100}), true)
        @Expect(valueA, 100)
        // deleted_cb 在完成时触发，句柄与条目都应释放
        @Expect(h.isRunning(), false)
        @Expect(Anim.liveCount(), 0)
    }

    /** cancel 立刻停；token 与闭包不残留（无限循环的动画尤其要能停） */
    @Tag[requires_display]
    @TestCase
    func testAnimCancelReleasesEntry() {
        valueA = 0
        Anim.cancelAll()
        let h = Anim.create().exec {v => valueA = v}.from(0).to(100).duration(5000).loop().start()
        @Expect(Anim.liveCount(), 1)
        h.cancel()
        h.cancel() // 幂等
        @Expect(h.isRunning(), false)
        @Expect(Anim.liveCount(), 0)
    }

    /** 完成回调：只在跑完后触发一次 */
    @Tag[requires_display]
    @TestCase
    func testAnimCompletedCallback() {
        completedCount = 0
        Anim.cancelAll()
        let h = Anim.create().exec {_ => ()}.from(0).to(10).duration(30).onCompleted {=> completedCount += 1}.start()
        @Expect(pumpUntil({=> completedCount > 0}), true)
        @Expect(completedCount, 1)
        @Expect(h.isRunning(), false)
        @Expect(Anim.liveCount(), 0)
    }

    /** 缺 exec 时必须抛异常（否则动画跑起来但没有消费者，等于静默失效） */
    @Tag[requires_display]
    @TestCase
    func testAnimRequiresExecCallback() {
        @ExpectThrows[LvglException](Anim.create().from(0).to(1).start())
        @Expect(Anim.liveCount(), 0)
    }

    /** 时间线：两段依次播放，总时长 = 第二段的起点 + 时长 */
    @Tag[requires_display]
    @TestCase
    func testTimelineRunsSegments() {
        valueA = -1
        valueB = -1
        Anim.cancelAll()
        let tl = Timeline
            .create()
            .add(Anim.create().exec {v => valueA = v}.from(0).to(10).duration(40), at: 0)
            .add(Anim.create().exec {v => valueB = v}.from(0).to(20).duration(40), at: 40)
        @Expect(tl.playTime(), UInt32(80))
        @Expect(Anim.liveCount(), 2)
        tl.start()
        @Expect(pumpUntil({=> valueB == 20}, rounds: 30), true)
        @Expect(valueA, 10)
        @Expect(valueB, 20)
        // 时间线不触发片段的 deleted_cb，所以关闭前条目仍在
        @Expect(Anim.liveCount(), 2)
        tl.close()
        @Expect(tl.isClosed(), true)
        @Expect(Anim.liveCount(), 0)
        tl.close() // 幂等
    }

    /** 滚动：内容高于容器时按绝对位置 / 相对位移都能滚 */
    @Tag[requires_display]
    @TestCase
    func testScrollToAndBy() {
        let box = Container(screen())
        box.size(100, 100)
        box.setStylePadAll(0)
        box.setStyleBorderWidth(0)
        box.scrollable()
        let content = Container(box)
        content.size(100, 400) // 内容比容器高 300
        box.updateLayout()

        @Expect(box.scrollY(), 0)
        box.scrollTo(0, 120)
        @Expect(box.scrollY(), 120)
        // 钉死 scrollBy 的符号：dy 是「内容位移」，与 scrollY 反向
        box.scrollBy(0, 20)
        @Expect(box.scrollY(), 100)
        box.scrollBy(0, -20)
        @Expect(box.scrollY(), 120)
        // 超出可滚范围会被钳制在 content - container
        box.scrollTo(0, 9999)
        @Expect(box.scrollY(), 300)
        box.close()
    }

    /**
     * `LV_OBJ_FLAG_SCROLLABLE` 只约束用户输入与 `scrollToView`，
     * **不拦程序化滚动**（`lv_obj_scroll_by` 不检查该 flag）。钉住这个语义，
     * 免得误以为「关掉 flag 就等于禁用滚动」。
     */
    @Tag[requires_display]
    @TestCase
    func testScrollFlagDoesNotBlockProgrammaticScroll() {
        let box = Container(screen())
        box.size(100, 100)
        box.setStylePadAll(0)
        box.setStyleBorderWidth(0)
        box.scrollable(on: false)
        let content = Container(box)
        content.size(100, 400)
        box.updateLayout()

        @Expect(box.hasFlag(LV_OBJ_FLAG_SCROLLABLE), false)
        box.scrollTo(0, 120)
        @Expect(box.scrollY(), 120)
        box.close()
    }
}
