/**
 * subject（数据绑定）—— 主题语义 + 声明式绑定 + 生命周期。
 *
 * 分两组：
 * - `SubjectTests` 只用主题本身（`lv_subject_*` 不依赖 display），默认就跑；
 * - `SubjectBindTests` 要真控件，打 `@Tag[requires_display]`，跑法见 widget_test.cj 文件头。
 *
 * `Subject.liveCount()` 是**全局**计数，而 cjpm test 会并发跑测试类，
 * 所以断言一律用「操作前记基线、操作后比基线」，不写死 0。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

// 计数用模块级变量：仓颉不允许把「捕获局部 var 的闭包」传给回调（会编译报错）
private var hits: Int32 = 0
private var lastSeen: Int32 = -1

// 测试类由 @Test/@TestCase 宏展开，展开出来的跑测函数无需（也无法）写 @throws 文档
@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class SubjectTests {
    @BeforeAll
    static func setup() {
        ensureLvglInit()
    }

    /** 值读写 + `previous()` + 「值没变不通知」 */
    @TestCase
    func testSetGetAndPrevious() {
        let s = Subject.of(10)
        hits = 0
        let o = s.subscribe {_ => hits += 1}
        @Expect(hits, 1) // 注册时 LVGL 会立即同步回调一次
        s.set(20)
        @Expect(s.get(), 20)
        @Expect(s.previous(), 10)
        @Expect(hits, 2)
        s.set(20) // 值没变 → LVGL 不通知
        @Expect(hits, 2)
        s.notify() // 强制刷新
        @Expect(hits, 3)
        o.cancel()
        s.close()
        @Expect(s.isClosed(), true)
    }

    /** 超出取值范围的 set 被钳住 */
    @TestCase
    func testRangeClamps() {
        let s = Subject.of(0)
        s.setRange(0, 100)
        s.set(150)
        @Expect(s.get(), 100)
        s.set(-5)
        @Expect(s.get(), 0)
        s.close()
    }

    /** `add` 越界不抛溢出异常（仓颉 Int32 加法溢出本来会抛） */
    @TestCase
    func testAddSaturatesInsteadOfThrowing() {
        let s = Subject.of(Int32.Max - 1)
        s.add(10)
        @Expect(s.get(), Int32.Max)
        let t = Subject.of(Int32.Min + 1)
        t.add(-10)
        @Expect(t.get(), Int32.Min)
        s.close()
        t.close()
    }

    /** 取消订阅后不再回调，条目表回到基线 */
    @TestCase
    func testCancelRemovesEntry() {
        let base = Subject.liveCount()
        let s = Subject.of(1)
        lastSeen = -1
        let o = s.subscribe {v => lastSeen = v}
        @Expect(Subject.liveCount(), base + 1)
        @Expect(lastSeen, 1)
        s.set(7)
        @Expect(lastSeen, 7)
        o.cancel()
        o.cancel() // 幂等
        @Expect(o.isActive(), false)
        @Expect(Subject.liveCount(), base)
        s.set(9)
        @Expect(lastSeen, 7) // 已经不再回调
        s.close()
    }

    /** `close()` 一次性清掉所有订阅，且不会因为闭包还挂在主题上而崩 */
    @TestCase
    func testCloseReleasesAllObservers() {
        let base = Subject.liveCount()
        let s = Subject.of(0)
        let _ = s.subscribe {_ => ()}
        let _ = s.subscribe {_ => ()}
        @Expect(Subject.liveCount(), base + 2)
        s.close()
        s.close() // 幂等
        @Expect(Subject.liveCount(), base)
        @Expect(s.get(), 0)
    }
}

// 测试类由 @Test/@TestCase 宏展开，展开出来的跑测函数无需（也无法）写 @throws 文档
@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class SubjectBindTests {
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

    /** 声明式 flag 绑定：值命中时加 flag，不命中时摘掉（零闭包、不入本库条目表） */
    @Tag[requires_display]
    @TestCase
    func testBindFlagIf() {
        let base = Subject.liveCount()
        let s = Subject.of(1)
        let box = Container(screen())
        box.bindFlagIf(s, LV_OBJ_FLAG_HIDDEN, 1)
        @Expect(box.hasFlag(LV_OBJ_FLAG_HIDDEN), true)
        s.set(0)
        @Expect(box.hasFlag(LV_OBJ_FLAG_HIDDEN), false)
        s.set(1)
        @Expect(box.hasFlag(LV_OBJ_FLAG_HIDDEN), true)
        @Expect(Subject.liveCount(), base) // 声明式绑定不占条目表
        box.finalize()
        s.close()
    }

    /**
     * 带闭包的 `bind`：控件删除后 LVGL 摘掉观察者，本库条目也回落到基线。
     *
     * 用 `finalize()` 而不是 `delete()`：后者是 `lv_obj_delete_async`，
     * 要泵一帧才真正销毁（测试里没有事件循环，断言会看到还没删的状态）。
     */
    @Tag[requires_display]
    @TestCase
    func testBindReleasesOnWidgetDelete() {
        let base = Subject.liveCount()
        let s = Subject.of(3)
        lastSeen = -1
        let box = Container(screen())
        let o = s.bind(box) {v => lastSeen = v}
        @Expect(lastSeen, 3) // 注册时立即回调一次
        @Expect(Subject.liveCount(), base + 1)
        s.set(4)
        @Expect(lastSeen, 4)
        box.finalize()
        @Expect(o.isActive(), false)
        @Expect(Subject.liveCount(), base)
        s.set(5) // 控件已没了，不能再回调
        @Expect(lastSeen, 4)
        s.close()
    }

    /** `Label.bindText` 的 fmt 串由控件保活：多设几次值不崩、主题关了也不崩 */
    @Tag[requires_display]
    @TestCase
    func testBindTextSurvivesChanges() {
        let s = Subject.of(0)
        let label = Label(screen())
        label.bindText(s, fmt: "温度 %d 度")
        s.set(26)
        s.set(27)
        s.close() // 主题先于控件释放
        label.finalize()
        @Expect(true)
    }
}
