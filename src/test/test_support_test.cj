/**
 * 测试公共辅助（同包其它 *_test.cj 直接调用 ensureLvglInit()）。
 *
 * 为什么不单开一个 test_env.cj：
 * - src/test 下的普通 .cj 会参与**正常构建**，里面只给测试用的函数会报 "unused function"；
 * - 全部用 *_test.cj 时，cjpm 在非测试构建下会整体跳过该目录，既没警告也不会编进库。
 * 所以辅助函数就放在测试文件里，并由下面这个冒烟用例保证它被覆盖。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

private var lvglInited = false

/** 幂等初始化：第一次调用执行 App.setup()（lv_init + 单调时钟），之后直接返回 */
func ensureLvglInit(): Unit {
    if (!lvglInited) {
        App.setup()
        lvglInited = true
    }
}

// 测试类由 @Test/@TestCase 宏展开，展开出来的跑测函数无需（也无法）写 @throws 文档
@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class TestEnvTests {

    /** 重复调用不能崩（lv_init 不宜重入，靠这个 flag 保证只跑一次） */
    @TestCase
    func testEnsureLvglInitIsIdempotent() {
        ensureLvglInit()
        ensureLvglInit()
        ensureLvglInit()
        @Expect(true)
    }
}
