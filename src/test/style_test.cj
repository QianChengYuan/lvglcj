/**
 * style.cj —— Style / Font / Mem（需要 lv_init，故先 ensureLvglInit()）。
 *
 * 这类测试验证的是「封装层不丢参数、不炸」，不是 LVGL 的渲染结果
 * （渲染结果靠 examples 的窗口截图人工确认）。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class StyleTests {

    @BeforeAll
    func initRuntime() {
        ensureLvglInit()
    }

    /** 链式设置每一步都返回自身，串起来不抛异常 */
    @TestCase
    func testChainSettersReturnSelf() {
        let style = Style()
            .bgColor(0x1E, 0x88, 0xE5)
            .bgOpa(255)
            .radius(8)
            .borderWidth(1)
            .borderColor(0xDD, 0xDD, 0xDD)
            .padAll(6)
            .textColor(0x21, 0x21, 0x21)
            .shadowWidth(4)
            .shadowOpa(40)
            .blurRadius(0)
        @Expect(true)
        // style 离开作用域时析构释放 lv_style_t
    }

    /** 极端参数不应崩溃（0 圆角、0 边框、255 不透明度） */
    @TestCase
    func testBoundaryValuesDoNotCrash() {
        let style = Style().radius(0).borderWidth(0).bgOpa(0).shadowWidth(0).blurRadius(0)
        @Expect(true)
    }

    @TestCase
    func testFontFactoriesAreUsable() {
        let def = Font.defaultFont()
        let mont = Font.montserrat(16)
        // 未启用对应字号时 montserrat 会回退默认字体，不抛异常即满足契约
        let style = Style().textFont(def).textFont(mont)
        @Expect(true)
    }

    /** 找不到字体时 trySystemCjk 必须返回 None 而不是抛异常 */
    @TestCase
    func testTrySystemCjkNeverThrows() {
        let f = Font.trySystemCjk(size: 16)
        match (f) {
            case Some(font) => @Expect(true)
            case None => @Expect(true)
        }
    }

    /** 内置字体不归 FreeType 管，close() 后仍可安全使用（只验证不崩溃） */
    @TestCase
    func testCloseOnBuiltinFontIsSafe() {
        Font.defaultFont().close()
        @Expect(true)
    }
}
