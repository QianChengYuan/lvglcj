/**
 * 常量回归测试。
 *
 * 这些值是**从 LVGL 9.5 头文件/预处理器实测**得到的（用 C 程序打印真实值），
 * 不是凭记忆抄的。历史上写错过 CHECKABLE / SCROLL_CHAIN / SCROLL_ELASTIC /
 * LABEL_LONG_MODE_DOTS / IMAGE_ALIGN_CENTER，症状是「编译通过、行为诡异」，
 * 因此这里逐个钉死，防止回退。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

// 测试类由 @Test/@TestCase 宏展开，展开出来的跑测函数无需（也无法）写 @throws 文档
@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class ConstantTests {

    /** LV_OBJ_FLAG_*：9.5 里 CLICK_FOCUSABLE 占 1<<2，CHECKABLE 是 1<<3 */
    @TestCase
    func testObjectFlagBits() {
        @Expect(LV_OBJ_FLAG_HIDDEN, UInt32(0x1))
        @Expect(LV_OBJ_FLAG_CLICKABLE, UInt32(0x2))
        @Expect(LV_OBJ_FLAG_CLICK_FOCUSABLE, UInt32(0x4))
        @Expect(LV_OBJ_FLAG_CHECKABLE, UInt32(0x8))
        @Expect(LV_OBJ_FLAG_SCROLLABLE, UInt32(0x10))
        @Expect(LV_OBJ_FLAG_SCROLL_ELASTIC, UInt32(0x20))
        // SCROLL_CHAIN = CHAIN_HOR(1<<8) | CHAIN_VER(1<<9)
        @Expect(LV_OBJ_FLAG_SCROLL_CHAIN, UInt32(0x300))
    }

    @TestCase
    func testStateBits() {
        @Expect(LV_STATE_DEFAULT, UInt32(0x0))
        @Expect(LV_STATE_CHECKED, UInt32(0x4))
        @Expect(LV_STATE_FOCUSED, UInt32(0x8))
        @Expect(LV_STATE_PRESSED, UInt32(0x80))
        @Expect(LV_STATE_DISABLED, UInt32(0x200))
        @Expect(LV_STATE_ANY, UInt32(0xFFFF))
    }

    @TestCase
    func testPartValues() {
        @Expect(LV_PART_MAIN, UInt32(0x0))
        @Expect(LV_PART_SCROLLBAR, UInt32(0x010000))
        @Expect(LV_PART_INDICATOR, UInt32(0x020000))
        @Expect(LV_PART_KNOB, UInt32(0x030000))
        @Expect(LV_PART_CURSOR, UInt32(0x060000))
        @Expect(LV_PART_ANY, UInt32(0x0F0000))
    }

    @TestCase
    func testAlignValues() {
        @Expect(LV_ALIGN_TOP_LEFT, UInt32(1))
        @Expect(LV_ALIGN_CENTER, UInt32(9))
        @Expect(LV_ALIGN_RIGHT_MID, UInt32(8))
        @Expect(LV_ALIGN_BOTTOM_RIGHT, UInt32(6))
    }

    /** 事件码是连续枚举，VALUE_CHANGED/DELETE 在中间被其它事件挤开 */
    @TestCase
    func testEventCodes() {
        @Expect(LV_EVENT_ALL, UInt32(0))
        @Expect(LV_EVENT_PRESSED, UInt32(1))
        @Expect(LV_EVENT_CLICKED, UInt32(10))
        @Expect(LV_EVENT_RELEASED, UInt32(11))
        @Expect(LV_EVENT_VALUE_CHANGED, UInt32(35))
        @Expect(LV_EVENT_DELETE, UInt32(42))
    }

    @TestCase
    func testColorFormatValues() {
        @Expect(LV_COLOR_FORMAT_RGB565, UInt32(0x12))
        @Expect(LV_COLOR_FORMAT_RGB565_SWAPPED, UInt32(0x1B))
        @Expect(LV_COLOR_FORMAT_RGB888, UInt32(0x0F))
        @Expect(LV_COLOR_FORMAT_ARGB8888, UInt32(0x10))
        @Expect(LV_COLOR_FORMAT_XRGB8888, UInt32(0x11))
        @Expect(LV_COLOR_FORMAT_L8, UInt32(0x06))
    }

    /** LVGL 的枚举是 INVALID 在前，OK=1 —— 写反会让「成功」被判成失败 */
    @TestCase
    func testResultCodes() {
        @Expect(LV_RESULT_OK, Int32(1))
        @Expect(LV_RESULT_INVALID, Int32(0))
    }

    @TestCase
    func testMiscEnums() {
        @Expect(LV_LABEL_LONG_MODE_WRAP, UInt32(0))
        @Expect(LV_LABEL_LONG_MODE_DOTS, UInt32(1))
        @Expect(LV_IMAGE_ALIGN_CENTER, UInt32(9))
        @Expect(LV_ANIM_OFF, UInt32(0))
        @Expect(LV_ANIM_ON, UInt32(1))
        @Expect(LV_ROLLER_MODE_NORMAL, UInt32(0))
        @Expect(LV_ROLLER_MODE_INFINITE, UInt32(1))
    }
}
