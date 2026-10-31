/**
 * widget*.cj / display.cj —— 需要 display 与屏幕的用例。
 *
 * 全部打了 @Tag[requires_display]，cjpm.toml 的 [profile.test] 默认排除它们，
 * 这样本地 cjpm test 不会弹窗、无图形环境的机器也不会整片 ERROR。
 *
 * 想跑必须**同时**顶掉配置里的排除项（只加 --include-tags 是无效的）：
 *
 *   cjpm test --include-tags=requires_display --exclude-tags=notag
 *
 * 默认走 SDL dummy 视频驱动（在内存里建 display，绘制路径照常执行，**不弹窗口**）——
 * 测试进程没有 SDL 事件循环，真窗口会一直"无响应"，人工点掉后 display 失效，
 * 后面的用例会连带失败。确实想看画面时：
 *
 *   LVGLCJ_TEST_REAL_WINDOW=1 cjpm test --include-tags=requires_display --exclude-tags=notag
 *
 * 等价入口：scripts/build.ps1 -DisplayTests / scripts/build.sh --display-tests。
 *
 * @BeforeAll 里创建 SDL 显示失败只记录原因、不中断整个测试进程（此时 screen()
 * 抛异常，这些用例会单独失败而不是把进程带崩）。注意它只 catch LvglException，
 * C 侧直接 abort/段错误是兜不住的 —— 这也是默认不启用它们的另一半理由。
 */
package lvglcj.test

import lvglcj.*
import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

// 测试类由 @Test/@TestCase 宏展开，展开出来的跑测函数无需（也无法）写 @throws 文档
@Test // cjlint-ignore !G.ERR.01 宏展开生成的测试入口，异常由测试框架处理
class WidgetTests {
    static var scr: Option<Screen> = None
    static var eventCount: Int32 = 0
    static var selfCount: Int32 = 0
    static var bubbleCount: Int32 = 0
    static var eventError: String = ""

    @BeforeAll
    static func setupDisplay() {
        ensureLvglInit()
        try {
            // 与其他测试类共用同一个 display：各自 Display.sdl() 会并发初始化 SDL，
            // 偶发 @BeforeAll 卡 40s 后整类用例不跑。
            scr = Some(ensureSdlScreen())
        } catch (e: LvglException) {
            // 无头环境（CI）无法创建 SDL 窗口。本类的用例都带 requires_display，
            // 默认已被 [profile.test] 的 exclude-tags 排除，因此这里不能拖垮整个测试进程。
            let _ = e.message
        }
    }

    private static func screen(): Screen {
        match (scr) {
            case Some(s) => s
            case None => throw LvglException("测试屏幕未初始化")
        }
    }

    /**
     * 几何：设置后能读回。
     * 注意 LVGL 的 coords 要经过一次布局计算才会更新（set_size 之后立刻 get_width 是 0），
     * 所以先 App.runOnce() 泵一次 timer，让 layout 跑完再断言。
     */
    @Tag[requires_display]
    @TestCase
    func testWidgetGeometry() {
        let box = Container(screen())
        box.size(120, 40)
        App.runOnce()
        @Expect(box.width(), 120)
        @Expect(box.height(), 40)
        box.finalize()
    }

    /** Label.setTextFmt 是仓颉侧做的 %d 替换，参数个数不足时不能崩 */
    @Tag[requires_display]
    @TestCase
    func testLabelTextAndFormat() {
        let label = Label(screen())
        label.text("你好")
        label.setTextFmt("滑块：%d", [35])
        label.setTextFmt("计数 %d / %d", [1, 2])
        // 参数少于占位符时保留原样，不崩即可
        label.setTextFmt("缺参数 %d %d", [7])
        label.finalize()
        @Expect(true)
    }

    /** Slider 的 range/value/valueGet 往返一致 */
    @Tag[requires_display]
    @TestCase
    func testSliderValueRoundTrip() {
        let slider = Slider(screen())
        slider.range(0, 100)
        slider.value(42, anim: false)
        @Expect(slider.valueGet(), 42)
        // 超出范围会被钳到上界
        slider.value(500, anim: false)
        @Expect(slider.valueGet(), 100)
        slider.finalize()
    }

    /** Button.checkable + 状态位 */
    @Tag[requires_display]
    @TestCase
    func testButtonCheckableFlag() {
        let btn = Button(screen())
        @Expect(btn.hasFlag(LV_OBJ_FLAG_CHECKABLE), false)
        btn.checkable()
        @Expect(btn.hasFlag(LV_OBJ_FLAG_CHECKABLE), true)
        btn.addState(LV_STATE_CHECKED)
        @Expect(btn.hasFlag(LV_OBJ_FLAG_HIDDEN), false)
        btn.finalize()
    }

    /** 事件订阅、手动触发、取消与对象删除后的自动失效 */
    @Tag[requires_display]
    @TestCase
    func testEventSubscriptionLifecycle() {
        eventCount = 0
        let btn = Button(screen())
        let sub = btn.onEvent(LV_EVENT_CLICKED) {_ => eventCount += 1}
        @Expect(sub.isActive(), true)

        btn.sendEvent(LV_EVENT_CLICKED)
        @Expect(eventCount, 1)

        sub.cancel()
        sub.cancel()
        @Expect(sub.isActive(), false)
        btn.sendEvent(LV_EVENT_CLICKED)
        @Expect(eventCount, 1)

        let sub2 = btn.onEvent(LV_EVENT_CLICKED) {_ => eventCount += 1}
        btn.finalize()
        @Expect(sub2.isActive(), false)
        @Expect(btn.isDeleted(), true)
        // 幂等：重复 finalize 不能再碰已释放的 C 指针
        btn.finalize()
        @Expect(eventCount, 1)
    }

    /** on(code) 只收精确匹配的事件码，不做全量分发 */
    @Tag[requires_display]
    @TestCase
    func testOnReceivesOnlyExactCode() {
        selfCount = 0
        let btn = Button(screen())
        let sub = btn.on(LV_EVENT_VALUE_CHANGED) {_ => selfCount += 1}
        btn.sendEvent(LV_EVENT_CLICKED)
        @Expect(selfCount, 0)
        btn.sendEvent(LV_EVENT_VALUE_CHANGED)
        @Expect(selfCount, 1)
        sub.cancel()
        btn.finalize()
        @Expect(true)
    }

    /**
     * on 与 onBubbled 互斥：
     * - 子对象冒泡上来的事件**不**触发父对象上的 on；
     * - 父对象自己发出的事件**不**触发它自己的 onBubbled。
     */
    @Tag[requires_display]
    @TestCase
    func testOnAndOnBubbledAreMutuallyExclusive() {
        selfCount = 0
        bubbleCount = 0
        let root = Container(screen())
        let child = Button(root)
        child.bubble()
        let s1 = root.on(LV_EVENT_CLICKED) {_ => selfCount += 1}
        let s2 = root.onBubbled(LV_EVENT_CLICKED) {_ => bubbleCount += 1}

        child.sendEvent(LV_EVENT_CLICKED) // 冒泡上来
        @Expect(selfCount, 0)
        @Expect(bubbleCount, 1)

        root.sendEvent(LV_EVENT_CLICKED) // 自己发出
        @Expect(selfCount, 1)
        @Expect(bubbleCount, 1)

        s1.cancel()
        s2.cancel()
        root.close() // 递归删除子对象
        @Expect(true)
    }

    /** 没开 EVENT_BUBBLE 的子对象，事件不会传到父对象 */
    @Tag[requires_display]
    @TestCase
    func testBubbleRequiresFlag() {
        bubbleCount = 0
        let root = Container(screen())
        let child = Button(root)
        let sub = root.onBubbled(LV_EVENT_CLICKED) {_ => bubbleCount += 1}

        child.sendEvent(LV_EVENT_CLICKED)
        @Expect(bubbleCount, 0)

        child.bubble()
        @Expect(child.hasFlag(LV_OBJ_FLAG_EVENT_BUBBLE), true)
        child.sendEvent(LV_EVENT_CLICKED)
        @Expect(bubbleCount, 1)

        child.bubble(on: false)
        @Expect(child.hasFlag(LV_OBJ_FLAG_EVENT_BUBBLE), false)
        child.sendEvent(LV_EVENT_CLICKED)
        @Expect(bubbleCount, 1)

        sub.cancel()
        root.close()
        @Expect(true)
    }

    /** 控件回调抛异常时交给 App.onCallbackError，不跨 C 边界传播 */
    @Tag[requires_display]
    @TestCase
    func testEventCallbackErrorIsReported() {
        eventError = ""
        App.onCallbackError {e => eventError = e.message}
        let btn = Button(screen())
        let sub = btn.onEvent(LV_EVENT_CLICKED) {
            _ => throw LvglException("event boom")
        }
        btn.sendEvent(LV_EVENT_CLICKED)
        App.clearCallbackErrorHandler()
        sub.cancel()
        btn.finalize()
        @Expect(eventError, "event boom")
    }

    /** Event.target() 是借用视图，调用 finalize() 必须被拒绝 */
    @Tag[requires_display]
    @TestCase
    func testEventTargetIsBorrowedView() {
        eventError = ""
        let btn = Button(screen())
        let sub = btn.onEvent(LV_EVENT_CLICKED) {
            e => try {
                e.target().finalize()
            } catch (err: LvglException) {
                eventError = err.message
            }
        }
        btn.sendEvent(LV_EVENT_CLICKED)
        sub.cancel()
        btn.finalize()
        @Expect(eventError, "该 Widget 是借用视图，不能释放")
    }

    /** Canvas 绘制 API 全部走通（RGB565 缓冲 + 中文文本） */
    @Tag[requires_display]
    @TestCase
    func testCanvasDrawing() {
        // 不用 `?? Font.defaultFont()`：`??` 右侧带副作用的调用会被 cjlint G.EXP.03 判为不规范
        let font = match (Font.trySystemCjk(size: 16)) {
            case Some(f) => f
            case None => Font.defaultFont()
        }
        let canvas = Canvas(screen(), 100, 60)
        canvas.fillBg(0x10, 0x18, 0x20)
        canvas.drawRect(4, 4, 40, 10, 0x1E, 0x88, 0xE5, radius: 3)
        canvas.drawText(4, 20, 90, "仪表", font, 0xF0, 0xF0, 0xF0)
        canvas.setPx(1, 1, 0xFF, 0x00, 0x00)
        canvas.invalidate()
        canvas.finalize()
        @Expect(true)
    }

    /** Theme.default 需要已存在的 display，正常路径不应抛 */
    @Tag[requires_display]
    @TestCase
    func testThemeApplies() {
        // 不用 `?? Font.defaultFont()`：`??` 右侧带副作用的调用会被 cjlint G.EXP.03 判为不规范
        let font = match (Font.trySystemCjk(size: 16)) {
            case Some(f) => f
            case None => Font.defaultFont()
        }
        Theme.default((0x1E, 0x88, 0xE5), (0x0F, 0x9D, 0x58), false, font)
        screen().setFont(font)
        @Expect(true)
    }

    /* ---------------- 新增控件：span / calendar / animimg ---------------- */

    /** SpanGroup：片段计数、样式、各类排版属性都要走通 */
    @Tag[requires_display]
    @TestCase
    func testSpanGroupRichText() {
        let sg = SpanGroup(screen())
        let warn = Style().textColor(0xFF, 0x50, 0x50)
        sg.add("警告：").style(warn)
        sg.add("磁盘剩余 12%")
        @Expect(sg.spanCount(), 2)

        sg.textAlign(LV_TEXT_ALIGN_LEFT)
        sg.overflow(LV_SPAN_OVERFLOW_ELLIPSIS)
        sg.indent(4)
        sg.mode(LV_SPAN_MODE_BREAK)
        sg.maxLines(3)
        sg.refresh()
        sg.size(280, 60)
        App.runOnce()
        // span 是惰性排版（refresh 只打标记，真正的换行在绘制时算），
        // 因此这里只校验片段数仍正确、各 setter 全部走通且不崩；
        // 排版效果由 examples 的 `main rich` 人工看图确认。
        @Expect(sg.spanCount(), 2)
        sg.invalidate()
        sg.finalize()
    }

    /**
     * Calendar：先钉死 lv_calendar_date_t 的 C 布局（uint16+uint8+uint8 = 4 字节），
     * 再验证 today / showMonth / highlight / pressedDate 的读写路径。
     */
    @Tag[requires_display]
    @TestCase
    func testCalendarDates() {
        @Expect(sizeOf<lv_calendar_date_t>(), 4)

        let cal = Calendar(screen())
        cal.today(2026, 10, 24)
        match (cal.todayDate()) {
            case Some(d) =>
                @Expect(d[0], UInt32(2026))
                @Expect(d[1], UInt32(10))
                @Expect(d[2], UInt32(24))
            case None => @Expect(false, true)
        }
        cal.showMonth(2026, 10)
        cal.highlight([(2026, 10, 1), (2026, 10, 24)])
        // 没有真实点击，不应返回日期
        @Expect(cal.pressedDate().isNone(), true)
        cal.finalize()
    }

    /**
     * Image.fromFile / setFile：
     * ① 路径不存在必须抛 LvglException（仓颉侧先查存在性）；
     * ② 文件存在但不是图片时，lv_image_set_src 无返回码，LVGL 只打 WARN，
     *    因此只要求"不抛、不崩"——真正的解码正确性由 examples 的 `main file` 人工看图。
     */
    @Tag[requires_display]
    @TestCase
    func testImageFromFile() {
        @ExpectThrows[LvglException](Image.fromFile(screen(), "/no/such/dir/lvglcj-none.png"))

        let tmp = "lvglcj-fromfile-test.bin"
        File.writeTo(tmp, Array<UInt8>(16, repeat: 0x7F))
        let img = Image.fromFile(screen(), tmp)
        img.finalize()
        removeIfExists(tmp)
        @Expect(true)
    }

    /** AnimImage：3 帧 RGB565 缓冲 -> 帧数组 -> 播放；帧数不足要抛异常 */
    @Tag[requires_display]
    @TestCase
    func testAnimImageFrames() {
        let w: Int32 = 8
        let h: Int32 = 8
        let buffers = ArrayList<ImageBuffer>()
        let dscs = ArrayList<ImageDsc>()
        var f: Int64 = 0
        while (f < 3) {
            let b = ImageBuffer(w, h, LV_COLOR_FORMAT_RGB565)
            let px = Array<UInt8>(Int64(w) * Int64(h) * 2, repeat: UInt8(f * 80))
            b.writePixels(px)
            buffers.add(b)
            dscs.add(b.toImageDsc())
            f += 1
        }

        let anim = AnimImage(screen())
        anim.frames(dscs.toArray(), durationMs: 300)
        @Expect(Int32(anim.srcCount()), 3)
        anim.repeatCount(LV_ANIM_REPEAT_INFINITE)
        anim.start()
        App.runOnce()
        anim.finalize()

        let single = ArrayList<ImageDsc>()
        single.add(dscs[0])
        @ExpectThrows[LvglException](AnimImage(screen()).frames(single.toArray()))
    }

    /**
     * AnimImage 帧数上限：LVGL 的 pic_count 是 int8_t，128 帧会被截成 -128，
     * 内部索引只做上界 clamp → 负下标取图源。必须在仓颉侧挡住。
     */
    @Tag[requires_display]
    @TestCase
    func testAnimImageRejectsMoreThan127Frames() {
        let buf = ImageBuffer(2, 2, LV_COLOR_FORMAT_RGB565)
        buf.writePixels(Array<UInt8>(8, repeat: 0x11))
        let dsc = buf.toImageDsc()
        let many = ArrayList<ImageDsc>()
        var i: Int64 = 0
        while (i < 128) {
            many.add(dsc)
            i += 1
        }
        let anim = AnimImage(screen())
        @ExpectThrows[LvglException](anim.frames(many.toArray()))
        anim.finalize()
    }

    /**
     * Line：lv_line_set_points 只存指针，顶点数组必须由控件保活。
     * 这里连续替换两次顶点并泵几帧（真绘制发生在 timer handler 里），
     * 修前的实现会在第一帧绘制时读到已 free 的内存（UAF）。
     */
    @Tag[requires_display]
    @TestCase
    func testLineSetPointsKeepsBufferAlive() {
        let line = Line(screen())
        let wide: Array<(Int32, Int32)> = [(0, 0), (20, 30), (40, 10), (60, 30), (80, 0)]
        line.setPoints(wide)
        // refreshNow 而不是 runOnce：后者可能没到刷新时刻，绘制路径根本没执行，
        // 那条「读到已释放顶点」的 UAF 也就测不出来（ASan 下必须真画一帧）。
        App.refreshNow()
        // 替换成更小的数组：旧缓冲必须在新缓冲生效后才释放
        let narrow: Array<(Int32, Int32)> = [(0, 0), (80, 80)]
        line.setPoints(narrow)
        App.refreshNow()
        // 少于 2 点必须拒绝，且不能破坏已有的顶点数组
        let singlePoint: Array<(Int32, Int32)> = [(0, 0)]
        @ExpectThrows[LvglException](line.setPoints(singlePoint))
        App.refreshNow()
        line.finalize()
        @Expect(true)
    }

    /**
     * Image.setSource 必须持有 ImageDsc 强引用：dsc 是临时对象时，
     * 若控件不保活，GC 后 lv_image 会读已释放的 dsc（画面花掉或崩）。
     */
    @Tag[requires_display]
    @TestCase
    func testImageSetSourceKeepsDsc() {
        let w: Int32 = 8
        let h: Int32 = 8
        let buf = ImageBuffer(w, h, LV_COLOR_FORMAT_RGB565)
        buf.writePixels(Array<UInt8>(Int64(w) * Int64(h) * 2, repeat: 0x3F))
        let img = Image(screen())
        img.setSource(buf.toImageDsc()) // 临时 dsc：由 Image 负责保活
        App.runOnce()
        @Expect(img.width() >= 0, true)
        // 换成文件源后应释放对 dsc 的引用（文件不存在会抛，且不影响已有引用）
        @ExpectThrows[LvglException](img.setFile("/no/such/dir/lvglcj-none.png"))
        App.runOnce()
        img.finalize()
        @Expect(true)
    }

    /**
     * Style 自动保活：applyTo 只把 lv_style_t* 交给 LVGL，若控件不持有仓颉对象，
     * 临时 Style 被 GC 后绘制就会读到已释放内存（偶发花屏）。这里断言"控件确实挂住了"。
     */
    @Tag[requires_display]
    @TestCase
    func testStyleTemporaryIsKeptByWidget() {
        let btn = Button(screen())
        @Expect(btn.keptCount(), 0)
        Style().radius(8).bgColor(0x33, 0x66, 0x99).applyTo(btn) // 临时对象，出语句即无本地引用
        @Expect(btn.keptCount(), 1)
        Style().borderWidth(2).applyTo(btn)
        @Expect(btn.keptCount(), 2)
        App.refreshNow() // 真画一帧：没保活的话，ASan 下这里就是 heap-use-after-free
        btn.finalize()
        @Expect(true)
    }

    /** SpanPart.style 同理：样式登记在所属 SpanGroup 上 */
    @Tag[requires_display]
    @TestCase
    func testSpanTemporaryStyleIsKeptByGroup() {
        let sg = SpanGroup(screen())
        sg.add("警告：").style(Style().textColor(255, 80, 80)) // 临时对象
        sg.add("磁盘剩余 12%")
        @Expect(sg.keptCount(), 1)
        App.refreshNow()
        sg.finalize()
        @Expect(true)
    }

    /** keep() 是追加式：多次调用累加，互不顶替 */
    @Tag[requires_display]
    @TestCase
    func testKeepIsAppendOnly() {
        let lb = Label(screen())
        lb.keep(Style())
        lb.keep(Style())
        lb.keep(Style())
        @Expect(lb.keptCount(), 3)
        lb.close()
        @Expect(true)
    }

    /** keepOnly() 是替换式：一套换一套，旧的立刻不再被引用 */
    @Tag[requires_display]
    @TestCase
    func testKeepOnlyReplacesWholeSet() {
        let lb = Label(screen())
        lb.keep(Style())
        lb.keep(Style())
        @Expect(lb.keptCount(), 2)
        lb.keepOnly(ArrayList<Object>())
        @Expect(lb.keptCount(), 0)
        lb.keepOnly(ArrayList<Object>([Style()]))
        @Expect(lb.keptCount(), 1)
        lb.close()
        @Expect(true)
    }

    /**
     * 换源（`keepOnly`）**不能**把 `applyTo` 挂上去的样式一起放开。
     *
     * 回归点：样式与 `keep()` 曾共用一份列表，`Image.setSource` / `Image.setFile` /
     * `AnimImage.frames` 调 `keepOnly` 时会把 Style 挤出保活表 → GC 后
     * `obj->styles[]` 指向已释放的 `lv_style_t`，下一帧读悬垂内存。
     */
    @Tag[requires_display]
    @TestCase
    func testKeepOnlyKeepsStyles() {
        let lb = Label(screen())
        Style().radius(8).bgColor(0x11, 0x22, 0x33).applyTo(lb)
        lb.keep(Style())
        @Expect(lb.keptCount(), 2)
        lb.keepOnly(ArrayList<Object>()) // 模拟换图源：清掉 keep 的对象
        @Expect(lb.keptCount(), 1) // 样式仍在
        App.refreshNow() // 真画一帧：样式若被提前释放，ASan 下这里就是 UAF
        lb.close()
        @Expect(true)
    }

    /**
     * keepBuf 按槽位并存：grid 的列/行描述符是两块**同时**存活的数组，
     * 早先「一个控件只留一块缓冲」的设计在这里会用掉前一块。
     */
    @Tag[requires_display]
    @TestCase
    func testKeepBufSlotsCoexistAndReplaceInPlace() {
        let lb = Label(screen())
        @Expect(lb.keptBufs(), 0)
        // 注意 malloc<T> 的 T 不能是 Unit（sizeOf/alignOf 为 0，内部对齐运算会除零）
        lb.keepBuf(CPointer<Unit>(unsafe { LibC.malloc<UInt8>(count: 8) }))
        @Expect(lb.keptBufs(), 1)
        lb.keepBuf(CPointer<Unit>(unsafe { LibC.malloc<UInt8>(count: 8) }), slot: 1)
        @Expect(lb.keptBufs(), 2)
        // 同槽替换：旧缓冲释放，槽位总数不变
        lb.keepBuf(CPointer<Unit>(unsafe { LibC.malloc<UInt8>(count: 16) }))
        @Expect(lb.keptBufs(), 2)
        App.refreshNow()
        lb.close() // 两块缓冲随控件一起 free
        @Expect(true)
    }

    /**
     * 状态样式：同一属性在 DEFAULT / PRESSED / DISABLED 各挂一份，互不顶替。
     * 能不能真的换色要看渲染结果，这里先钉住「三份都登记上了且切换状态不崩」。
     */
    @Tag[requires_display]
    @TestCase
    func testStateSelectorStylesCoexist() {
        let btn = Button(screen())
        Style().bgColor(0x21, 0x96, 0xF3).applyTo(btn) // 常态
        Style().bgColor(0x15, 0x65, 0xC0).applyTo(btn, state: LV_STATE_PRESSED)
        Style().bgColor(0x9E, 0x9E, 0x9E).applyTo(btn, state: LV_STATE_DISABLED)
        @Expect(btn.keptCount(), 3)
        btn.addState(LV_STATE_PRESSED)
        App.refreshNow()
        btn.removeState(LV_STATE_PRESSED)
        btn.addState(LV_STATE_DISABLED)
        App.refreshNow()
        btn.close()
        @Expect(true)
    }

    /** part 选择器：滑块轨道 / 指示条 / 滑块头是三个不同 part，可各挂一套 */
    @Tag[requires_display]
    @TestCase
    func testPartSelectorStylesCoexist() {
        let sl = Slider(screen())
        Style().bgColor(0xD0, 0xD0, 0xD0).applyTo(sl, part: LV_PART_MAIN)
        Style().bgColor(0x21, 0x96, 0xF3).applyTo(sl, part: LV_PART_INDICATOR)
        Style().bgColor(0xFF, 0xFF, 0xFF).applyTo(sl, part: LV_PART_KNOB)
        @Expect(sl.keptCount(), 3)
        App.refreshNow()
        sl.close()
        @Expect(true)
    }

    /** 直接 setter 组：part / state 都能透传，且可反复覆盖同一属性 */
    @Tag[requires_display]
    @TestCase
    func testInlineStyleSetters() {
        let box = Container(screen())
        box.setStyleBgColor(0x11, 0x22, 0x33)
        box.setStyleBgOpa(200)
        box.setStyleRadius(8)
        box.setStyleBorderWidth(2)
        box.setStyleBorderColor(0x00, 0x00, 0x00)
        box.setStylePadAll(12)
        box.setStyleShadowWidth(4)
        box.setStyleBgColor(0x44, 0x55, 0x66, state: LV_STATE_PRESSED)
        box.setStyleTextColor(0xFF, 0xFF, 0xFF, part: LV_PART_MAIN, state: LV_STATE_FOCUSED)
        App.refreshNow()
        @Expect(box.width() >= 0, true)
        box.close()
        @Expect(true)
    }

    /**
     * 几何断言样板（headless，SDL dummy 驱动，不弹窗）。
     *
     * 这是 flex/grid 用例的验证基座：`set_pos` / `set_size` 之后**必须**
     * 先 `updateLayout()` 再读坐标，否则读到的是布局前的旧值。
     */
    @Tag[requires_display]
    @TestCase
    func testGeometryIsReadableInHeadlessMode() {
        let box = Container(screen())
        box.size(200, 100)
        box.pos(10, 10)
        box.updateLayout()
        @Expect(box.x(), 10)
        @Expect(box.y(), 10)
        @Expect(box.width(), 200)
        @Expect(box.height(), 100)
        box.close()
    }

    /** 内容区 = 外框减去 padding / 边框：布局算的是内容区，断言不能拿 width() 顶替 */
    @Tag[requires_display]
    @TestCase
    func testContentAreaShrinksWithPadding() {
        let box = Container(screen())
        box.size(120, 80)
        Style().padAll(10).applyTo(box)
        box.updateLayout()
        @Expect(box.contentWidth() <= box.width(), true)
        @Expect(box.contentWidth() > 0, true)
        @Expect(box.contentWidth() < 120, true)
        box.close()
    }

    /** 子对象坐标是相对**父内容区**的，不是相对父外框 */
    @Tag[requires_display]
    @TestCase
    func testChildPositionIsRelativeToParentContentArea() {
        let outer = Container(screen())
        outer.size(200, 200)
        outer.pos(0, 0)
        let inner = Container(outer)
        inner.size(50, 50)
        inner.pos(0, 0)
        inner.updateLayout()
        @Expect(inner.x() >= 0, true)
        @Expect(inner.y() >= 0, true)
        @Expect(inner.width(), 50)
        outer.close() // 递归删除子对象，子对象上的订阅/保活一并回收
        @Expect(true)
    }
}
