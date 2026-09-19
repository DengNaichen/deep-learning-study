# 课程资料索引

这里按课程集中记录官方入口、使用版本和本地资料状态。自学时参考课程内容顺序，但不照搬学校的开课日期。

每门课程的目录都包含：

```text
courses/<course>/
  README.md
  materials/
  notes/
  labs/
  anki/drafts/
```

## 课程总表

| 课程 | 当前资料版本 | 官方入口 | 本地目录 |
|---|---|---|---|
| CSAPP / CMU 15-213 | CS:APP 3e；CMU 15-213 Fall 2026 | [CS:APP](https://csapp.cs.cmu.edu/) · [15-213](https://www.cs.cmu.edu/~213/) | [csapp](csapp/) |
| MIT 6.S081 / 6.1810 | MIT Fall 2026 | [课程主页](https://pdos.csail.mit.edu/6.S081/2026/) · [Schedule](https://pdos.csail.mit.edu/6.S081/2026/schedule.html) | [6s081](6s081/) |
| Stanford CS144 | 当前公开课程页面 | [课程主页](https://cs144.stanford.edu/) | [cs144](cs144/) |
| CMU 15-445 | Fall 2026 | [课程主页](https://15445.courses.cs.cmu.edu/fall2026/) · [Assignments](https://15445.courses.cs.cmu.edu/fall2026/assignments.html) | [15-445](15-445/) |
| Stanford CS336 | Spring 2026；保留官方 assignments 作为自学资料 | [课程主页](https://cs336.stanford.edu/) | [cs336](cs336/) |

## 收集规则

### 建议纳入课程目录

- 课程资料索引、版本说明、阅读顺序和来源链接，放在对应课程的 `README.md`；
- 许可明确允许再分发的 handout、starter code 和小型辅助脚本；
- 自己写的笔记、实验报告、测试和复盘；
- 能帮助复现环境的版本文件和命令记录。

### 默认只保留链接

- 教材完整 PDF、课程视频和大型数据集；
- 许可不明确的课程内部材料；
- 第三方整理的答案、solution、writeup 或已完成的 Lab；
- 未来可能频繁变化的课程网页快照。

公开资料的版权和使用条件需要单独判断；“能下载”不等于“适合提交到仓库”。

## 版本记录

| 资料 | 版本/日期 | 记录 |
|---|---|---|
| 本索引 | 2026-09-19 | 初始建立；学习从 2026-10-01 开始 |

每次替换课程版本时，在对应课程目录的 README 中更新版本和日期，不覆盖旧版本的来源记录。
