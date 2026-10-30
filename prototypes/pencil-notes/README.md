# Pencil Notes：手写选区与上下文采集原型

这是独立的个人产品实验，**不是课程作业代码**。它不依赖课程仓库，也不修改学习计划。

当前有两条独立实验链路：

1. 手写 → 框选 → 预览图片与坐标 → 本地模拟助手回执。
2. 显式开启采集 → 定时保留近期观察 → 拼装“历史 + 最新笔记 + 问题” → 检查、导出上下文。

**目前没有连接真实模型、pi 或云端，没有网络请求。** 模拟助手仅检查单次选区请求；连续上下文独立导出，不自动附加到模拟请求。采集层不依赖 agent。

ReplayKit 采集方式、系统边界详见 [上下文采集实验](docs/context-capture.md)。新增的过程记录与 pi 设计借鉴详见 [观察事件日志](docs/observation-events.md)。

## 已实现

- SwiftUI 界面，PencilKit 手写画布；Apple Pencil 或手指输入；固定黑笔和整笔画橡皮。
- 独立的矩形框选模式：支持反向拖动、边界裁剪、忽略过小选区。
- 选区 PNG 与整页 PNG：从 `PKDrawing` 渲染，不截入工具栏、键盘或蓝色选框。
- 提交前预览，整页预览额外标出选区位置。
- 固定快照请求：问题、笔记 ID、修订号、请求 ID、时间、页内坐标、两张图像。
- 显式点击后提交给本地模拟助手；关闭预览会取消正在等待的模拟请求。
- 通过系统文件导出器保存请求 JSON 或选区 PNG。
- 单页笔记自动保存、重启恢复；文件不可读取时禁止编辑，避免覆盖原始文件。
- 笔记上下文定时采样：文档发生变化才保留，书写／擦除过程中暂缓。
- ReplayKit 本 App 视频帧适配器：用户显式开启，限频、图像方向归一与尺寸压缩；真机待验证。
- 有帧数、编码字节数和年龄限制的内存历史；上下文检查器、JSON 导出与清空。
- 非活跃时停止采集、打开检查器时停止、迟到回调保护；不自动恢复。
- 同步记录工具使用、修订变化、选区和模式变化等事实；笔记快照关联事件序号。
- 独立的上下文组装器，不改写原始事件；检查器支持图像／事件视图和事件 JSONL 导出。

## 本地运行

需要 macOS、Xcode（含 iOS SDK / iPad 模拟器）、XcodeGen。部署目标为 iPadOS 17+，没有第三方 Swift 依赖。

```bash
# 如果尚未安装 XcodeGen：brew install xcodegen
cd prototypes/pencil-notes
xcodegen generate
open PencilNotes.xcodeproj
```

在 Xcode 里选择 `PencilNotes` scheme 和一个 iPad 模拟器，点击 Run。

真机运行：连接 iPad，在应用 target 的 **Signing & Capabilities** 中选择自己的 Team，必要时改成唯一的 Bundle Identifier；按 Xcode 提示启用设备开发者模式，再选择设备运行。签名配置不要写死到公共模板中。

`project.yml` 是工程配置源文件；生成的 `.xcodeproj` 和 `DerivedData` 被忽略。如果重新生成工程，临时修改的签名等设置可能需要重新配置。

### 编译与测试

```bash
xcodebuild \
  -project PencilNotes.xcodeproj -scheme PencilNotes \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build

# 先查看本机已安装的模拟器，再替换下面的设备名称
xcrun simctl list devices available
xcodebuild \
  -project PencilNotes.xcodeproj -scheme PencilNotes \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

当前已在 Xcode 27.0 / iOS 26.5 的 iPad Pro 11-inch (M5) 模拟器上验证：

- 模拟器编译通过。
- 38 个单元测试通过：选区、图像、持久化、采样、历史限制、异步启停，以及同步事件顺序、写后擦除、中断、停录隐私、事件／图像关联、JSONL、不可变上下文组装。
- 2 个 UI 测试通过：原有框选模拟回执流程，以及定时笔记采样 → 图像／事件检查器 → 不自动恢复采集。
- UI 测试使用独立的临时笔记，不清空用户笔记。

**尚未验证真实 ReplayKit 授权／视频采集、Apple Pencil 真机输入、导出文件的完整人工操作及不同 iPad 多窗口布局。** 假采集源测试不等于真实系统录屏已通过。

## 上手试验

1. 在“书写”模式写一个简单公式，或在模拟器中拖动鼠标画一条线。
2. 切换“框选”，拖出矩形。这个选区用于取图，不是 PencilKit 的笔画移动套索。
3. 编辑底部的问题，点击“预览选区请求”。
4. 检查选区图像；展开“整页上下文”，确认蓝框位置。
5. 点击“发送给本地模拟助手”，查看实际收到的修订号、坐标及图片尺寸。
6. 可导出 JSON 或 PNG，点击“完成”返回。
7. 继续书写，退出并重新打开，检查笔记恢复。

建议真机重点试：横竖屏、反向框选、贴边框选、空白选区、Pencil 与手指切换，以及输入问题时键盘是否遮挡操作。空白选区目前允许提交——本轮测数据链路，不判断内容是否有意义。

## 试用上下文记录

1. 保持默认来源“笔记内容”，点击“开始记录”。
2. 写一点，落笔结束后等一个采样周期（默认五秒）；上方上下文帧数会增加。
3. 在问题输入框填写问题，点击“上下文”。记录会停止，打开历史与最新笔记的检查器。
4. 切换“图像／事件”检查快照和过程事实。可导出完整上下文 JSON 或仅含元数据的原始事件 JSONL；也可清空内存中的图像和事件。
5. 真机上可切换“本 App 屏幕 · ReplayKit”试验屏幕来源；它不等于跨 App 或后台读取屏幕。

详细采集机制、SDK 弃用信息和真机检查表见 [docs/context-capture.md](docs/context-capture.md)。

## 代码入口

| 文件 | 职责 |
|---|---|
| `Sources/PrototypeConfiguration.swift` | 有含义的可调数值：页面大小、最小选区、笔宽、图像倍率、延迟、布局 |
| `Sources/NotebookCanvas.swift` | PencilKit 封装、页面缩放、选区手势 |
| `Sources/SelectionGeometry.swift` | 选区标准化与裁剪，不依赖界面 |
| `Sources/NotebookStore.swift` | 笔记状态、自动保存、读取失败保护 |
| `Sources/AssistantRequest.swift` | 请求数据结构、图像生成、助手协议与模拟实现 |
| `Sources/RequestPreview.swift` | 提交前预览、回执、导出 |
| `Sources/PencilNotesApp.swift` | 应用入口及编辑界面 |
| `Sources/LearningContext.swift` | 与 agent 无关的帧、历史缓冲和上下文数据契约 |
| `Sources/ContextRecorder.swift` | 定时采样、事实事件订阅、会话生命周期 |
| `Sources/ObservationLog.swift` | 事件类型、稳定 ID、追加顺序、保留窗口、JSONL |
| `Sources/ContextAssembler.swift` | 从固定历史与最新现场构建上下文，不改写原始记录 |
| `Sources/ReplayKitCapture.swift` | 系统视频回调、限频、方向归一和图像编码 |
| `Sources/ContextInspector.swift` | 采集控制、历史检查、导出和清空 |

配置数值集中命名，避免在业务代码中散布魔法数字。坐标原点 `0`、修订递增 `1`、求中心时除以 `2` 等数学含义直接可见的数值不机械包装。测试中的具体坐标是样例输入，不是生产配置。

## 坐标与请求契约

页面采用固定尺寸，运行时等比适配视口。坐标原点在页左上角，x 向右、y 向下，单位为**页内点**，不是屏幕像素。横竖屏不会改变文档坐标。

请求的 JSON 字段直接对应 `AssistantRequest`：

- `schemaVersion`：请求格式版本。
- `id`、`notebookID`、`drawingRevision`、`createdAt`：标识本次固定快照。
- `prompt`：用户问题。
- `coordinateSpace`、`page`、`selection`：坐标约定和区域，区域包含 `x / y / width / height`。
- `selectionImage`、`pageImage`：包含 `mimeType / widthPixels / heightPixels / base64`。

选区图像为较高倍率，整页图像为较低倍率，具体值见配置。每张图的原点分别为选区左上角和页面左上角；用 `selection` 可以建立两者关系。

这是原型自己的数据契约，不是任何模型服务商的 HTTP 格式。后续后端需要将它转换成相应模型的图像与文本输入。

## 本地数据与隐私

笔迹以 PencilKit 数据存于应用沙盒：`Documents/PencilNotes/notebook.json`，包含笔记 ID 与修订号。延迟保存以减少连续落盘，并在应用转入非活动状态时补一次保存；突发进程终止仍可能丢失尚未落盘的最后修改。

默认不上传、不记录远端日志。**导出的选区请求 JSON 含整页图像，不只含框选内容；上下文 JSON 还含全部保留的历史图片。** 屏幕来源可能包含本 App 的非笔记界面。历史只保存在内存中，清空历史不会删除原笔记或已导出的文件。接真实后端前应保留提交范围提示，并进一步决定整页上下文是否可选。不要把模型 API Key 放进 iPad 客户端或版本库。

## 刻意未做

- 多页、PDF 导入、无限画布、手动缩放、笔迹移动套索。
- 专门的撤销/重做 UI、笔迹颜色与工具面板。
- OCR、公式结构化、实时纠错、画图工具、AI 写回页面。
- 真实模型、后端部署、账号、云同步和长期学习记忆。
- 跨 App 广播扩展、后台定时录屏、可重建笔迹的完整笔画几何日志、屏幕像素到页内点的映射。
- 永久事件存储、逐帧排除策略、上下文摘要或压缩。

当前选区只是某个修订下的矩形，不是能跟着笔迹移动的语义锚点。任何笔迹修改都会清除当前选区；已生成的请求保持不变。后续若允许助手写回，应先校验修订并实现可撤销的页面操作，而不是把旧坐标直接应用到新页面。

下一步先用真实 iPad 检查两种来源的图像、方向、时序和授权行为，确认导出的上下文准确表达了现场及近期过程，再决定是否接入模型。
