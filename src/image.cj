/**
 * 友好 API 层：像素缓冲 / 图像 / 画布（image.cj）
 */
package lvglcj

/**
 * 像素缓冲：申请一块 LVGL 可直接消费的内存，经 toImageDsc() 喂给 lv_image。
 * 缓冲由系统堆分配（LibC.malloc），析构时释放。
 */
public class ImageBuffer {
    private var data: CPointer<UInt8>
    private var width: Int32
    private var height: Int32
    private var bytesPerPx: UInt32
    private var cf: UInt32

    /**
     * @param w   宽（像素）
     * @param h   高（像素）
     * @param cf  LV_COLOR_FORMAT_*（决定每像素字节数）
     * @throws[LvglException] 像素缓冲 malloc 失败（尺寸过大或内存不足）时
     */
    public init(w: Int32, h: Int32, cf: UInt32) {
        let bpp = unsafe { UInt32(lv_color_format_get_bpp(cf)) }
        bytesPerPx = (bpp + 7) / 8
        width = w
        height = h
        this.cf = cf
        data = unsafe { LibC.malloc<UInt8>(count: Int64(w) * Int64(h) * Int64(bytesPerPx)) }
        if (data.isNull()) {
            throw LvglException("像素缓冲分配失败：${w}x${h} cf=0x${cf}")
        }
    }

    public func getWidth(): Int32 {
        width
    }

    public func getHeight(): Int32 {
        height
    }

    /**
     * 从仓颉字节数组拷入像素（长度须 >= w*h*每像素字节数；RGB565 为小端字面量）
     * @param bytes 像素数据，长度不足会抛异常
     * @throws[LvglException] `bytes` 长度小于 w*h*每像素字节数时
     */
    public func writePixels(bytes: Array<UInt8>): Unit {
        let need = Int64(width) * Int64(height) * Int64(bytesPerPx)
        if (Int64(bytes.size) < need) {
            throw LvglException("writePixels 长度不足：需要 ${need}，实际 ${bytes.size}")
        }
        unsafe {
            var i: Int64 = 0
            while (i < need) {
                data.write(i, bytes[i])
                i += 1
            }
        }
    }

    /**
     * 生成 lv_image_dsc_t（自动填 magic/cf/w/h/stride/data_size），可直接喂给 Image.setSource
     * @throws[LvglException] `lv_image_dsc_t` 分配失败时
     */
    public func toImageDsc(): ImageDsc {
        let dsc = unsafe { lv_image_dsc_new_cjbindwrapper() }
        if (dsc.isNull()) {
            throw LvglException("lv_image_dsc_t 分配失败")
        }
        let stride = UInt32(width) * bytesPerPx
        unsafe {
            lv_image_dsc_fill_cjbindwrapper(dsc, cf, UInt32(width), UInt32(height), stride, data, stride * UInt32(height))
        }
        ImageDsc(dsc)
    }

    ~init() {
        if (!data.isNull()) {
            unsafe { LibC.free(data) }
        }
    }
}

/** 图像描述符：lv_image_dsc_t 的友好包装（头部由垫片在 C 侧填充） */
public class ImageDsc {
    private var handle: CPointer<lv_image_dsc_t>

    internal init(handle: CPointer<lv_image_dsc_t>) {
        this.handle = handle
    }

    ~init() {
        if (!handle.isNull()) {
            unsafe { lv_image_dsc_delete_cjbindwrapper(handle) }
        }
    }

    internal func raw(): CPointer<lv_image_dsc_t> {
        handle
    }
}

/**
 * 画布：自绘仪表 / 波形 / 图表。
 * 底层使用 lv_draw_buf_create 分配对齐缓冲，高层绘制经垫片（layer API 封装）。
 */
public class Canvas <: Widget {
    private var drawBuf: CPointer<lv_draw_buf_t>

    /**
     * @param parent 父控件（通常是 Screen）
     * @param w      宽（像素）
     * @param h      高（像素）
     * @param cf     LV_COLOR_FORMAT_*（默认 RGB565）
     * @throws[LvglException] 画布绘制缓冲 `lv_draw_buf_create` 分配失败时
     */
    public init(parent: Widget, w: Int32, h: Int32, cf!: UInt32 = LV_COLOR_FORMAT_RGB565) {
        super(unsafe { lv_canvas_create(parent.raw()) })
        drawBuf = unsafe { lv_draw_buf_create(UInt32(w), UInt32(h), cf, 0) }
        if (drawBuf.isNull()) {
            throw LvglException("画布缓冲分配失败：${w}x${h}")
        }
        unsafe { lv_canvas_set_draw_buf(handle, drawBuf) }
    }

    /** 填充背景 */
    public func fillBg(r: UInt8, g: UInt8, b: UInt8, opa!: UInt8 = 255): Unit {
        unsafe { lv_canvas_fill_bg(handle, Color.of(r, g, b), opa) }
    }

    /** 画矩形 */
    public func drawRect(x: Int32, y: Int32, w: Int32, h: Int32, r: UInt8, g: UInt8, b: UInt8, radius!: Int32 = 0,
        opa!: UInt8 = 255): Unit {
        unsafe {
            lv_canvas_draw_rect_cjbindwrapper(handle, x, y, w, h, radius, Color.of(r, g, b), opa)
        }
    }

    /** 画文本（font 为空时用 LV_FONT_DEFAULT） */
    public func drawText(x: Int32, y: Int32, w: Int32, text: String, font: Font, r: UInt8, g: UInt8, b: UInt8,
        opa!: UInt8 = 255): Unit {
        withCString(text) {
            cs => unsafe {
                lv_canvas_draw_text_cjbindwrapper(handle, x, y, w, cs, font.raw(), Color.of(r, g, b), opa)
            }
        }
    }

    /** 设置单像素 */
    public func setPx(x: Int32, y: Int32, r: UInt8, g: UInt8, b: UInt8, opa!: UInt8 = 255): Unit {
        unsafe { lv_canvas_set_px(handle, x, y, Color.of(r, g, b), opa) }
    }

    ~init() {
        if (!drawBuf.isNull()) {
            unsafe { lv_draw_buf_destroy(drawBuf) }
        }
    }
}
