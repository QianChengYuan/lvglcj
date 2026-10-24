/**
 * util.cj —— 版本号与异常。
 * 这两个能力不依赖 lv_init，可在任何时机断言。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class VersionTests {

    /** 静态库真的是 9.5.0（打包错库时这里会先炸） */
    @TestCase
    func testVersionMatchesBundledLibrary() {
        @Expect(version(), "9.5.0")
    }

    @TestCase
    func testExceptionCarriesMessageAndClassName() {
        let e = LvglException("后端创建失败")
        @Expect(e.message, "后端创建失败")
        @Expect(e.getClassName(), "LvglException")
    }

    /** 可以被 catch 成它的父类型（下游写 catch (e: Exception) 才有效） */
    @TestCase
    func testExceptionIsCatchableAsException() {
        var caught = false
        try {
            throw LvglException("x")
        } catch (e: Exception) {
            caught = true
        }
        @Expect(caught)
    }
}
