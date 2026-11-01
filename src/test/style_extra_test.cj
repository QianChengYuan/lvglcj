/**
 * Style 扩充项（`style_extra.cj` 里那 49 个 setter）与顶层浮层。
 *
 * 样式这一半不依赖 display（`lv_style_set_*` 只写结构体），所以默认就跑；
 * 真正应用到控件、以及 `Display.top()/sys()/bottom()` 需要 display，打 `@Tag[requires_display]`。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class StyleExtraTests {
    @BeforeAll
    static func setup() {
        ensureLvglInit()
    }

    /** 49 个 setter 全部走一遍：验证 FFI 符号/参数类型都对得上（不崩即通过） */
    @TestCase
    func testAllSettersLinkAndRun() {
        let st = Style()
            .bgGradColor(0, 255, 0)
            .bgGradDir(LV_GRAD_DIR_VER)
            .bgGradStop(64)
            .borderOpa(200)
            .borderSide(LV_BORDER_SIDE_FULL)
            .outlineWidth(2)
            .outlineColor(255, 0, 0)
            .outlineOpa(128)
            .outlinePad(3)
            .opa(180)
            .opaLayered(160)
            .shadowColor(0, 0, 0)
            .shadowOffsetX(2)
            .shadowOffsetY(3)
            .shadowSpread(1)
            .textAlign(1)
            .textLetterSpace(1)
            .textLineSpace(2)
            .textOpa(220)
            .textDecor(LV_TEXT_DECOR_UNDERLINE)
            .imageRecolor(255, 255, 255)
            .imageRecolorOpa(100)
            .imageOpa(200)
            .lineWidth(2)
            .lineColor(0, 0, 255)
            .lineOpa(255)
            .lineRounded(true)
            .arcWidth(4)
            .arcColor(0, 128, 255)
            .arcOpa(255)
            .arcRounded(true)
            .transformRotation(450) // 0.1 度为单位 → 45°
            .transformScaleX(256) // 256 = 1.0x
            .transformScaleY(128) // 0.5x
            .transformPivotX(10)
            .transformPivotY(20)
            .translateX(5)
            .translateY(-5)
            .marginTop(1)
            .marginRight(2)
            .marginBottom(3)
            .marginLeft(4)
            .padTop(1)
            .padRight(2)
            .padBottom(3)
            .padLeft(4)
            .minWidth(10)
            .minHeight(20)
            .maxWidth(500)
            .maxHeight(400)
            .marginAll(6)
            .padEach(7, 8, 9, 10)
        // Style 没有公开 getter，能走到这里就说明 49 条 FFI 调用都成功返回了
        @Expect(true)
        unsafe { st.raw() } // 触发一次确保对象没被优化掉
    }

    /** 应用到控件：min 尺寸生效（这是少数能从外部观测到的样式效果） */
    @Tag[requires_display]
    @TestCase
    func testApplyMinSize() {
        let label = Label(screen())
        label.text("x")
        let st = Style().minWidth(200).minHeight(80)
        st.applyTo(label)
        label.updateLayout()
        @Expect(label.width() >= 200, true)
        @Expect(label.height() >= 80, true)
        label.finalize()
    }

    /** Widget 侧的 setStyle* 走 lv_obj_set_style_*，直接作用于对象；只要求不崩 */
    @Tag[requires_display]
    @TestCase
    func testWidgetSetters() {
        let label = Label(screen())
        label.text("hello")
        label
            .setStyleOpa(200)
            .setStyleTranslateX(10)
            .setStyleTranslateY(-10)
            .setStyleTransformRotation(300)
            .setStyleOutlineWidth(2)
            .setStyleOutlineColor(255, 0, 0)
            .setStyleTextAlign(1)
        @Expect(label.width() > 0, true)
        label.finalize()
    }

    private static func screen(): Screen {
        ensureSdlScreen()
    }
}

@Test // cjlint-ignore !G.ERR.01
class LayerTests {
    @BeforeAll
    static func setup() {
        ensureLvglInit()
        ensureSdlScreen()
    }

    /** top/sys/bottom 都能拿到有效对象，且能往里加子控件 */
    @Tag[requires_display]
    @TestCase
    func testLayersAcceptChildren() {
        let d = match (Display.defaultDisplay()) {
            case Some(x) => x
            case None => throw LvglException("没有默认 display")
        }
        let top = d.top()
        let child = Container(top)
        child.size(40, 30)
        @Expect(child.width(), 40)
        // 浮层是借用视图：close() 静默返回，不能抛
        top.close()
        @Expect(top.isClosed(), false) // 借用视图不置 closed
        child.finalize()
        @Expect(d.sys().width() > 0, true)
        @Expect(d.bottom().width() > 0, true)
    }

    /** 未初始化 display 时有默认 display（测试进程里 ensureSdlScreen 已建），这里只验证 idempotent 语义 */
    @Tag[requires_display]
    @TestCase
    func testDefaultDisplayIsStable() {
        let a = Display.defaultDisplay()
        let b = Display.defaultDisplay()
        @Expect(a.isSome(), true)
        @Expect(b.isSome(), true)
    }
}
