# Anki 路由表

## 路由顺序

收到 Anki 请求后按以下顺序处理：

1. **识别操作**：`draft`、`review`、`write`、`organize` 或 `template`。
2. **识别课程**：从课程名称、章节、Lab、代码仓库或用户上下文推断；存在歧义时询问。
3. **确定牌组**：使用下表的顶层牌组；只有用户明确要求时才使用子牌组。
4. **确定 Note Type**：默认 `Basic`；需要从句中回忆时使用 `Cloze`；代码机制仍使用 `Basic`，不要把整段代码当作答案。
5. **附加标签**：课程、主题、来源和验证状态。

## 课程到牌组

| 用户说法 | 目标牌组 | 常见主题标签 |
|---|---|---|
| CSAPP、CS:APP、15-213 | `CSAPP` | `bits`、`assembly`、`memory`、`cache`、`linking`、`process`、`concurrency` |
| CS336、Stanford LLM Systems | `CS336` | `transformer`、`tokenizer`、`attention`、`training`、`evaluation` |
| 15-445、15445、BusTub | `15-445` | `buffer-pool`、`index`、`query`、`concurrency`、`recovery` |
| 6.S081、6.1810、xv6 | `6.S081` | `syscall`、`trap`、`vm`、`process`、`file-system`、`lock` |
| CS144、Stanford Networking、TCP/IP | `CS144` | `ethernet`、`ip`、`tcp`、`routing`、`reliability` |

当前已知的课程牌组包括 `CSAPP` 和 `CS336`。`CS336::Test` 只在用户明确要求测试牌组时使用；普通 CS336 卡片进入 `CS336`。

如果目标课程牌组不存在：

- 草稿模式：仍使用目标牌组名记录在草稿中，不自动改变 Anki。
- 写入模式：用户明确要求写入时，可以先创建目标牌组，再写入；创建结果必须报告。

## 操作路由

| 请求意图 | 默认行为 | 允许的副作用 |
|---|---|---|
| “根据这段内容做卡片” | 生成草稿 | 不连接或不写入 Anki 也可以 |
| “看看 CSAPP 有什么卡片” | 只读查询 | 读取牌组/卡片 |
| “把这些卡片加到 CSAPP” | 预览后写入 | 仅新增明确列出的卡片 |
| “同步/更新这些卡片” | 先查重再更新 | 仅更新匹配到的 Note |
| “整理牌组/建牌组” | 检查现状后执行 | 创建或移动用户指定对象 |
| “删除牌组/清空卡片” | 先报告影响范围 | 必须有明确删除指令 |

## 标签规范

标签使用小写、短词和稳定的层级前缀：

```text
course::csapp
topic::assembly
source::csapp-3e-ch03
type::basic
status::verified
```

推荐最少包含：一个 `course::`、一个 `topic::`、一个 `source::` 和一个 `status::` 标签。无法确定来源时使用 `status::verify`，不编造来源。

## 重复检查

写入前按以下顺序查重：

1. 相同牌组内的精确 Front；
2. 去除 Markdown 标记、大小写和多余空白后的 Front；
3. 语义上明显重复的卡片。

发现疑似重复时保留草稿并报告，不自动覆盖原卡。用户明确选择更新时，先展示旧卡与新卡的差异。
