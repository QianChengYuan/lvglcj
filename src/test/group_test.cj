/**
 * 焦点组（`lv_group`）：键盘/编码器导航的基础设施。
 *
 * 分两组：
 * - `GroupTests` 只碰组本身（不需要 display）；
 * - `GroupFocusTests` 要真控件（`lv_group_add_obj` 的对象必须已创建），打 `@Tag[requires_display]`。
 *
 * `lv_group_delete` 会给当前焦点控件发 `LV_EVENT_DEFOCUSED`、并从所有 indev 上摘除，
 * 所以「先删组还是先删控件」都不该崩 —— 这里两种情况都覆盖。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

private var focusHits: Int32 = 0
private var lastFocusedNull: Bool = false

@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class GroupTests {
    @BeforeAll
    static func setup() {
        ensureLvglInit()
    }

    /** 建/关：close 幂等，关后 isClosed() 为真 */
    @TestCase
    func testCreateAndClose() {
        let g = Group.of()
        @Expect(g.isClosed(), false)
        g.close()
        @Expect(g.isClosed(), true)
        g.close() // 幂等
    }

    /** 开关类属性：wrap / editing / freeze 只是转发到 LVGL，读回来要一致 */
    @TestCase
    func testFlags() {
        let g = Group.of()
        // lv_group_create 里 wrap 默认是 1（会循环）
        @Expect(g.wrap(), true)
        g.setWrap(false)
        @Expect(g.wrap(), false)
        g.setWrap(true)
        @Expect(g.wrap(), true)
        @Expect(g.editing(), false)
        g.setEditing(true)
        @Expect(g.editing(), true)
        g.freeze(true)
        g.freeze(false)
        g.close()
    }

    /** 关掉的组再调任何方法都应抛 `LvglException`，而不是把空指针塞给 LVGL */
    @TestCase
    func testUseAfterCloseThrows() {
        let g = Group.of()
        g.close()
        var caught = false
        try {
            g.setWrap(true)
        } catch (e: LvglException) {
            caught = true
        }
        @Expect(caught, true)
    }

    /** 空组上 focusNext/focusPrev/focused() 都应是安全空操作 */
    @TestCase
    func testEmptyGroupNavigation() {
        let g = Group.of()
        g.focusNext()
        g.focusPrev()
        @Expect(g.focused().isNone(), true)
        @Expect(g.objAt(0).isNone(), true)
        g.close()
    }
}

@Test // cjlint-ignore !G.ERR.01
class GroupFocusTests {
    @BeforeAll
    static func setup() {
        ensureLvglInit()
        ensureSdlScreen()
    }

    /** 加控件 → focus → focused() 拿回同一个对象；焦点回调被调用 */
    @Tag[requires_display]
    @TestCase
    func testFocusAndCallback() {
        let root = Container(screen())
        let a = Button(root)
        let b = Button(root)
        let g = Group.of()
        focusHits = 0
        lastFocusedNull = true
        g.onFocus {
            w =>
                focusHits += 1
                lastFocusedNull = w.isNone()
        }
        g.add(a)
        g.add(b)
        g.focus(a)
        @Expect(focusHits >= 1, true)
        @Expect(lastFocusedNull, false)
        @Expect(g.focused().isSome(), true)
        g.focusNext()
        @Expect(g.focused().isSome(), true)
        g.clear()
        g.close()
        root.finalize()
    }

    /** 组比控件先删：不应崩；反过来先删控件再删组也不应崩 */
    @Tag[requires_display]
    @TestCase
    func testDeleteOrderIsSafe() {
        let root = Container(screen())
        let a = Button(root)
        let g = Group.of()
        g.add(a)
        g.focus(a)
        g.close() // 组先走
        a.finalize() // 控件后走
        let g2 = Group.of()
        let b = Button(root)
        g2.add(b)
        g2.focus(b)
        b.finalize() // 控件先走（组仍持有已删对象）
        g2.close()
        root.finalize()
        @Expect(true)
    }

    private static func screen(): Screen {
        ensureSdlScreen()
    }
}
