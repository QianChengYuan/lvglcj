# 常见问题（按现象查）

## 目录

- [A. 编译 / 链接阶段](#a-编译--链接阶段)
- [B. 启动阶段](#b-启动阶段)
- [C. 显示与渲染](#c-显示与渲染)
- [D. 中文与字体](#d-中文与字体)
- [E. 输入与交互](#e-输入与交互)
- [F. 内存与性能](#f-内存与性能)
- [G. 仓颉语言层面的坑](#g-仓颉语言层面的坑)
- [G'. 单元测试相关](#g-单元测试相关)
- [H. 平台相关](#h-平台相关)

---

## A. 编译 / 链接阶段

### A1. `can not find the library 'lvgl' which is listed in 'ffi.c' field`

没设 `LVGLCJ_LIB_DIR`，或者设的目录里没有 `liblvgl.a`。

```powershell
$env:LVGLCJ_LIB_DIR = "lib/windows-x64"        # Windows
```
```bash
export LVGLCJ_LIB_DIR=lib/linux-x64        # WSL / Linux
```

`cjpm` 支持 `${VAR}` 替换但**不支持默认值** `${VAR:-xxx}`，所以这个变量必须显式给。

不想手填就用脚本，它会按平台自动挑目录并转成绝对路径：

```powershell
./scripts/build.ps1            # Windows
```
```bash
bash scripts/build.sh          # Linux / WSL
```

### A2. `the environment variable '${...:-...}' is wrong in cjpm.toml`

同上：`cjpm.toml` 里写了 shell 风格的默认值。只写 `${LVGLCJ_LIB_DIR}`，默认值放到脚本/文档里说明。

### A3. `the customized key 'xxx' is wrong, the example is 'cfg_1'`

`[profile.customized-option]` 的键名只能是 `cfg`、`cfg_1`、`cfg_2`……，并且 `cjpm build --cfg` **只匹配字面量 `cfg`**。用 `target-sdl` 之类的名字会直接报错。

### A4. `undefined symbol: SDL_Init` / `undefined symbol: FT_Init_FreeType`

静态库不会传递自己的依赖。最终链接方（你的 app 包）必须补：

```toml
link-option = "-lSDL2 -lfreetype"
```

### A5. `skipping incompatible .../liblvgl.a when searching for -llvgl`

用了**别的平台**的库。例如在 x86_64 Linux 上指向了 `lib/linux-arm64`（aarch64），或反过来。按 [编译指南](build-guide.md#0-先搞清楚产物与选择方式) 选对目录。

顺带一提：仓颉侧交叉到 aarch64 还需要 **linux-aarch64 版 SDK**，光有 `lib/linux-arm64` 不够。

### A6. cmake 说 `Configuration file ... not found`，或后端全被静默关掉

LVGL 9.5 的参数是 **`LV_BUILD_CONF_PATH`**。写成老名 `LV_CONF_PATH` 不会报错，只会静默用默认配置——表现就是「编译通过但 SDL/DRM 全没启用」。

### A7. cmake 编译很慢 / 顺带编了一堆 C++

漏了 `-DCONFIG_LV_USE_THORVG_INTERNAL=OFF`，LVGL 会把 ThorVG 也编一遍。

### A8. `drm.h: No such file or directory`（交叉编译）

`lv_linux_drm.c` include 的是 `<xf86drm.h>`、`<xf86drmMode.h>`、`<drm_fourcc.h>`，而交叉 gcc 不会搜宿主机的 `/usr/include`。把 `xf86drm*.h` 和 `/usr/include/libdrm/*.h` 拷到一个独立目录再 `-I`（仓库脚本用的是 `/opt/arm64-include`）。

### A9. `LV_USE_MEM_MONITOR redefined`

`LV_USE_SYSMON` 为 0 时，LVGL 会把 `LV_USE_PERF_MONITOR`/`LV_USE_MEM_MONITOR` 强改回 0。想开监控必须先 `#define LV_USE_SYSMON 1`。

### A10. `there is no '.cj' file in directory 'src/shim'`

C 垫片被放进了 `src/` 下。`src-dir` 下的非仓颉目录会被 cjpm 每次构建都警告一次——本仓库把 C 代码放在 `native/`（`native/shim/`、`native/config/`），`src/` 下只留 `.cj`。

### A11. 怀疑 `LV_*` 常量值不对（行为诡异但编译通过）

这类错误最阴：常量是 `public const` 手写的，写错一位不会报错，只会在运行时表现成「点击没反应」「状态判断反了」。

排查方法——让 C 编译器打印真实值，和你定义的值对比：

```c
/* probe.c */
#include "lvgl.h"
#include <stdio.h>
int main(void) {
    printf("CHECKABLE=0x%X SCROLL_CHAIN=0x%X\n",
           (unsigned)LV_OBJ_FLAG_CHECKABLE, (unsigned)LV_OBJ_FLAG_SCROLL_CHAIN);
    return 0;
}
```

```bash
gcc -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE \
    -I<lvgl 源码根> -I native/config/sdl -o probe probe.c && ./probe
```

本仓库已经把实测值固化成 `src/test/constants_test.cj` 回归测试，改常量后 `cjpm test` 会立刻拦住。

---

## B. 启动阶段

### B1. `error while loading shared libraries: libcangjie-runtime.so`

没加载仓颉 SDK 的环境变量（`LD_LIBRARY_PATH` 里要有 `runtime/lib/<平台>`）。

```bash
source /etc/profile.d/cangjie.sh     # 或官方 envsetup.sh
# 或者用登录 shell
bash -lc './target/release/bin/main widgets'
```

用 `wsl -d 发行版 -e bash -c "..."` 这类**非登录 shell** 最容易踩。

### B2. Windows 上提示缺 `SDL2.dll` / `libfreetype-6.dll`

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
```

或把这两个 DLL 拷到 exe 同目录。

### B2'. Windows 上进程一启动就 `0xC0000139`（或 `exit code 3221225785`，无任何输出）

抓到了**错版本**的 `libwinpthread-1.dll` / `libstdc++-6.dll`：仓颉 SDK 的 `tools\bin` 里也有这些
运行库，如果它在 `PATH` 里排在 `C:\msys64\ucrt64\bin` 之前就会被优先加载，入口点对不上。

关键在**顺序**，不只是"有没有加进 PATH"：

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + ($env:PATH -split ';' -ne 'C:\msys64\ucrt64\bin' -join ';')
```

`scripts/build.ps1` 会自动把 `ucrt64\bin` 挪到首位（不只是追加）。

### B3. `Input.evdev` 抛「创建设备失败」（桌面环境）

桌面构建里 `LV_USE_EVDEV=0`，`/dev/input/*` 也是 Linux 专有。桌面用 `Display.sdl()` 自带的 SDL 鼠标键盘即可，不要调 `Input.evdev`。

### B4. `Display.drm()` 抛「后端创建失败」

三种可能：

1. 当前构建没开 `LV_USE_LINUX_DRM`（Windows 必然如此）；
2. 树莓派没启用 KMS：`/boot/firmware/config.txt` 里要有 `dtoverlay=vc4-kms-v3d`，改完重启；
3. 设备节点权限：`ls -l /dev/dri/card0`、`sudo usermod -aG video,input $USER` 重新登录。

例外情况：如果你自己改过 `LV_RESULT_*` 常量，注意 **LVGL 里 `LV_RESULT_OK = 1`**（`INVALID` 在前），写反了会把成功当失败。

---

## C. 显示与渲染

### C1. 第一帧之后画面卡住

没给 LVGL 时间基准。本库在 `App.setup()` 里已挂 `lv_tick_set_cb`，所以：

- 确认调用了 `App.setup()`（而不是只 `lv_init`）；
- 自己接管主循环时，要保证 `lv_timer_handler()` 被周期性调用（`App.runOnce()`）。

### C2. 黑屏 / 只画了一部分

- fbdev：把渲染模式改 `DIRECT`（`disp.setRenderMode(LV_DISPLAY_RENDER_MODE_DIRECT)`），仍不行再 `disp.setForceRefresh(true)`（有性能代价）；
- 检查 `LV_MEM_SIZE` 是否太小（128 KB 跑复杂界面会分配失败，试 256 KB）；
- 检查 `LV_COLOR_DEPTH` 与面板实际色深是否一致。

### C3. 颜色偏色 / 红蓝反

用 `LV_COLOR_FORMAT_RGB565_SWAPPED`，或在 flush 路径里做 `lv_draw_sw_rgb565_swap`。`ImageBuffer` 写像素时也要按对应格式字节序填。

### C4. 分辨率不对

- HDMI 屏：先给屏上电再给板子上电；
- `fbset -fb /dev/fb0` 看内核实际模式；
- DRM 下 `connector_id = -1` 自动选第一个接口，多屏时可能需要指定。

### C5. 屏幕上有闪烁光标

内核控制台光标。树莓派在 `/boot/firmware/cmdline.txt` 加 `vt.global_cursor_default=0`。

### C6. 8bpp 彩色屏初始化失败

fbdev 只接受灰度 8bpp；彩色屏请改 16/32 位。

---

## D. 中文与字体

### D1. 中文全是方框

三连击排查：

1. **字体没启用**：`lv_conf.h` 里 `LV_USE_FREETYPE 1`（内置思源黑体子集只有 1338 字，"滑""块""概"等都可能缺）；
2. **字体没应用**：只给控件 `setFont` 不够，LVGL 默认主题会显式设 `text_font` 覆盖继承值，必须走 `Theme.default(..., font)`；
3. **字体文件不存在**：`Font.trySystemCjk()` 按固定候选路径找，找不到返回 `None` 就回退内置子集了。用 `Font.load("你的字体路径")` 显式指定。

```cangjie
let f = Font.trySystemCjk(size: 16) ?? Font.load("/usr/share/fonts/xxx.ttf")
Theme.default((0x1E,0x88,0xE5), (0x0F,0x9D,0x58), false, f)
disp.screen().setFont(f)
```

### D2. Windows 正常，WSL/Linux 下是方框

Linux 默认没装中文字体：

```bash
sudo apt install fonts-noto-cjk     # → /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
```

### D3. `freetype already initialized`

`lv_init()` 内部已经调用过 `lv_freetype_init()`。再次调用会返回 `LV_RESULT_INVALID`（"already initialized"）。不要重复初始化。

### D4. 换字体后界面没变化

同上 D1-2：主题在初始化时就把 `text_font` 写进了控件；要么重建主题（重新 `Theme.default` 并 `lv_theme_apply`），要么给控件/容器单独 `setFont`。

### D5. 中文正常了，英文/数字却是方框

字体本身**不含拉丁字形**。典型例子是树莓派（Raspberry Pi OS）唯一自带的中文字体
`/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf`：它的 charset 从 `U+0020` 直接跳到 `U+0E3F`，
中间的基本拉丁字母一个都没有 —— 于是中文好看了，`LVGL 9.5` 变成 `□□□□ □.□`。

LVGL 9.5 的字体带缺字回退链，挂一个含拉丁的字体即可：

```cangjie
let f = Font.trySystemCjk(size: 16) ?? Font.defaultFont()
f.setFallback(Font.montserrat(16))     // ASCII 交给 Montserrat
Theme.default((0x1E,0x88,0xE5), (0x0F,0x9D,0x58), false, f)
```

排查手段：`fc-query -f "%{charset}\n" 字体文件 | tr ' ' '\n' | head` 看有没有 `21-7e` 段。

注意回退链只能挂在 `Font.load` / `Font.systemCjk` 加载出来的字体上：`Font.montserrat` / `Font.defaultFont` 是链接进只读段的 `const lv_font_t`，写它的 `fallback` 会崩，所以 `setFallback` 会抛 `LvglException`。

---

## E. 输入与交互

### E1. 点了没反应

- 按钮被别的控件盖住（后创建的在上层）；
- 目标没开 `LV_OBJ_FLAG_CLICKABLE`（`widget.addFlag(LV_OBJ_FLAG_CLICKABLE)`）；
- 父容器 `LV_OBJ_FLAG_SCROLLABLE` 抢走了滑动/点击；
- 回调里抛异常被吞（**异常不能跨 C 边界**，务必在回调里 `try/catch`）。

### E2. 触摸坐标反了 / 偏移

```cangjie
touch.swapAxes(true)                    // X/Y 颠倒
touch.calibrate(0, 0, 4095, 4095)       // 原始量程 → 屏幕
```

### E3. 多点触摸只有第一个点生效

当前版本按单指针设备处理（`LV_INDEV_TYPE_POINTER` 一个实例）。多点需要 `lv_indev` 的多点支持，尚未封装。

### E4. `Input.discover()` 没有回调

evdev 发现是**轮询式**，需要主循环持续跑（`App.run()`）；桌面构建下 `LV_USE_EVDEV=0`，直接抛异常。

---

## F. 内存与性能

### F1. `Perf.fps()` 显示 0.99 / 1.0，看起来很低

正常。本库的 fps 统计的是「发生了真实渲染调度」的次数，静态界面 LVGL 只在有脏区时重绘。

### F2. `Perf.cpu()` 一直是 0

监控开关没开：

```c
#define LV_USE_SYSMON 1
#define LV_USE_PERF_MONITOR 1
#define LV_USE_MEM_MONITOR 1
```

并且需要在主循环里跑（`App.run()` / `App.runOnce()` 才会采样）。

### F3. 右下角那块 FPS/CPU 小字怎么去掉

那是 LVGL 自带的 sysmon 悬浮标签，`LV_USE_PERF_MONITOR=1` 时 display 一创建就会被挂上。两种去法：

```cangjie
let disp = Display.sdl(480, 272)
Perf.hideMonitor(disp: Some(disp))   // 运行时隐藏（采样照常，随时可 Perf.showMonitor() 恢复）
```

或者在 `lv_conf.h` 里 `#define LV_USE_PERF_MONITOR 0` 后重编静态库 —— 这样连采样定时器都不会创建，真正省 CPU。注意此时 `Perf.fps()` / `Perf.cpu()` 仍可用（那是本库自己在主循环里采的，与 sysmon 无关）。

### F3. `Mem.monitor()` 数字全是 0

同上，`LV_USE_MEM_MONITOR` 没开。另外 `LV_MEM_SIZE` 很小时统计也没参考价值。

### F4. 跑一会儿崩溃 / 内存持续增长

常见原因：

- **句柄泄漏**：每个 `Widget` 都对应一个 LVGL 对象，删了界面要 `finalize()`；反复创建/销毁列表项时尤其注意；
- **回调闭包累积**：`onEvent` 注册的闭包存在全局表里，对象销毁时不会自动清（当前实现的已知限制），高频重建控件时建议复用控件而不是反复新建；
- **`Style` 被提前回收**：LVGL 只存指针，`Style` 对象要活到控件销毁之后。

### F5. 界面刷新慢、CPU 吃满

- `App.run(idleMs: 5)` 的 `idleMs` 别设 0；
- 减少大面积半透明（`bgOpa < 255`）与大面积模糊；
- 图片预解码并常驻，别在切界面时现解；
- 树莓派上开 NEON：`LV_USE_DRAW_SW_ASM = LV_DRAW_SW_ASM_NEON`。

---

## G. 仓颉语言层面的坑

### G1. `lambda capturing mutable variables needs to be called directly`

闭包捕获了**局部 `var`** 又想把它当值传出去（比如传给 `onClick`/`Timer.every`）。把状态放模块级变量或对象字段：

```cangjie
var clickCount: Int32 = 0        // ✅ 模块级

btn.onClick {
    clickCount += 1
}
```

### G2. `[count]` 报 `mismatched types`

`Label.setTextFmt` 的第二个参数是 `Array<Int32>`。`var count = 0` 推出的是 `Int64`，要显式转：

```cangjie
counter.setTextFmt("点击次数：%d", [Int32(count)])
```

或者直接声明成 `var count: Int32 = 0`。

### G3. 非命名参数不能带名字

默认值只能声明在命名参数上，调用也必须带名字：

```cangjie
Display.drm(card: "/dev/dri/card1")     // ✅
Theme.default(primary: (...), ...)      // ❌ 这几个是普通参数
```

### G4. `used before being defined`

仓颉**顶层声明顺序敏感**：常量/变量必须写在引用它的函数之前。写回调分发函数时尤其容易踩（先声明回调表，再写 `@C` 分发函数，再写 class）。

### G5. 顶层 `main` 不加 `func`

```cangjie
main() { ... }        // ✅
public func main()    // ❌
```

### G6. 回调里抛异常会不会把进程带崩？

库已经在 C 边界统一兜底：`onEvent`、`Timer`、`App.post` 任务里的 `Exception` 不会跨语言传播。默认打印到控制台；想看日志/弹错误页就注册处理器：

```cangjie
App.onCallbackError {e =>
    println("UI 回调失败：${e.message}")
}
```

处理器本身仍在主线程执行，别再抛异常或做阻塞 IO。未注册时只打印，不会 abort。

### G7. `ambiguous use of 'Timer'`（同时导入 `std.sync.*`）

`std.sync` 也有一个 `Timer`。两个包都通配导入时，写 `Timer.every` 会歧义。用库提供的无冲突别名：

```cangjie
import lvglcj.*
import std.sync.*

LvglTimer.every(1000) { ... }    // ✅ 等价于 lvglcj.Timer
```

或者只导入需要的符号，避免 `std.sync.*` 通配。

### G8. 后台线程里更新控件，偶尔花屏 / 崩在 LVGL 内部

LVGL 不是线程安全的，所有 `lv_*` 必须在同一线程。后台线程（网络、采集、解码）只能走 `App.post`：

```cangjie
spawn {
    let data = fetch()
    App.post { label.text(data) }     // ✅ 下一轮主循环在主线程执行
}
```

想在开发期就抓住误用，打开跨线程断言：

```cangjie
App.enableThreadAssert(true)          // 调试构建里开
```

打开后，`Widget.onEvent`、`Timer.every/once`、`Style.applyTo` 在非 UI 线程调用会抛
`LvglException`（信息里带当前线程 id 和 UI 线程 id），而不是留到运行时变成堆损坏。

### G9. 析构函数（`~init`）不在主线程执行

**实测**：仓颉 1.2.0 的终结器跑在独立的 GC 线程（主线程 `Thread.currentThread.id == 1`，
所有 `~init` 都是 `id == 2`）。所以"在析构里调 `lv_*`"是跨线程操作。

库内的处理：

- `Style.~init` 的 `lv_style_delete` 会改 LVGL 样式链表 → 经 `App.releaseStyle()`
  回投到 UI 线程，下一轮 `runOnce()` 执行；
- 只做 `LibC.free` / `lv_draw_buf_destroy` 的终结器（`Line`、`Calendar`、`AnimImage`、
  `ImageBuffer`、`ImageDsc`、`Canvas`）跨线程安全，保持同步释放。

副作用：如果从来不跑 `App.run()` / `App.runOnce()`，回投的样式释放任务不会执行
（每个样式泄漏一两百字节）。这是刻意取舍 —— 宁可变慢泄漏，也不要在渲染中途动 LVGL 内部结构。

---

## G'. 单元测试相关

### G'1. `Illegal parameters for @Tag["xxx"]`

`@Tag` 的标签必须是**标识符**，不能是字符串字面量：

```cangjie
@Tag[requires_display]        // ✅
@Tag["requires_display"]      // ❌ macro evaluation has failed
```

### G'2. `@ExpectThrows[T] { ... }` 报 `expected declaration`

`@ExpectThrows` 是**括号**形式，不接受尾随 lambda：

```cangjie
@ExpectThrows[LvglException](buf.writePixels(shortArray))   // ✅
@ExpectThrows[LvglException] { buf.writePixels(shortArray) } // ❌
```

### G'3. 测试里 `set_size` 之后 `width()` 读到 0

LVGL 的 `coords` 要经过一次布局计算才更新。设置尺寸后先泵一次主循环再断言：

```cangjie
box.size(120, 40)
App.runOnce()          // 让 layout timer 跑一轮
@Expect(box.width(), 120)
```

### G'4. 某个用例卡住直到 60 秒超时

多半是碰了不该碰的句柄。例如对**内置字体**调用 `Font.close()` 会卡死——它不是 FreeType 创建的，`lv_freetype_font_delete` 找不到对应的 face。本仓库已修复（`Font` 内部记录所有权，内置字体的 `close()` 变空操作）。

排查手段：`cjpm test --filter="ClassName.caseName"` 单独跑，配合 `--timeout-each=5s` 快速定位。

---

## H. 平台相关

### H1. WSL 里跑不起来

WSL2 没有 `/dev/dri`、`/dev/fb0`，必须用 SDL 后端 + WSLg：

```bash
export SDL_VIDEODRIVER=x11     # 必要时显式指定
./target/release/bin/main widgets
```

确认 WSLg 可用：`echo $DISPLAY` 应为 `:0`。

### H2. WSL 里 `cjc` / `ninja` / `git` 行为诡异

WSL 默认把 Windows 的 `PATH` 注入 Linux，会命中 `cjc.exe`、MSYS2 的 `ninja` 等。编辑 `/etc/wsl.conf`：

```ini
[interop]
appendWindowsPath = false
```

然后 `wsl --terminate <发行版>` 重进。

### H3. Windows 下 gcc 说文件不存在（路径明明存在）

把 `C:\a\b` 传给 MSYS2 的 gcc/cmake 时反斜杠会被当转义符。统一用正斜杠 `C:/a/b`。

### H4. Windows 链接全错

用了 32 位 `mingw32` 或 `clang64` 的库。`cjc` 目标是 `x86_64-w64-mingw32`，只能用 **ucrt64**。

### H5. Pi 上权限不足打不开设备

```bash
sudo usermod -aG video,input $USER    # 重新登录生效
ls -l /dev/dri/card0 /dev/input/event*
```

### H6. 想在没有 Pi 的情况下验证 aarch64 产物

```bash
sudo apt install qemu-user-static
qemu-aarch64-static -L /usr/aarch64-linux-gnu ./main hello
```

只能验证「能不能跑起来、逻辑对不对」，**不能**验证真实渲染性能。

### H7. 想验证「没有悬垂指针 / 越界」这类内存问题

用 ASan，但必须先把 **LVGL 本体**用 `-fsanitize=address` 重编，预编译的 `lib/*/liblvgl.a`
没插桩、ASan 对它内部完全无效：

```bash
LVGL_SRC=/path/to/lvgl bash scripts/build-lvgl-asan.sh   # 产出 .build/asan-lib
bash scripts/asan-test.sh
```

两个坑：

- `cjpm.toml` 的 `link-option` 是直接交给 `ld` 的，不能写 `-fsanitize=address`
  （`ld` 会报 `-f may not be used without -shared`），要写 `-lasan` 并
  `LD_PRELOAD=$(gcc -print-file-name=libasan.so)`；`asan-test.sh` 都替你做了。
- 测试里要 `App.refreshNow()` 强制画一帧：`App.runOnce()` 可能没到 33ms 刷新时刻，
  绘制路径没执行，UAF 也就"测不出来"（这条是踩过的坑：旧版 `Line` 用例就是因为这个才一直绿）。
