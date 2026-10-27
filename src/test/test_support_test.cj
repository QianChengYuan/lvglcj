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
import std.env.*
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*

private var lvglInited = false
private var cachedScreen: Option<Screen> = None // cjlint-ignore !G.VAR.02 测试进程内共享的只读缓存
private let SCREEN_LOCK = Mutex()

/** 幂等初始化：第一次调用执行 App.setup()（lv_init + 单调时钟），之后直接返回 */
func ensureLvglInit(): Unit {
    if (!lvglInited) {
        App.setup()
        lvglInited = true
    }
}

/**
 * 懒建一个 320x240 的 SDL 屏幕，**整个测试进程共用**。
 *
 * 两件事都必须在真正建 display 之前做掉：
 *
 * ① **默认切到 dummy 视频驱动**。测试进程里没有 SDL 事件循环，真窗口会一直
 *    "无响应"（标题栏变灰），人工点掉后 display 就失效了 —— 后续用例连带失败，
 *    表现为某个类的 `@BeforeAll` 卡几十秒后报 `Before all step failed`。
 *    dummy 驱动直接在内存里渲染，绘制/截图路径照样执行。
 *    确实想看画面时：`LVGLCJ_TEST_REAL_WINDOW=1 cjpm test ...`。
 * ② 单例复用。多个测试类各自 `Display.sdl()` 会重复初始化 SDL，没必要。
 */
func ensureSdlScreen(): Screen {
    synchronized(SCREEN_LOCK) {
        match (cachedScreen) {
            case Some(s) => s
            case None =>
                if (getVariable("SDL_VIDEODRIVER").isNone() && getVariable("LVGLCJ_TEST_REAL_WINDOW").isNone()) {
                    setVariable("SDL_VIDEODRIVER", "dummy")
                }
                let s = Display.sdl(320, 240).screen()
                cachedScreen = Some(s)
                s
        }
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
