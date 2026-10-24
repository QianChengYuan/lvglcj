# API 参考（友好层 `lvglcj`）

> 本文档对应仓库 `src/*.cj` 的当前实现。`src/ffi_*.cj` 是内部 FFI 层，`foreign` 声明不导出、不供下游直接使用；下游只需要 `import lvglcj.*`。

## 目录

- [0. 通用约定](#0-通用约定)
- [1. util.cj —— 异常 / 版本 / 颜色 / 内存](#1-utilcj--异常--版本--颜色--内存)
- [2. app.cj —— 生命周期 / 主循环 / 定时器 / 性能](#2-appcj--生命周期--主循环--定时器--性能)
- [3. display.cj —— 显示后端与屏幕](#3-displaycj--显示后端与屏幕)
- [4. input.cj —— 输入设备](#4-inputcj--输入设备)
- [5. widget.cj —— 对象基类与控件](#5-widgetcj--对象基类与控件)
- [6. style.cj —— 样式 / 字体 / 主题](#6-stylecj--样式--字体--主题)
- [7. image.cj —— 像素缓冲 / 图像 / 画布](#7-imagecj--像素缓冲--图像--画布)
- [8. 常量速查](#8-常量速查)
- [9. 边界与限制](#9-边界与限制)

---

## 0. 通用约定

### 0.1 命名参数默认值

仓颉只允许**命名参数**（形参名后带 `!`）声明默认值，因此本库的可选参数一律是命名参数，调用时必须带名字：

```cangjie
Display.drm()                                  // ✅
Display.drm(card: "/dev/dri/card1")            // ✅
Display.drm("/dev/dri/card1")                  // ❌ 编译报错
```

### 0.2 异常

所有失败路径统一抛 `LvglException`（继承 `Exception`），消息里带具体原因与排查提示：

```cangjie
try {
    Display.drm()
} catch (e: LvglException) {
    println("DRM 不可用，退回 SDL：${e.message}")
    Display.sdl(480, 272)
}
```

### 0.3 线程模型（硬约束）

**LVGL 不是线程安全的。** 所有 `lv_*` 调用都必须在同一线程（主线程）：

- `Timer.every/once` 的回调在 `lv_timer_handler` 里执行 → 属于主线程，可直接操作控件；
- `Widget.onEvent` 的回调同理；
- **回调里抛出的异常不能跨 C 边界传播**（会直接 abort），回调内部必须自行 `try/catch`；
- 后台线程（网络/采集/解码）只投递数据，UI 更新交回主线程。

### 0.4 句柄所有权

| 类型 | 谁持有 | 释放方式 |
|---|---|---|
| `Widget` 及其子类 | LVGL 对象树（C 侧） | `finalize()` / `delete()`，或随父对象一起销毁 |
| `Screen` | LVGL display | 不要手动释放 |
| `Event.target()` 返回的 `Widget` | **借用**（与源控件共享句柄） | **不要**调用 `finalize()` |
| `Style` | 仓颉对象持有 C 堆 `lv_style_t` | 析构自动 `lv_style_delete` |
| `Font.load/systemCjk` | FreeType | `close()`，或随进程结束回收 |
| `ImageBuffer` | 系统堆（`LibC.malloc`） | 析构自动 `free` |
| `ImageDsc` | 垫片分配 | 析构自动释放 |
| `Canvas` | `lv_draw_buf_t` | 析构自动 `lv_draw_buf_destroy` |

### 0.5 初始化顺序

```
App.setup()  →  Display.xxx()  →  Theme.default(...)（可选）  →  建控件  →  App.run()
```

顺序不可颠倒：`Theme.default` 需要已存在的 display；任何控件创建都需要已 `setup`（`lv_init`）。

---

## 1. util.cj —— 异常 / 版本 / 颜色 / 内存

### `LvglException <: Exception`

```cangjie
public class LvglException <: Exception {
    public init(message: String)
    public override func getClassName(): String   // "LvglException"
}
```

### `version(): String`

LVGL 版本号文本，如 `"9.5.0"`（编译期常量，不分配内存）。

```cangjie
println("LVGL ${version()}")
```

### `Color`

LVGL 有两种"颜色"，用途不同，别混用：

| 方法 | 返回 | 用途 |
|---|---|---|
| `Color.of(r, g, b: UInt8): lv_color_t` | LVGL 内部颜色结构 | 样式、画布绘制 API |
| `Color.rgb565(r, g, b: UInt8): UInt16` | RGB565 像素字面量 | 写像素缓冲（`ImageBuffer.writePixels`） |
| `Color.argb8888(r, g, b, a: UInt8): UInt32` | ARGB8888 像素字面量 | 写 32 位像素缓冲 |

```cangjie
let c = Color.of(0x1E, 0x88, 0xE5)        // 给样式用
let px = Color.rgb565(0x1E, 0x88, 0xE5)   // 给像素缓冲用
```

### `Mem` / `MemStat`

需 `lv_conf.h` 打开 `LV_USE_SYSMON 1` + `LV_USE_MEM_MONITOR 1`，否则数值恒为 0。

```cangjie
public class MemStat {
    public let totalSize: UIntNative
    public let freeSize: UIntNative
    public let usedSize: UIntNative     // totalSize - freeSize
    public let maxUsed: UIntNative
    public let usedPct: UInt8
    public let fragPct: UInt8
}

public class Mem {
    public static func monitor(): MemStat
}
```

```cangjie
let m = Mem.monitor()
println("内存 ${m.usedSize}/${m.totalSize} 字节（${m.usedPct}%），碎片 ${m.fragPct}%")
```

---

## 2. app.cj —— 生命周期 / 主循环 / 定时器 / 性能

### `App`

| 方法 | 说明 |
|---|---|
| `App.setup(): Unit` | `lv_init()` + 把单调时钟挂到 `lv_tick_set_cb`。**必须最先调用**；不挂 tick，画面第一帧后就会卡死 |
| `App.shutdown(): Unit` | `lv_deinit()` 与资源回收 |
| `App.mainDisplay(): Display` | 默认 display 的包装 |
| `App.runOnce(): UInt32` | 手动泵一次 `lv_timer_handler`，返回距下次定时器的毫秒数（便于和业务线程协作） |
| `App.run(idleMs!: UInt32 = 5): Unit` | 主循环：`runOnce()` + `lv_sleep_ms(idleMs)`，直到 `App.stop()` |
| `App.stop(): Unit` | 请求退出主循环 |

`idleMs` 的取舍：5 ms 足够流畅；设 0 会空转吃满一个核；低功耗场景可放到 10–16 ms。

### `Perf`

LVGL 9.5 没有导出 perf monitor 的查询 API（数据在私有结构体里），因此本库在 `runOnce()` 里自行采样，口径与 LVGL 一致：

- `Perf.cpu(): Int32` —— 1 秒窗口内 `lv_timer_handler` 繁忙时间占墙钟时间的百分比；
- `Perf.fps(): Float64` —— 1 秒窗口内发生真实渲染调度（繁忙 ≥ 1 ms）的次数。

> 静态画面下 `fps` 会很低甚至为 1，这是正常的：LVGL 只在有脏区时才重绘。

另有 LVGL 自带的屏幕悬浮监视器（默认右下角，显示 FPS/CPU 小字）：

| 方法 | 说明 |
|---|---|
| `Perf.hideMonitor(disp!: Option<Display> = None)` | 隐藏悬浮标签（只是隐藏，采样照常） |
| `Perf.showMonitor(disp!: Option<Display> = None)` | 重新显示 |

`LV_USE_PERF_MONITOR=1` 时 `lv_display_create` 会自动把它打开，所以要么在创建 display 之后立刻 `Perf.hideMonitor()`，要么在 `lv_conf.h` 里把 `LV_USE_PERF_MONITOR` 设为 0 再重编静态库（后者才真正省掉这部分开销）。

### `Timer`

```cangjie
public class Timer {
    public static func every(period: UInt32, cb: () -> Unit): Unit   // 每 period 毫秒
    public static func once(delay: UInt32, cb: () -> Unit): Unit     // 延时一次
}
```

回调在主线程执行，可直接改控件。**计数器要放模块级**——仓颉不允许"捕获了局部可变变量的闭包"作为值传递（编译报 `lambda capturing mutable variables needs to be called directly`）：

```cangjie
var elapsedSec: Int32 = 0            // 模块级

main() {
    ...
    Timer.every(1000) {
        elapsedSec += 1
        label.setTextFmt("已运行 %d 秒", [elapsedSec])
    }
}
```

> `once` 的定时器触发后由库自动 `lv_timer_delete`，无需手工清理。

---

## 3. display.cj —— 显示后端与屏幕

### 三个后端（同一接口，按平台自动降级）

| 工厂方法 | 平台 | 说明 |
|---|---|---|
| `Display.drm(card!: String = "/dev/dri/card0")` | Linux 真机 | DRM/KMS，`connector_id = -1` 自动选第一个接口 |
| `Display.fbdev(dev!: String = "/dev/fb0")` | Linux 兜底 | 无 DRM 时用；仅接受灰度 8bpp 或 16/32 位 |
| `Display.sdl(w: Int32, h: Int32)` | 桌面 | 同时创建 SDL 鼠标 + 键盘输入，模拟环境下直接可交互 |

三者都会在失败时抛 `LvglException`，消息里会指出"当前构建是否启用了对应驱动"。因此在 Windows 上写 `try { Display.drm() } catch { Display.sdl(...) }` 可以正常编译运行。

### 查询

| 方法 | 返回 | 说明 |
|---|---|---|
| `width()` | `Int32` | 实际横向分辨率 |
| `height()` | `Int32` | 实际纵向分辨率 |
| `colorDepth()` | `UInt32` | 当前色深（位），由 color format 决定 |
| `screen()` | `Screen` | 当前活动屏幕，可作为控件 parent |

### 调优

| 方法 | 说明 |
|---|---|
| `setRotation(rotation: UInt32)` | `LV_DISPLAY_ROTATION_0/90/180/270`，软旋转（有绘制代价） |
| `setColorFormat(cf: UInt32)` | `LV_COLOR_FORMAT_RGB565` / `RGB565_SWAPPED` / `XRGB8888` / `L8` … |
| `setRenderMode(mode: UInt32)` | `PARTIAL`（默认，省内存）/ `DIRECT` / `FULL` |
| `setForceRefresh(on: Bool)` | 每次 flush 强制整屏刷新。**仅 fbdev 驱动有效**，黑屏/花屏排障用，有性能代价 |

### `Screen <: Widget`

| 方法 | 说明 |
|---|---|
| `load()` | 把本屏幕设为活动屏幕 |

因为 `Screen` 继承 `Widget`，所以 `size/pos/align/setFont/setStyle*/onEvent` 等全部可用。**全局换字体就靠它**（`text_font` 可继承）。

```cangjie
let scr = disp.screen()
scr.setStyleBgColor(0xF5, 0xF5, 0xF5)   // 全屏背景
scr.setFont(font)                        // 整个界面默认字体
```

---

## 4. input.cj —— 输入设备

### 创建

| 方法 | 说明 |
|---|---|
| `Input.evdev(indevType: UInt32, dev: String): Input` | 按设备节点创建，`LV_INDEV_TYPE_POINTER`（触摸/鼠标）或 `KEYPAD`（键盘） |
| `Input.discover(cb: () -> Unit): Unit` | 扫描 `/dev/input/` 并支持热插拔，发现新设备时回调 |
| `Input.stopDiscover(): Unit` | 停止设备发现 |
| `Input.activePoint(): Option<(Int32, Int32)>` | 最近一次处理的指针坐标；无指针设备时返回 `None` |

> Windows / WSL 桌面构建里 `LV_USE_EVDEV=0`，`Input.evdev()` 会抛 `LvglException`（垫片返回 NULL）。桌面模拟请走 `Display.sdl()` 自带的 SDL 输入。

### 实例配置

| 方法 | 说明 |
|---|---|
| `attach(display: Display)` | 绑定到指定 display（默认已绑默认 display） |
| `calibrate(minX, minY, maxX, maxY: Int32)` | 原始坐标 → 屏幕坐标映射（触摸校准） |
| `swapAxes(on: Bool)` | 修正 X/Y 颠倒的面板 |
| `setCursor(obj: Widget)` | 给鼠标类设备挂光标对象 |

```cangjie
let touch = Input.evdev(LV_INDEV_TYPE_POINTER, "/dev/input/event0")
touch.calibrate(0, 0, 4095, 4095)   // 常见 12 位电阻屏
touch.attach(disp)
```

---

## 5. widget.cj —— 对象基类与控件

### `Event`

```cangjie
public class Event {
    public func code(): UInt32        // LV_EVENT_*
    public func target(): Widget      // 借用：不要 finalize
}
```

### `Widget`（基类，所有控件都有）

**几何**

| 方法 | 说明 |
|---|---|
| `size(w, h: Int32)` | 宽高（像素） |
| `pos(x, y: Int32)` | 相对父对象左上角 |
| `align(a: UInt32, dx!: Int32 = 0, dy!: Int32 = 0)` | 相对父对象对齐，`LV_ALIGN_*` |
| `center()` | 居中 |
| `width()` / `height(): Int32` | 实际宽高 |

**标志与状态**

| 方法 | 说明 |
|---|---|
| `addFlag(f: UInt32)` / `removeFlag(f)` / `hasFlag(f): Bool` | `LV_OBJ_FLAG_*` |
| `addState(s: UInt32)` / `removeState(s: UInt32)` | `LV_STATE_*` |

**事件**

| 方法 | 说明 |
|---|---|
| `onEvent(mask: UInt32, cb: (Event) -> Unit)` | 订阅事件，`mask` 为 `LV_EVENT_*` 或 `LV_EVENT_ALL` |

```cangjie
slider.onEvent(LV_EVENT_VALUE_CHANGED) { _ =>
    println("值变了：${slider.valueGet()}")   // 直接捕获控件对象，见 9.3
}
```

**局部样式快捷接口**

| 方法 | 说明 |
|---|---|
| `setStyleBgColor(r, g, b, part!: UInt32 = LV_PART_MAIN)` | 背景色 |
| `setStyleTextColor(r, g, b, part!)` | 文字色 |
| `setStyleRadius(radius, part!)` | 圆角 |
| `setFont(f: Font, part!)` | 字体；`text_font` 可继承，设在 Screen/容器上即对该子树生效 |

**生命周期**

| 方法 | 说明 |
|---|---|
| `finalize()` | 从父对象删除并销毁 |
| `delete()` | 同 `finalize()`（在定时器回调里删除更安全） |
| `invalidate()` | 内容变化后触发重绘 |

### 控件一览

| 类 | 构造 | 专属方法 |
|---|---|---|
| `Container(parent)` | `lv_obj_create` | 无（纯容器） |
| `Label(parent)` | `lv_label_create` | `text(s)`、`setTextFmt(fmt, args)`、`color(r,g,b)`、`longMode(mode)` |
| `Button(parent)` | `lv_button_create` | `onClick(cb: () -> Unit)`、`checkable()` |
| `Switch(parent)` | `lv_switch_create` | `setChecked(on)`、`isChecked(): Bool` |
| `Checkbox(parent)` | `lv_checkbox_create` | `text(s)`、`setChecked(on)`、`isChecked()` |
| `Slider(parent)` | `lv_slider_create` | `value(v, anim!: Bool = true)`、`valueGet(): Int32`、`range(min, max)` |
| `Arc(parent)` | `lv_arc_create` | `value(v)`、`angles(start, end)`、`rotation(deg)` |
| `Bar(parent)` | `lv_bar_create` | `value(v, anim!)`、`range(min, max)` |
| `Spinbox(parent)` | `lv_spinbox_create` | `value(v)`、`range(min, max)` |
| `Dropdown(parent)` | `lv_dropdown_create` | `options(s)`（`\n` 分隔） |
| `Roller(parent)` | `lv_roller_create` | `options(s, mode!: UInt32 = LV_ROLLER_MODE_NORMAL)`、`selected(i)` |
| `TextArea(parent)` | `lv_textarea_create` | `text(s)`、`oneLine(on)`、`password(on)` |
| `Keyboard(parent)` | `lv_keyboard_create` | `target(ta: TextArea)` |
| `List(parent)` | `lv_list_create` | `addText(s): Widget`、`addButton(s): Button` |
| `Table(parent)` | `lv_table_create` | `cellValue(row, col, s)` |
| `TabView(parent)` | `lv_tabview_create` | `addTab(name): Widget` |
| `Menu(parent)` | `lv_menu_create` | 无 |
| `MsgBox(parent)` | `lv_msgbox_create` | 无 |
| `Win(parent)` | `lv_win_create` | `addTitle(s): Label` |
| `Image(parent)` | `lv_image_create` | `setSource(dsc)`、`rotate(deg)`、`scale(factor: Float64)` |
| `Chart(parent)` | `lv_chart_create` | `pointCount(n)`、`range(axis, min, max)`、`addSeries(r,g,b): ChartSeries`、`setNextValue(series, v)` |
| `Line(parent)` | `lv_line_create` | `setPoints(points: Array<(Int32, Int32)>)`（≥2 点） |
| `Scale(parent)` | `lv_scale_create` | `range(min, max)` |
| `Led(parent)` | `lv_led_create` | `color(r,g,b)`、`brightness(v)`、`on()`、`off()` |
| `Canvas(parent, w, h, cf!)` | `lv_canvas_create` | 见 [7](#7-imagecj--像素缓冲--图像--画布) |
| `SpanGroup(parent)` | `lv_spangroup_create` | `add(): SpanPart`、`add(text)`、`spanCount()`、`textAlign(a)`、`overflow(o)`、`indent(px)`、`mode(m)`、`maxLines(n)`、`refresh()` |
| `Calendar(parent)` | `lv_calendar_create` | `today(y,m,d)`、`showMonth(y,m)`、`headerArrow()`、`headerDropdown()`、`highlight(dates)`、`pressedDate()`、`onPressed(cb)` |
| `AnimImage(parent)` | `lv_animimg_create` | `frames(list, durationMs!)`、`start()`、`repeatCount(n)`、`srcCount()` |
| `ImePinyin(parent)` | `lv_ime_pinyin_create` | `bindKeyboard(kb: Keyboard)`、`mode(m)` |

#### 富文本 `SpanGroup` / `SpanPart`

一段文本里混排不同颜色与字号，靠 `lv_span` 片段实现（Control 本身是 `lv_spangroup`）：

```cangjie
let warn = Style().textColor(0xE5, 0x3E, 0x3E).textFont(font)
let normal = Style().textColor(0x55, 0x55, 0x55).textFont(font)
let sg = SpanGroup(scr)
sg.add("警告：").style(warn)
sg.add("磁盘剩余 12%，请及时清理").style(normal)
sg.size(600, 44)
sg.mode(LV_SPAN_MODE_BREAK)     // FIXED / EXPAND / BREAK
sg.textAlign(LV_TEXT_ALIGN_LEFT)
sg.align(LV_ALIGN_TOP_LEFT, dx: 20, dy: 36)
```

> **生命周期硬约束**：`lv_spangroup_set_span_style` 只保存 `lv_style_t*`，**`Style` 对象必须活得比片段久**——不要写成 `sg.add("x").style(Style().textColor(...))`（临时对象出作用域即析构，之后绘制会读到已释放内存）。
>
> span 是**惰性排版**：`refresh()` 只打标记，真正换行在绘制时计算，因此 `set_size` 之后立刻 `width()` 读到的值不可靠。

#### 日历 `Calendar`

```cangjie
let cal = Calendar(scr)
cal.size(260, 230)
cal.headerArrow()            // 9.5 的日历默认没有年月头部，要自己加
cal.today(2026, 10, 24)      // 高亮“今天”
cal.showMonth(2026, 10)
cal.highlight([(2026, 10, 1), (2026, 10, 24)])
cal.onPressed { (y, m, d) => println("选中 ${y}-${m}-${d}") }
```

> `lv_calendar_date_t` 在 C 侧是 **uint16 year + uint8 month + uint8 day**（共 4 字节），不是三个 uint32。`Calendar` 内部的 `highlight()` 数组会保活（LVGL 只存指针）。

#### 帧动画 `AnimImage`

```cangjie
let anim = AnimImage(scr)
anim.frames(dscs.toArray(), durationMs: 800)   // dscs: Array<ImageDsc>，至少 2 帧
anim.repeatCount(LV_ANIM_REPEAT_INFINITE)
anim.start()
```

> 同样只存指针：`frames()` 传入的 `Array<ImageDsc>` 及其背后的 `ImageBuffer` 都会被类内部保活，调用方别提前 `finalize()` 或让缓冲失效。

#### 拼音输入法 `ImePinyin`

```cangjie
let kb = Keyboard(scr)
let ta = TextArea(scr)
kb.target(ta)
let ime = ImePinyin(scr)
ime.bindKeyboard(kb)                      // 候选词面板挂到键盘上
ime.mode(LV_IME_PINYIN_MODE_K26)          // K26 / K9 / K9_NUMBER
```

> 依赖 `lv_conf.h` 的 `LV_USE_IME_PINYIN 1`（LVGL 9.5 默认是 0）。本仓库两份配置均已打开并重编了静态库；自己换库时注意同样要开，否则链接期报 `lv_ime_pinyin_*` 未定义。

`Label.setTextFmt` 只支持 `%d`（仓颉侧完成替换，不走 C 的 printf）：

```cangjie
label.setTextFmt("滑块：%d", [35])     // → "滑块：35"
```

`Image.scale` 的 `factor` 是倍率（内部 `× 256` 转 LVGL 的 scale）：

```cangjie
img.scale(0.5)   // 缩小一半
img.rotate(900)  // LVGL 的角度单位是 0.1°，900 = 90°
```

`Chart.range` 的 `axis`：`0` 主 Y 轴、`1` 次 Y 轴（9.5 把 v8 的 `lv_chart_set_range` 改成了 `lv_chart_set_axis_range`）。

---

## 6. style.cj —— 样式 / 字体 / 主题

### `Style`（链式）

```cangjie
let s = Style()
    .bgColor(0xFF, 0xFF, 0xFF).bgOpa(255)
    .radius(8).borderWidth(1).borderColor(0xDD, 0xDD, 0xDD)
    .padAll(6).shadowWidth(4).shadowOpa(40)
s.applyTo(button)
```

| 方法 | 说明 |
|---|---|
| `bgColor(r,g,b)` / `bgOpa(opa: UInt8)` | 背景色 / 不透明度（0–255） |
| `radius(r: Int32)` | 圆角 |
| `borderWidth(w)` / `borderColor(r,g,b)` | 边框 |
| `padAll(pad)` | 四周内边距 |
| `textFont(f: Font)` / `textColor(r,g,b)` | 字体 / 文字色 |
| `shadowWidth(w)` / `shadowOpa(opa)` | 阴影（9.5 原生渲染） |
| `blurRadius(r)` | 模糊（9.5 原生；很吃 CPU，小面积用） |
| `applyTo(obj: Widget, part!: UInt32 = LV_PART_MAIN)` | 应用到控件的指定部位 |

> `Style` 对象**必须保持存活**：LVGL 只存指针不拷贝。局部变量出作用域后样式对象可能被回收，导致渲染异常。建议作为字段/全局持有。

### `Font`

| 方法 | 说明 |
|---|---|
| `Font.montserrat(size: Int32): Font` | 内置 Montserrat（8–48，实际以 `lv_conf.h` 启用的字号为准，未启用则回退默认字体） |
| `Font.defaultFont(): Font` | `LV_FONT_DEFAULT` |
| `Font.load(path: String, size!: Int32 = 16, bold!: Bool = false): Font` | 从 `.ttf/.ttc/.otf` 加载，**需 `LV_USE_FREETYPE=1`**；失败抛异常 |
| `Font.systemCjk(size!: Int32 = 16, bold!: Bool = false): Font` | 按候选路径加载系统中文字体，找不到抛异常 |
| `Font.trySystemCjk(size!, bold!): Option<Font>` | 同上，找不到返回 `None` |
| `setFallback(fb: Font): Font` | 设置缺字回退字体（LVGL 9.5 `lv_font_t::fallback`），返回 `this`；**仅 FreeType 字体可用**，内置字体调用抛 `LvglException` |
| `clearFallback(): Font` | 清空回退链（同样仅 FreeType 字体） |
| `fallback(): Option<Font>` | 读取当前回退字体 |
| `close()` | 释放 FreeType 字体；**内置字体（montserrat/defaultFont）调用是空操作**，可重复调用 |

`systemCjk` / `trySystemCjk` 的候选路径顺序：

```
C:/Windows/Fonts/msyh.ttc                                    Windows 微软雅黑
C:/Windows/Fonts/Deng.ttf                                    Windows 等线
C:/Windows/Fonts/simhei.ttf                                  Windows 黑体
/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc       Debian/Ubuntu Noto CJK
/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc       部分发行版的 Noto 位置
/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf
/usr/share/fonts/truetype/wqy/wqy-microhei.ttc               文泉驿微米黑
/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf    树莓派（只有 CJK，没有拉丁字母）
```

> **系统 CJK 字体不一定带拉丁字形**：Raspberry Pi OS 只装 `DroidSansFallbackFull.ttf`，它没有 U+0021..U+007E，直接当主题字体时中文正常但 `LVGL 9.5` 会渲染成一排方框。挂个回退即可：
>
> ```cangjie
> let f = Font.trySystemCjk(size: 16) ?? Font.defaultFont()
> f.setFallback(Font.montserrat(16))   // 缺的字去 Montserrat 里找
> Theme.default((0x1E, 0x88, 0xE5), (0x0F, 0x9D, 0x58), false, f)
> ```
>
> 回退字体需比主字体**活得更久**（这里都是模块级/长生命周期对象，无需额外处理）。
> 反过来不行：`Font.montserrat()` / `Font.defaultFont()` 指向 `const lv_font_t`（链接进只读段 `.rdata`/`.rodata`），写它的 `fallback` 字段会崩，所以 `setFallback` 在主字体是内置字体时直接抛异常。需要给内置字体加回退请用 `Font.load(...)` 自己加载。

### `Theme`

```cangjie
public static func default(primary: (UInt8,UInt8,UInt8), secondary: (UInt8,UInt8,UInt8),
                           dark: Bool, font: Font): Unit
```

初始化默认主题并应用到当前屏幕。**换字体必须走这里**：LVGL 默认主题会给控件显式设置 `text_font`，只在 `Screen` 上挂样式会被主题覆盖。

```cangjie
let f = Font.trySystemCjk(size: 16) ?? Font.defaultFont()
Theme.default((0x1E, 0x88, 0xE5), (0x0F, 0x9D, 0x58), false, f)
disp.screen().setFont(f)      // 双保险：主题 + 屏幕级
```

---

## 7. image.cj —— 像素缓冲 / 图像 / 画布

### `ImageBuffer`

自己产出像素（摄像头、算法生成、解码结果）时用它，再 `toImageDsc()` 喂给 `Image`。

| 成员 | 说明 |
|---|---|
| `ImageBuffer(w: Int32, h: Int32, cf: UInt32)` | 申请 `w × h × 每像素字节数`，由系统堆分配 |
| `getWidth()` / `getHeight(): Int32` | 尺寸 |
| `writePixels(bytes: Array<UInt8>)` | 从仓颉字节数组拷入；长度不足抛异常；RGB565 按小端 |
| `toImageDsc(): ImageDsc` | 生成 `lv_image_dsc_t`，自动填 `magic/cf/w/h/stride/data_size` |

```cangjie
let w = 64; let h = 64
let buf = ImageBuffer(w, h, LV_COLOR_FORMAT_RGB565)
var px = Array<UInt8>(w * h * 2, repeat: 0)
for (y in 0..h) {
    for (x in 0..w) {
        let c = Color.rgb565(UInt8(x * 4), UInt8(y * 4), 0x80)
        px[(y * w + x) * 2] = UInt8(c & 0xFF)
        px[(y * w + x) * 2 + 1] = UInt8(c >> 8)
    }
}
buf.writePixels(px)
Image(disp.screen()).setSource(buf.toImageDsc())
```

### `ImageDsc`

`lv_image_dsc_t` 的包装，只能由 `ImageBuffer.toImageDsc()` 产出，直接传给 `Image.setSource`。

### `Image <: Widget`（像素缓冲或图片文件）

| 方法 | 说明 |
|---|---|
| `Image(parent)` | 空图像控件 |
| `img.setSource(dsc: ImageDsc)` | 用 `ImageBuffer.toImageDsc()` 的产物作源（不经过解码器，最省） |
| `Image.fromFile(parent, path): Image` | 从 **PNG** 文件创建；需 `LV_USE_LODEPNG` + `LV_USE_FS_STDIO`（本仓库三平台产物已打开） |
| `img.setFile(path)` | 换成另一张图片文件；路径不存在抛 `LvglException` |

```cangjie
let img = Image.fromFile(scr, "/home/pi/logo.png")
img.align(LV_ALIGN_CENTER, dx: 0, dy: 0)
```

> 垫片 `lvglcj_image_set_file_cjbindwrapper()` 负责把系统路径补成 LVGL 要求的 `A:<path>`（`LV_FS_STDIO_LETTER`）：`lv_image_set_src()` 只把「已注册驱动器字母 + `:`」开头的字符串当文件路径，否则会当成 symbol 去查字库。
>
> `lv_image_set_src()` **没有返回码**：文件存在但格式不支持/解码失败时 LVGL 只打 WARN、控件显示空白，仓颉侧无法据此抛异常。JPG/GIF/WebP 需在 `lv_conf.h` 打开 `LV_USE_TJPGD` / `LV_USE_GIF` / `LV_USE_LIBWEBP` 后重编库。
>
> **Windows 路径限制**：`LV_USE_FS_STDIO` 底层是 `fopen`（ANSI 代码页），**路径含中文时可能打不开**；调试请用 ASCII 路径，或自行改用 `LV_USE_FS_WIN32`（Unicode，需相应调整驱动器字母）。Linux / Pi（UTF-8）没有这个问题。

### `Canvas <: Widget`（自绘仪表 / 波形 / 图表）

```cangjie
public init(parent: Widget, w: Int32, h: Int32, cf!: UInt32 = LV_COLOR_FORMAT_RGB565)
```

| 方法 | 说明 |
|---|---|
| `fillBg(r, g, b, opa!: UInt8 = 255)` | 填充背景 |
| `drawRect(x, y, w, h, r, g, b, radius!: Int32 = 0, opa!: UInt8 = 255)` | 矩形（`radius` 圆角） |
| `drawText(x, y, w, text, font, r, g, b, opa!)` | 文本；中文要传支持中文的 `Font` |
| `setPx(x, y, r, g, b, opa!)` | 单像素 |

```cangjie
let cv = Canvas(scr, 220, 130)
cv.fillBg(0x10, 0x18, 0x20)
cv.drawText(8, 6, 200, "自绘仪表", font, 240, 240, 240)
cv.drawRect(8, 40, 200, 12, 0x1E, 0x88, 0xE5, radius: 6)
cv.setPx(10, 100, 0xFF, 0, 0)
```

> `Canvas` 的绘制是**直接写缓冲**，不会自动重绘整屏；内容变化后调 `invalidate()`。

---

## 8. 常量速查

本库只导出了常用的 `LV_*` 常量（不是 LVGL 全量）。需要其它值时，可对照 `lvgl-ref` 头文件的数值自行定义，或在 `src/ffi_obj.cj` 补一行 `public const`。

### 对象标志 `LV_OBJ_FLAG_*`

| 常量 | 值 |
|---|---|
| `LV_OBJ_FLAG_HIDDEN` | `1 << 0` |
| `LV_OBJ_FLAG_CLICKABLE` | `1 << 1` |
| `LV_OBJ_FLAG_CLICK_FOCUSABLE` | `1 << 2` |
| `LV_OBJ_FLAG_CHECKABLE` | `1 << 3` |
| `LV_OBJ_FLAG_SCROLLABLE` | `1 << 4` |
| `LV_OBJ_FLAG_SCROLL_CHAIN` | `(1 << 8) \| (1 << 9)` = 0x300 |
| `LV_OBJ_FLAG_SCROLL_ELASTIC` | `1 << 5` |

### 状态 `LV_STATE_*`

`LV_STATE_DEFAULT`(0)、`LV_STATE_CHECKED`(1<<2)、`LV_STATE_FOCUSED`(1<<3)、`LV_STATE_PRESSED`(1<<7)、`LV_STATE_DISABLED`(1<<9)、`LV_STATE_ANY`(0xFFFF)

### 部位 `LV_PART_*`（用于样式）

`LV_PART_MAIN`(0)、`LV_PART_SCROLLBAR`(0x010000)、`LV_PART_INDICATOR`(0x020000)、`LV_PART_KNOB`(0x030000)、`LV_PART_CURSOR`(0x060000)、`LV_PART_ANY`(0x0F0000)

### 对齐 `LV_ALIGN_*`

`DEFAULT`(0)、`TOP_LEFT`、`TOP_MID`、`TOP_RIGHT`、`BOTTOM_LEFT`、`BOTTOM_MID`、`BOTTOM_RIGHT`、`LEFT_MID`、`RIGHT_MID`、`CENTER`(9)

### 事件 `LV_EVENT_*`

`LV_EVENT_ALL`(0)、`PRESSED`(1)、`PRESSING`(2)、`PRESS_LOST`(3)、`SHORT_CLICKED`(4)、`SINGLE_CLICKED`(5)、`DOUBLE_CLICKED`(6)、`TRIPLE_CLICKED`(7)、`LONG_PRESSED`(8)、`LONG_PRESSED_REPEAT`(9)、`CLICKED`(10)、`RELEASED`(11)、`VALUE_CHANGED`(35)、`DELETE`(42)

### 输入 `LV_INDEV_*`

类型：`NONE`(0)、`POINTER`(1)、`KEYPAD`(2)、`BUTTON`(3)、`ENCODER`(4)
状态：`RELEASED`(0)、`PRESSED`(1)

### 显示

- 旋转：`LV_DISPLAY_ROTATION_0/90/180/270`
- 渲染模式：`LV_DISPLAY_RENDER_MODE_PARTIAL/DIRECT/FULL`

### 颜色格式 `LV_COLOR_FORMAT_*`

`RGB565`(0x12)、`RGB565_SWAPPED`(0x1B)、`RGB888`(0x0F)、`XRGB8888`(0x11)、`ARGB8888`(0x10)、`L8`(0x06)、`I1`(0x07)、`I8`(0x0A)

### 其它

| 常量 | 用途 |
|---|---|
| `LV_ANIM_ON`(1) / `LV_ANIM_OFF`(0) | 值变化是否带动画 |
| `LV_ANIM_REPEAT_INFINITE`(0xFFFFFFFF) | 动画/帧动画无限循环 |
| `LV_LABEL_LONG_MODE_WRAP`(0) / `LV_LABEL_LONG_MODE_DOTS`(1) | Label 长文本模式（**实测 DOTS=1，不是 2**） |
| `LV_ROLLER_MODE_NORMAL`(0) / `LV_ROLLER_MODE_INFINITE`(1) | Roller 模式 |
| `LV_SPAN_MODE_FIXED`(0) / `LV_SPAN_MODE_EXPAND`(1) / `LV_SPAN_MODE_BREAK`(2) | SpanGroup 宽度模式 |
| `LV_SPAN_OVERFLOW_CLIP`(0) / `LV_SPAN_OVERFLOW_ELLIPSIS`(1) | SpanGroup 溢出处理 |
| `LV_TEXT_ALIGN_AUTO`(0) / `LEFT`(1) / `CENTER`(2) / `RIGHT`(3) | 文本对齐 |
| `LV_IME_PINYIN_MODE_K26`(0) / `K9`(1) / `K9_NUMBER`(2) | 拼音输入法键盘布局 |
| `LV_IMAGE_ALIGN_*` | 图像对齐 |
| `LV_RESULT_OK`(1) / `LV_RESULT_INVALID`(0) | 结果码（**注意与直觉相反**：OK=1） |

---

## 9. 边界与限制

### 9.1 不支持的能力

- 视频播放（解码链路不在本库范围；可走 LVGL 的 GStreamer 源或 v4l2m2m → `ImageBuffer`）
- GPU 加速渲染（当前为纯 CPU 软渲染）
- 事件回调里的异常跨语言传播

### 9.2 需要自己配 `lv_conf.h`

下列能力取决于静态库编译时的开关（见 [编译指南](build-guide.md)）：

| 能力 | 开关 |
|---|---|
| FreeType 字体（完整中文） | `LV_USE_FREETYPE` |
| PNG 图片文件（`Image.fromFile`） | `LV_USE_LODEPNG` + `LV_USE_FS_STDIO`（驱动器字母 `LV_FS_STDIO_LETTER`） |
| 中文拼音输入法（`ImePinyin`） | `LV_USE_IME_PINYIN` + `LV_IME_PINYIN_USE_DEFAULT_DICT` |
| 内存/FPS 监控 | `LV_USE_SYSMON` + `LV_USE_PERF_MONITOR` + `LV_USE_MEM_MONITOR` |
| PNG/JPG/GIF/WebP 解码 | `LV_USE_LODEPNG` / `LV_USE_LIBPNG` / `LV_USE_TJPGD` / `LV_USE_GIF` / `LV_USE_LIBWEBP` |
| DRM / fbdev / evdev | `LV_USE_LINUX_DRM` / `LV_USE_LINUX_FBDEV` / `LV_USE_EVDEV` |

开关没开时，对应 API 不会链接失败（都经垫片转发），而是运行期抛 `LvglException`。

### 9.3 从 `Event` 反查控件

`Event.target()` 返回的是**通用 `Widget` 视图**（只保证句柄相同），拿不到 `Slider.valueGet()` 这类控件专属方法。仓颉没有通用的运行时向下转型，**推荐做法是在闭包里直接捕获控件对象**：

```cangjie
let slider = Slider(scr)
slider.onEvent(LV_EVENT_VALUE_CHANGED) { _ =>
    println("值是 ${slider.valueGet()}")   // 推荐
}
```

如果事件来源不确定（例如多个控件共用一个回调），就让每个控件各自注册一个自己的闭包，而不是在回调里猜类型。

### 9.3.1 回调里不能捕获局部可变变量

这是仓颉的语言规则，不是本库的限制：**捕获了局部 `var` 的闭包不能作为值传出**（只能立即调用），否则编译报

```
error: lambda capturing mutable variables needs to be called directly
```

所以需要跨回调保持的状态（计数器、缓存、状态机）要放**模块级变量**或某个对象字段里：

```cangjie
var clickCount: Int32 = 0        // 模块级

...
btn.onClick {
    clickCount += 1              // ✅ 引用模块级变量
}
```

```cangjie
var count = 0                    // ❌ 局部 var
btn.onClick {
    count += 1                   // 编译报错
}
```

### 9.4 控件覆盖情况

已覆盖：`obj`(Container) / `label` / `button` / `image` / `slider` / `arc` / `bar` / `switch` / `checkbox` / `dropdown` / `roller` / `textarea` / `keyboard` / `list` / `table` / `tabview` / `menu` / `msgbox` / `win` / `spinbox` / `scale` / `line` / `led` / `chart` / `canvas` / `span` / `calendar` / `animimg` / `ime_pinyin`。

仍未封装（C API 都已在 FFI 层可直接用，需要时按现有模式补一层 class）：

`lv_buttonmatrix`、`lv_spinner`、`lv_imagebutton`、`lv_arclabel`、`lv_gif`、`lv_tileview`、`lv_lottie`、`lv_3dtexture`、`lv_property`。

> **`lv_colorwheel` 不存在于 LVGL 9.5**：上游源码树 `src/widgets/` 里已没有该控件，配置宏 `LV_USE_COLORWHEEL` 也一并消失，因此本库不提供、也没有迁移路径。需要取色器时用 `Canvas` 自绘，或等上游后续方案。
