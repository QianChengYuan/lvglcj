/**
 * 全功能演示（`./main all`）：一个窗口里用标签页覆盖
 *
 *   控件 / 布局 / 样式 / 数据绑定 / 焦点组 / 动画 / 绘图与图表 / 富文本与浮层
 *
 * 目的是把 lvglcj 的公开 API 都跑一遍，当作活文档用；单项细节看对应的
 * `./main hello|widgets|rich|...`，真机专项（DRM/evdev）看 touch 示例。
 */
package lvglcj_examples

import lvglcj.*
import std.collection.ArrayList
import std.math.*

/** 回调里要改的可变状态；仓颉闭包作 C 回调时不能捕获可变局部变量 */
private class Counter {
    var value: Int32
    init(v: Int32) {
        value = v
    }
}

/** 建一个标签页，内容区用纵向 flex 排布 */
private func page(tv: TabView, name: String): Container {
    let t = tv.addTab(name)
    let box = Container(t)
    box.size(776, 392)
    box.setStylePadAll(8)
    box.flex(FlexFlow.COLUMN, gap: 6)
    return box
}

/**
 * 横向一行。
 *
 * 三个必须归零/显式设置的点（都是 LVGL 默认主题挖的坑）：
 * - 主题给普通对象的 `pad_all` 是中屏 20px、边框 2px。不归零的话，一行高 46 的容器
 *   内容区只剩 46 - 2*(20+2) = 2px，里面的控件会被裁掉、并撑出滚动条。
 * - 主题还留了 `pad_row` / `pad_column`（不受 `pad_all` 影响），所以要 `flex(gap:)` 显式设。
 * - 垂直居中要写 `trackCross`：`cross` 只在同一行内高矮不一时才看得出差别。
 */
private func row(parent: Widget, h: Int32, gap!: Int32 = 8): Container {
    let r = Container(parent)
    r.size(760, h)
    r.setStylePadAll(0)
    r.setStyleBorderWidth(0)
    r.flex(FlexFlow.ROW, gap: gap)
    r.flexAlign(FlexAlign.START, cross: FlexAlign.CENTER, trackCross: FlexAlign.CENTER)
    return r
}

/** 文案 */
private func caption(parent: Widget, s: String): Label {
    let l = Label(parent)
    l.text(s)
    return l
}

/**
 * 指定尺寸、且内边距/边框归零的容器。
 *
 * LVGL 默认主题会给普通对象留下中屏 20px 的 `pad_all` 和 2px 边框：固定高度的容器
 * 若不清零，内容区会被吃掉 44px，里面的子对象随即溢出、被裁剪。凡是「固定尺寸 +
 * 里面放别的东西」的容器都走这里。
 */
private func bareBox(parent: Widget, w: Int32, h: Int32): Container {
    let c = Container(parent)
    c.size(w, h)
    c.setStylePadAll(0)
    c.setStyleBorderWidth(0)
    return c
}

/** 纯色圆角块，用来演示布局与样式 */
private func block(parent: Widget, w: Int32, h: Int32, r: UInt8, g: UInt8, b: UInt8): Container {
    let c = bareBox(parent, w, h)
    c.setStyleBgColor(r, g, b)
    c.setStyleRadius(8)
    return c
}

/* ==================== 1. 控件 ==================== */

/** 软键盘的显示状态；闭包不能捕获可变局部变量，用引用类型记住 */
private class KbState {
    var shown: Bool
    init(shown: Bool) {
        this.shown = shown
    }
}

private func setKeyboardVisible(kb: Keyboard, st: KbState, on: Bool): Unit {
    if (on) {
        kb.removeFlag(LV_OBJ_FLAG_HIDDEN)
    } else {
        kb.addFlag(LV_OBJ_FLAG_HIDDEN)
    }
    st.shown = on
}

private func showcaseWidgets(box: Widget, kb: Keyboard, kbState: KbState): Unit {
    caption(box, "基础控件：按钮 / 开关 / 复选框 / 滑块 / 进度条 / 圆弧 / LED / 下拉 / 滚轮 / 数字框 / 文本域")

    let r1 = row(box, 48)
    let btn = Button(r1)
    btn.size(140, 44)
    let bl = Label(btn)
    bl.text("点击 0 次")
    bl.center()
    let clicks = Counter(0)
    btn.onClick {
        =>
            clicks.value += 1
            bl.setTextFmt("点击 %d 次", clicks.value)
    }

    let sw = Switch(r1)
    sw.size(52, 30)
    let sl = Label(r1)
    sl.text("开关：关")
    sw.onEvent(LV_EVENT_VALUE_CHANGED) {
        _ => sl.text(if (sw.isChecked()) {
            "开关：开"
        } else {
            "开关：关"
        })
    }

    let cb = Checkbox(r1)
    cb.text("复选框")
    cb.setChecked(true)
    cb.onEvent(LV_EVENT_VALUE_CHANGED) {
        _ => println("[showcase] 复选框 = ${cb.isChecked()}")
    }

    let r2 = row(box, 44)
    let slider = Slider(r2)
    slider.size(240, 18)
    slider.range(0, 100)
    slider.value(40)
    let sliderLabel = Label(r2)
    sliderLabel.text("滑块：40")
    slider.onValueChanged {
        v => sliderLabel.setTextFmt("滑块：%d", v)
    }

    let bar = Bar(r2)
    bar.size(180, 16)
    bar.range(0, 100)
    bar.value(65)
    let barLabel = Label(r2)
    barLabel.text("进度条 65%")
    slider.onValueChanged {
        v => bar.value(v, anim: false)
    }

    let r3 = row(box, 84)
    let arc = Arc(r3)
    arc.size(80, 80)
    arc.angles(0, 270)
    arc.value(70)
    let led = Led(r3)
    led.size(24, 24)
    led.color(80, 220, 120)
    led.on()
    let led2 = Led(r3)
    led2.size(24, 24)
    led2.color(240, 90, 90)
    led2.brightness(120)

    let cc = Counter(0)
    let ledBtn = Button(r3)
    ledBtn.size(120, 40)
    let ledBtnLabel = Label(ledBtn)
    ledBtnLabel.text("切换 LED")
    ledBtnLabel.center()
    ledBtn.onClick {
        =>
            cc.value += 1
            if (cc.value % 2 == 1) {
                led.off()
            } else {
                led.on()
            }
    }

    let r4 = row(box, 92, gap: 16)
    let dd = Dropdown(r4)
    dd.size(180, 40)
    dd.options("选项 A\n选项 B\n选项 C")
    let roller = Roller(r4)
    roller.size(110, 90)
    roller.options("一\n二\n三\n四")
    roller.selected(1)
    let spin = Spinbox(r4)
    spin.size(130, 40)
    spin.range(0, 100)
    spin.value(20)

    // 文本域 + 软键盘：键盘挂在 screen 上浮在所有标签页之上，默认隐藏，
    // 点文本域或点「软键盘」按钮才弹出，点键盘的 ✓ / ✕ 收起。
    let rta = row(box, 48)
    let ta = TextArea(rta)
    ta.size(420, 44)
    ta.text("点这里弹出软键盘…")
    ta.oneLine(false)
    let kbt = Button(rta)
    kbt.size(120, 40)
    let kbl = Label(kbt)
    kbl.text("软键盘")
    kbl.center()
    kb.target(ta)

    ta.on(LV_EVENT_CLICKED) {_ => setKeyboardVisible(kb, kbState, true)}
    ta.on(LV_EVENT_FOCUSED) {_ => setKeyboardVisible(kb, kbState, true)}
    kb.on(LV_EVENT_READY) {_ => setKeyboardVisible(kb, kbState, false)}
    kb.on(LV_EVENT_CANCEL) {_ => setKeyboardVisible(kb, kbState, false)}
    kbt.onClick {=> setKeyboardVisible(kb, kbState, !kbState.shown)}
}

/* ==================== 2. 布局 ==================== */

private func showcaseLayout(box: Widget): Unit {
    caption(box, "flex：三个色块按 1 : 2 : 1 分配宽度；grid：2 行 3 列，中间那个跨两列")

    let fr = bareBox(box, 760, 72)
    fr.flex(FlexFlow.ROW, gap: 6)
    let a = block(fr, 100, 64, 0xE5, 0x4B, 0x4B)
    a.flexGrow(1)
    let b = block(fr, 100, 64, 0x42, 0xA5, 0xF5)
    b.flexGrow(2)
    let c = block(fr, 100, 64, 0x66, 0xBB, 0x6A)
    c.flexGrow(1)

    let g = bareBox(box, 760, 140)
    g.grid([GridSize.Fr(1), GridSize.Fr(1), GridSize.Fr(1)], [GridSize.Fr(1), GridSize.Fr(1)])
    // 容器级对齐只能用 START/CENTER/END/SPACE_*（STRETCH 在 LVGL 侧是未实现的，
    // 会让轨道起点取到未初始化内存）；子对象填满单元格靠 place() 的默认 STRETCH。
    g.gridAlign(col: GridAlign.START, row: GridAlign.START)
    let g1 = block(g, 100, 80, 0xFF, 0xB3, 0x00)
    g1.place(col: 0, row: 0)
    let g2 = block(g, 100, 80, 0x8E, 0x24, 0xAA)
    g2.place(col: 1, row: 0, colSpan: 2)
    let g3 = block(g, 100, 80, 0x00, 0xAC, 0xC1)
    g3.place(col: 0, row: 1)
    let g4 = block(g, 100, 80, 0x79, 0x55, 0x48)
    g4.place(col: 1, row: 1)
    let g5 = block(g, 100, 80, 0x26, 0xA6, 0x9A)
    g5.place(col: 2, row: 1)

    // 滚动：内容超宽时容器可滚，用 scrollTo 演示"滚到末尾"
    caption(box, "滚动容器：点击按钮滚到末尾（scrollToX，带动画）")
    let scroll = bareBox(box, 760, 46)
    scroll.scrollable(on: true)
    scroll.scrollDir(LV_DIR_HOR)
    let longText = Label(scroll)
    longText.text("← 一行很长的内容，用来演示横向滚动：ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 →")
    longText.size(1100, 40)
    let sbtn = Button(box)
    sbtn.size(160, 40)
    let sbtnLabel = Label(sbtn)
    sbtnLabel.text("滚到末尾")
    sbtnLabel.center()
    sbtn.onClick {
        => scroll.scrollToX(scroll.width(), anim: true)
    }

}

/* ==================== 3. 样式 ==================== */

private func showcaseStyles(box: Widget): Unit {
    caption(box, "style.cj / style_extra.cj 的常用属性：描边、阴影、渐变、旋转、透明度、文本装饰")

    let r1 = row(box, 90, gap: 14)
    let outline = block(r1, 120, 80, 0x33, 0x33, 0x3A)
    outline.setStyleOutlineWidth(3)
    outline.setStyleOutlineColor(0x4E, 0xC9, 0xE8)
    outline.setStyleOutlinePad(2)

    let shadow = block(r1, 120, 80, 0x33, 0x33, 0x3A)
    shadow.setStyleShadowWidth(14)
    shadow.setStyleShadowColor(0x00, 0x00, 0x00)
    shadow.setStyleShadowOffsetX(4)
    shadow.setStyleShadowOffsetY(6)

    let grad = Container(r1)
    grad.size(140, 80)
    grad.setStyleRadius(10)
    grad.setStyleBgGradColor(0x00, 0x00, 0x00)
    grad.setStyleBgGradDir(LV_GRAD_DIR_HOR)
    grad.setStyleBgGradStop(255)
    grad.setStyleBgColor(0xE5, 0x39, 0x35)

    let rotated = block(r1, 80, 80, 0x42, 0xA5, 0xF5)
    rotated.setStyleTransformRotation(150) // 15°（单位 0.1°）
    rotated.setStyleTransformScaleX(288) // 1.125x（单位 1/256）

    let r2 = row(box, 70, gap: 14)
    let half = block(r2, 120, 60, 0xAB, 0x47, 0xBC)
    half.setStyleOpa(120) // 整体 47% 不透明
    let translated = block(r2, 90, 50, 0x26, 0xC6, 0xDA)
    translated.setStyleTranslateX(24)
    translated.setStyleTranslateY(6)

    let caps = caption(r2, "下划线 + 描边文字")
    caps.setStyleTextDecor(LV_TEXT_DECOR_UNDERLINE)
    caps.setStyleTextOpa(200)
    caps.setStyleTextLetterSpace(2)

    caption(box, "边框：只画左边与下边")
    let borderBox = block(box, 260, 60, 0x2B, 0x2B, 0x30)
    borderBox.setStyleBorderWidth(3)
    borderBox.setStyleBorderColor(0xFF, 0x70, 0x43)
    borderBox.setStyleBorderSide(LV_BORDER_SIDE_LEFT | LV_BORDER_SIDE_BOTTOM)
}

/* ==================== 4. 数据绑定 ==================== */

private func showcaseBinding(box: Widget): Unit {
    caption(box, "Subject（Int32）：滑块与进度条共享同一个数据源，标签自动跟随；改动走 set()")

    let sub = Subject.of(35)
    let r1 = row(box, 50)
    let slider = Slider(r1)
    slider.size(240, 18)
    slider.range(0, 100)
    slider.bindValue(sub)
    let bar = Bar(r1)
    bar.size(200, 18)
    bar.range(0, 100)
    bar.bindValue(sub)
    let valueLabel = Label(r1)
    valueLabel.bindText(sub, fmt: "当前值 = %d")

    let stepBtn = Button(r1)
    stepBtn.size(130, 40)
    let stepLabel = Label(stepBtn)
    stepLabel.text("值 +10")
    stepLabel.center()
    stepBtn.onClick {
        =>
            let next = sub.get() + 10
            sub.set(if (next > 100) {
                0
            } else {
                next
            })
    }

    caption(box, "StringSubject：字符串主题 + Label.bindText，容量 64 字节（UTF-8 汉字 3 字节）")
    let r2 = row(box, 48)
    let ssub = StringSubject.of("就绪", capacity: 64)
    let sLabel = Label(r2)
    sLabel.bindText(ssub)
    let prog = Counter(0)
    let sBtn = Button(r2)
    sBtn.size(160, 40)
    let sBtnLabel = Label(sBtn)
    sBtnLabel.text("写字符串")
    sBtnLabel.center()
    sBtn.onClick {
        =>
            prog.value += 1
            ssub.set("进度 ${prog.value}%")
    }

    caption(box, "ColorSubject（0xRRGGBB）与 PointerSubject：回调里自己决定怎么用")
    let r3 = row(box, 48, gap: 16)
    let csub = ColorSubject.of(0x2196F3)
    let swatch = block(r3, 90, 44, 0x21, 0x96, 0xF3)
    csub.subscribe {
        c => swatch.setStyleBgColor(UInt8((c >> 16) & 0xFF), UInt8((c >> 8) & 0xFF), UInt8(c & 0xFF))
    }
    let colors: Array<(UInt8, UInt8, UInt8)> = [
        (0x21, 0x96, 0xF3),
        (0xF4, 0x43, 0x36),
        (0x4C, 0xAF, 0x50),
        (0xFF, 0x98, 0x00)
    ]
    let cIdx = Counter(0)
    let cBtn = Button(r3)
    cBtn.size(140, 40)
    let cBtnLabel = Label(cBtn)
    cBtnLabel.text("换颜色")
    cBtnLabel.center()
    cBtn.onClick {
        =>
            cIdx.value = (cIdx.value + 1) % Int32(colors.size)
            let (r, g, b) = colors[Int64(cIdx.value)]
            csub.set((UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b))
    }

    let psub = PointerSubject.of(CPointer<Unit>())
    let pLabel = Label(r3)
    pLabel.text("指针 = null")
    psub.bind(r3) {
        p => pLabel.text(if (p.isNull()) {
            "指针 = null"
        } else {
            "指针 = ${p.toUIntNative()}"
        })
    }
    // 指针主题本身不做类型约束，这里塞一块堆内存的地址演示（演示用，进程退出即回收）
    let raw = LibC.malloc<UInt8>(count: 16)
    let pBtn = Button(r3)
    pBtn.size(130, 40)
    let pBtnLabel = Label(pBtn)
    pBtnLabel.text("设置指针")
    pBtnLabel.center()
    let pNull = Counter(0)
    pBtn.onClick {
        =>
            pNull.value = 1 - pNull.value
            psub.set(if (pNull.value == 1) {
                CPointer<Unit>(raw)
            } else {
                CPointer<Unit>()
            })
    }
}

/* ==================== 5. 焦点组 ==================== */

private func showcaseGroup(box: Widget): Unit {
    caption(box,
        "焦点组：把若干控件编成一组，用 focusNext/focusPrev 或方向键在组内移动焦点（Input.setGroup 后可用实体按键）")

    let g = Group.of()
    let r1 = row(box, 52, gap: 12)
    let names = ["播放", "暂停", "停止"]
    let btns = ArrayList<Button>()
    for (n in names) {
        let b = Button(r1)
        b.size(120, 44)
        let l = Label(b)
        l.text(n)
        l.center()
        g.add(b)
        btns.add(b)
    }

    let focusLabel = Label(box)
    focusLabel.text("焦点：未设置")
    g.onFocus {
        w => match (w) {
            case Some(_) => focusLabel.text("焦点：已切换（回调收到 Widget）")
            case None => focusLabel.text("焦点：无")
        }
    }

    let r2 = row(box, 46, gap: 12)
    let prev = Button(r2)
    prev.size(130, 40)
    let prevL = Label(prev)
    prevL.text("上一个焦点")
    prevL.center()
    prev.onClick {
        => g.focusPrev()
    }
    let next = Button(r2)
    next.size(130, 40)
    let nextL = Label(next)
    nextL.text("下一个焦点")
    nextL.center()
    next.onClick {
        => g.focusNext()
    }

    let wrapBtn = Button(r2)
    wrapBtn.size(150, 40)
    let wrapL = Label(wrapBtn)
    wrapL.text("切换 wrap")
    wrapL.center()
    let wrapOn = Counter(1)
    wrapBtn.onClick {
        =>
            wrapOn.value = 1 - wrapOn.value
            g.setWrap(wrapOn.value == 1)
    }
    g.setWrap(true)
    g.focus(btns[0])
}

/* ==================== 6. 动画 ==================== */

private func showcaseAnim(box: Widget): Unit {
    caption(box, "Anim：translateX 从 -120 到 560 像素来回（playback），可暂停/继续/取消")

    let track = bareBox(box, 760, 92)
    track.setStyleBgOpa(0)
    let moving = block(track, 64, 64, 0x7E, 0x57, 0xC2)
    moving.align(LV_ALIGN_LEFT_MID)

    let handle = Anim
        .create()
        .exec {
            v => moving.setStyleTranslateX(v)
        }
        .from(-120)
        .to(560)
        .duration(1200)
        .easing(Easing.EASE_IN_OUT)
        .loop()
        .playback(900)
        .start()

    let r = row(box, 46, gap: 12)
    let pBtn = Button(r)
    pBtn.size(110, 40)
    let pL = Label(pBtn)
    pL.text("暂停")
    pL.center()
    pBtn.onClick {
        => handle.pause()
    }
    let rBtn = Button(r)
    rBtn.size(110, 40)
    let rL = Label(rBtn)
    rL.text("继续")
    rL.center()
    rBtn.onClick {
        => handle.resume()
    }
    let cBtn = Button(r)
    cBtn.size(110, 40)
    let cL = Label(cBtn)
    cL.text("取消")
    cL.center()
    cBtn.onClick {
        => if (handle.isRunning()) {
            handle.cancel()
        }
    }

    // Timeline：两段动画按时间轴先后播放
    caption(box, "Timeline：两段动画依次播放（0ms / 700ms）")
    let tlTrack = bareBox(box, 760, 70)
    tlTrack.setStyleBgOpa(0)
    let t1 = block(tlTrack, 48, 48, 0x42, 0xA5, 0xF5)
    t1.align(LV_ALIGN_LEFT_MID)
    let t2 = block(tlTrack, 48, 48, 0xEF, 0x53, 0x50)
    t2.align(LV_ALIGN_LEFT_MID)
    let tl = Timeline.create()
    tl.add(
        Anim.create().exec {
            v => t1.setStyleTranslateX(v)
        }.from(0).to(320).duration(700),
        at: 0
    )
    tl.add(
        Anim.create().exec {
            v => t2.setStyleTranslateX(v)
        }.from(0).to(320).duration(700).easing(Easing.BOUNCE),
        at: 700
    )
    tl.start()
}

/* ==================== 7. 绘图与图表 ==================== */

private func showcaseDraw(box: Widget): Unit {
    caption(box, "Canvas：定时器每 80ms 画一条正弦波（fillBg + setPx）")
    let r1 = row(box, 170, gap: 12)

    let canvas = Canvas(r1, 360, 150)
    let phase = Counter(0)
    Timer.every(80) {
        =>
            phase.value += 1
            canvas.fillBg(0x10, 0x14, 0x18)
            var x: Int32 = 0
            while (x < 360) {
                let y = 75 + Int32(60.0 * sin(Float64(x) / 26.0 + Float64(phase.value) * 0.25))
                canvas.setPx(x, y, UInt8(0x4E), UInt8(0xC9), UInt8(0xE8))
                if (y + 1 < 150) {
                    canvas.setPx(x, y + 1, UInt8(0x2A), UInt8(0x7A), UInt8(0x8E))
                }
                x += 1
            }
            canvas.drawText(8, 6, 200, "waveform", uiFont(), 0x9A, 0xA0, 0xA6)
    }

    // Image / ImageBuffer：现场生成一张渐变图
    let iw: Int32 = 160
    let ih: Int32 = 120
    let buf = ImageBuffer(iw, ih, LV_COLOR_FORMAT_RGB565)
    let px = Array<UInt8>(Int64(iw * ih * 2), repeat: 0)
    var i: Int32 = 0
    while (i < ih) {
        var j: Int32 = 0
        while (j < iw) {
            let c = Color.rgb565(UInt8(255 - i * 2), UInt8(i * 2), UInt8(j))
            let idx = (i * iw + j) * 2
            px[Int64(idx)] = UInt8(c & 0xFF)
            px[Int64(idx) + 1] = UInt8((c >> 8) & 0xFF)
            j += 1
        }
        i += 1
    }
    buf.writePixels(px)
    let img = Image(r1)
    img.size(160, 120)
    img.setSource(buf.toImageDsc())

    let col = Container(r1)
    col.size(200, 160)
    col.flex(FlexFlow.COLUMN, gap: 8)
    let line = Line(col)
    line.size(190, 90)
    line.setPoints([(0, 80), (30, 20), (60, 70), (90, 10), (120, 60), (150, 30), (185, 85)])
    let scale = Scale(col)
    scale.size(190, 14)
    scale.range(0, 100)
    caption(col, "Line / Scale")
}

private func showcaseChart(box: Widget): Unit {
    caption(box, "Chart：两条曲线，Timer 每 180ms 推一个点（pointCount 决定可见点数）")

    let r = row(box, 200, gap: 12)
    let chart = Chart(r)
    chart.size(380, 190)
    chart.pointCount(40)
    chart.range(0, 0, 100)
    let s1 = chart.addSeries(0x42, 0xA5, 0xF5)
    let s2 = chart.addSeries(0xFF, 0x70, 0x43)
    let tick = Counter(0)
    Timer.every(180) {
        =>
            tick.value += 1
            chart.setNextValue(s1, Int32(50.0 + 40.0 * sin(Float64(tick.value) * 0.22)))
            chart.setNextValue(s2, Int32(50.0 + 30.0 * sin(Float64(tick.value) * 0.13 + 1.7)))
    }

    let right = Container(r)
    right.size(360, 190)
    right.flex(FlexFlow.COLUMN, gap: 10)
    let table = Table(right)
    table.size(350, 110)
    table.cellValue(0, 0, "控件")
    table.cellValue(0, 1, "覆盖")
    table.cellValue(1, 0, "Chart")
    table.cellValue(1, 1, "双序列滚动")
    table.cellValue(2, 0, "Table")
    table.cellValue(2, 1, "单元格赋值")
    let list = List(right)
    list.size(350, 70)
    let _ = list.addText("List：分组标题")
    let li = list.addButton("List：可点条目")
    li.onClick {
        => println("[showcase] List 条目被点击")
    }
}

/* ==================== 8. 富文本、日历与浮层 ==================== */

private func showcaseRich(disp: Display, box: Widget): Unit {
    caption(box, "SpanGroup：同一段文字里混排不同颜色/字号；Calendar：高亮今天与几个日期")
    let r1 = row(box, 130, gap: 16)

    let span = SpanGroup(r1)
    span.size(420, 120)
    let p1 = span.add("lvglcj ")
    p1.style(Style().textColor(0x4E, 0xC9, 0xE8).textFont(uiFont()))
    let p2 = span.add("全功能")
    p2.style(Style().textColor(0xFF, 0x70, 0x43).textFont(uiFont()))
    let p3 = span.add(" 演示：样式、绑定、动画、绘图一次看全。")
    p3.style(Style().textColor(0xE0, 0xE0, 0xE0).textFont(uiFont()))
    span.textAlign(LV_TEXT_ALIGN_LEFT)

    let cal = Calendar(r1)
    cal.size(280, 130)
    cal.headerArrow()
    cal.today(2026, 11, 1)
    cal.showMonth(2026, 11)
    cal.highlight([(2026, 11, 1), (2026, 11, 11), (2026, 11, 26)])
    cal.onPressed {
        y, m, d => println("[showcase] 日历选中 ${y}-${m}-${d}")
    }

    caption(box, "AnimImage：4 帧 RGB565 现场生成；浮层：top 层弹通知条，bottom 层放水印，Win 演示带标题的窗口")
    let r2 = row(box, 120, gap: 16)

    let frames = ArrayList<ImageDsc>()
    var f = 0
    while (f < 4) {
        let b = ImageBuffer(72, 72, LV_COLOR_FORMAT_RGB565)
        let fpx = Array<UInt8>(Int64(72 * 72 * 2), repeat: 0)
        var y = 0
        while (y < 72) {
            var x = 0
            while (x < 72) {
                let radius = 12 + f * 6
                let on = ((x - 36) * (x - 36) + (y - 36) * (y - 36)) < radius * radius
                let c = if (on) {
                    Color.rgb565(UInt8(0x4E), UInt8(0xC9), UInt8(0xE8))
                } else {
                    Color.rgb565(UInt8(0x20), UInt8(0x24), UInt8(0x2C))
                }
                let idx = (y * 72 + x) * 2
                fpx[Int64(idx)] = UInt8(c & 0xFF)
                fpx[Int64(idx) + 1] = UInt8((c >> 8) & 0xFF)
                x += 1
            }
            y += 1
        }
        b.writePixels(fpx)
        frames.add(b.toImageDsc())
        f += 1
    }
    let animImg = AnimImage(r2)
    animImg.size(72, 72)
    animImg.frames(frames.toArray(), durationMs: 500)
    animImg.repeatCount(LV_ANIM_REPEAT_INFINITE)
    animImg.start()

    let win = Win(r2)
    win.size(300, 110)
    let _ = win.addTitle("Win 窗口")
    let winBody = Label(win)
    winBody.text("带标题栏的窗口容器")
    winBody.align(LV_ALIGN_CENTER, dy: 8)

    let toastBtn = Button(r2)
    toastBtn.size(160, 44)
    let toastL = Label(toastBtn)
    toastL.text("弹浮层通知")
    toastL.center()
    toastBtn.onClick {
        =>
            let toast = Container(disp.top())
            toast.size(260, 44)
            toast.align(LV_ALIGN_TOP_MID, dy: 12)
            toast.setStyleBgColor(0x26, 0x32, 0x38)
            toast.setStyleRadius(22)
            toast.setStyleBorderWidth(1)
            toast.setStyleBorderColor(0x4E, 0xC9, 0xE8)
            let tl = Label(toast)
            tl.text("来自 top 层的通知")
            tl.center()
            Timer.once(1600) {
                => toast.delete()
            }
    }

    // bottom 层：常驻水印，不影响任何控件
    let mark = Label(disp.bottom())
    mark.text("lvglcj · 全功能演示")
    mark.align(LV_ALIGN_BOTTOM_LEFT, dx: 8, dy: -4)
    mark.setStyleTextColor(0x55, 0x5A, 0x60)
}

/* ==================== 入口 ==================== */

/**
 * `./main all`：全功能演示。
 *
 * 8 个标签页，覆盖公开 API 的绝大部分；状态类回调都用 `Counter` 持有。
 */
func demoShowcase(): Unit {
    let disp = createDisplay(w: 800, h: 480)
    let scr = disp.screen()

    let tv = TabView(scr)
    tv.size(800, 480)

    // 键盘挂在 screen 上（浮在所有标签页之上），默认隐藏：
    // 点文本域或点「软键盘」按钮才弹出，点键盘的 ✓ / ✕ 收起。
    let kb = Keyboard(scr)
    kb.size(760, 200)
    kb.align(LV_ALIGN_BOTTOM_MID, dx: 0, dy: -8)
    kb.addFlag(LV_OBJ_FLAG_HIDDEN)

    let kbState = KbState(false)
    showcaseWidgets(page(tv, "控件"), kb, kbState)
    // 切标签页时收起键盘，免得它盖住别的页面
    tv.on(LV_EVENT_VALUE_CHANGED) {_ => setKeyboardVisible(kb, kbState, false)}
    showcaseLayout(page(tv, "布局"))
    showcaseStyles(page(tv, "样式"))
    showcaseBinding(page(tv, "绑定"))
    showcaseGroup(page(tv, "焦点组"))
    showcaseAnim(page(tv, "动画"))
    showcaseDraw(page(tv, "绘图"))
    showcaseChart(page(tv, "图表"))
    showcaseRich(disp, page(tv, "富文本"))

    App.run(idleMs: 5)
}
