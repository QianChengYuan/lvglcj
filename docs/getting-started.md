# 快速开始

目标：**在本机弹出一个 LVGL 窗口，显示中文并响应点击**。按下面顺序走，卡住时对照 [常见问题](faq.md)。

## 1. 确认前置

```bash
cjc -v      # 需要 Cangjie Compiler: 1.2.0 (cjnative)
cjpm -v     # 1.2.0
```

再确认 `lib/` 下已有对应平台的静态库：

| 你的环境 | 需要的目录 |
|---|---|
| Windows | `lib/windows-x64/` |
| WSL / Linux 桌面 | `lib/linux-x64/` |
| Raspberry Pi | `lib/linux-arm64/` |

目录里应该有 `liblvgl.a`、`liblvglcjshim.a`（约 2–3 MB / 9 KB）。**目录是空的**说明还没编 LVGL，见 [编译指南](build-guide.md)。

## 2. 建工程

新建目录，写 `cjpm.toml`：

```toml
[package]
cjc-version = "1.2.0"
name = "helloLvgl"
version = "0.1.0"
output-type = "executable"

# 静态库带不出依赖，这两行不能省
link-option = "-lSDL2 -lfreetype"

[dependencies]
lvglcj = { path = "../lvglcj" }     # 指向上面的仓库根目录

[profile.customized-option]
cfg = "--cfg=\"lv_backend=sdl\""
```

## 3. 写最小程序

`src/main.cj`：

```cangjie
import lvglcj.*

// 模块级计数器。仓颉不允许"捕获了局部可变变量的闭包"作为值传递
// （会报 lambda capturing mutable variables needs to be called directly），
// 所以需要跨回调保持的状态放模块级。
var clickCount: Int32 = 0

main() {
    // 1) 初始化：lv_init + 挂单调时钟（不挂 tick，画面第一帧后就会卡死）
    App.setup()

    // 2) 显示后端：桌面用 SDL，Pi 上换成 Display.drm()
    let disp = Display.sdl(480, 272)

    // 3) 字体与主题：内置字体没有这几个汉字，加载系统中文字体
    let font = Font.trySystemCjk(size: 16) ?? Font.defaultFont()
    Theme.default((0x1E, 0x88, 0xE5), (0x0F, 0x9D, 0x58), false, font)

    // 4) 界面
    let scr = disp.screen()
    scr.setStyleBgColor(0xF5, 0xF5, 0xF5)

    let title = Label(scr)
    title.text("你好，仓颉 + LVGL")
    title.align(LV_ALIGN_TOP_MID, dy: 24)

    let btn = Button(scr)
    btn.size(160, 48)
    btn.center()
    let btnText = Label(btn)
    btnText.text("点我")
    btnText.center()

    let counter = Label(scr)
    counter.text("点击次数：0")
    counter.align(LV_ALIGN_BOTTOM_MID, dy: -24)

    // 回调在主线程执行，可安全改控件；状态用模块级变量（见文件开头说明）
    btn.onClick {
        clickCount += 1
        counter.setTextFmt("点击次数：%d", [clickCount])
    }

    // 5) 主循环
    App.run()
}
```

> 如果你是把这段代码贴进已有工程，注意 `main.cj` 首行要有 `package <包名>`，且包名要跟 `cjpm.toml` 的 `[package] name` 一致（cjpm 会校验）。

## 4. 编译运行

**Windows（PowerShell）**

```powershell
$env:LVGLCJ_LIB_DIR = "<仓库路径>/lib/windows-x64"   # 指向真正的库目录
cjpm build --cfg
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH   # 运行期 DLL
./target/release/bin/main.exe
```

**WSL / Linux**

```bash
export LVGLCJ_LIB_DIR=/path/to/lvglcj/lib/linux-x64
cjpm build --cfg
./target/release/bin/main
```

看到窗口、中文正常、点按钮数字会加，就算跑通了。

## 5. 直接跑仓库自带的九个示例

不想自己写代码，就先看示例：

```bash
cd examples
export LVGLCJ_LIB_DIR=../lib/linux-x64      # Windows 用 ../lib/windows-x64
cjpm build --cfg
./target/release/bin/main hello             # 最小窗口
./target/release/bin/main widgets           # 控件总览
./target/release/bin/main touch             # 触摸/指针 + 校准
./target/release/bin/main image             # RGB565 像素缓冲直出
./target/release/bin/main canvas            # Canvas 自绘仪表
./target/release/bin/main perf              # FPS / CPU / 内存
./target/release/bin/main rich              # 富文本 / 日历 / 帧动画（SpanGroup、Calendar、AnimImage）
./target/release/bin/main file logo.png     # 从 PNG 文件加载（Image.fromFile）
./target/release/bin/main thread            # 后台线程 App.post 刷 UI + 回调异常兜底
```

示例源码都在 `examples/src/main.cj`，是学习 API 最快的入口。

## 6. 换成真机的样子

把显示后端换掉即可，其它代码不动：

```cangjie
let disp = try {
    Display.drm()                            // 树莓派：DRM/KMS
} catch (e: LvglException) {
    println("DRM 不可用（${e.message}），退回 fbdev")
    Display.fbdev()                          // 老内核兜底
}
```

触摸输入：

```cangjie
let touch = Input.evdev(LV_INDEV_TYPE_POINTER, "/dev/input/event0")
touch.swapAxes(false)                        // 坐标颠倒时改 true
touch.calibrate(0, 0, 4095, 4095)            // 按面板实际量程
touch.attach(disp)
```

## 7. 下一步

- 控件清单与全部方法：[API 参考](api-reference.md)
- 换平台 / 自己编 LVGL / 交叉编译：[编译指南](build-guide.md)
- 报错排查：[常见问题](faq.md)

## 附：一个可复用的界面骨架

```cangjie
import lvglcj.*

var uptimeSec: Int32 = 0      // 需要跨回调保持的状态放模块级

main() {
    App.setup()
    let disp = Display.sdl(480, 272)
    let font = Font.trySystemCjk(size: 16) ?? Font.defaultFont()
    Theme.default((0x1E, 0x88, 0xE5), (0x0F, 0x9D, 0x58), false, font)

    let scr = disp.screen()
    scr.setStyleBgColor(0xFA, 0xFA, 0xFA)

    // 标题栏
    let header = Container(scr)
    header.size(480, 40)
    header.align(LV_ALIGN_TOP_MID)
    header.setStyleBgColor(0x1E, 0x88, 0xE5)
    header.setStyleRadius(0)
    let title = Label(header)
    title.text("设备面板")
    title.setStyleTextColor(0xFF, 0xFF, 0xFF)
    title.align(LV_ALIGN_LEFT_MID, dx: 12)

    // 内容区
    let body = Container(scr)
    body.size(456, 200)
    body.align(LV_ALIGN_TOP_MID, dy: 48)
    body.setStyleBgColor(0xFF, 0xFF, 0xFF)
    body.setStyleRadius(8)

    let names = ["温度", "湿度", "气压"]
    var i: Int64 = 0
    while (i < Int64(names.size)) {
        let item = Label(body)
        item.text("${names[i]}：--")
        item.align(LV_ALIGN_TOP_LEFT, dx: 12, dy: 12 + Int32(i) * 32)
        i += 1
    }

    // 每秒刷新一次（回调在主线程，可安全操作控件）
    let clock = Label(scr)
    clock.align(LV_ALIGN_BOTTOM_MID, dy: -8)
    Timer.every(1000) {
        uptimeSec += 1
        clock.setTextFmt("已运行 %d 秒", [uptimeSec])
    }

    App.run()
}
```
