/**
 * widget.cj / display.cj —— 需要真实 display 与屏幕的用例。
 *
 * 全部打了 @Tag[requires_display]，cjpm.toml 的 [profile.test] 默认排除它们。
 * @BeforeAll 会尝试创建 SDL 显示，但无头环境（CI）下创建失败只记录原因、
 * 不中断测试进程；因此默认的 cjpm test 不依赖桌面或 Xvfb。
 *
 * 单独运行：
 *   cjpm test --include-tags=requires_display
 *   （会真的弹出 320x240 的 LVGL 窗口，属于人工验证）
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
    static var disp: Option<Display> = None
    static var scr: Option<Screen> = None
    static var eventCount: Int32 = 0
    static var eventError: String = ""

    @BeforeAll
    static func setupDisplay() {
        ensureLvglInit()
        try {
            let d = Display.sdl(320, 240)
            disp = Some(d)
            scr = Some(d.screen())
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
}
