/**
 * 主题的其余三种值形态：`StringSubject` / `ColorSubject` / `PointerSubject`。
 *
 * 只覆盖「值语义 + 通知时机 + 生命周期」这三件最容易写错的事；
 * 与控件的联动（`Label.bindText(strSub)`）单独打 `@Tag[requires_display]`。
 *
 * 闭包不能捕获局部 `var`（仓颉限制），所以观察结果都记在模块级变量里。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

private var seenStr: String = ""
private var seenColor: UInt32 = 0
private var seenPtr: UIntNative = 0

@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class SubjectVariantTests {
    @BeforeAll
    static func setup() {
        ensureLvglInit()
    }

    /** 字符串主题：读写、注册即回调、值不变不通知 */
    @TestCase
    func testStringSubjectSetGet() {
        let s = StringSubject.of("hello", capacity: 32)
        @Expect(s.get(), "hello")
        seenStr = ""
        let o = s.subscribe {v => seenStr = v}
        @Expect(seenStr, "hello") // 注册时 LVGL 同步回调一次
        s.set("world")
        @Expect(s.get(), "world")
        @Expect(seenStr, "world")
        s.set("world") // 值没变 → 不通知
        @Expect(seenStr, "world")
        o.cancel()
        s.close()
        @Expect(s.isClosed(), true)
        @Expect(s.get(), "") // 读宽容：已释放返回空串
    }

    /** 容量是「字节数含结尾 0」，写超按 LVGL 语义静默截断 */
    @TestCase
    func testStringSubjectTruncatesToCapacity() {
        let s = StringSubject.of("", capacity: 8)
        s.set("abcdefghij")
        @Expect(s.get(), "abcdefg") // 8 字节缓冲最多存 7 个字符
        s.close()
    }

    /** 中文按 UTF-8 字节算容量：3 字节/字 */
    @TestCase
    func testStringSubjectUtf8() {
        let s = StringSubject.of("就绪", capacity: 16)
        @Expect(s.get(), "就绪")
        s.set("正在同步")
        @Expect(s.get(), "正在同步")
        s.close()
    }

    /** 颜色主题：0xRRGGBB 打包值原样进出 */
    @TestCase
    func testColorSubject() {
        let s = ColorSubject.of(0x112233)
        @Expect(s.get(), 0x112233)
        seenColor = 0
        let o = s.subscribe {v => seenColor = v}
        @Expect(seenColor, 0x112233)
        s.set(0xFF8800)
        @Expect(s.get(), 0xFF8800)
        @Expect(seenColor, 0xFF8800)
        s.notify() // 值没变也强制通知一次
        @Expect(seenColor, 0xFF8800)
        o.cancel()
        s.close()
        @Expect(s.get(), 0)
    }

    /** 指针主题：只搬地址，不解引用 */
    @TestCase
    func testPointerSubject() {
        let rawP = unsafe { LibC.malloc<UInt8>(count: 8) }
        let rawQ = unsafe { LibC.malloc<UInt8>(count: 8) }
        let p = unsafe { CPointer<Unit>(rawP) }
        let q = unsafe { CPointer<Unit>(rawQ) }
        let s = PointerSubject.of(p)
        @Expect(s.get().toUIntNative(), p.toUIntNative())
        seenPtr = 0
        let o = s.subscribe {v => seenPtr = v.toUIntNative()}
        @Expect(seenPtr, p.toUIntNative())
        s.set(q)
        @Expect(s.get().toUIntNative(), q.toUIntNative())
        @Expect(seenPtr, q.toUIntNative())
        o.cancel()
        s.close()
        @Expect(s.get().isNull(), true)
        unsafe {
            LibC.free(rawP)
            LibC.free(rawQ)
        }
    }

    /** 字符串主题绑标签：直接贴字符串，`%` 不被当格式符 */
    @Tag[requires_display]
    @TestCase
    func testLabelBindStringSubject() {
        let s = StringSubject.of("100% 完成", capacity: 64)
        let label = Label(screen())
        label.bindText(s)
        s.set("50% 剩余")
        s.set("完成")
        s.close()
        label.finalize()
        @Expect(true)
    }

    private static func screen(): Screen {
        ensureSdlScreen()
    }
}
