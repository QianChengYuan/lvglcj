/**
 * util.cj —— Color：像素字面量与 LVGL 内部颜色结构。
 *
 * 这里断言的是**位运算结果**，与 LVGL 运行时无关（不需要 lv_init）。
 * 位算错了会导致整屏偏色 / 红蓝反，属于最容易静默出错的地方。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ColorTests {

    @TestCase
    func testRgb565Boundaries() {
        @Expect(Color.rgb565(0, 0, 0), UInt16(0x0000))
        @Expect(Color.rgb565(255, 255, 255), UInt16(0xFFFF))
    }

    /** 纯色三分量：R 在高 5 位、G 在中间 6 位、B 在低 5 位 */
    @TestCase
    func testRgb565Primaries() {
        @Expect(Color.rgb565(255, 0, 0), UInt16(0xF800))
        @Expect(Color.rgb565(0, 255, 0), UInt16(0x07E0))
        @Expect(Color.rgb565(0, 0, 255), UInt16(0x001F))
    }

    /** 低位丢弃：0x1F 与 0x00 在 5 位分量里等价 */
    @TestCase
    func testRgb565TruncatesLowBits() {
        @Expect(Color.rgb565(0x07, 0x00, 0x00), UInt16(0x0000))
        @Expect(Color.rgb565(0x08, 0x00, 0x00), UInt16(0x0800))
        // G 是 6 位：0x03 丢，0x04 保留
        @Expect(Color.rgb565(0, 0x03, 0), UInt16(0x0000))
        @Expect(Color.rgb565(0, 0x04, 0), UInt16(0x0020))
    }

    @TestCase
    func testArgb8888Layout() {
        @Expect(Color.argb8888(0, 0, 0, 0), UInt32(0x00000000))
        @Expect(Color.argb8888(0xFF, 0xFF, 0xFF, 0xFF), UInt32(0xFFFFFFFF))
        // A<<24 | R<<16 | G<<8 | B
        @Expect(Color.argb8888(0x12, 0x34, 0x56, 0x78), UInt32(0x78123456))
        @Expect(Color.argb8888(0xFF, 0x00, 0x00, 0x80), UInt32(0x80FF0000))
    }

    /** Color.of 走的是 LVGL 的 lv_color_t（字段顺序是 BGR 存储，但语义是 RGB） */
    @TestCase
    func testColorOfKeepsComponentValues() {
        let c = Color.of(0x12, 0x34, 0x56)
        @Expect(c.red, UInt8(0x12))
        @Expect(c.green, UInt8(0x34))
        @Expect(c.blue, UInt8(0x56))
    }
}
