/**
 * 样式扩展：`lv_style_set_*` / `lv_obj_set_style_*` 的高频子集。
 *
 * 基础属性（背景色/背景不透明度/圆角/边框宽度/边框色/文本色/文本字体/阴影宽度/
 * 阴影不透明度/模糊/内边距）在 `style.cj` 与 `widget.cj` 里；这里补齐做 UI 时
 * 最常改的第二梯队：渐变、外描边、整体不透明度、变换、图像着色、线/弧属性、
 * 文本排版、外边距、四向内边距、尺寸限制。
 *
 * 所有颜色参数都按 `(r, g, b)` 三个 `UInt8` 传，避免调用方自己拼 `lv_color_t`。
 */
package lvglcj

/* ==================== 常量 ==================== */

/* LV_GRAD_DIR_*（lv_grad.h:32） */
public const LV_GRAD_DIR_NONE: Int32 = 0
public const LV_GRAD_DIR_VER: Int32 = 1
public const LV_GRAD_DIR_HOR: Int32 = 2

/* LV_BORDER_SIDE_*（lv_style.h:112，位掩码） */
public const LV_BORDER_SIDE_NONE: Int32 = 0x00
public const LV_BORDER_SIDE_BOTTOM: Int32 = 0x01
public const LV_BORDER_SIDE_TOP: Int32 = 0x02
public const LV_BORDER_SIDE_LEFT: Int32 = 0x04
public const LV_BORDER_SIDE_RIGHT: Int32 = 0x08
public const LV_BORDER_SIDE_FULL: Int32 = 0x0F

/* LV_TEXT_DECOR_*（lv_text.h，位掩码） */
public const LV_TEXT_DECOR_NONE: Int32 = 0
public const LV_TEXT_DECOR_UNDERLINE: Int32 = 1
public const LV_TEXT_DECOR_STRIKETHROUGH: Int32 = 2

/* ==================== FFI：样式表属性 ==================== */

foreign func lv_style_set_bg_grad_color(style: CPointer<lv_style_t>, value: lv_color_t): Unit

foreign func lv_style_set_bg_grad_dir(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_bg_grad_stop(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_border_opa(style: CPointer<lv_style_t>, value: UInt8): Unit

foreign func lv_style_set_border_side(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_outline_width(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_outline_color(style: CPointer<lv_style_t>, value: lv_color_t): Unit

foreign func lv_style_set_outline_opa(style: CPointer<lv_style_t>, value: UInt8): Unit

foreign func lv_style_set_outline_pad(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_opa(style: CPointer<lv_style_t>, value: UInt8): Unit

foreign func lv_style_set_opa_layered(style: CPointer<lv_style_t>, value: UInt8): Unit

foreign func lv_style_set_shadow_color(style: CPointer<lv_style_t>, value: lv_color_t): Unit

foreign func lv_style_set_shadow_offset_x(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_shadow_offset_y(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_shadow_spread(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_text_align(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_text_letter_space(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_text_line_space(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_text_opa(style: CPointer<lv_style_t>, value: UInt8): Unit

foreign func lv_style_set_text_decor(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_image_recolor(style: CPointer<lv_style_t>, value: lv_color_t): Unit

foreign func lv_style_set_image_recolor_opa(style: CPointer<lv_style_t>, value: UInt8): Unit

foreign func lv_style_set_image_opa(style: CPointer<lv_style_t>, value: UInt8): Unit

foreign func lv_style_set_line_width(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_line_color(style: CPointer<lv_style_t>, value: lv_color_t): Unit

foreign func lv_style_set_line_opa(style: CPointer<lv_style_t>, value: UInt8): Unit

foreign func lv_style_set_line_rounded(style: CPointer<lv_style_t>, value: Bool): Unit

foreign func lv_style_set_arc_width(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_arc_color(style: CPointer<lv_style_t>, value: lv_color_t): Unit

foreign func lv_style_set_arc_opa(style: CPointer<lv_style_t>, value: UInt8): Unit

foreign func lv_style_set_arc_rounded(style: CPointer<lv_style_t>, value: Bool): Unit

foreign func lv_style_set_transform_rotation(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_transform_scale_x(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_transform_scale_y(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_transform_pivot_x(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_transform_pivot_y(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_translate_x(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_translate_y(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_margin_top(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_margin_right(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_margin_bottom(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_margin_left(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_pad_top(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_pad_right(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_pad_bottom(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_pad_left(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_min_width(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_min_height(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_max_width(style: CPointer<lv_style_t>, value: Int32): Unit

foreign func lv_style_set_max_height(style: CPointer<lv_style_t>, value: Int32): Unit

/* ==================== FFI：控件局部属性 ==================== */

foreign func lv_obj_set_style_bg_grad_color(obj: CPointer<lv_obj_t>, value: lv_color_t, selector: UInt32): Unit

foreign func lv_obj_set_style_bg_grad_dir(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_bg_grad_stop(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_border_opa(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit

foreign func lv_obj_set_style_border_side(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_outline_width(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_outline_color(obj: CPointer<lv_obj_t>, value: lv_color_t, selector: UInt32): Unit

foreign func lv_obj_set_style_outline_opa(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit

foreign func lv_obj_set_style_outline_pad(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_opa(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit

foreign func lv_obj_set_style_opa_layered(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit

foreign func lv_obj_set_style_shadow_color(obj: CPointer<lv_obj_t>, value: lv_color_t, selector: UInt32): Unit

foreign func lv_obj_set_style_shadow_offset_x(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_shadow_offset_y(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_shadow_spread(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_text_align(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_text_letter_space(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_text_line_space(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_text_opa(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit

foreign func lv_obj_set_style_text_decor(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_image_recolor(obj: CPointer<lv_obj_t>, value: lv_color_t, selector: UInt32): Unit

foreign func lv_obj_set_style_image_recolor_opa(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit

foreign func lv_obj_set_style_image_opa(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit

foreign func lv_obj_set_style_line_width(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_line_color(obj: CPointer<lv_obj_t>, value: lv_color_t, selector: UInt32): Unit

foreign func lv_obj_set_style_line_opa(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit

foreign func lv_obj_set_style_line_rounded(obj: CPointer<lv_obj_t>, value: Bool, selector: UInt32): Unit

foreign func lv_obj_set_style_arc_width(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_arc_color(obj: CPointer<lv_obj_t>, value: lv_color_t, selector: UInt32): Unit

foreign func lv_obj_set_style_arc_opa(obj: CPointer<lv_obj_t>, value: UInt8, selector: UInt32): Unit

foreign func lv_obj_set_style_arc_rounded(obj: CPointer<lv_obj_t>, value: Bool, selector: UInt32): Unit

foreign func lv_obj_set_style_transform_rotation(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_transform_scale_x(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_transform_scale_y(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_transform_pivot_x(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_transform_pivot_y(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_translate_x(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_translate_y(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_margin_top(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_margin_right(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_margin_bottom(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_margin_left(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_min_width(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_min_height(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_max_width(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

foreign func lv_obj_set_style_max_height(obj: CPointer<lv_obj_t>, value: Int32, selector: UInt32): Unit

/* ==================== Style：链式 setter ==================== */

extend Style {
    /** `lv_style_set_bg_grad_color` */
    public func bgGradColor(r: UInt8, g: UInt8, b: UInt8): Style {
        unsafe { lv_style_set_bg_grad_color(raw(), Color.of(r, g, b)) }
        this
    }

    /** `lv_style_set_bg_grad_dir` */
    public func bgGradDir(v: Int32): Style {
        unsafe { lv_style_set_bg_grad_dir(raw(), v) }
        this
    }

    /** `lv_style_set_bg_grad_stop` */
    public func bgGradStop(v: Int32): Style {
        unsafe { lv_style_set_bg_grad_stop(raw(), v) }
        this
    }

    /** `lv_style_set_border_opa` */
    public func borderOpa(v: UInt8): Style {
        unsafe { lv_style_set_border_opa(raw(), v) }
        this
    }

    /** `lv_style_set_border_side` */
    public func borderSide(v: Int32): Style {
        unsafe { lv_style_set_border_side(raw(), v) }
        this
    }

    /** `lv_style_set_outline_width` */
    public func outlineWidth(v: Int32): Style {
        unsafe { lv_style_set_outline_width(raw(), v) }
        this
    }

    /** `lv_style_set_outline_color` */
    public func outlineColor(r: UInt8, g: UInt8, b: UInt8): Style {
        unsafe { lv_style_set_outline_color(raw(), Color.of(r, g, b)) }
        this
    }

    /** `lv_style_set_outline_opa` */
    public func outlineOpa(v: UInt8): Style {
        unsafe { lv_style_set_outline_opa(raw(), v) }
        this
    }

    /** `lv_style_set_outline_pad` */
    public func outlinePad(v: Int32): Style {
        unsafe { lv_style_set_outline_pad(raw(), v) }
        this
    }

    /** `lv_style_set_opa` */
    public func opa(v: UInt8): Style {
        unsafe { lv_style_set_opa(raw(), v) }
        this
    }

    /** `lv_style_set_opa_layered` */
    public func opaLayered(v: UInt8): Style {
        unsafe { lv_style_set_opa_layered(raw(), v) }
        this
    }

    /** `lv_style_set_shadow_color` */
    public func shadowColor(r: UInt8, g: UInt8, b: UInt8): Style {
        unsafe { lv_style_set_shadow_color(raw(), Color.of(r, g, b)) }
        this
    }

    /** `lv_style_set_shadow_offset_x` */
    public func shadowOffsetX(v: Int32): Style {
        unsafe { lv_style_set_shadow_offset_x(raw(), v) }
        this
    }

    /** `lv_style_set_shadow_offset_y` */
    public func shadowOffsetY(v: Int32): Style {
        unsafe { lv_style_set_shadow_offset_y(raw(), v) }
        this
    }

    /** `lv_style_set_shadow_spread` */
    public func shadowSpread(v: Int32): Style {
        unsafe { lv_style_set_shadow_spread(raw(), v) }
        this
    }

    /** `lv_style_set_text_align` */
    public func textAlign(v: Int32): Style {
        unsafe { lv_style_set_text_align(raw(), v) }
        this
    }

    /** `lv_style_set_text_letter_space` */
    public func textLetterSpace(v: Int32): Style {
        unsafe { lv_style_set_text_letter_space(raw(), v) }
        this
    }

    /** `lv_style_set_text_line_space` */
    public func textLineSpace(v: Int32): Style {
        unsafe { lv_style_set_text_line_space(raw(), v) }
        this
    }

    /** `lv_style_set_text_opa` */
    public func textOpa(v: UInt8): Style {
        unsafe { lv_style_set_text_opa(raw(), v) }
        this
    }

    /** `lv_style_set_text_decor` */
    public func textDecor(v: Int32): Style {
        unsafe { lv_style_set_text_decor(raw(), v) }
        this
    }

    /** `lv_style_set_image_recolor` */
    public func imageRecolor(r: UInt8, g: UInt8, b: UInt8): Style {
        unsafe { lv_style_set_image_recolor(raw(), Color.of(r, g, b)) }
        this
    }

    /** `lv_style_set_image_recolor_opa` */
    public func imageRecolorOpa(v: UInt8): Style {
        unsafe { lv_style_set_image_recolor_opa(raw(), v) }
        this
    }

    /** `lv_style_set_image_opa` */
    public func imageOpa(v: UInt8): Style {
        unsafe { lv_style_set_image_opa(raw(), v) }
        this
    }

    /** `lv_style_set_line_width` */
    public func lineWidth(v: Int32): Style {
        unsafe { lv_style_set_line_width(raw(), v) }
        this
    }

    /** `lv_style_set_line_color` */
    public func lineColor(r: UInt8, g: UInt8, b: UInt8): Style {
        unsafe { lv_style_set_line_color(raw(), Color.of(r, g, b)) }
        this
    }

    /** `lv_style_set_line_opa` */
    public func lineOpa(v: UInt8): Style {
        unsafe { lv_style_set_line_opa(raw(), v) }
        this
    }

    /** `lv_style_set_line_rounded` */
    public func lineRounded(on: Bool): Style {
        unsafe { lv_style_set_line_rounded(raw(), on) }
        this
    }

    /** `lv_style_set_arc_width` */
    public func arcWidth(v: Int32): Style {
        unsafe { lv_style_set_arc_width(raw(), v) }
        this
    }

    /** `lv_style_set_arc_color` */
    public func arcColor(r: UInt8, g: UInt8, b: UInt8): Style {
        unsafe { lv_style_set_arc_color(raw(), Color.of(r, g, b)) }
        this
    }

    /** `lv_style_set_arc_opa` */
    public func arcOpa(v: UInt8): Style {
        unsafe { lv_style_set_arc_opa(raw(), v) }
        this
    }

    /** `lv_style_set_arc_rounded` */
    public func arcRounded(on: Bool): Style {
        unsafe { lv_style_set_arc_rounded(raw(), on) }
        this
    }

    /** `lv_style_set_transform_rotation` */
    public func transformRotation(v: Int32): Style {
        unsafe { lv_style_set_transform_rotation(raw(), v) }
        this
    }

    /** `lv_style_set_transform_scale_x` */
    public func transformScaleX(v: Int32): Style {
        unsafe { lv_style_set_transform_scale_x(raw(), v) }
        this
    }

    /** `lv_style_set_transform_scale_y` */
    public func transformScaleY(v: Int32): Style {
        unsafe { lv_style_set_transform_scale_y(raw(), v) }
        this
    }

    /** `lv_style_set_transform_pivot_x` */
    public func transformPivotX(v: Int32): Style {
        unsafe { lv_style_set_transform_pivot_x(raw(), v) }
        this
    }

    /** `lv_style_set_transform_pivot_y` */
    public func transformPivotY(v: Int32): Style {
        unsafe { lv_style_set_transform_pivot_y(raw(), v) }
        this
    }

    /** `lv_style_set_translate_x` */
    public func translateX(v: Int32): Style {
        unsafe { lv_style_set_translate_x(raw(), v) }
        this
    }

    /** `lv_style_set_translate_y` */
    public func translateY(v: Int32): Style {
        unsafe { lv_style_set_translate_y(raw(), v) }
        this
    }

    /** `lv_style_set_margin_top` */
    public func marginTop(v: Int32): Style {
        unsafe { lv_style_set_margin_top(raw(), v) }
        this
    }

    /** `lv_style_set_margin_right` */
    public func marginRight(v: Int32): Style {
        unsafe { lv_style_set_margin_right(raw(), v) }
        this
    }

    /** `lv_style_set_margin_bottom` */
    public func marginBottom(v: Int32): Style {
        unsafe { lv_style_set_margin_bottom(raw(), v) }
        this
    }

    /** `lv_style_set_margin_left` */
    public func marginLeft(v: Int32): Style {
        unsafe { lv_style_set_margin_left(raw(), v) }
        this
    }

    /** `lv_style_set_pad_top` */
    public func padTop(v: Int32): Style {
        unsafe { lv_style_set_pad_top(raw(), v) }
        this
    }

    /** `lv_style_set_pad_right` */
    public func padRight(v: Int32): Style {
        unsafe { lv_style_set_pad_right(raw(), v) }
        this
    }

    /** `lv_style_set_pad_bottom` */
    public func padBottom(v: Int32): Style {
        unsafe { lv_style_set_pad_bottom(raw(), v) }
        this
    }

    /** `lv_style_set_pad_left` */
    public func padLeft(v: Int32): Style {
        unsafe { lv_style_set_pad_left(raw(), v) }
        this
    }

    /** `lv_style_set_min_width` */
    public func minWidth(v: Int32): Style {
        unsafe { lv_style_set_min_width(raw(), v) }
        this
    }

    /** `lv_style_set_min_height` */
    public func minHeight(v: Int32): Style {
        unsafe { lv_style_set_min_height(raw(), v) }
        this
    }

    /** `lv_style_set_max_width` */
    public func maxWidth(v: Int32): Style {
        unsafe { lv_style_set_max_width(raw(), v) }
        this
    }

    /** `lv_style_set_max_height` */
    public func maxHeight(v: Int32): Style {
        unsafe { lv_style_set_max_height(raw(), v) }
        this
    }

    /** 四向外边距一起设（`lv_style_set_margin_*` 没有 all 变体） */
    public func marginAll(v: Int32): Style {
        marginTop(v).marginRight(v).marginBottom(v).marginLeft(v)
    }

    /** 四向内边距一起设（除 `padAll` 之外按边微调时用） */
    public func padEach(top: Int32, right: Int32, bottom: Int32, left: Int32): Style {
        padTop(top).padRight(right).padBottom(bottom).padLeft(left)
    }
}

/* ==================== Widget：局部样式便捷方法 ==================== */

extend Widget {
    /** `lv_obj_set_style_bg_grad_color` */
    public func setStyleBgGradColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN,
        state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_bg_grad_color(raw(), Color.of(r, g, b), part | state) }
        this
    }

    /** `lv_obj_set_style_bg_grad_dir` */
    public func setStyleBgGradDir(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_bg_grad_dir(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_bg_grad_stop` */
    public func setStyleBgGradStop(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_bg_grad_stop(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_border_opa` */
    public func setStyleBorderOpa(v: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_border_opa(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_border_side` */
    public func setStyleBorderSide(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_border_side(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_outline_width` */
    public func setStyleOutlineWidth(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_outline_width(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_outline_color` */
    public func setStyleOutlineColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN,
        state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_outline_color(raw(), Color.of(r, g, b), part | state) }
        this
    }

    /** `lv_obj_set_style_outline_opa` */
    public func setStyleOutlineOpa(v: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_outline_opa(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_outline_pad` */
    public func setStyleOutlinePad(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_outline_pad(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_opa` */
    public func setStyleOpa(v: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_opa(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_opa_layered` */
    public func setStyleOpaLayered(v: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_opa_layered(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_shadow_color` */
    public func setStyleShadowColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN,
        state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_shadow_color(raw(), Color.of(r, g, b), part | state) }
        this
    }

    /** `lv_obj_set_style_shadow_offset_x` */
    public func setStyleShadowOffsetX(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_shadow_offset_x(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_shadow_offset_y` */
    public func setStyleShadowOffsetY(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_shadow_offset_y(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_shadow_spread` */
    public func setStyleShadowSpread(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_shadow_spread(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_text_align` */
    public func setStyleTextAlign(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_text_align(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_text_letter_space` */
    public func setStyleTextLetterSpace(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_text_letter_space(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_text_line_space` */
    public func setStyleTextLineSpace(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_text_line_space(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_text_opa` */
    public func setStyleTextOpa(v: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_text_opa(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_text_decor` */
    public func setStyleTextDecor(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_text_decor(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_image_recolor` */
    public func setStyleImageRecolor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN,
        state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_image_recolor(raw(), Color.of(r, g, b), part | state) }
        this
    }

    /** `lv_obj_set_style_image_recolor_opa` */
    public func setStyleImageRecolorOpa(v: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_image_recolor_opa(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_image_opa` */
    public func setStyleImageOpa(v: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_image_opa(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_line_width` */
    public func setStyleLineWidth(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_line_width(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_line_color` */
    public func setStyleLineColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN,
        state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_line_color(raw(), Color.of(r, g, b), part | state) }
        this
    }

    /** `lv_obj_set_style_line_opa` */
    public func setStyleLineOpa(v: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_line_opa(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_line_rounded` */
    public func setStyleLineRounded(on: Bool, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_line_rounded(raw(), on, part | state) }
        this
    }

    /** `lv_obj_set_style_arc_width` */
    public func setStyleArcWidth(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_arc_width(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_arc_color` */
    public func setStyleArcColor(r: UInt8, g: UInt8, b: UInt8, part!: UInt32 = LV_PART_MAIN,
        state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_arc_color(raw(), Color.of(r, g, b), part | state) }
        this
    }

    /** `lv_obj_set_style_arc_opa` */
    public func setStyleArcOpa(v: UInt8, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_arc_opa(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_arc_rounded` */
    public func setStyleArcRounded(on: Bool, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_arc_rounded(raw(), on, part | state) }
        this
    }

    /** `lv_obj_set_style_transform_rotation` */
    public func setStyleTransformRotation(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_transform_rotation(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_transform_scale_x` */
    public func setStyleTransformScaleX(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_transform_scale_x(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_transform_scale_y` */
    public func setStyleTransformScaleY(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_transform_scale_y(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_transform_pivot_x` */
    public func setStyleTransformPivotX(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_transform_pivot_x(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_transform_pivot_y` */
    public func setStyleTransformPivotY(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_transform_pivot_y(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_translate_x` */
    public func setStyleTranslateX(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_translate_x(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_translate_y` */
    public func setStyleTranslateY(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_translate_y(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_margin_top` */
    public func setStyleMarginTop(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_margin_top(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_margin_right` */
    public func setStyleMarginRight(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_margin_right(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_margin_bottom` */
    public func setStyleMarginBottom(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_margin_bottom(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_margin_left` */
    public func setStyleMarginLeft(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_margin_left(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_pad_top` */

    /** `lv_obj_set_style_pad_right` */

    /** `lv_obj_set_style_pad_bottom` */

    /** `lv_obj_set_style_pad_left` */

    /** `lv_obj_set_style_min_width` */
    public func setStyleMinWidth(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_min_width(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_min_height` */
    public func setStyleMinHeight(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_min_height(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_max_width` */
    public func setStyleMaxWidth(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_max_width(raw(), v, part | state) }
        this
    }

    /** `lv_obj_set_style_max_height` */
    public func setStyleMaxHeight(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        unsafe { lv_obj_set_style_max_height(raw(), v, part | state) }
        this
    }

    /** 四向外边距一起设 */
    public func setStyleMarginAll(v: Int32, part!: UInt32 = LV_PART_MAIN, state!: UInt32 = LV_STATE_DEFAULT): Widget {
        setStyleMarginTop(v, part: part, state: state)
        setStyleMarginRight(v, part: part, state: state)
        setStyleMarginBottom(v, part: part, state: state)
        setStyleMarginLeft(v, part: part, state: state)
        this
    }
}
