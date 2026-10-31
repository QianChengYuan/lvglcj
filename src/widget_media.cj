/**
 * 友好 API 层：图像、图表 / 曲线 / 刻度 / LED。
 *
 * 原 widget.cj 按主题拆分而来（同属 package lvglcj，对外 API 不变）。
 */
package lvglcj

import std.collection.*
import std.fs.*

/* ==================== 图像 ==================== */

/**
 * 图像（lv_image）。
 *
 * `lv_image_set_src` 只保存指针：dsc 被回收后 LVGL 读到的是已释放内存。
 * 因此 setSource() 会把 ImageDsc 登记进保活表（按 lv_obj 地址），
 * 一直保到下次换源或**控件被删除**；而 ImageDsc 又持有产出它的 ImageBuffer 引用，
 * 所以 `img.setSource(buf.toImageDsc())` 这种「传临时对象」的写法也是安全的。
 */
public class Image <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_image_create(parent.raw()) })
    }

    /** 设置图像源（ImageBuffer.toImageDsc() 的产物）；dsc 由控件保活到换源/删除 */
    public func setSource(dsc: ImageDsc): Unit {
        unsafe { lv_image_set_src(handle, CPointer<Unit>(dsc.raw())) }
        let keep = ArrayList<Object>()
        keep.add(dsc)
        keepOnly(keep)
    }

    /**
     * 从图片文件创建图像控件。
     * 前置：静态库编入了 `LV_USE_LODEPNG` + `LV_USE_FS_STDIO`（本仓库四份产物都已打开）；
     * JPG/GIF/WebP 还需在 `lv_conf.h` 另开 `LV_USE_TJPGD` / `LV_USE_GIF` / `LV_USE_LIBWEBP` 并重编。
     */
    public static func fromFile(parent: Widget, path: String): Image {
        // 先校验再创建控件：否则 setFile 抛异常时会在父对象上留下一个空白 Image
        if (!exists(path)) {
            throw LvglException("图片文件不存在：${path}")
        }
        let img = Image(parent)
        try {
            img.setFile(path)
        } catch (e: Exception) {
            img.finalize()
            throw e
        }
        img
    }

    /**
     * 换成图片文件（路径不存在直接抛异常）。
     *
     * 注意：`lv_image_set_src` 返回 void，解码失败时 LVGL 只打 WARN 日志、控件显示空白，
     * 仓颉侧无法区分"文件在但格式不支持"——这种情况请检查 lv_conf.h 的解码器开关。
     * @param path 图片文件路径（系统路径，垫片负责补驱动器字母）
     * @throws[LvglException] `path` 不存在，或当前构建未启用 LV_USE_FS_STDIO 时
     */
    public func setFile(path: String): Unit {
        if (!exists(path)) {
            throw LvglException("图片文件不存在：${path}")
        }
        let r = withCString(path) {cs => unsafe { lvglcj_image_set_file_cjbindwrapper(handle, cs) }}
        if (r != LV_RESULT_OK) {
            throw LvglException("图片加载失败：${path}（确认 lv_conf.h 已开 LV_USE_FS_STDIO 并重编了 liblvgl.a）")
        }
        // 源已换成文件路径，之前 setSource() 传入的 dsc 不再被 LVGL 引用。
        keepOnly(ArrayList<Object>())
    }

    /**
     * 旋转到指定角度（度，逆时针；内部按 LVGL 的 0.1° 单位换算）。
     * 例：`img.rotateDeg(90.0)` 是转四分之一圈。
     */
    public func rotateDeg(deg: Float64): Unit {
        unsafe { lv_image_set_rotation(handle, Int32(deg * 10.0)) }
    }

    /**
     * 旋转（LVGL 原生单位 **0.1°**，即 900 = 90°）。
     * 不确定单位时优先用 rotateDeg()。
     */
    public func rotateTenthDeg(tenthDeg: Int32): Unit {
        unsafe { lv_image_set_rotation(handle, tenthDeg) }
    }

    /** 缩放（1.0 为原始大小） */
    public func scale(factor: Float64): Unit {
        unsafe { lv_image_set_scale(handle, UInt32(factor * 256.0)) }
    }
}

/* ==================== 图表 / 曲线 / LED ==================== */

/** 图表数据系列（lv_chart_series_t 的友好包装） */
public class ChartSeries {
    private var handle: CPointer<Unit>

    internal init(handle: CPointer<Unit>) {
        this.handle = handle
    }

    internal func raw(): CPointer<Unit> {
        handle
    }
}

public class Chart <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_chart_create(parent.raw()) })
    }

    public func pointCount(n: UInt32): Unit {
        unsafe { lv_chart_set_point_count(handle, n) }
    }

    /** axis: 0 = 主 Y 轴，1 = 次 Y 轴 */
    public func range(axis: UInt32, min: Int32, max: Int32): Unit {
        unsafe { lv_chart_set_axis_range(handle, axis, min, max) }
    }

    public func addSeries(r: UInt8, g: UInt8, b: UInt8): ChartSeries {
        ChartSeries(unsafe { lv_chart_add_series(handle, Color.of(r, g, b), 0) })
    }

    public func setNextValue(series: ChartSeries, v: Int32): Unit {
        unsafe { lv_chart_set_next_value(handle, series.raw(), v) }
    }
}

/**
 * 折线（lv_line）。
 *
 * `lv_line_set_points` **只保存指针、不拷贝顶点数组**，而绘制发生在后续的
 * lv_timer_handler 里 —— 数组必须活到下一次 setPoints() 或**控件被删除**。
 * 缓冲登记在保活表里（按 lv_obj 地址），由 LV_EVENT_DELETE 统一释放，
 * 不依赖仓颉包装对象什么时候被 GC。
 */
public class Line <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_line_create(parent.raw()) })
    }

    /**
     * 设置折线顶点（至少 2 个点）。新数组生效后才释放旧数组。
     * @param points 顶点坐标数组
     * @throws[LvglException] 顶点少于 2 个，或顶点缓冲分配失败时
     */
    public func setPoints(points: Array<(Int32, Int32)>): Unit {
        App.assertUIThread("Line.setPoints")
        if (points.size < 2) {
            throw LvglException("Line.setPoints 至少需要 2 个点")
        }
        let buf = unsafe { LibC.malloc<lv_point_t>(count: Int64(points.size)) }
        if (buf.isNull()) {
            throw LvglException("Line.setPoints 顶点数组分配失败")
        }
        unsafe {
            var i: Int64 = 0
            for (p in points) {
                var pt = lv_point_t()
                pt.x = p[0]
                pt.y = p[1]
                buf.write(i, pt)
                i += 1
            }
            lv_line_set_points(handle, buf, UInt32(points.size))
        }
        // 登记后，旧缓冲由保活表释放；控件删除时连新缓冲一起释放。
        keepBuf(CPointer<Unit>(buf))
    }
}

public class Scale <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_scale_create(parent.raw()) })
    }

    public func range(min: Int32, max: Int32): Unit {
        unsafe { lv_scale_set_range(handle, min, max) }
    }
}

public class Led <: Widget {
    public init(parent: Widget) {
        super(unsafe { lv_led_create(parent.raw()) })
    }

    public func color(r: UInt8, g: UInt8, b: UInt8): Unit {
        unsafe { lv_led_set_color(handle, Color.of(r, g, b)) }
    }

    public func brightness(v: UInt8): Unit {
        unsafe { lv_led_set_brightness(handle, v) }
    }

    public func on(): Unit {
        unsafe { lv_led_on(handle) }
    }

    public func off(): Unit {
        unsafe { lv_led_off(handle) }
    }
}
