# lvglcj — 仓颉 (Cangjie) 语言的 LVGL 封装库

作者：yuan_1992

## 文档

| 文档 | 内容 |
|---|---|
| [docs/快速开始](docs/getting-started.md) | 15 分钟在本机跑出第一个 LVGL 窗口（含可编译的完整示例） |
| [docs/编译指南](docs/build-guide.md) | Windows（MSYS2）/ WSL / aarch64 交叉三条构建路径，依赖、参数、排错 |
| [docs/API 参考](docs/api-reference.md) | 友好层全部公开类型、方法、`LV_*` 常量 |
| [docs/常见问题](docs/faq.md) | 按现象索引的排障手册（编译 / 启动 / 显示 / 中文 / 输入 / 性能 / 平台） |
| [docs/README](docs/README.md) | 文档索引与 30 秒速览 |

基于仓颉 FFI（`foreign`）对 LVGL 共享库/静态库的封装，分两层：

- **友好 API 层**（`lvglcj`）：显示后端、输入设备、控件、样式、图像、画布、定时器、主循环等高层能力，对外不暴露 C 指针细节，推荐日常使用。
- **底层 FFI 层**（`src/ffi_*.cj`）：逐函数映射 LVGL C API（`lvxxx_cjbindwrapper`），需要直接操作 `lv_display_t` / `lv_obj_t` / `lv_indev_t` / `lv_image_dsc_t` 等句柄时使用。
  > 实现约束（cjc 1.2.0 实测）：`foreign` 声明不允许任何访问修饰符（`public`/`protected` 均报 modifiers conflict），且**不可跨包导入**。因此 FFI 层与友好层同处根包 `lvglcj`，FFI 声明为包内 internal（对本模块可见、不导出给下游），下游模块经 `import lvglcj.*` 只能看到友好 API 与 `LV_*` 常量。

- 语言：仓颉 Cangjie **1.2.0**（`cjc` / `cjpm`；本机已安装该版本 SDK，`cjc -v` 显示 `Cangjie Compiler: 1.2.0 (cjnative)`，Target `x86_64-w64-mingw32`）
- LVGL：**9.5.0**（2026-02-18 发布的稳定版，对应上游 tag `v9.5.0`，发布日期已经克隆上游源码以 `git log` 核实）
- 开发机：**Windows 10/11 + MSYS2 UCRT64**（已实测全链路）或 **WSL2（Ubuntu 22.04/24.04，x86_64）**
- 目标机：**Raspberry Pi Zero 2 W**（BCM2710A1，Cortex-A53 四核 1 GHz，512 MB LPDDR2，VideoCore IV，Wi-Fi 2.4G）
- 后端：优先 **DRM/KMS**（`/dev/dri/card0`），兼容 **fbdev**（`/dev/fb0`），输入用 **evdev**；开发机统一用 **SDL2**
- 协议：本库 **MIT**；LVGL **MIT**（见「九、许可与合规」）

> 目标机以 **Raspberry Pi Zero 2 W** 为准撰写。若你指的是其他树莓派型号（4B / 5 / CM4），只需替换交叉工具链 sysroot 与 `lv_conf.h` 中的分辨率/色深，其余章节通用。

---

## 〇、开发与部署拓扑

```
┌──────────── 开发机（Windows + MSYS2 UCRT64 / WSL2 Ubuntu） ────────────┐
│  编码 / cjpm 依赖管理 / 交叉编译                                       │
│                                                                        │
│  lvglcj 垫片 ──┐                                                       │
│                ├─► gcc(ucrt64) / aarch64-linux-gnu-gcc ─► liblvgl.a    │
│  LVGL 9.5 源码 ┘                                          + liblvglcjshim.a
│                                                     │                   │
│  仓颉 SDK (cjc) ──► cjpm build --cfg ──► bin/main.exe / bin/main       │
│                                                     │                   │
│  ── 本机验证 ──                                     │                   │
│  SDL2 后端，Windows 直接弹窗 / WSL 走 WSLg 弹窗                        │
└──────────────────────────────┬────────────────────────────────────────┘
                               │  scp / rsync over Wi-Fi（SSH）
                               ▼
┌──────────────── Raspberry Pi Zero 2 W (aarch64) ──────────────────────┐
│  /dev/dri/card0 (vc4-kms-v3d)   /dev/input/eventX (触摸/鼠标/键盘)     │
│  ./main  →  单文件，已静态链入仓颉运行时 + LVGL，无需 CANGJIE_HOME     │
└───────────────────────────────────────────────────────────────────────┘
```

**为什么开发机不能用真显示后端**：WSL2 / Windows 都没有 `/dev/dri` 与 `/dev/fb0`，fbdev / DRM 后端在本机根本跑不起来。所以开发机统一走 **SDL2 后端**（Windows 原生弹窗、WSL 走 WSLg）验证 UI 逻辑与交互，真机只做最终联调（显示/触摸/性能）。

> 非 Linux 构建里 `LV_USE_LINUX_DRM` / `LV_USE_LINUX_FBDEV` / `LV_USE_EVDEV` 为 0，liblvgl.a 中不存在这些符号。库内的 `Display.drm()` / `Display.fbdev()` / `Input.evdev()` 统一经 C 垫片转发：开关关闭时垫片返回 NULL / `LV_RESULT_INVALID`，仓颉侧抛 `LvglException` 而不是链接失败。示例里 `try { Display.drm() } catch { Display.sdl(...) }` 的回退逻辑因此在任何平台都能编译运行。

---

## 一、功能特性（完整清单）

### 1. 底层 FFI 层（`src/ffi_*.cj`）绑定的 LVGL 模块

| LVGL 模块 | 绑定范围（均为 `lvxxx_cjbindwrapper` 形式） |
|---|---|
| **核心 core** | `lv_init`/`lv_deinit`、`LVGL_VERSION_MAJOR/MINOR/PATCH`（CMake 生成的 `lv_version.h` 宏，编译期常量，无需垫片）、`lv_tick_inc`/`lv_tick_set_cb`/`lv_tick_get`、`lv_timer_handler`、`lv_timer_create`/`set_period`/`set_cb`/`ready`/`pause`/`resume`/`delete`、`lv_sleep_ms`、`lv_delay_ms` |
| **显示 display** | `lv_display_create`、`set_resolution`、`set_physical_resolution`、`set_offset`、`set_color_format`、`set_buffers`、`set_flush_cb`、`set_rotation`、`set_default`、`get_default`、`get_screen_active`、`lv_screen_load`/`lv_screen_active`、`lv_display_flush_ready`、`flush_is_last`、`get_horizontal_resolution`/`get_vertical_resolution` |
| **Linux 显示驱动** | `lv_linux_fbdev_create`/`lv_linux_fbdev_set_file`/`set_force_refresh`、`lv_linux_drm_create`/`lv_linux_drm_set_file`（以所用 9.5 头文件实际导出名为准） |
| **输入 indev** | `lv_indev_create`/`delete`、`set_type`、`set_read_cb`、`set_display`、`set_cursor`、`set_group`、`lv_indev_get_point` |
| **evdev 输入驱动** | `lv_evdev_create`、`lv_evdev_create_fd`、`lv_evdev_delete`、`lv_evdev_set_calibration`、`lv_evdev_set_swap_axes`、`lv_evdev_discovery_start`/`stop` |
| **基础对象 obj** | `lv_obj_create`/`delete`/`clean`、`set_size`/`set_width`/`set_height`、`set_pos`/`set_x`/`set_y`、`set_align`/`align`/`center`、`add_flag`/`remove_flag`、`add_state`/`remove_state`、`add_style`/`remove_style`、`add_event_cb`、`set_style_*` 快捷系列 |
| **控件 widgets** | `lv_label_*`、`lv_button_*`、`lv_image_*`、`lv_slider_*`、`lv_arc_*`、`lv_bar_*`、`lv_switch_*`、`lv_checkbox_*`、`lv_dropdown_*`、`lv_roller_*`、`lv_textarea_*`、`lv_keyboard_*`、`lv_list_*`、`lv_table_*`、`lv_tabview_*`、`lv_menu_*`、`lv_msgbox_*`、`lv_spinbox_*`、`lv_scale_*`、`lv_line_*`、`lv_led_*`、`lv_canvas_*`、`lv_win_*`、`lv_chart_*` |
| **样式 style** | `lv_style_init`/`reset`、`lv_style_set_bg_color`/`bg_opa`/`radius`/`border_width`/`border_color`/`pad_all`/`text_font`/`text_color`/`shadow_width`/`shadow_opa`（9.5 起阴影/模糊为原生能力） |
| **图像 image** | `lv_image_create`、`lv_image_set_src`、`set_rotation`、`set_scale`、`set_pivot`、`set_inner_align`、`lv_image_dsc_t` 构造与填充 |
| **画布 canvas** | `lv_canvas_create`、`set_buffer`、`set_palette`、`fill_bg`、`draw_rect`、`draw_text`、`set_px`、`copy_buffer` |
| **字体 font** | `lv_font_montserrat_N` 系列、`lv_font_default`、字体加载/释放（Freetype）、控件自定义字体 |
| **主题 theme** | `lv_theme_default_init(disp, primary, secondary, dark, font)`、`lv_theme_apply`、`lv_obj_remove_theme`（v9 主题管理 API） |
| **内存 / 诊断** | `lv_mem_monitor`、`LV_USE_PERF_MONITOR`（FPS/CPU）、`LV_USE_MEM_MONITOR`（内存/碎片） |
| **常量** | `LV_COLOR_FORMAT_*`（`RGB565`/`RGB565_SWAPPED`/`RGB888`/`XRGB8888`/`ARGB8888`/`L8`/`I1`）、`LV_DISPLAY_RENDER_MODE_*`、`LV_DISPLAY_ROTATION_*`、`LV_INDEV_TYPE_*`、`LV_ALIGN_*`、`LV_PART_*`、`LV_STATE_*`、`LV_OPA_*`、`LV_PCT()` 等 |

**不透明类型**（仓颉侧只持句柄，不复制布局）：`lv_display_t`、`lv_indev_t`、`lv_obj_t`、`lv_style_t`、`lv_theme_t`、`lv_timer_t`、`lv_draw_buf_t`、`lv_font_t`、`lv_event_t`、`lv_anim_t`、`lv_group_t`、`lv_image_decoder_t`。

**按值结构体**（需与 C 布局一致，用 offsetof 实测）：`lv_area_t`（`x1/y1/x2/y2`，int32×4）、`lv_point_t`（`x/y`，int32×2）、`lv_color_t` / `lv_color32_t`、`lv_image_header_t`（位域：`magic`/`cf`/`flags`/`w`/`h`/`stride`/`reserved_2`）、`lv_image_dsc_t`（`header` + `data_size` + `data` + `reserved`/`reserved_2`）、`lv_indev_data_t`、`lv_mem_monitor_t`。

### 2. 为什么必须有一层 C 垫片

LVGL 头文件里塞满了 **`static inline` 函数和宏**（`LV_PCT()`、`LV_HOR_RES`、`LV_OPA_50`、`LV_IMAGE_HEADER_MAGIC` 等宏/导出常量，以及各模块私有的 inline 辅助函数……），这些在 `.so/.a` 里**没有可链接符号**，`foreign` 声明必然在链接期报 undefined symbol。因此新增一层极薄的 C 垫片：

```c
/* native/shim/lvgl_shim.c —— 把宏/inline 包成真函数，全部以 _cjbindwrapper 结尾 */
#include "lvgl.h"

uint32_t lv_color_hex_cjbindwrapper(uint32_t hex)      { return lv_color_hex(hex).full; }
int32_t  lv_pct_cjbindwrapper(int32_t x)               { return LV_PCT(x); }  /* LV_PCT 是宏，须包一层 */
void     lv_obj_set_size_cjbindwrapper(lv_obj_t *o, int32_t w, int32_t h) { lv_obj_set_size(o, w, h); }
size_t   lv_sizeof_style_cjbindwrapper(void)           { return sizeof(lv_style_t); }
size_t   lv_sizeof_image_dsc_cjbindwrapper(void)       { return sizeof(lv_image_dsc_t); }
/* 还有 offsetof 实测：lv_offsetof_image_dsc_data_cjbindwrapper() 等 */
```

垫片编译成 `liblvglcjshim.a`（与 `liblvgl.a` 一起静态链入），仓颉侧只 `foreign` 这些 `_cjbindwrapper` 符号。**规则：凡是头文件里没有独立符号的，一律先进垫片。**

### 3. 回调如何跨语言（LVGL 的灵魂）

LVGL 是回调驱动：flush、输入读取、定时器、事件都要 C 函数指针。仓颉侧用 `@C` 修饰的函数即可直接作为 `CFunc` 传入，调用须在 `unsafe` 上下文中：

```cangjie
// 不透明句柄：空 @C struct 占位（满足 CType 约束，仓颉侧只持地址、从不解引用）
@C
struct lv_display_t {}

@C
struct lv_area_t {}

@C
func cjFlushCb(disp: CPointer<lv_display_t>, area: CPointer<lv_area_t>, pxMap: CPointer<UInt8>): Unit {
    // 把 pxMap 的区域内容搬进 framebuffer / DRM dumb buffer
    unsafe { lv_display_flush_ready_cjbindwrapper(disp) }
}

// 注册：@C 函数直接按 CFunc 类型传入即可。
// 注意不能写 CFunc<...>(cjFlushCb)——CFunc 构造只接受 CPointer（从函数指针还原），不接受函数值
unsafe { lv_display_set_flush_cb_cjbindwrapper(disp, cjFlushCb) }
```

**线程模型硬约束**：LVGL **不是线程安全的**，所有 `lv_*` 调用必须在同一个线程内完成。仓颉侧约定——主线程持有 LVGL：
- `lv_timer_handler()` 只由主线程调用；
- 业务线程（网络、采集、日志）不得直接触碰 `lv_obj_*`，统一用 `App.post { ... }` 投递到主线程任务队列；
- flush 回调内禁止做仓颉侧的重量级分配（GC 停顿会直接体现在掉帧上）。

调试点：`App.enableThreadAssert(true)` 后，`Widget.onEvent` / `Timer.every` / `Style.applyTo`
在非 UI 线程调用会直接抛 `LvglException`（带两边的线程 id），不必等花屏或堆损坏才发现。

> **不要依赖终结器**：实测仓颉 1.2.0 的 `~init` 跑在独立 GC 线程上（主线程 id=1、终结器 id=2），
> 而且**触发时机由分配压力决定**（丢引用后 sleep 1s 不回收、UI 帧循环 300 帧一次都不触发、进程退出也不保证执行）。
> 更关键的是 `Widget` 是 `open` 类，仓颉**不允许 open 类带终结器**，所以控件只能显式释放：
> `finalize()` / `delete()` / `close()`，或者用 `try (w = Button(scr)) { ... }` 跟着作用域走。
> 控件里那些"LVGL 只存指针"的缓冲（顶点数组、日期数组、样式、图像描述符）则登记在按 `lv_obj` 地址
> 索引的保活表里，随控件删除同步释放，与 GC 时机无关。细节见 `docs/api-reference.md` 的「0.3 / 0.4」。

### 4. 友好 API 层（包 `lvglcj`）能力清单

| 能力 | 入口 | 说明 |
|---|---|---|
| 版本信息 | `version()` | 返回 LVGL 主/次/补丁版本号文本 |
| **主循环** | `App.run(...)` / `App.runOnce()` | 封装 `lv_init` → 显示/输入创建 → `lv_timer_handler` 循环 + 优雅退出；`tick` 自动用 `lv_tick_set_cb` 挂接单调时钟（缺了这步画面会「第一帧后卡死」） |
| **UI 线程调度** | `App.post(task)` | 任意线程安全入队，下一轮主循环在 UI 线程执行；每轮最多 256 个任务 |
| **显示后端** | `Display.drm(card)` / `Display.fbdev(dev)` / `Display.sdl(w,h)` | 三个后端同一接口；自动读取设备真实分辨率与色深，无需手填 |
| 显示调优 | `Display.setRotation/setColorFormat/setRenderMode/setForceRefresh` | 旋转（软旋转）、色深切换、partial/direct/full 模式、整屏强制刷新 |
| **输入** | `Input.evdev(type, dev)` / `Input.discover()` | 触摸/鼠标/键盘；`calibrate(minX,minY,maxX,maxY)`、`swapAxes(true)` 修正坐标错位 |
| 控件构建 | `Label` / `Button` / `Image` / `Slider` / `Arc` / `Bar` / `Switch` / `Checkbox` / `Dropdown` / `Roller` / `TextArea` / `Keyboard` / `List` / `Table` / `TabView` / `Menu` / `MsgBox` / `Chart` / `Canvas` / `Win` / **`SpanGroup`（富文本混排）** / **`Calendar`** / **`AnimImage`（帧动画）** / **`ImePinyin`（拼音输入法）** | 每个控件一个仓颉 class，链式调用，内部只持 `lv_obj_t` 句柄；`finalize()` 同步删除、`delete()` 异步删除，均幂等 |
| 事件 | `Widget.onEvent(mask, cb)` | 返回 `EventSubscription`，可 `cancel()`；控件删除时自动回收订阅；`Button.onClick`、`Switch/Checkbox.onChanged`、`Slider.onValueChanged` 提供带类型的快捷订阅 |
| 样式 | `Style()` | `bgColor/bgOpa/radius/border/pad/textFont/textColor/shadow` 等链式设置，`applyTo(obj, part)`；9.5 原生阴影/模糊可直接用 |
| **像素/图像** | `ImageBuffer(w, h, cf)` | 申请并持有一块 LVGL 可直接消费的像素缓冲；`toImageDsc()` 生成 `lv_image_dsc_t`（自动填 `magic`/`cf`/`w`/`h`/`stride`/`data_size`）；`writePixels(bytes)` 从仓颉 `Array<UInt8>` 拷入 |
| **图片文件** | `Image.fromFile(parent, path)` | PNG（内置 lodepng + STDIO 文件系统），C 垫片负责补 `A:` 驱动器前缀；路径不存在抛 `LvglException` |
| 色彩工具 | `Color.rgb565(r,g,b)` / `Color.argb8888(...)` | 产出与目标 `LV_COLOR_FORMAT` 匹配的字面量，避免手写移位出错 |
| 画布 | `Canvas(w,h)` | `fillBg` / `drawRect` / `drawText` / `setPx`，适合自绘仪表、波形、图表 |
| 定时器 | `Timer.every(ms, cb)` / `Timer.once(ms, cb)` | 返回 `TimerHandle`：`cancel/pause/resume/ready/setPeriod`；cb 运行在主线程，可直接操作控件；一次性定时器触发后自动失效 |
| 主题 | `Theme.default(primary, secondary, dark, font)` | 一行切换全局主题与深色模式 |
| 诊断 | `Perf.fps()` / `Mem.monitor()` | 读取 FPS/CPU 占用与内存碎片，配合 `LV_USE_PERF_MONITOR` |
| **确定性释放** | `Widget <: Resource` | `try (w = Button(scr)) { ... }` 出作用域（含异常路径）自动 `close()`，不依赖 GC；也支持显式 `finalize()`/`delete()` |
| 泄漏排查 | `App.enableWidgetTracking()` / `App.reportLiveWidgets()` | 开启后统计未释放控件（关闭时零开销），用于定位"忘了 finalize" |
| 错误处理 | 全部抛 `Exception` / `App.onCallbackError` | LVGL 9 的参数校验断言族（`LV_USE_ASSERT_NULL`/`LV_USE_ASSERT_MALLOC` 默认开启，`LV_USE_ASSERT_OBJ` 等可按需在 `lv_conf.h` 打开），本层把返回的 `LV_RESULT_INVALID` 转为异常；事件/定时器/post 任务中的回调异常统一兜底，可注册处理器 |

### 5. 平台支持矩阵（开发机 vs 真机）

| 项 | Windows x86_64（开发，已实测） | WSL2 x86_64（开发） | 树莓派 Zero 2 W aarch64（目标） |
|---|---|---|---|
| LVGL 版本 | 9.5.0 | 9.5.0 | 9.5.0（同一份源码） |
| 显示后端 | **SDL2**（原生窗口） | **SDL2**（WSLg 窗口） | **DRM/KMS** 优先，fbdev 兼容 |
| 输入后端 | SDL 指针/键盘；evdev 经垫片降级为不可用 | SDL 指针 / evdev | **evdev**（`/dev/input/eventX`） |
| 中文字体 | FreeType + 系统雅黑（`msyh.ttc`） | FreeType + Noto CJK | FreeType + `DroidSansFallbackFull.ttf`（该字体无拉丁字形，需 `Font.setFallback(Montserrat)` 补 ASCII）；内置思源黑体子集作兜底 |
| 链接形式 | `-lSDL2 -lfreetype` 动态 + LVGL 静态 | 同左 | LVGL 静态 + 仓颉运行时静态，产物单文件 |
| 构建命令 | `./scripts/build-lvgl-sdl.ps1` + `cjpm build --cfg` | `scripts/build-lvgl-sdl.sh` + `cjpm build --cfg` | `cjpm build`（交叉）或 Pi 上 `cjpm build`（原生） |
| 源码 / `cjpm.toml` | 同一份（用 `@When[os == "Linux" && arch == "aarch64"]` 做条件编译分流） | 同一份 | 同一份 |
| 用途 | UI 逻辑、交互、样式开发（最快） | UI 逻辑、交互、样式开发 | 显示/触摸/性能终验 |

### 6. 明确不在 v1 范围（Roadmap 与边界）

| 能力 | 状态 / 规划 |
|---|---|
| **视频播放** | ❌ v1 不做。路线：v1.1 接 LVGL 的 GStreamer 源（9.5 已支持无音轨源，可直接吃摄像头）；或走 v4l2m2m 硬解 → `ImageBuffer` → `lv_image` |
| 硬件加速渲染（OpenGL ES / EGL，VC4 支持 GLES2） | v2。v1 为纯 CPU 软渲染（已开 NEON） |
| 中文字体方案 | ✅ v1 已支持：`Font.systemCjk()` / `trySystemCjk()` 经 FreeType 加载系统 TTF/TTC，缺字用 `setFallback` 挂回退；内置思源黑体子集（1338 字）只作兜底 |
| SquareLine Studio / EEZ Studio 导出 UI 接入 | v2（导出 C → 由垫片层接入） |
| LVGL XML UI | 官方已把 XML 引擎移出主仓库，不跟进 |
| 多屏 / 多窗口 | v2 |
| 3D（glTF）/ 矢量图形（ThorVG） | 不在 Zero 2 W 的算力预算内，明确不做 |
| JPG / GIF / WebP 图片文件 | PNG 已支持（见 `Image.fromFile`，内置 lodepng）；其余格式需在 `lv_conf.h` 打开 `LV_USE_TJPGD` / `LV_USE_GIF` / `LV_USE_LIBWEBP` 后重编 `liblvgl.a`。纯像素数据走 `ImageBuffer` + `Image.setSource()`，无需解码器 |

---

## 二、LVGL 版本选型与获取（9.5.0）

### 为什么是 9.5.0

1. **v9 是必须跨过的坎**：v9 把 `lv_disp_drv_t` / `lv_disp_draw_buf_t` 换成 `lv_display_t` + `lv_display_set_buffers()`（**尺寸单位从像素数改为字节数**），`lv_disp_*`→`lv_display_*`、`img_*`→`image_*`、`scr`→`screen`、`lv_color_t` 语义统一为 RGB888、`LV_IMG_CF_*`→`LV_COLOR_FORMAT_*`。绑定层按 v8 写必然编译失败；
2. **9.5 是 2026-02-18 发布的稳定版**，原生阴影/模糊（`lv_style_set_shadow_*`/`lv_style_set_blur_*`/`lv_style_set_drop_shadow_*`）、RISC-V 向量加速（`LV_DRAW_SW_ASM_RISCV_V`）、WebP 解码（捆绑 libwebp）、GStreamer 无音轨源（音频管线按需链接）都已落地；
3. 后续 minor 只加特性不改 API，绑定层不会漂移。

### 方式 A：直接用仓库自带的预编译静态库（推荐）

三份产物**互不兼容**（目标格式不同），按平台分目录；配置源与产物分离：`native/config/sdl/lv_conf.h`（内含 `_WIN32` 分支，Windows/Linux 共用）、`native/config/pi/lv_conf.h`（Pi 专用）：

```
native/config/
├── sdl/lv_conf.h                       # 配置源（SDL 后端，Windows + WSL 共用）
└── pi/lv_conf.h                        # 配置源（Pi：DRM + evdev + RGB565）

lib/                                    # 只有编译产物，不含配置
├── windows-x64/     liblvgl.a  liblvglcjshim.a   # PE x86_64，Windows（MSYS2 UCRT64）
├── linux-x64/       liblvgl.a  liblvglcjshim.a   # ELF x86_64，WSL（SDL2 + WSLg）
├── linux-arm64/     liblvgl.a  liblvglcjshim.a   # ELF aarch64，Pi（DRM + evdev，tty 独占）
└── linux-arm64-sdl/ liblvgl.a  liblvglcjshim.a   # ELF aarch64，Pi（SDL 桌面 + FreeType 中文）
```

每个目录都有 `BUILD_INFO.md`（LVGL tag / 配置源及其 SHA-256 快照 / 构建命令）
与 `SHA256SUMS`（CI 强制校验），换库或重编后要一起更新。

用哪个目录由环境变量 `LVGLCJ_LIB_DIR` 决定（见 `cjpm.toml` 的 `[ffi.c]`）：

| 场景 | 设置 |
|---|---|
| Windows 本机 | `$env:LVGLCJ_LIB_DIR = "lib/windows-x64"` |
| WSL 本机验证 | `export LVGLCJ_LIB_DIR=lib/linux-x64` |
| 交叉/真机 Pi | `export LVGLCJ_LIB_DIR=lib/linux-arm64-sdl`（DRM 独占场景才用 `lib/linux-arm64`） |

> 不设这个变量，cjpm 会报 `can not find the library 'lvgl' which is listed in 'ffi.c' field`——这是最容易踩的第一个坑。
>
> **不用手动记**：`scripts/build.ps1` / `scripts/build.sh` 会按平台自动挑目录、转绝对路径并注入变量，见「六、构建与运行步骤 → 一键构建」。

> **Windows（MSYS2 UCRT64）已验证全链路跑通**：
>
> ```powershell
> # 1) 装工具链（只需一次，MSYS2 UCRT64 终端里执行）
> pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake `
>         mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-SDL2 `
>         mingw-w64-ucrt-x86_64-freetype mingw-w64-ucrt-x86_64-pkgconf
>
> # 2) 编 LVGL + 垫片 → lib/windows-x64/
> ./scripts/build-lvgl-sdl.ps1
>
> # 3) 编示例并运行（运行时 DLL 在 ucrt64/bin）
> $env:LVGLCJ_LIB_DIR = "lib/windows-x64"
> cd examples; cjpm build --cfg
> $env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
> ./target/release/bin/main.exe widgets
> ```
>
> 注意三点：
> 1. **必须用 64 位 ucrt64**（与 cjc 目标 `x86_64-w64-mingw32` 一致）；`mingw32`/`clang64` 的位数或 CRT 不匹配，链接必然失败；
> 2. 运行期需要 `SDL2.dll`、`libfreetype-6.dll` 在 `PATH`（即 `C:\msys64\ucrt64\bin`），否则启动即报缺 DLL；
> 3. 传路径给 MSYS2 的 gcc/cmake 一律用**正斜杠**（`C:/msys64/...`），反斜杠会被当作转义符。

> **WSL（Ubuntu 24.04）已验证全链路跑通**，见「六、构建与运行步骤 → WSL 准备」。

### 方式 B：自行交叉编译（需要改 lv_conf 时）

```bash
# WSL 里装交叉工具链与依赖
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu cmake ninja-build pkg-config
sudo apt install libdrm-dev:arm64 libevdev-dev:arm64        # DRM 后端 + evdev 输入
sudo apt install libsdl2-dev libsdl2-image-dev              # 仅 WSL 本机模拟验证用

# LVGL 本体
git clone -b v9.5.0 --depth 1 https://github.com/lvgl/lvgl.git
cmake -B build-pi -G Ninja -S lvgl \
  -DCMAKE_TOOLCHAIN_FILE=../cmake/toolchain-aarch64.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DCONFIG_LV_BUILD_EXAMPLES=OFF -DCONFIG_LV_BUILD_DEMOS=OFF \
  -DCONFIG_LV_USE_THORVG_INTERNAL=OFF \
  -DLV_BUILD_CONF_PATH=$PWD/lv_conf.h
cmake --build build-pi      # → liblvgl.a
```

> **两个 9.5 的坑**：
> 1. 配置项叫 `LV_BUILD_CONF_PATH`（9.2 及以前才是 `LV_CONF_PATH`）。传错名字 cmake **不报错**，只会在 `-- Using configuration` 里打印一个空值，然后静默用默认配置，结果是 SDL/DRM 后端全被关掉；
> 2. `CONFIG_LV_USE_THORVG_INTERNAL=OFF` 必须显式传，否则会顺带编一遍 ThorVG（几百个 C++ 文件，慢且把 libstdc++ 拖进静态库）。

`cmake/toolchain-aarch64.cmake`：

```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
```

### `lv_conf.h` 关键开关（目标机 / 模拟器两份）

| 宏 | Pi Zero 2 W | WSL / Windows SDL 模拟器 | 说明 |
|---|---|---|---|
| `LV_COLOR_DEPTH` | **16**（RGB565） | 32 | 512 MB 内存 + 软渲染，16 位是带宽与内存的最优解 |
| `LV_USE_LINUX_DRM` | **1** | 0 | 现代 KMS 路径，支持 modesetting |
| `LV_USE_LINUX_FBDEV` | 0（兜底时才开） | 0 | 老内核/无 DRM 时用 `/dev/fb0` |
| `LV_USE_SDL` | 0 | **1** | 桌面窗口验证（WSLg / Windows 原生） |
| `LV_USE_EVDEV` | **1** | Linux 上 1，Windows 上 **0** | Windows/MinGW 没有 `<linux/input.h>`，输入改用 SDL 鼠标/键盘；`native/config/sdl/lv_conf.h` 里按 `_WIN32` 分支处理 |
| `LV_USE_DRAW_SW_ASM` | **`LV_DRAW_SW_ASM_NEON`** | 默认 | Cortex-A53 的 NEON 加速软渲染 |
| `LV_USE_THORVG_INTERNAL` | **0** | 0 | Zero 2 W 上矢量图形性价比低，关掉省 Flash |
| `LV_USE_ASSERT_MEM_INTEGRITY` / `LV_USE_ASSERT_OBJ` | **0** | 1 | 发布版必须关，开着会显著变慢 |
| `LV_DEF_REFR_PERIOD` | **33**（≈30 fps） | 16 | 按面板刷新率与算力定 |
| `LV_MEM_SIZE` | **512 KB**（开了 FreeType，字形位图要吃 draw_buf） | 256 KB | LVGL 自带内存池 |
| `LV_USE_SYSMON` | 1（调试）→ 0（发布） | 1 | 9.5 起 PERF/MEM 监控挂在 SYSMON 下，`LV_USE_SYSMON=0` 会把它们强行改回 0 |
| `LV_USE_PERF_MONITOR` | 1（调试）→ 0（发布） | 1 | FPS / CPU 占用 |
| `LV_USE_FREETYPE` | **1** | **1** | 运行时加载系统 TTF/TTC 显示完整中文；开它需给编译器补 freetype 头文件路径（交叉编译见 `scripts/build-lvgl-pi.sh` 的 `FT_INC`），链接补 `-lfreetype` |
| `LV_USE_LODEPNG` | **1** | **1** | PNG 解码（`Image.fromFile`）；LVGL 内置、零外部依赖，约 +170 KB |
| `LV_USE_FS_STDIO` + `LV_FS_STDIO_LETTER` | **1** / `'A'` | **1** / `'A'` | 文件系统 STDIO 驱动；垫片把系统路径拼成 `A:<path>`。关掉则 `fromFile` 直接抛异常 |
| `LV_USE_IME_PINYIN` | **1** | **1** | 拼音输入法（`ImePinyin` 的候选词面板）；LVGL 9.5 默认 0，本仓库两份配置都显式打开并重编了静态库 |
| `LV_FONT_SOURCE_HAN_SANS_SC_16_CJK` | 1 | 1 | LVGL 内置思源黑体 16px 子集（仅 1338 字，覆盖不全，作为兜底） |

---

## 三、像素格式与内存预算（Pi Zero 2 W 专章）

512 MB RAM 是这条链路上唯一的硬约束。三个数字必须先算清楚：

| 分辨率 | 格式 | 每行字节 | 全帧 | 1/10 屏 partial |
|---|---|---|---|---|
| 320×240 | RGB565 | 640 B | 150 KB | 15 KB |
| 480×272 | RGB565 | 960 B | 255 KB | 26 KB |
| 800×480 | RGB565 | 1600 B | 750 KB | 75 KB |
| **1024×600** | **RGB565** | 2048 B | **1.17 MB** | **123 KB** |
| 1024×600 | ARGB8888 | 4096 B | **2.34 MB** | 246 KB |

**结论**：
- 默认 `LV_COLOR_DEPTH 16` + `LV_DISPLAY_RENDER_MODE_PARTIAL`，partial buffer 取 **1/10 屏**（1024×600 约 123 KB），是 Zero 2 W 的甜点；
- 只有当 UI 大面积动画、partial 明显撕裂时，才升到 `DIRECT` + 双缓冲（2×1.17 MB ≈ 2.34 MB，可接受）；
- **不要**在 1024×600 上用 ARGB8888 + FULL 模式：单缓冲就 2.34 MB，软渲染 alpha blend 会把 A53 打满；
- 若 SPI 小屏字节序反了，直接用 `LV_COLOR_FORMAT_RGB565_SWAPPED`，别在 flush 里手写 swap（省一次全缓冲遍历）。

---

## 四、目录结构

```
lvglcj/
├── cjpm.toml                  # 库包配置（output-type = static，[ffi.c] 声明 lvgl / lvglcjshim）
├── LICENSE                    # MIT
├── LICENSE.LVGL               # LVGL MIT 协议文本
├── cmake/
│   └── toolchain-aarch64.cmake    # WSL → aarch64 交叉编译工具链
├── native/                    # C 侧代码与配置（放在 src/ 之外，避免 cjpm 扫包告警）
│   ├── shim/lvgl_shim.c|.h    # 宏 / static inline → _cjbindwrapper；平台后端空实现
│   └── config/
│       ├── sdl/lv_conf.h      # SDL 后端配置源（Windows + WSL 共用，内含 _WIN32 分支）
│       └── pi/lv_conf.h       # Pi 专用配置（DRM + evdev + RGB565 + NEON）
├── src/                       # 纯仓颉源码（cjpm src-dir，根包 lvglcj）
│   ├── main.cj                # 根包占位文件（让 src 根目录被 cjpm 扫描）
│   ├── ffi_structs.cj         # FFI：不透明句柄 + 按值结构体（@C struct）
│   ├── ffi_core.cj            # FFI：lv_init / tick / timer / version
│   ├── ffi_display.cj         # FFI：lv_display_* + linux 显示驱动
│   ├── ffi_indev.cj           # FFI：lv_indev_* + evdev
│   ├── ffi_obj.cj             # FFI：lv_obj_* + LV_* 常量（flags/states/parts/aligns/events/formats）
│   ├── ffi_widgets.cj         # FFI：各控件
│   ├── ffi_draw.cj            # FFI：style / theme / mem / 垫片桥接
│   ├── util.cj                # 友好 API：版本/颜色/异常/内存诊断
│   ├── app.cj                 # 友好 API：App 生命周期、主循环、tick、定时器
│   ├── display.cj             # 友好 API：Display（DRM/fbdev/SDL）+ 渲染模式/旋转
│   ├── input.cj               # 友好 API：Input（evdev）+ 触摸校准
│   ├── widget.cj              # 友好 API：事件桥接 + Widget 基类 + Container
│   ├── widget_basic.cj        # 友好 API：文本 / 按钮 / 值 / 选择类控件
│   ├── widget_container.cj    # 友好 API：列表 / 表格 / 标签页 / 菜单 / 窗口
│   ├── widget_media.cj        # 友好 API：图像 / 图表 / 曲线 / 刻度 / LED
│   ├── widget_rich.cj         # 友好 API：富文本 span / 日历 / 帧动画 / 拼音输入法
│   ├── style.cj               # 友好 API：Style / Theme / Font（含 FreeType 字体加载）
│   ├── image.cj               # 友好 API：ImageBuffer / ImageDsc / Canvas
│   └── test/                  # 单元测试（package lvglcj.test，cjpm test 发现）
│       ├── test_support_test.cj   # 幂等 lv_init 辅助 + 冒烟用例
│       ├── version_test.cj    # 版本号 / 异常
│       ├── constants_test.cj  # LV_* 常量回归（钉死 LVGL 9.5 实测值）
│       ├── color_test.cj      # RGB565 / ARGB8888 位运算
│       ├── image_buffer_test.cj   # 像素缓冲尺寸 / 长度校验 / dsc
│       ├── style_test.cj      # Style 链式 / Font 工厂
│       └── widget_test.cj     # 控件行为（@Tag[requires_display]，默认跳过）
├── lib/                       # 预编译静态库（按平台，.a 随仓库发布）
│   ├── windows-x64/           # PE x86_64（MSYS2 UCRT64）
│   ├── linux-x64/             # ELF x86_64（WSL / Linux 桌面）
│   ├── linux-arm64/           # ELF aarch64（Pi：DRM + evdev，tty 独占）
│   └── linux-arm64-sdl/       # ELF aarch64（Pi：SDL 桌面 + FreeType 中文）
├── scripts/                   # 构建 / 部署脚本（ps1 与 sh 成对命名）
│   ├── build.ps1 / build.sh   # 一键构建：自动选库目录 + 注入 LVGLCJ_LIB_DIR → cjpm
│   ├── build-lvgl-sdl.ps1     # Windows：编 LVGL + 垫片 → lib/windows-x64
│   ├── build-lvgl-sdl.sh      # Linux/WSL：→ lib/linux-x64
│   ├── build-lvgl-pi.sh       # 交叉：→ lib/linux-arm64
│   ├── check.ps1              # cjfmt 格式检查 + cjlint 静态检查（本地与 CI 同一套）
│   └── deploy-pi.sh           # scp 产物到 Pi + 远程运行
├── docs/                      # 使用文档（快速开始 / 编译指南 / API / FAQ）
├── .build/                    # LVGL 构建中间目录（.gitignore，可删）
├── examples/                  # 独立示例工程（path 依赖引用本库）
│   └── src/main.cj            # hello / widgets / touch / image / canvas / perf / rich / file / thread 九个演示
└── target/                    # cjpm 构建产物（.gitignore）
```

**目录约定**（与同仓库其它仓颉项目保持一致）：

- `src/` 只放 `.cj`：任何非仓颉目录放进去都会触发 cjpm 的 "there is no '.cj' file in directory" 警告；
- `src/test/` 是测试包 `lvglcj.test` 的独立目录，文件名统一 `*_test.cj`；
- `native/` 放 C 代码与 `lv_conf.h`，`lib/` 只放编译好的 `.a`，配置与产物分离；
- `lib/<platform>/` 用平台名而非后端名（`windows-x64` / `linux-x64` / `linux-arm64`），避免"SDL 库到底能不能在 Windows 用"这类歧义；
- 构建中间产物统一进 `.build/`，与 cjpm 的 `target/` 分开。

> FFI 层为何在根包而非子包：`foreign` 声明不能带访问修饰符且不可跨包导入（cjc 1.2.0 实测），放在子包里父包无法使用。
> C 垫片为何在 `native/` 而非 `src/` 下：`src-dir` 下非仓颉目录会让 cjpm 每次构建都打印 "there is no '.cj' file in directory ..." 警告。

---

## 五、开发实施步骤（每一步做什么）

| # | 步骤 | 做什么 | 状态 |
|---|---|---|---|
| 1 | 项目骨架 | `cjpm.toml`、`.gitignore`、`LICENSE`、`LICENSE.LVGL`、目录结构 | ✅ |
| 2 | 获取 LVGL 9.5 | 三份静态库均已生成：`lib/windows-x64/`（Windows PE）、`lib/linux-x64/`（WSL ELF x86_64）、`lib/linux-arm64/`（aarch64 交叉，`Machine: AArch64` 已校验），产物随仓库发布 | ✅ |
| 3 | C 垫片层 | `native/shim/lvgl_shim.c`：把宏/inline/sizeof/offsetof 包成 `_cjbindwrapper`；非 Linux 后端（DRM/fbdev/evdev）给空实现保证跨平台可链接 | ✅ |
| 4 | 结构体偏移表 | `.cache/lvgl_offsets.c` 用交叉 gcc 对 9.5 头文件实测 offsetof，写入 `src/ffi_structs.cj`（`lv_area_t`/`lv_point_t`/`lv_image_header_t`/`lv_image_dsc_t`/`lv_indev_data_t`/`lv_mem_monitor_t`） | ✅ |
| 5 | FFI 声明层 | `ffi_core.cj`（init/tick/timer）→ `ffi_display.cj` → `ffi_indev.cj` → `ffi_obj.cj` → `ffi_widgets.cj` → `ffi_draw.cj`，每个宏/inline 配 `_cjbindwrapper` | ✅ |
| 6 | 友好 API 层 | `util.cj` → `app.cj`（主循环/tick）→ `display.cj` → `input.cj` → `widget.cj` → `style.cj` → `image.cj`；`ImageBuffer.toImageDsc()` 是喂像素给 LVGL 的核心 | ✅ |
| 7 | 示例项目 | `examples/`：①hello ②widgets ③touch ④image（RGB565 直出）⑤canvas（自绘仪表）⑥perf（FPS/内存）⑦rich（富文本 / 日历 / 帧动画）⑧file（`Image.fromFile` 加载 PNG）⑨thread（`App.post` 跨线程刷 UI + 回调异常兜底） | ✅ |
| 8 | 本机 SDL 验证 | Windows：九示例全部真实弹窗（LVGL Simulator + SDL 鼠标键盘）；WSL（Ubuntu 24.04 + WSLg）：编译通过，窗口用例受 WSLg 限制跳到真机/Windows 验证 | ✅ Windows + WSL |
| 9 | **真机联调（Pi Zero 2 W）** | SDL 后端在 Pi 桌面（labwc/Wayland）出图 + grim 截图确认中文/数字/自绘均正常；`Display.drm()` 直连未验证（桌面占着 DRM master，需切到 console 跑）；evdev 触摸校准待现场调 | 🟡 已跑通图形，DRM/触摸待验 |
| 10 | 文档与发布 | README 收尾、API 参考补全、Gitcode 发布 | 🟡 文档已成体系，发布待做 |

> 状态说明：步骤 1–8 已完成并双平台实测：
> - **Windows + MSYS2 UCRT64**：`./scripts/build-lvgl-sdl.ps1` → `lib/windows-x64/`；`cjpm build` 与 `examples` 的 `cjpm build --cfg` 均 0 error；九个示例逐一弹窗。
> - **WSL（Ubuntu-dev）+ WSLg**：`scripts/build-lvgl-sdl.sh` → `lib/linux-x64/`；`cjpm build` / `cjpm build --cfg` 编译通过。
> - **单测**：`cjpm test` 与 display 用例全部通过（当时 49 个用例；后续补了保活/释放回归，现为 62 个，最新数据见「单元测试」一节）。
>   > 本机 WSLg 的 Xwayland 报 `your 131072x1 screen size is bogus`，窗口投不到 Windows 桌面，因此 WSL 侧只做**无窗口验证**（控件真实创建、日历日期读写、帧动画帧数组与播放路径均已覆盖），视觉确认以 Windows 截图与 Pi 真机截图为准。
> - **交叉编译**：`scripts/build-lvgl-pi.sh` → `lib/linux-arm64/`，`readelf` 校验 `ELF64 / Machine: AArch64`，DRM/evdev 符号已编入。
> - **仓颉侧 aarch64 产物不需要单独的 aarch64 SDK**：用本机 linux-x64 的 cjc，`cjpm.toml` 里配 `--target aarch64-unknown-linux-gnu --sysroot /usr/aarch64-linux-gnu --static`，静态链接后 scp 到 Pi 直接运行（约 7 MB，不依赖目标机上的仓颉运行时）。

---

## 六、构建与运行步骤

### 一键构建（推荐入口）

预编译静态库已在 `lib/` 里，`LVGLCJ_LIB_DIR` 由脚本按平台自动挑（已有环境变量则沿用），
并转成绝对路径（`examples` 是独立模块，相对路径会解析错）：

```powershell
# Windows（PowerShell 7）
./scripts/build.ps1                       # 库
./scripts/build.ps1 -Test -Examples       # + 单测 + examples
./scripts/build.ps1 -DisplayTests         # requires_display 用例（SDL dummy 驱动）
```

```bash
# Linux / WSL
bash scripts/build.sh                     # 库
bash scripts/build.sh --test --examples   # + 单测 + examples
bash scripts/build.sh --display-tests     # requires_display 用例（SDL dummy 驱动）
```

两个脚本还会把 MSYS2 `ucrt64\bin` 挪到 `PATH` 最前面（Windows）：
SDK 的 `tools\bin` 里也有 `libwinpthread-1.dll`，顺序反了会加载到不匹配的 DLL
（症状是测试进程一起动就 `0xC0000139 入口点找不到`）。


### WSL 准备（Ubuntu 24.04，已实测）

```bash
# 1) 依赖（首次）
sudo apt install build-essential cmake ninja-build pkg-config git curl \
                 libsdl2-dev libfreetype-dev libevdev-dev fonts-noto-cjk
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu          # 交叉到 Pi

# 2) arm64 头文件（交叉编译 DRM/evdev 后端必需）
sudo dpkg --add-architecture arm64
sudo apt install libdrm-dev:arm64 libevdev-dev:arm64

# 3) 仓颉 SDK 解压到 /opt，并写进 /etc/profile.d/cangjie.sh（别只在当前终端 export）

# 4) 编 LVGL（首次或改 lv_conf 时）
export LVGL_DIR=/opt/lvgl-9.5.0
./scripts/build-lvgl-sdl.sh        # → lib/linux-x64/（WSL 本机验证）
./scripts/build-lvgl-pi.sh         # → lib/linux-arm64/（aarch64 交叉）
```

> multiarch 源怎么配、arm64 头文件怎么摆、SDK profile 的完整写法：**`docs/build-guide.md` 第 3、4 章**。

**WSL 上跑起来（SDL2 + WSLg）**：

```bash
export LVGLCJ_LIB_DIR=lib/linux-x64
cd examples && cjpm build --cfg
./target/release/bin/main widgets          # WSLg 直接弹窗
```

必须注意的三点（都实测踩过）：

1. **`LD_LIBRARY_PATH` 要生效**，否则启动报 `error while loading shared libraries: libcangjie-runtime.so`。非登录 shell（`wsl -d xxx -e bash -c ...`）不读 `/etc/profile.d`，用 `bash -lc` 或先 `source`；
2. **关掉 Windows PATH 注入**：`/etc/wsl.conf` 里写 `[interop] appendWindowsPath = false`，否则 `cjc` / `ninja` 会跑到 Windows 程序上；
3. **中文显示**：不装 `fonts-noto-cjk` 时 `Font.trySystemCjk()` 落空，界面方框（内置子集只有 1338 字）。

> **仓颉侧交叉需要 linux-aarch64 版 SDK**：linux-x64 SDK 的 `runtime/lib` 里只有 `linux_x86_64_cjnative`，
> 直接链 `lib/linux-arm64` 会得到 `skipping incompatible .../liblvgl.a when searching for -llvgl`。
> 装上 aarch64 SDK 后用 `cjpm build --target=aarch64-unknown-linux-gnu`；若链接报 `Scrt1.o`/`crti.o`
> 找不到，补 `--sysroot /usr/aarch64-linux-gnu -L ...`（cjc 没有 gcc 的 `-B`）。
> 完整命令、`@When` 平台分流与退路（qemu / Pi 原生编译）见 `docs/build-guide.md` 4.5。

### 构建 + 部署到 Pi

**前置**：`lib/linux-arm64/` 的 C 库已就绪（`scripts/build-lvgl-pi.sh`），并且装好 **linux-aarch64 版仓颉 SDK**。linux-x64 SDK 无法产出 aarch64 目标。

```bash
# 用 aarch64 SDK（解压到 /opt 后）
export CANGJIE_HOME=/opt/cangjie_1.2.0_aarch64/cangjie
export PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$PATH"
export LVGLCJ_LIB_DIR=lib/linux-arm64

cd examples
cjpm build --target=aarch64-unknown-linux-gnu --cfg   # → target/release/bin/main（aarch64 ELF）
file target/release/bin/main                          # 确认 ELF 64-bit LSB, ARM aarch64

# 部署（改 scripts/deploy-pi.sh 里的 IP）
scp target/release/bin/main pi@raspberrypi.local:/home/pi/
ssh pi@raspberrypi.local 'chmod +x ~/main && ~/main widgets'
```

> 链接报 `Scrt1.o`/`crti.o` 找不到就补 `--sysroot`（cjc 没有 gcc 的 `-B`），完整命令见 `docs/build-guide.md` 4.5；
> 实在不行就在 Pi 上原生 `cjpm build`（慢但零坑）。

### 真机运行

```bash
# 目标机只需要这些设备节点有权限，不需要任何仓颉运行时
ls -l /dev/dri/card0 /dev/input/event*
sudo usermod -aG video,input $USER    # 避免每次 sudo

./main hello      # 最小窗口
./main widgets    # 控件总览
./main touch      # 触摸/指针 + 校准信息
./main image      # RGB565 像素缓冲直出
./main canvas     # 自绘仪表/波形
./main perf       # FPS / CPU / 内存占用
```

**仓颉运行时**：发布时用静态链接方式把运行时模块编译进可执行文件，目标机无需部署 `CANGJIE_HOME`，拷一个二进制过去就能跑。

### 本机验证（SDL：Windows 原生 / WSLg）

```bash
cd examples && cjpm build --cfg                    # --cfg 见 cjpm.toml 的 [profile.customized-option]
./target/release/bin/main widgets                  # Windows 弹窗 / WSLg 弹窗
```

Windows 上运行前必须把 DLL 目录加进 PATH（`SDL2.dll`、`libfreetype-6.dll`）：

```powershell
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
./target/release/bin/main.exe widgets
```

> `liblvgl.a` 是静态库，**带不出自己的依赖**：SDL 后端要 `-lSDL2`、中文 FreeType 要 `-lfreetype`，两个都必须由**最终链接方**补。`examples/cjpm.toml` 里已写好 `link-option = "-lSDL2 -lfreetype"`；自己新建工程引用本库时也要照抄这一行，否则会看到成片的 `undefined symbol: SDL_Init` / `undefined symbol: FT_Init_FreeType`。

### 运行单元测试

测试源码在 `src/test/`（package `lvglcj.test`），由 `cjpm test` 自动发现：

```powershell
# Windows
$env:LVGLCJ_LIB_DIR = "lib/windows-x64"
$env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH    # 测试二进制也要 SDL2/freetype 的 DLL
cjpm test
```
```bash
# WSL / Linux
export LVGLCJ_LIB_DIR=lib/linux-x64
cjpm test
```

实测结果（Windows / WSL，2026-10）：**62 个用例，39 passed / 23 skipped / 0 failed**；
加上 `--include-tags=requires_display --exclude-tags=notag` 后 **23 个 display 用例全部 passed**
（默认自动切到 `SDL_VIDEODRIVER=dummy`，在内存里渲染、**不弹窗口**；想看画面加 `LVGLCJ_TEST_REAL_WINDOW=1`）。

| 测试文件 | 覆盖 | 是否依赖窗口 |
|---|---|---|
| `version_test.cj` | 版本号、`LvglException` | 否 |
| `constants_test.cj` | `LV_OBJ_FLAG_*` / `LV_STATE_*` / `LV_PART_*` / `LV_EVENT_*` / `LV_COLOR_FORMAT_*` 的**实测值**回归 | 否 |
| `color_test.cj` | `Color.rgb565` / `argb8888` 位运算边界 | 否 |
| `image_buffer_test.cj` | 每像素字节数推导、`writePixels` 长度校验、`toImageDsc` | 否 |
| `style_test.cj` | `Style` 链式、`Font` 工厂与 `close()` 语义 | 需 lv_init |
| `app_test.cj` | `App.post`（含跨线程）、回调异常处理、`TimerHandle` 的 ready/cancel/一次性失效 | 否 |
| `widget_test.cj` | 几何、`setTextFmt`、Slider 取值、Button 标志、**事件订阅/取消/删除回收**、Canvas 绘制、Theme、**SpanGroup / Calendar / AnimImage / Image.fromFile**、**`Line` 顶点保活（refreshNow 真画一帧）/ `Image.setSource` 句柄保活** | **是**，打 `@Tag[requires_display]` |
| `keepalive_test.cj` | **try-with-resources 自动释放**、`close()` 幂等、借用视图 `close()` 静默、同一 `Style` 挂多控件删其一不影响其余、**泄漏追踪计数随生命周期变化**、`Line` 缓冲随控件释放 | **是**，打 `@Tag[requires_display]` |

需要 display 的用例默认被 `[profile.test].exclude-tags` 排除（本地不弹窗、无图形环境不报错）。
注意 **`--include-tags` 不会覆盖配置里的 `exclude-tags`**，必须用一个不存在的 tag 顶掉它：

```bash
cjpm test --include-tags=requires_display --exclude-tags=notag   # 默认 dummy 驱动，不弹窗

LVGLCJ_TEST_REAL_WINDOW=1 cjpm test --include-tags=requires_display --exclude-tags=notag   # 想肉眼看画面
```

> 测试进程没有 SDL 事件循环，**真窗口会一直"无响应"**，人工点掉后 display 失效、
> 后续用例连带失败（症状是某个类 `@BeforeAll` 卡几十秒后报 `Before all step failed`）。
> 所以测试默认用 dummy 驱动。

> `@Tag` 只接受**标识符**：写 `@Tag[requires_display]`，不能写成 `@Tag["requires_display"]`（宏会报 "Illegal parameters for @Tag"）。
>
> 另外 `@ExpectThrows` 是**括号**形式：`@ExpectThrows[LvglException](expr)`，不支持尾随 lambda。

### 内存检查（ASan，Linux/WSL）

```bash
LVGL_SRC=/path/to/lvgl bash scripts/build-lvgl-asan.sh   # 插桩版 LVGL → .build/asan-lib
bash scripts/asan-test.sh                                # 普通用例 + requires_display 用例
```

关键点：**必须重编 LVGL**。预编译的 `lib/*/liblvgl.a` 没插桩，LVGL 内部读已释放内存时 ASan
什么都看不见（实测：注入 Line 的 UAF 后毫无反应；换插桩库立刻报 `heap-use-after-free @ lv_line.c:226`）。
细节见 `docs/build-guide.md` 第 7 节。

### 代码检查（格式 + 静态）

`scripts/check.ps1` 封装了 `cjfmt` / `cjlint`（PowerShell 7，需先 `envsetup.ps1` 把 `tools\bin` 加进 PATH）：

```powershell
./scripts/check.ps1                 # 检查 src/ + examples/，只读
./scripts/check.ps1 -Fix            # 格式不一致时就地格式化后重查
./scripts/check.ps1 -SkipExamples   # 只查库源码
./scripts/check.ps1 -SkipLint       # 只查格式
./scripts/check.ps1 -SkipFormat     # 只跑静态检查
```

- **格式**：`cjfmt` 没有 `--check` 模式，脚本先格式化到 `target/check/fmt/`，再与原文逐字节比对，行尾（LF/CRLF）和末尾换行差异都能发现。
- **静态**：`cjlint` 的 `-m` 必须指向 `CANGJIE_HOME` 根目录（不是 `modules/`），否则报 `Can not find modules`。报告输出到 `target/check/cjlint/cjlint-report.json`。
- **判定**：格式不一致返回 1，`cjlint` 出现 ERROR/WARNING 返回 2（可叠加）；`SUGGESTIONS` 只汇总、不判失败。

本库已确认的误报/既定风格固化在 `tools/cjlint/exclude_lists.json`，当前基线是 **0 条 SUGGESTIONS**。机制：

- 豁免按"规则 + 文件名 + 行号"精确匹配（`cjlint` 不支持只按文件或只按规则豁免），新增代码仍会正常告警。
- 脚本运行时把当前 SDK 的 `tools/config/` 复制到 `target/check/cjlint/config/`，再用仓库里的名单覆盖 `exclude_lists.json`；规则文件始终跟随 SDK，仓库只维护豁免项。
- 代码改动导致行号漂移时，旧告警会重新出现，按报告补一条即可。

已豁免的类别：FFI 结构体沿用 C 名（G.NAM.03）、`src/test/` 的包名约定（G.NAM.01）、`@Test` 宏展开产生的符号（G.NAM.03 / G.ITF.02）、`CPointer<T>` 同宽转换（FFI.C.7）、通配符导入（G.PKG.01）、FFI/绘图 API 的多参数（G.FUN.01），以及模块级状态和自增索引等已合理的作用域提示（G.VAR.02）。

### 持续集成（GitHub Actions）

`.github/workflows/ci.yml` 在 push / PR 到 `master` 时执行：

- **格式与静态检查**：在 Linux 上运行 `scripts/check.ps1`（cjfmt + cjlint）。
- **Linux x64**：安装 SDL2 / FreeType，执行 `cjpm build`、`cjpm test` 和 examples 构建。
- **Windows x64**：用 MSYS2 UCRT64 提供 SDL2 / FreeType，执行同样的编译、测试和 examples 构建。

SDK 由 `.github/actions/setup-cangjie` 从仓颉官网直链下载并校验 SHA-256，解压目录通过 `actions/cache` 复用；格式规则固定为仓库根的 `cangjie-format.toml`，避免 SDK 默认配置变化导致判定漂移。

### 引用方式

```toml
[dependencies]
# 本地开发
lvglcj = { path = ".." }
# 发布后（Gitcode）
# lvglcj = { git = "https://gitcode.com/yuan_1992/lvglcj.git", commitId = "main" }
```

---

## 七、API 速查（完整签名见 `docs/api-reference.md`）

一层一个文件组，下面只回答「从哪进去」；参数默认值、后端能力差异、所有权与线程约束都在
`docs/api-reference.md`。

| 文件 | 主要入口 | 一句话 |
|---|---|---|
| `util.cj` | `version()` / `Color.*` / `Perf.fps()` / `Mem.monitor()` / `sleepMs()` | 版本、颜色字面量、性能与内存观测 |
| `app.cj` | `App.setup()` → `App.run()`；`App.post()`；`Timer.every/once`（别名 `LvglTimer`） | 生命周期、主循环、跨线程投递、定时器 |
| `display.cj` | `Display.sdl(w,h)` / `.drm()` / `.fbdev()`；`screen()`；`setRotation` / `setColorFormat` / `setForceRefresh` | 三种后端；默认参数只能按名字传（`Display.drm(card: "...")`） |
| `input.cj` | `Input.evdev(...)` / `Input.discover()`；`attach()` / `calibrate()` / `swapAxes()` / `setCursor()` | evdev 输入（触摸/鼠标/键盘） |
| `widget*.cj` | `Container(parent)` 打底，其余控件同名构造；`onEvent/offEvent`；`finalize()/delete()` | 控件（事件、标志、状态、释放） |
| `style.cj` | `Style()` 链式 + `applyTo(obj)`；`Theme.default(...)`；`Font.montserrat/load/trySystemCjk` | 样式、主题、字体（中文必须 FreeType） |
| `image.cj` | `ImageBuffer(w,h,cf)` → `toImageDsc()` → `Image.setSource`；`Canvas(w,h)` | 像素缓冲、图像源、画布 |

三处最容易踩的：

1. **中文必须换主题字体**：内置 `lv_font_source_han_sans_sc_16_cjk` 只有 1338 个字形，缺字显示方框；
   而且只给 Screen `setFont` 不管用 —— 默认主题会显式给控件设 `text_font` 覆盖继承值，要连着主题一起换：
   `Theme.default(primary, secondary, dark, f)` + `screen().setFont(f)`。
   另外 `lv_init()` 内部已调过 `lv_freetype_init()`，别再自己调。
2. **样式与图像句柄由库保活**：`Style().radius(8).applyTo(btn)`、`img.setSource(buf.toImageDsc())`
   都可以传临时对象 —— 控件会把 `Style` / `ImageDsc`（进而 `ImageBuffer`）挂在自己身上。
3. **`ImageDsc` 没有 `bind()`**：像素内容变了要自己 `obj.invalidate()` 触发重绘；
   `img.setFile()` 解码失败只打 WARN、控件显示空白（`lv_image_set_src` 无返回码）。

控件的完整清单（含 `Slider/Arc/Bar/Switch/Checkbox/Dropdown/Roller/TextArea/Keyboard/List/Table/TabView/Menu/MsgBox/Chart/Canvas/Win/SpanGroup/Calendar/AnimImage/ImePinyin`）与逐个方法见
`docs/api-reference.md` 第 5 节。

---

## 八、Pi Zero 2 W 性能清单

1. **开 NEON**：`LV_USE_DRAW_SW_ASM = LV_DRAW_SW_ASM_NEON`，A53 上 blend/fill 收益明显；
2. **关断言**：`LV_USE_ASSERT_MEM_INTEGRITY` / `LV_USE_ASSERT_OBJ` / `LV_USE_ASSERT_STYLE` 在发布版全部为 0，否则每次对象/样式访问都做校验；
3. **partial 行数**：从 1/10 屏开始调，到 1/4 屏收益递减明显；瓶颈会从「绘制」转到「刷屏带宽」；
4. **少用大面积透明**：`bg_opa < 100%` 的区域要逐像素 blend，在 1024×600 上代价很高；
5. **阴影/模糊按需**：9.5 的原生模糊很吃 CPU，小面积用阴影，大面积模糊留给 v2 的 GPU 后端；
6. **图片预解码**：启动时一次性解码并常驻，别在界面切换时现解 PNG；
7. **定时器周期**：`lv_timer_handler` 每 5–10 ms 调一次即可，更频繁不会更流畅；
8. **后台线程不碰 UI**：网络/采集线程只投递数据，UI 更新统一在主线程的 `Timer` 回调里做；
9. **禁止在 flush_cb 里分配**：flush 回调只做「搬像素 + `lv_display_flush_ready`」，不要在里面做仓颉对象分配。

---

## 九、许可与合规

- **本库 `lvglcj`：MIT** — 可自由用于商业闭源产品。
- **LVGL 9.5：MIT** — 静态链接、修改、再分发均无传染性，只需保留版权声明（见 `LICENSE.LVGL`）。

---

## 附：常见坑速查

| 现象 | 原因与解法 |
|---|---|
| 第一帧出来后就卡住 | 没给 LVGL 时间基准：确认 `lv_tick_set_cb` / `lv_tick_inc` 已生效 |
| 黑屏 / 只画一部分 | fbdev 下把渲染模式改 `DIRECT`；仍不行就 `setForceRefresh(true)` |
| 分辨率不对 | 先给屏上电再给板子上电（HDMI 常见）；`fbset -fb /dev/fb0` 看内核实际选择 |
| 屏幕上有闪烁光标 | 内核控制台光标，Pi 上在 `/boot/cmdline.txt` 加 `vt.global_cursor_default=0` |
| 8bpp 彩色屏初始化失败 | fbdev 只接受灰度 8bpp，彩色请改 16/32 位 |
| 颜色偏色 / 红蓝反 | 用 `LV_COLOR_FORMAT_RGB565_SWAPPED`，或在 flush 里 `lv_draw_sw_rgb565_swap` |
| 触摸坐标反了 / 偏移 | `swapAxes(true)` + `calibrate(minX,minY,maxX,maxY)` |
| 链接报 undefined symbol | 该 API 是宏或 `static inline` → 补进 `native/shim/lvgl_shim.c` 再导出（见第一节第 2 点） |
| `undefined symbol: lv_linux_drm_*` / `lv_evdev_*` | 当前构建关掉了对应驱动（Windows 必然如此），但仓颉侧无条件 `foreign` 声明 → 一律经垫片转发（垫片给空实现） |
| `undefined symbol: SDL_Init` / `FT_Init_FreeType` | 静态库带不出依赖：最终链接方要加 `link-option = "-lSDL2 -lfreetype"` |
| 启动时报缺 `SDL2.dll` / `libfreetype-6.dll` | 把 `C:\msys64\ucrt64\bin` 加进 `PATH`，或把这两个 DLL 拷到 exe 旁边 |
| cmake 说找不到 lv_conf.h / 后端全被关掉 | 9.5 的选项是 `-DLV_BUILD_CONF_PATH=...`（老名 `LV_CONF_PATH` 被静默忽略） |
| `the customized key 'xxx' is wrong, the example is 'cfg_1'` | cjpm 1.2.0 只允许 `cfg` / `cfg_1` / … 作键名，且 `--cfg` 只匹配字面量 `cfg` |
| 中文全是方框 | 内置思源黑体子集只有 1338 字 → `Font.trySystemCjk()` + `Theme.default(..., font)` 换系统字体（只挂 Screen 不管用） |
| 换字体后仍无效果 | LVGL 主题显式设了控件字体，覆盖了继承值 → 必须把字体传给 `Theme.default`，并重建/重新 apply 主题 |
| `freetype already initialized` | `lv_init()` 已内部调用 `lv_freetype_init()`，不要重复初始化 |
| `gcc: No such file or directory`（Windows 下路径明明存在） | 把 Windows 反斜杠路径传给 MSYS2 的 gcc/cmake 会被当转义符 → 统一用正斜杠 |
| MinGW 链接全错 | 用了 32 位 `mingw32` 或 `clang64` 的库，与 cjc 目标 `x86_64-w64-mingw32` 不匹配 → 只认 `ucrt64` |
| UI 偶发错乱 / 崩溃 | 有线程在非主线程调 `lv_*`；统一用 `App.post { ... }` 收敛到主线程 |
| 回调异常后界面无响应 | 已注册 `App.onCallbackError` 但处理器内部又阻塞/抛错；处理器只做轻量日志或状态切换 |
| 事件越订越多 / 控件删了还收到回调 | 用 `onEvent` 返回的 `EventSubscription.cancel()` 显式取消，或依赖控件删除时的自动回收；不要反复给同一控件注册无句柄的回调 |
| WSL 里跑不起来 | WSL2 无 `/dev/dri`、无 `/dev/fb0` → 用 SDL 后端 + WSLg 验证 |
| 想看实时开销 | 开 `LV_USE_SYSMON` + `LV_USE_PERF_MONITOR` + `LV_USE_MEM_MONITOR`，跑 `./main perf` |
| `can not find the library 'lvgl' which is listed in 'ffi.c' field` | 没设 `LVGLCJ_LIB_DIR`（或设错平台目录）；cjpm 不支持 `${VAR:-默认值}`，必须显式设置 |
| `error while loading shared libraries: libcangjie-runtime.so` | 非登录 shell 没加载 `/etc/profile.d/cangjie.sh` → 用 `bash -lc` 或先 `source` |
| WSL 里 `cjc`/`ninja` 跑到了 Windows 版本 | WSL 默认注入 Windows `PATH` → `/etc/wsl.conf` 设 `[interop] appendWindowsPath = false` |
| 交叉编译报 `drm.h: No such file or directory` | `xf86drmMode.h` 内是 `#include <drm.h>` → 需要 `-I/usr/include/libdrm`；本仓库脚本把架构无关头文件扁平拷到 `/opt/arm64-include` |
| 交叉编译报 `linux/input.h` 找不到 | 缺 arm64 内核头：`libc6-dev:arm64` / `linux-libc-dev:arm64` |
| `skipping incompatible .../liblvgl.a when searching for -llvgl` | 链接器架构不匹配：x86_64 上用了 `lib/linux-arm64`，或反过来说 Linux 上用了 `lib/windows-x64` |
| Pi 上 `LV_USE_MEM_MONITOR redefined` 告警 | `LV_USE_SYSMON=0` 时 LVGL 会把 PERF/MEM 强改回 0 → 想开监控必须先开 `LV_USE_SYSMON 1` |
| WSL 下中文方框（Windows 正常） | Linux 无中文字体 → `sudo apt install fonts-noto-cjk`（路径 `/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc` 已在候选表里） |

