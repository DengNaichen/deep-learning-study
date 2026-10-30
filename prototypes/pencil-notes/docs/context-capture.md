# 上下文采集实验：先不接 agent

目标不是让模型持续思考，而是验证：**我们能获取哪些可追溯的观察，以及如何把近期过程、当前现场和问题拼成可检查的数据。**

## 两种采集来源

### 1. 笔记内容：PencilKit

既然应用持有 `PKDrawing`，不需要录屏才能知道用户写了什么：

- `PKCanvasViewDelegate.canvasViewDrawingDidChange` 更新笔迹与修订号。
- `canvasViewDidBeginUsingTool` / `canvasViewDidEndUsingTool` 标记正在书写或擦除，采样时避开工具使用中状态。
- 使用 `PKDrawing.image(from:scale:)` 生成白底 PNG，同时取得笔记 ID、修订号、选区和编辑模式。
- 图像与文档元数据在主线程同一次同步操作中生成，具有明确的对应关系。

开始时生成基线帧，之后每五秒检查一次。文档状态没有变化时跳过；选区或编辑模式变化也算上下文变化。整页被擦空依然需要记录，不能把“空白”当成无意义而过滤。

这是**文档内容快照**，不是用户屏幕截图：不包含工具栏、键盘、问题输入、其他应用。

### 2. 本 App 屏幕：ReplayKit

用户提到的接口是 ReplayKit。本机 Xcode 27.0 SDK 的 `RPScreenRecorder.h` 确认：

- `RPScreenRecorder.shared().startCapture(handler:completionHandler:)` 开始本应用采集，持续回调 `CMSampleBuffer`；系统可能要求用户确认。
- 视频回调不等于“五秒一张图”。适配器按单调时钟限频，多余帧直接丢弃，不排队。
- 用 `CMSampleBufferGetImageBuffer` 取得图像缓冲，读取 `RPVideoSampleOrientationKey` 的方向；若附件缺失，按 `.up` 处理，这一点需要真机验证。
- 把方向变换应用到实际像素，等比缩小后编码成 JPEG；最终图像不依赖 EXIF 旋转信息。
- 接受的视频帧会进入历史缓冲区；逐字节相同且来源、元数据相同的相邻记录才去重。不把“JPEG 不同”等同于“数学内容发生变化”。
- 关闭麦克风和摄像头；丢弃所有非视频 sample，不保存或导出音频。不生成电影文件。

**这个实现不是跨 App 观察器。** 不能据此声称能后台定时读取 Goodnotes、Safari 或其他应用。跨 App 屏幕广播是另一条涉及系统用户操作和 Broadcast Upload Extension 的路线，不在本轮范围内；也不会因此获得其他 App 的文档或笔迹 API。

ReplayKit 帧是异步到达的，所以只附采集来源、帧 ID、应用收到并处理该帧时的时间和图像尺寸，**不硬贴当前文档修订号或页内选区坐标**。屏幕像素到笔记页内点的映射尚未实现。

### SDK 版本注意事项

本机 Xcode 27 SDK 已将 `RPScreenRecorder` 标记为在 iOS 27 弃用，并建议使用 ScreenCaptureKit。当前应用部署目标是 iPadOS 17+，因此先把 ReplayKit 作为兼容性实验，隔离在 `ReplayKitCapture.swift` 中。

这不意味着未来所有系统都应继续用 ReplayKit，也不意味着 ScreenCaptureKit 在全部目标系统上都有等价能力。若改变最低系统版本，应重新验证 ScreenCaptureKit 的可用性与授权范围，再替换 `ScreenCaptureSource` 适配器。

参考入口：

- [PKCanvasViewDelegate](https://developer.apple.com/documentation/pencilkit/pkcanvasviewdelegate)
- [PKDrawing](https://developer.apple.com/documentation/pencilkit/pkdrawing)
- [RPScreenRecorder](https://developer.apple.com/documentation/replaykit/rpscreenrecorder)
- [ReplayKit](https://developer.apple.com/documentation/replaykit)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)

实现时实际核对的是本机 SDK 的 `ReplayKit.framework/Headers/RPScreenRecorder.h` 与 `RPBroadcastExtension.h`，不是假设记忆中的接口一定适用于当前 SDK。

## 数据流

```text
PencilKit 文档状态 ── 定时检查、同步渲染 ──┐
                                         ├─ ContextFrame ─ ContextHistory
ReplayKit 视频流 ── 限频、方向归一、JPEG ─┘                     │
                                                               ▼
用户点击“上下文” ── 停止采集 ── 最新笔记 + 问题 + 近期帧 ─ LearningContext
                                                               │
                                                   检查器预览 / 导出 JSON
```

此链路完全不依赖 agent、模型供应商或对话格式。现在还同步记录应用事实事件，供 `ContextAssembler` 与图像一起组装；事件顺序、图像关联和 JSONL 格式见 [观察事件日志](observation-events.md)。

原来的“预览选区请求 → 模拟助手”仍是单次选区实验；它**不会自动附加历史**。检查连续过程应使用新增的“上下文”按钮，它导出独立的 `LearningContext` 数据契约。没有任何历史会悄悄进入已有模拟请求。

## 上下文中有哪些内容

`LearningContext` 包含：

- `schemaVersion / kind / id / assembledAt`：格式与本次组装的身份；当前上下文版本为 2。
- `prompt`：组装时的问题。
- `history`：按接受顺序排列的近期观察，每份具有来源、时间、图片，以及可用时的精确文档状态。
- `currentDocument`：**组装时重新取得的笔记快照**，不拿最后一张历史图冒充当前现场。
- `observations`：原始事件窗口的不可变副本、日志身份、序号及淘汰信息。笔记帧用 `eventCursor` 关联事件边界，ReplayKit 帧不建立此关联。
- `samplingIntervalSeconds / retention`：采样与保留策略。
- `evictedFrames / skippedDuplicateFrames / rejectedOversizedFrames`：缓冲区淘汰、相邻重复图像跳过、单帧超预算拒绝的数量。不是视频流丢帧统计；未变化文档的跳过也不计入重复图像数量。

没有 OCR、推导解释、用户意图猜测、掌握程度或自动总结。

当前快照和历史均是不可变数据。预览打开后，导出的就是预览中这份内容；历史后续变化不会暗中改变导出结果。

## 采样与资源限制

所有可调数值位于 `PrototypeConfiguration.Context`：

| 参数 | 初始值 | 含义 |
|---|---:|---|
| 检查／视频接受间隔 | 5 秒 | 不是系统实时性保证；视频无回调、落笔中或非活跃时可能更稀疏 |
| 历史帧数上限 | 12 | 超出时移除最旧记录 |
| 历史 base64 字节预算 | 16 MiB | 不等于进程总内存上限 |
| 最大历史年龄 | 600 秒 | 下次采样、接收或组装时剔除过期帧 |
| 屏幕图像最长边 | 1024 像素 | 只缩小，不放大；需实测小字可读性 |
| 屏幕 JPEG 质量 | 0.75 | 体积和细节的实验性取舍 |

历史只在内存中，不做后台磁盘录像。PNG/JPEG 解码、渲染和 JSON 导出仍有额外瞬时内存占用。历史数量上限不代表当前笔记或 UI 图片解码完全不占内存。

离散图像可能漏掉“在五秒内写了又擦掉”的内容。新增事件日志可以保留工具使用、修订变化等过程事实，但不保存笔画几何，仍不能还原被擦掉的公式。若需要完整书写轨迹，应另行设计笔画级记录，而不是声称降低截图间隔即可保证不遗漏。

## 生命周期与隐私

- 默认关闭，用户显式开始；屏幕来源额外显示采集范围确认。
- 录制时持续显示状态和停止按钮，不能隐藏系统采集提示。
- 进入非活跃状态时，正在进行的记录停止；回到前台不自动恢复。
- 系统授权窗口可能令“正在启动”的应用暂时非活跃，这时等待授权结果；如果真正进入后台或用户已经点击停止，晚到的启动成功会立即走停止流程。
- 打开选区预览或上下文检查器会先停止接收帧，避免截图递归包含检查器本身。
- 停止时立即作废会话 ID；晚到的帧无法写入新会话或重新填充已经清空的历史。
- 系统停止失败时明确显示错误并允许重试，不伪装成成功停止。
- 历史不会在应用重启后恢复；原始笔记的本地保存逻辑不变。
- 导出 JSON 包含整页和全部保留的历史图像，屏幕帧可能包含本 App 的非笔记 UI。导出前可检查、停止、清空；清空内存不删除已导出的文件副本。

## 如何验证

### 可在模拟器验证的笔记路径

1. 选择“笔记内容”，点击“开始记录”，应立即获得一帧基线。
2. 写一条公式，落笔结束后等待一个采样周期；帧数增加。
3. 停着不写；帧数不应每五秒无故增加。
4. 框选某一块，再等待一轮，检查历史中的选区状态。
5. 输入问题并点击“上下文”；采集停止，检查最新笔记、历史及问题。
6. 导出 JSON，核对图片和来源；或清空历史，确认原始笔记还在。

### 必须做的 ReplayKit 真机验证

1. 选择“本 App 屏幕 · ReplayKit”，开始并阅读确认提示；分别测试允许、拒绝。
2. 写字、显示问题输入、横竖屏切换；等待取样，再打开检查器看图像方向和内容范围。
3. 检查帧没有被错误标记为笔记文档坐标或修订。
4. 测试录制期间退后台、锁屏、系统主动停止、授权尚未结束就取消等情况。
5. 检查应用状态与系统录屏指示器是否一致；不可用时应提示失败，不假造视频帧。
6. 在最小字号下检查压缩后的可读性，并检查持续运行的电量、内存和发热。

当前验证范围：模拟器编译和自动测试已经覆盖文档定时采样、缓冲区策略、上下文组装、图像方向转换，以及使用假采集源测试的异步启停边界。**真实 ReplayKit 授权、视频帧采集和 Apple Pencil 真机体验尚未验证。**
