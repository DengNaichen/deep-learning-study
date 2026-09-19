# Deep Learning

这里的 `Deep Learning` 指“深度的学习”，是一个以计算机系统为主线的长期学习项目，不是单独的深度学习课程仓库。

## 从哪里开始

1. 查看全年路线：[学习计划.md](学习计划.md)
2. 查看当前月份：[plan/01-CSAPP基础.md](plan/01-CSAPP基础.md)
3. 查看课程资料索引：[courses/INDEX.md](courses/INDEX.md)
4. 阅读项目协作规则：[AGENTS.md](AGENTS.md)

正式开始日：2026 年 10 月 1 日。第一阶段从 CSAPP 开始。

## 目录约定

```text
courses/          按课程组织的资料、笔记、实验和 Anki 草稿
plan/             月度学习计划
.agents/skills/   项目级 AI 辅助技能
```

每门课程目录统一使用以下结构：

```text
courses/<course>/
  README.md       课程资料入口、版本和来源
  materials/      许可允许保存的课程资料
  notes/          自己的概念笔记和复盘
  labs/           starter code、自己的实现和测试
  anki/drafts/    该课程的 Anki 草稿
```

课程资料不是无差别下载目录。每份本地资料都应保留来源、版本和获取日期；公开可见不代表可以重新分发。

## 学习产物的边界

- 先阅读和验证，再把内容写进对应课程的 `notes/` 或制作 Anki 卡片；
- 课程实验的核心实现由自己完成，AI 只提供解释、调试方向和工具帮助；
- 不把第三方解答、课程 solution 或可以直接提交的实现放进仓库；
- 构建产物、虚拟环境、缓存和大型媒体文件不纳入版本控制。
