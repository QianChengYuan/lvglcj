/**
 * lvglcj 示例：hello / widgets / touch / image / canvas / perf
 *
 * 用法：
 *   ./main hello      # 最小窗口
 *   ./main widgets    # 控件总览
 *   ./main touch      # 触摸/指针 + 校准
 *   ./main image      # RGB565 像素缓冲直出
 *   ./main canvas     # 自绘仪表
 *   ./main perf       # FPS / CPU / 内存
 *
 * 后端选择：优先 DRM/KMS（真机），失败回退 SDL 窗口（WSL/桌面）。
 */
package lvglcj_examples

import lvglcj.*
import std.collection.*
import std.math.*

/** 打开显示：真机走 DRM，WSL/无 DRM 环境回退 SDL */
func openDisplay(w: Int32, h: Int32): Display {
    try {
        return Display.drm()
    } catch (e: LvglException) {
        println("[lvglcj] DRM 不可用，回退 SDL 窗口：${e.message}")
    }
    Display.sdl(w, h)
}

/** 演示统一使用的字体（createDisplay 时确定；Canvas 自绘等需要显式传字体的地方用它） */
private var demoFont: Option<Font> = None

func uiFont(): Font {
    match (demoFont) {
        case Some(f) => f
        case None => Font.defaultFont()
    }
}

/**
 * 创建显示 + 换中文字体。
 * 内置思源黑体子集只有 1338 字，完整中文界面用系统的 TTF/TTC（FreeType 加载）。
 * 注意：默认主题会显式给控件设置 text_font，只在 Screen 上挂样式覆盖不了，
 * 必须用主题字体；加载不到就退回 LV_FONT_DEFAULT，保证演示不中断。
 */
func createDisplay(w!: Int32 = 480, h!: Int32 = 272): Display {
    let disp = openDisplay(w, h)
    // LV_USE_PERF_MONITOR=1 时 display 一创建就带右下角 FPS/CPU 小字，演示里默认藏掉；
    // 想看就调 Perf.showMonitor()。
    Perf.hideMonitor(disp: Some(disp))
    let font = match (Font.trySystemCjk(size: 16)) {
        case Some(f) =>
            // 系统 CJK 字体可能只含汉字（树莓派的 DroidSansFallbackFull 就没有拉丁字母），
            // 把 Montserrat 挂成缺字回退，否则 "LVGL 9.5" 会渲染成一排方框。
            f.setFallback(Font.montserrat(16))
        case None =>
            println("[lvglcj] 未找到系统中文字体，使用内置思源黑体子集")
            Font.defaultFont()
    }
    demoFont = Some(font)
    Theme.default((0x1E, 0x88, 0xE5), (0x0F, 0x9D, 0x58), false, font)
    disp.screen().setFont(font)
    disp
}

/**
 * 可变单元格：仓颉闭包一旦作为 C 回调（CFunc）注册，就不能捕获可变变量，
 * 需要用引用类型（class）持有回调内要修改的状态。
 */
private class Cell<T> {
    var value: T
    init(value: T) {
        this.value = value
    }
}

func demoHello(): Unit {
    let disp = createDisplay()
    let scr = disp.screen()
    let label = Label(scr)
    label.text("你好，LVGL ${version()} + 仓颉")
    label.center()
    App.run()
}

func demoWidgets(): Unit {
    let disp = createDisplay()
    let scr = disp.screen()

    let title = Label(scr)
    title.text("控件总览")
    title.align(LV_ALIGN_TOP_MID, dx: 0, dy: 8)

    // 按钮 + 点击计数（仓颉闭包直接作事件回调）
    let btn = Button(scr)
    btn.size(130, 40)
    btn.align(LV_ALIGN_TOP_LEFT, dx: 16, dy: 40)
    let btnLabel = Label(btn)
    btnLabel.text("点我")
    btnLabel.center()
    let clicks: Int32 = 0
    let clickCell = Cell<Int32>(clicks)
    btn.onClick {
        =>
            clickCell.value += 1
            btnLabel.setTextFmt("点击 %d 次", clickCell.value)
    }

    // 滑块
    let slider = Slider(scr)
    slider.size(200, 16)
    slider.align(LV_ALIGN_LEFT_MID, dx: 16, dy: -30)
    slider.range(0, 100)
    slider.value(35)
    let sliderLabel = Label(scr)
    sliderLabel.align(LV_ALIGN_LEFT_MID, dx: 16, dy: -6)
    sliderLabel.text("滑块：35")
    slider.onEvent(LV_EVENT_VALUE_CHANGED) {
        _ => sliderLabel.setTextFmt("滑块：%d", slider.valueGet())
    }

    // 开关 / 复选框 / 进度条 / 圆弧 / LED
    let sw = Switch(scr)
    sw.align(LV_ALIGN_LEFT_MID, dx: 16, dy: 20)
    let swLabel = Label(scr)
    swLabel.align(LV_ALIGN_LEFT_MID, dx: 70, dy: 22)
    swLabel.text("开关：关")
    sw.onEvent(LV_EVENT_VALUE_CHANGED) {
        _ => swLabel.text(if (sw.isChecked()) {
            "开关：开"
        } else {
            "开关：关"
        })
    }

    let cb = Checkbox(scr)
    cb.text("复选框")
    cb.align(LV_ALIGN_LEFT_MID, dx: 16, dy: 50)
    cb.setChecked(true)

    let bar = Bar(scr)
    bar.size(140, 14)
    bar.align(LV_ALIGN_RIGHT_MID, dx: -16, dy: -30)
    bar.range(0, 100)
    bar.value(60)

    let arc = Arc(scr)
    arc.size(80, 80)
    arc.align(LV_ALIGN_RIGHT_MID, dx: -60, dy: 20)
    arc.angles(0, 270)
    arc.value(65)

    let led = Led(scr)
    led.align(LV_ALIGN_RIGHT_MID, dx: -16, dy: 40)
    led.color(80, 220, 120)
    led.on()

    App.run()
}

func demoTouch(): Unit {
    let disp = createDisplay()
    let scr = disp.screen()

    let title = Label(scr)
    title.text("触摸 / 指针设备")
    title.align(LV_ALIGN_TOP_MID, dx: 0, dy: 8)

    let hint = Label(scr)
    hint.text("校准：Input.calibrate(minX,minY,maxX,maxY)\n轴向反了：swapAxes(true)")
    hint.align(LV_ALIGN_CENTER, dx: 0, dy: 30)

    // Pi 上按实际设备节点修改（ls /dev/input/eventX）
    try {
        let touch = Input.evdev(LV_INDEV_TYPE_POINTER, "/dev/input/event0")
        touch.attach(disp)
        println("[lvglcj] evdev 已接入：/dev/input/event0")
    } catch (e: LvglException) {
        println("[lvglcj] evdev 不可用（SDL 环境用鼠标即可）：${e.message}")
    }

    // 指针位置标记：每 50ms 轮询一次当前输入点（Input.activePoint）
    let marker = Container(scr)
    marker.size(16, 16)
    marker.setStyleBgColor(255, 80, 80)
    Timer.every(50) {
        => match (Input.activePoint()) {
            case Some(p) => marker.pos(p[0] - 8, p[1] - 8)
            case None => ()
        }
    }

    App.run()
}

func demoImage(): Unit {
    let disp = createDisplay()
    let scr = disp.screen()

    let w: Int32 = 160
    let h: Int32 = 120
    let buf = ImageBuffer(w, h, LV_COLOR_FORMAT_RGB565)

    // 横向渐变：每像素 2 字节，小端 RGB565 字面量（Color.rgb565 直接产出）
    let pixelCount = Int64(w) * Int64(h)
    let bytes: Array<UInt8> = Array<UInt8>(pixelCount * 2, repeat: 0)
    var y: Int32 = 0
    while (y < h) {
        var x: Int32 = 0
        while (x < w) {
            let r = UInt8((Int64(x) * 255 / Int64(w)) & 0xFF)
            let g = UInt8((Int64(y) * 255 / Int64(h)) & 0xFF)
            let c = Color.rgb565(r, g, 128)
            let idx = (Int64(y) * Int64(w) + Int64(x)) * 2
            bytes[idx] = UInt8(c & 0xFF)
            bytes[idx + 1] = UInt8((c >> 8) & 0xFF)
            x += 1
        }
        y += 1
    }
    buf.writePixels(bytes)

    let img = Image(scr)
    img.setSource(buf.toImageDsc())
    img.center()

    let caption = Label(scr)
    caption.text("ImageBuffer → lv_image_dsc_t（RGB565 直出）")
    caption.align(LV_ALIGN_BOTTOM_MID, dx: 0, dy: -12)

    App.run()
}

func demoCanvas(): Unit {
    let disp = createDisplay()
    let scr = disp.screen()

    let cv = Canvas(scr, 220, 130)
    cv.align(LV_ALIGN_CENTER, dx: 0, dy: -16)
    cv.fillBg(20, 24, 32)
    cv.drawText(8, 6, 200, "自绘仪表（Canvas）", uiFont(), 240, 240, 240)

    // 动态条形 + 波形点（level/dir 为回调内修改的状态，用 Cell 持有）
    let level = Cell<Int32>(0)
    let dir = Cell<Int32>(1)
    Timer.every(50) {
        =>
            cv.drawRect(8, 60, 204, 22, 40, 44, 52)
            let fillW = level.value * 204 / 100
            cv.drawRect(8, 60, fillW, 22, 80, 200, 120)
            var i: Int32 = 0
            while (i < 204) {
                let v = (i * 7 + level.value * 3) % 30
                cv.setPx(8 + i, 50 - v, 255, 200, 60)
                i += 2
            }
            level.value += dir.value * 4
            if (level.value >= 100) {
                level.value = 100
                dir.value = -1
            }
            if (level.value <= 0) {
                level.value = 0
                dir.value = 1
            }
    }

    let caption = Label(scr)
    caption.text("fillBg / drawRect / drawText / setPx")
    caption.align(LV_ALIGN_BOTTOM_MID, dx: 0, dy: -12)

    App.run()
}

func demoPerf(): Unit {
    let disp = createDisplay()
    let scr = disp.screen()

    let title = Label(scr)
    title.text("性能监视器（需 LV_USE_PERF_MONITOR / LV_USE_MEM_MONITOR）")
    title.align(LV_ALIGN_TOP_MID, dx: 0, dy: 8)

    let stat = Label(scr)
    stat.align(LV_ALIGN_CENTER)

    // 制造一点负载，让曲线动起来（phase 用 Cell 持有）
    let phase = Cell<Float64>(0.0)
    let load = Bar(scr)
    load.size(200, 14)
    load.align(LV_ALIGN_CENTER, dx: 0, dy: 40)
    load.range(0, 100)

    Timer.every(500) {
        =>
            let m = Mem.monitor()
            let usedKb = m.usedSize / 1024
            let totalKb = m.totalSize / 1024
            stat.text(
                "FPS ${Perf.fps()} | CPU ${Perf.cpu()}% | 内存 ${usedKb}/${totalKb} KB (${m.usedPct}% 已用, 碎片 ${m.fragPct}%)")
            phase.value += 0.5
            load.value(Int32(50.0 + 45.0 * sin(phase.value)), anim: false)
    }

    App.run()
}

/**
 * 富文本 / 日历 / 帧动画（SpanGroup / Calendar / AnimImage）。
 * 同屏验证三件事：① 一行内混排不同颜色字体；② 日历今天高亮；③ 现场生成 8 帧渐变动画。
 */
func demoRich(): Unit {
    // 三个控件同屏，窗口取 640x420（其余演示仍用默认 480x272）
    let disp = createDisplay(w: 640, h: 420)
    let scr = disp.screen()
    let font = uiFont()

    let title = Label(scr)
    title.text("富文本 / 日历 / 帧动画")
    title.align(LV_ALIGN_TOP_MID, dx: 0, dy: 6)

    // ① SpanGroup：片段样式必须由调用方保活（LVGL 只存指针）
    let warn = Style().textColor(0xE5, 0x3E, 0x3E).textFont(font)
    let normal = Style().textColor(0x55, 0x55, 0x55).textFont(font)
    let sg = SpanGroup(scr)
    sg.add("警告：").style(warn)
    sg.add("磁盘剩余 12%，请及时清理").style(normal)
    sg.size(600, 44)
    sg.mode(LV_SPAN_MODE_BREAK)
    sg.align(LV_ALIGN_TOP_LEFT, dx: 20, dy: 36)

    // ② Calendar：显示 2026 年 10 月，今天（10-24）高亮；
    //    9.5 的日历默认不带年月头部，要自己加（arrow = 左右箭头翻月）
    let cal = Calendar(scr)
    cal.size(260, 230)
    cal.align(LV_ALIGN_BOTTOM_LEFT, dx: 20, dy: -16)
    cal.headerArrow()
    cal.today(2026, 10, 24)
    cal.showMonth(2026, 10)

    // ③ AnimImage：ImageBuffer 现场生成 8 帧 RGB565 色块
    let w: Int32 = 90
    let h: Int32 = 90
    let buffers = ArrayList<ImageBuffer>()
    let dscs = ArrayList<ImageDsc>()
    var i: Int32 = 0
    while (i < 8) {
        let buf = ImageBuffer(w, h, LV_COLOR_FORMAT_RGB565)
        let px = Array<UInt8>(Int64(w) * Int64(h) * 2, repeat: 0)
        var y: Int32 = 0
        while (y < h) {
            var x: Int32 = 0
            while (x < w) {
                let c = Color.rgb565(UInt8((i * 30) % 256), UInt8((x * 2) % 256), UInt8((y * 2) % 256))
                let idx = (Int64(y) * Int64(w) + Int64(x)) * 2
                px[idx] = UInt8(c & 0xFF)
                px[idx + 1] = UInt8((c >> 8) & 0xFF)
                x += 1
            }
            y += 1
        }
        buf.writePixels(px)
        buffers.add(buf)
        dscs.add(buf.toImageDsc())
        i += 1
    }
    let anim = AnimImage(scr)
    anim.frames(dscs.toArray(), durationMs: 800)
    anim.repeatCount(LV_ANIM_REPEAT_INFINITE)
    anim.start()
    // 右上角留出 perf 监控标签的位置（它在右下角），故动画放右中偏上
    anim.align(LV_ALIGN_RIGHT_MID, dx: -40, dy: -40)

    App.run()
}

/**
 * 从图片文件加载（Image.fromFile）：需要静态库编入解码器 + FS 驱动
 * （本仓库三平台产物已打开 LV_USE_LODEPNG + LV_USE_FS_STDIO，支持 PNG）。
 */
func demoFile(path: String): Unit {
    let disp = createDisplay()
    let scr = disp.screen()

    // 标题限定宽度 + 超长省略，避免长路径把窗口撑破
    let title = Label(scr)
    title.text("Image.fromFile：${path}")
    title.size(scr.width() - 24, 40)
    title.longMode(LV_LABEL_LONG_MODE_DOTS)
    title.align(LV_ALIGN_TOP_MID, dx: 0, dy: 6)

    let img = Image.fromFile(scr, path)
    img.align(LV_ALIGN_CENTER, dx: 0, dy: 14)

    App.run()
}

func usage(): Unit {
    println("用法：main <demo>")
    println("  hello | widgets | touch | image | canvas | perf | rich")
    println("  file <png路径>      # 从图片文件加载（Image.fromFile）")
}

main(args: Array<String>): Unit {
    if (args.size < 1) {
        usage()
        return
    }
    App.setup()
    println("[lvglcj] LVGL ${version()}，演示：${args[0]}")
    match (args[0]) {
        case "hello" => demoHello()
        case "widgets" => demoWidgets()
        case "touch" => demoTouch()
        case "image" => demoImage()
        case "canvas" => demoCanvas()
        case "perf" => demoPerf()
        case "rich" => demoRich()
        case "file" =>
            if (args.size < 2) {
                println("用法：main file <png路径>")
            } else {
                demoFile(args[1])
            }
        case _ =>
            println("未知演示：${args[0]}")
            usage()
    }
    App.shutdown()
}
