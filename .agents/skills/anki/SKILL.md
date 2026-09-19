---
name: anki
description: Create, review, route, and safely synchronize study cards for this computer-science learning project. Use when the user asks to make Anki cards, choose a deck or card type, inspect existing cards, or write cards to Anki.
---

# Anki 学习卡片 Skill

这个 Skill 服务于本项目的 CSAPP、6.S081、CS144、15-445 和 CS336 学习。它把“理解和验证过的知识”转换成可复习的卡片，并通过 AnkiConnect 与本地 Anki Desktop 协作。

## 先路由，再制卡

1. 先读取 [routing.md](references/routing.md)，确定课程、牌组、操作模式和标签。
2. 制卡或选择卡片类型时读取 [templates.md](references/templates.md)。
3. 如果课程或目标牌组不明确，不要猜测；先询问一个最小澄清问题。

## 操作模式

- **draft**：根据用户提供的笔记、代码、复述或已验证结论生成卡片草稿。默认模式，不写入 Anki。
- **review**：只读检查 Anki 的牌组、卡片、重复项或字段；可使用 `version`、`deckNames`、`findCards` 和 `notesInfo`。
- **write**：只有用户在本轮明确要求“写入/添加/同步到 Anki”时才执行。写入前确认目标牌组、笔记类型、卡片数量和关键字段；写入后用只读查询验证结果。
- **organize**：创建牌组、移动卡片或维护标签。创建牌组可直接执行；删除牌组、删除卡片和清空内容必须得到明确指令，并先检查影响范围。
- **template**：解释或修改卡片模板，不生成未经用户要求的卡片。

“帮我做卡片”“整理成 Anki”只授权生成草稿，不等于写入授权；“直接加到 Anki”“写入 CSAPP”才是写入意图。

## 内容门槛

- 一张卡只考察一个可复现的概念、不变量、边界条件、错误原因或设计取舍。
- 卡片必须来自学习者已经阅读、实现、运行、调试或用自己的话验证过的内容。
- 题目、Lab 和 Project 可以制作概念卡，但不能把题目答案、关键实现、完整伪代码或可直接提交的解法变成卡片。
- 不确定、版本相关或尚未验证的内容标记为 `status::verify`，不要写成确定事实。
- 重要卡片记录来源：教材章节、Lecture、Lab、代码文件或实验名称。

## 连接与写入

- 优先使用已配置的 `anki-cli`；如果不可用，使用 AnkiConnect 的本地接口 `http://127.0.0.1:8765`。
- 在任何写入前先做只读连通性检查，并确认目标牌组和 Note Type 存在。
- 写入时优先使用结构化字段，不通过 UI 模拟点击批量录入。
- 添加后检查返回的 note ID，并用 `notesInfo` 或 `findCards` 验证牌组、字段和标签。
- AnkiConnect 不可用时如实报告并停止写入；不能假装同步成功。
- 不主动安装、启用或切换 MCP/插件，也不把多个 Anki 桥接工具叠加使用；除非用户明确要求改变工具链。

## 项目输出

- 草稿使用 [templates.md](references/templates.md) 中的 Markdown 结构，放在对应课程的 `courses/<course>/anki/drafts/` 下；该目录不存在时再创建。
- 月度计划保持简洁，不把卡片内容或 Anki 操作日志写进 `plan/`。
- 新增卡片时保留课程、主题、来源和验证状态标签，便于后续检索和复习。
