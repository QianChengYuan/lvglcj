/**
 * 友好 API 层：样式（Style）与主题（Theme）。
 * 样式对象持有一块 C 堆上的 lv_style_t，析构时归还。
 */
package lvglcj

import std.fs.*

public class Style {
    private var handle: CPointer<lv_style_t>

    public init() {
        handle = unsafe { lv_style_new_cjbindwrapper() }
        if (handle.isNull()) {
            throw LvglException("lv_style_t 分配失败")
        }
    }

    /* ---- 链式设置（返回 this 便于串联） ---- */

    public func bgColor(r: UInt8, g: UInt8, b: UInt8): Style {
        unsafe { lv_style_set_bg_color(handle, Color.of(r, g, b)) }
        this
    }

    public func bgOpa(opa: UInt8): Style {
        unsafe { lv_style_set_bg_opa(handle, opa) }
        this
    }

    public func radius(radius: Int32): Style {
        unsafe { lv_style_set_radius(handle, radius) }
        this
    }

    public func borderWidth(w: Int32): Style {
        unsafe { lv_style_set_border_width(handle, w) }
        this
    }

    public func borderColor(r: UInt8, g: UInt8, b: UInt8): Style {
        unsafe { lv_style_set_border_color(handle, Color.of(r, g, b)) }
        this
    }

    public func padAll(pad: Int32): Style {
        unsafe { lv_style_set_pad_all_cjbindwrapper(handle, pad) }
        this
    }

    public func textFont(f: Font): Style {
        unsafe { lv_style_set_text_font(handle, f.raw()) }
        this
    }

    public func textColor(r: UInt8, g: UInt8, b: UInt8): Style {
        unsafe { lv_style_set_text_color(handle, Color.of(r, g, b)) }
        this
    }

    /** 阴影宽度（9.5 起为原生渲染能力） */
    public func shadowWidth(w: Int32): Style {
        unsafe { lv_style_set_shadow_width(handle, w) }
        this
    }

    public func shadowOpa(opa: UInt8): Style {
        unsafe { lv_style_set_shadow_opa(handle, opa) }
        this
    }

    /** 模糊半径（9.5 起原生；很吃 CPU，小面积使用） */
    public func blurRadius(r: Int32): Style {
        unsafe { lv_style_set_blur_radius(handle, r) }
        this
    }

    /* ---- 应用 ---- */

    /**
     * 应用到控件的指定部位。
     * @param part LV_PART_MAIN / SCROLLBAR / INDICATOR / KNOB ...（可或上 LV_STATE_*）
     */
    public func applyTo(obj: Widget, part!: UInt32 = LV_PART_MAIN): Unit {
        unsafe { lv_obj_add_style(obj.raw(), handle, part) }
    }

    /** 底层句柄（内部使用：span 等需要直接传 lv_style_t* 的 API） */
    internal func raw(): CPointer<lv_style_t> {
        handle
    }

    ~init() {
        if (!handle.isNull()) {
            unsafe { lv_style_delete_cjbindwrapper(handle) }
        }
    }

}

/** 常见系统中文字体候选路径（Windows / Linux 桌面 / 树莓派） */
private let CJK_FONT_CANDIDATES: Array<String> = [
    "C:/Windows/Fonts/msyh.ttc", // Windows 微软雅黑
    "C:/Windows/Fonts/Deng.ttf", // Windows 等线
    "C:/Windows/Fonts/simhei.ttf", // Windows 黑体
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", // Debian/Ubuntu Noto CJK
    "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc", // 文泉驿微米黑
    "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf"
]

/** 字体：内置 Montserrat 系列的友好入口（指针由垫片交出） */
public class Font {
    private var handle: CPointer<lv_font_t>
    /** true = 由 FreeType 创建（load/systemCjk），才允许 close()；内置字体为 false */
    private var owned: Bool

    private init(handle: CPointer<lv_font_t>, owned!: Bool = false) {
        this.handle = handle
        this.owned = owned
    }

    /** Montserrat 指定字号（8..48，以 lv_conf.h 实际启用的为准，未启用回退默认字体） */
    public static func montserrat(size: Int32): Font {
        Font(unsafe { lv_font_montserrat_cjbindwrapper(size) })
    }

    /** LV_FONT_DEFAULT */
    public static func defaultFont(): Font {
        Font(unsafe { lv_font_default_cjbindwrapper() })
    }

    /**
     * 从字体文件加载（需 lv_conf.h 打开 LV_USE_FREETYPE；支持 .ttf/.ttc/.otf）。
     * 字体对象由 FreeType 管理，用完可调 close() 释放，否则随进程结束回收。
     * @param path 字体文件绝对路径
     * @param size 字号（像素）
     * @param bold 是否加粗
     */
    public static func load(path: String, size!: Int32 = 16, bold!: Bool = false): Font {
        let style: UInt32 = if (bold) { 2u32 } else { 0u32 }
        let f = withCString(path) { cs =>
            unsafe { lvglcj_freetype_font_create_cjbindwrapper(cs, UInt32(size), style) }
        }
        if (f.isNull()) {
            throw LvglException("字体加载失败：$path（确认 LV_USE_FREETYPE=1 且文件存在）")
        }
        Font(f, owned: true)
    }

    /**
     * 加载系统里的中文字体（按平台候选路径依次尝试）。
     * 内置思源黑体子集只覆盖常用字，完整中文界面建议用本方法。
     */
    public static func systemCjk(size!: Int32 = 16, bold!: Bool = false): Font {
        for (p in CJK_FONT_CANDIDATES) {
            if (exists(Path(p))) {
                return load(p, size: size, bold: bold)
            }
        }
        throw LvglException("未找到系统中文字体，请改用 Font.load(自定义字体路径)")
    }

    /** 尝试加载系统中文字体，找不到返回 None */
    public static func trySystemCjk(size!: Int32 = 16, bold!: Bool = false): Option<Font> {
        for (p in CJK_FONT_CANDIDATES) {
            if (exists(Path(p))) {
                let f = withCString(p) { cs =>
                    unsafe { lvglcj_freetype_font_create_cjbindwrapper(cs, UInt32(size), if (bold) { 2u32 } else { 0u32 }) }
                }
                if (!f.isNull()) {
                    return Some(Font(f, owned: true))
                }
            }
        }
        None
    }

    /**
     * 释放 FreeType 字体。**内置字体（montserrat / defaultFont）调用它什么也不做**——
     * 它们不归 FreeType 管，强行删除会卡死（lv_freetype_font_delete 找不到对应的面）。
     * 可重复调用。
     */
    public func close(): Unit {
        if (owned) {
            unsafe { lvglcj_freetype_font_delete_cjbindwrapper(handle) }
            owned = false
            handle = CPointer<lv_font_t>()
        }
    }

    internal func raw(): CPointer<lv_font_t> {
        handle
    }
}

/** 主题：一行切换全局主题与深色模式 */
public class Theme {
    private init() {}

    /**
     * 初始化默认主题并应用到默认 display。
     * @param primary   主色 (r, g, b)
     * @param secondary 次色 (r, g, b)
     * @param dark      是否深色模式
     * @param font      主题字体
     */
    public static func default(primary: (UInt8, UInt8, UInt8), secondary: (UInt8, UInt8, UInt8),
                               dark: Bool, font: Font): Unit {
        let disp = unsafe { lv_display_get_default() }
        if (disp.isNull()) {
            throw LvglException("Theme.default 需要先创建 display")
        }
        let theme = unsafe {
            lv_theme_default_init(disp,
                                  Color.of(primary[0], primary[1], primary[2]),
                                  Color.of(secondary[0], secondary[1], secondary[2]),
                                  dark, font.raw())
        }
        if (theme.isNull()) {
            throw LvglException("lv_theme_default_init 失败")
        }
        unsafe { lv_theme_apply(unsafe { lv_screen_active() }) }
    }
}
