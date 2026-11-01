# examples —— lvglcj 示例工程

独立 cjpm 模块，通过 `path = ".."` 依赖仓库根目录的 `lvglcj` 库。

**它是一个模块、不是一个独立的 cjpm 工程**：`cjpm build` 会顺着 `[dependencies]` 去编
`..`（库本体），所以库和示例可以在一条命令里一起构建；但它同时也意味着 **`cjpm build`
必须拿到 `LVGLCJ_LIB_DIR`**，否则链接阶段会报：

```
Error: can not find the library 'lvgl' which is listed in 'ffi.c' field at .../cjpm.toml
```

## 一行构建（推荐）

```powershell
# Windows（自动设 LVGLCJ_LIB_DIR + 拷运行时 DLL 到产物目录）
pwsh scripts/build-example.ps1              # 只构建
pwsh scripts/build-example.ps1 -Run all     # 构建后直接跑全功能演示
```

```bash
# Linux / WSL
./scripts/build-example.sh                  # 只构建
./scripts/build-example.sh --run all        # 构建后直接跑
```

`build-example.ps1` 会把 `SDL2.dll`、`libfreetype-6.dll`、`libstdc++-6.dll`、
`libgcc_s_seh-1.dll`、`libwinpthread-1.dll` 等依赖连同仓颉运行时的两个 DLL 一起拷到
`target/release/bin/`，**不需要再改 PATH**，双击 `main.exe` 也能跑。

## 手工构建

```powershell
$env:LVGLCJ_LIB_DIR = "$PWD/../lib/windows-x64"   # 必须绝对路径
cd examples
cjpm build --cfg
./target/release/bin/main.exe all
```

```bash
export LVGLCJ_LIB_DIR="$PWD/../lib/linux-x64"
cd examples
cjpm build --cfg
./target/release/bin/main all
```

`--cfg` 对应根 `cjpm.toml` 的 `[profile.customized-option]`，保留它是为了让脚本/文档里的
命令能原样执行；当前它不影响任何编译产物。

## 运行入口

| 命令 | 内容 |
| --- | --- |
| `main all` | **全功能演示**：控件 / 布局 / 样式 / 数据绑定 / 焦点组 / 动画 / 绘图 / 图表 / 富文本与浮层（8 个标签页） |
| `main hello` | 最小窗口 |
| `main widgets` | 控件总览 |
| `main touch` | 触摸/指针 + 校准信息（需要 evdev） |
| `main image` | RGB565 像素缓冲直出 |
| `main canvas` | 自绘仪表/波形 |
| `main perf` | FPS / CPU / 内存占用 |
| `main rich` | 表格 / 图表 / 日历 / 富文本 |
| `main thread` | 后台线程 `App.post` + 回调异常兜底 |
| `main file <png>` | 从图片文件加载（需要 LV_USE_FS_STDIO / 解码器） |

## 跨平台说明

* 预编译库分四份（`lib/windows-x64`、`lib/linux-x64`、`lib/linux-arm64`、
  `lib/linux-arm64-sdl`），互不兼容，靠 `LVGLCJ_LIB_DIR` 切换；
* 交叉到 Pi 用 `cjpm build --target aarch64-unknown-linux-gnu --cfg`，还需
  `LVGLCJ_AARCH64_SDL_LIB` 指向 aarch64 的 SDL2/FreeType 库目录，详见 `docs/build-guide.md`；
* 链接方必须自己补 `-lSDL2 -lfreetype`（已写在 `examples/cjpm.toml` 的 `link-option`）。
