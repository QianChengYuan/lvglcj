# lvglcj 文档

仓颉（Cangjie）语言的 LVGL 9.5 封装库。本文档目录面向使用者，根目录的 [`README.md`](../README.md) 面向项目概览与设计决策。

## 文档导航

| 文档 | 内容 | 适合谁 |
|---|---|---|
| [快速开始](getting-started.md) | 15 分钟内在本机跑出第一个 LVGL 窗口 | 第一次接触本项目 |
| [编译指南](build-guide.md) | Windows（MSYS2）/ WSL / aarch64 交叉三种构建路径，含全部依赖与参数 | 需要自己编 LVGL 或换平台 |
| [API 参考](api-reference.md) | 友好层全部公开类型、方法、常量 | 写业务界面 |
| [常见问题](faq.md) | 按现象索引的排障手册 | 编译/运行报错时 |

## 30 秒了解这个库

```cangjie
import lvglcj.*

main() {
    App.setup()                                   // lv_init + 单调时钟 tick 源
    let disp = Display.sdl(480, 272)              // 桌面模拟；真机换 Display.drm()
    let font = Font.trySystemCjk(size: 16) ?? Font.defaultFont()
    Theme.default((0x1E, 0x88, 0xE5), (0x0F, 0x9D, 0x58), false, font)

    Label(disp.screen()).text("你好，仓颉")
    App.run()                                     // 主循环，直到 App.stop()
}
```

## 分层结构

```
使用者代码
   │  import lvglcj.*
   ▼
友好 API 层   util / app / display / input / widget / style / image   ← 本文档主要描述这一层
   │  仓颉函数调用
   ▼
FFI 层        src/ffi_*.cj（foreign 声明 + LV_* 常量）                ← 不导出给下游
   │  C ABI
   ▼
C 垫片        native/shim/lvgl_shim.c（宏 / inline / offsetof → 真函数）      ← _cjbindwrapper 后缀
   │
   ▼
LVGL 9.5 静态库  lib/{windows-x64,linux-x64,linux-arm64}/liblvgl.a
```

**为什么要 C 垫片**：LVGL 大量 API 是宏或 `static inline`（`LV_PCT()`、`style_set_*` 等），在 `.a` 里没有可链接符号，直接 `foreign` 声明必然链接失败。所以凡是宏/inline，都由垫片包一层真函数导出。

## 支持的平台

| 平台 | 显示后端 | 输入 | 状态 |
|---|---|---|---|
| Windows 10/11 + MSYS2 UCRT64 | SDL2（原生窗口） | SDL 鼠标/键盘 | ✅ 实测 |
| WSL2 Ubuntu 24.04 + WSLg | SDL2（WSLg 窗口） | SDL 鼠标/键盘 | ✅ 实测 |
| Raspberry Pi Zero 2 W（aarch64） | DRM/KMS，fbdev 兜底 | evdev | ⏳ C 库已交叉编译，待真机联调 |

## 版本要求

- 仓颉 SDK **1.2.0**（`cjc` / `cjpm`）
- LVGL **9.5.0**（仓库自带预编译静态库，三平台各一份）
- 桌面模拟额外需要 SDL2 2.30+；中文显示需要 FreeType 2.13+
