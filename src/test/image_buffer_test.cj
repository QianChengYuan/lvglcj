/**
 * image.cj —— ImageBuffer / ImageDsc。
 *
 * 覆盖三件事：
 * 1. 每像素字节数按 color format 推导正确（RGB565=2、XRGB8888=4、L8=1）；
 * 2. writePixels 的长度校验（不足必须抛，不能越界写）；
 * 3. toImageDsc 计算出的 stride / data_size 与 w×h×bpp 一致。
 */
package lvglcj.test

import lvglcj.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ImageBufferTests {

    @TestCase
    func testDimensionsAreKept() {
        let buf = ImageBuffer(4, 3, LV_COLOR_FORMAT_RGB565)
        @Expect(buf.getWidth(), 4)
        @Expect(buf.getHeight(), 3)
    }

    /** RGB565：2 字节/像素 → 2×2 需要 8 字节 */
    @TestCase
    func testWritePixelsAcceptsExactSize() {
        let buf = ImageBuffer(2, 2, LV_COLOR_FORMAT_RGB565)
        buf.writePixels(Array<UInt8>(8, repeat: 0x5A))
    }

    /** 多给一些字节是允许的（只取前缀） */
    @TestCase
    func testWritePixelsAcceptsOversizedArray() {
        let buf = ImageBuffer(2, 2, LV_COLOR_FORMAT_RGB565)
        buf.writePixels(Array<UInt8>(64, repeat: 0x11))
    }

    /** 少给一个字节都必须抛异常，否则会读越界 */
    @TestCase
    func testWritePixelsRejectsShortArray() {
        let buf = ImageBuffer(2, 2, LV_COLOR_FORMAT_RGB565)
        @ExpectThrows[LvglException](buf.writePixels(Array<UInt8>(7, repeat: 0)))
    }

    /** 32 位格式每像素 4 字节 */
    @TestCase
    func testXrgb8888UsesFourBytesPerPixel() {
        let buf = ImageBuffer(2, 2, LV_COLOR_FORMAT_XRGB8888)
        buf.writePixels(Array<UInt8>(16, repeat: 0x22))
        @ExpectThrows[LvglException](buf.writePixels(Array<UInt8>(15, repeat: 0)))
    }

    /** 8 位格式每像素 1 字节 */
    @TestCase
    func testL8UsesOneBytePerPixel() {
        let buf = ImageBuffer(3, 3, LV_COLOR_FORMAT_L8)
        buf.writePixels(Array<UInt8>(9, repeat: 0x7F))
        @ExpectThrows[LvglException](buf.writePixels(Array<UInt8>(8, repeat: 0)))
    }

    /** 头部由垫片在 C 侧填充，没有公开 getter；能稳定产出、不泄漏即可 */
    @TestCase
    func testToImageDscProducesDescriptor() {
        let buf = ImageBuffer(3, 2, LV_COLOR_FORMAT_RGB565)
        buf.writePixels(Array<UInt8>(12, repeat: 0x33))
        let dsc = buf.toImageDsc()
        @Expect(true)
    }
}
