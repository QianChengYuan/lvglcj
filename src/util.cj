/**
 * 友好 API 层：工具（版本 / 颜色 / 异常 / 内存诊断）
 */
package lvglcj

/** lvglcj 异常：后端创建失败、参数校验失败（LV_RESULT_INVALID）等场景抛出 */
public class LvglException <: Exception {
    public init(message: String) {
        super(message)
    }

    public override func getClassName(): String {
        "LvglException"
    }
}

/** LVGL 版本号文本，如 "9.5.0" */
public func version(): String {
    unsafe {
        "${lv_version_major_cjbindwrapper()}.${lv_version_minor_cjbindwrapper()}.${lv_version_patch_cjbindwrapper()}"
    }
}

/**
 * 把仓颉 String 临时转为 CString，调用后立即释放。
 * LVGL 的全部文本 setter 均在 C 侧内部拷贝，因此调用返回后即可安全释放。
 */
internal func withCString<T>(s: String, action: (CString) -> T): T {
    let cs = unsafe { LibC.mallocCString(s) }
    let result = unsafe { action(cs) }
    unsafe { LibC.free(cs) }
    result
}

/**
 * 颜色工具。
 * - of()：构造 LVGL 内部颜色（lv_color_t，9.5 起恒为 3 字节 BGR 值结构）；
 * - rgb565()/argb8888()：产出与目标 LV_COLOR_FORMAT 匹配的**像素字面量**，
 *   供 ImageBuffer.writePixels / Canvas 直写像素使用，避免手写移位出错。
 */
public class Color {
    private init() {}

    /** LVGL 内部颜色（样式 / 画布 API 使用） */
    public static func of(r: UInt8, g: UInt8, b: UInt8): lv_color_t {
        var c = lv_color_t()
        c.blue = b
        c.green = g
        c.red = r
        c
    }

    /** RGB565 像素字面量（R<<11 | G<<5 | B） */
    public static func rgb565(r: UInt8, g: UInt8, b: UInt8): UInt16 {
        let rv = (UInt16(r) & 0xF8) << 8
        let gv = (UInt16(g) & 0xFC) << 3
        let bv = UInt16(b) >> 3
        rv | gv | bv
    }

    /** ARGB8888 像素字面量（A<<24 | R<<16 | G<<8 | B） */
    public static func argb8888(r: UInt8, g: UInt8, b: UInt8, a: UInt8): UInt32 {
        (UInt32(a) << 24) | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }
}

/** 内存统计快照（lv_mem_monitor_t 的友好视图） */
public class MemStat {
    public let totalSize: UIntNative
    public let freeSize: UIntNative
    public let usedSize: UIntNative
    public let maxUsed: UIntNative
    public let usedPct: UInt8
    public let fragPct: UInt8

    public init(totalSize: UIntNative, freeSize: UIntNative, usedSize: UIntNative, maxUsed: UIntNative, usedPct: UInt8,
        fragPct: UInt8) {
        this.totalSize = totalSize
        this.freeSize = freeSize
        this.usedSize = usedSize
        this.maxUsed = maxUsed
        this.usedPct = usedPct
        this.fragPct = fragPct
    }
}

/** 内存诊断（需 lv_conf.h 开启 LV_USE_MEM_MONITOR） */
public class Mem {
    private init() {}

    public static func monitor(): MemStat {
        var mon = lv_mem_monitor_t() // cjlint-ignore !G.VAR.01 inout 出参必须是可变变量
        unsafe { lv_mem_monitor(inout mon) }
        MemStat(mon.totalSize, mon.freeSize, mon.totalSize - mon.freeSize, mon.maxUsed, mon.usedPct, mon.fragPct)
    }
}
