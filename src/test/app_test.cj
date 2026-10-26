/**
 * app.cj —— UI 线程调度、回调异常兜底与定时器生命周期。
 *
 * 这些用例只需要 lv_init（App.setup），不依赖 display，因此在无头 CI 中也会执行。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.testmacro.*

// 测试类由 @Test/@TestCase 宏展开，展开出来的跑测函数无需（也无法）写 @throws 文档
@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class AppDispatcherTests {
    static var posted: Int32 = 0
    static var ticks: Int32 = 0
    static var caught: String = ""

    @TestCase
    func testPostRunsOnPump() {
        ensureLvglInit()
        posted = 0
        App.post {posted = 1}
        App.runOnce()
        @Expect(posted, 1)
    }

    @TestCase
    func testPostFromWorkerThread() {
        ensureLvglInit()
        posted = 0
        let worker = spawn {
            App.post {posted = 2}
        }
        worker.get()
        App.runOnce()
        @Expect(posted, 2)
    }

    @TestCase
    func testPostCallbackErrorIsReported() {
        ensureLvglInit()
        caught = ""
        App.onCallbackError {e => caught = e.message}
        App.post {
            throw LvglException("post boom")
        }
        App.runOnce()
        App.clearCallbackErrorHandler()
        @Expect(caught, "post boom")
    }

    @TestCase
    func testTimerOnceRunsAndBecomesInactive() {
        ensureLvglInit()
        ticks = 0
        let handle = Timer.once(60_000) {ticks += 1}
        handle.ready()
        App.runOnce()
        @Expect(ticks, 1)
        @Expect(handle.isActive(), false)
    }

    @TestCase
    func testTimerCancelPreventsCallback() {
        ensureLvglInit()
        ticks = 0
        let handle = Timer.once(60_000) {ticks += 1}
        handle.cancel()
        handle.cancel()
        handle.ready()
        App.runOnce()
        @Expect(ticks, 0)
        @Expect(handle.isActive(), false)
    }

    @TestCase
    func testTimerCallbackErrorIsReported() {
        ensureLvglInit()
        caught = ""
        App.onCallbackError {e => caught = e.message}
        let handle = Timer.once(60_000) {
            throw LvglException("timer boom")
        }
        handle.ready()
        App.runOnce()
        App.clearCallbackErrorHandler()
        @Expect(caught, "timer boom")
        @Expect(handle.isActive(), false)
    }
}
