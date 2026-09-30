# Stanford CS336 资料

## 采用版本

参考 Stanford Spring 2026 的公开课程材料。课程官方节奏只用于内容顺序，不作为本项目的截止日期。

## 学习安排

当前主修课程，安排在第 1–12 周（2026/10/01–2026/12/23）。首月围绕 Assignment 1: Basics 展开，见 [首月计划](../../plan/01-CS336基础.md)。

## 官方资料

- [课程主页](https://cs336.stanford.edu/)
- [Assignment 1: Basics](https://github.com/stanford-cs336/assignment1-basics)
- [官方讲义仓库](https://github.com/stanford-cs336/lectures)

## 本地官方讲义

- 位置：[materials/lectures](materials/lectures/)，作为 Git submodule 保留官方历史，由父仓库记录具体 commit。
- 课程版本：Spring 2026；获取日期：2026-09-28。
- 获取时 commit：`de53a9f979a6ee35f7d13a5e1aadee5ea1afc58e`（2026-09-12）。
- 来源：https://github.com/stanford-cs336/lectures
- 阅读入口：[官方 README](materials/lectures/README.md)。讲义包含可执行的 Python 文件和 PDF 幻灯片。

与 A1 起步相关的材料：

| 讲座 | 本地材料 | 在线阅读 |
|---|---|---|
| Lecture 1：Overview、Tokenization | [lecture_01.py](materials/lectures/lecture_01.py) | [交互式讲义](https://cs336.stanford.edu/lectures/?trace=lecture_01) |
| Lecture 2：PyTorch、资源核算 | [lecture_02.py](materials/lectures/lecture_02.py) | [交互式讲义](https://cs336.stanford.edu/lectures/?trace=lecture_02) |
| Lecture 3：Architectures、Hyperparameters | [lecture_03.pdf](materials/lectures/lecture_03.pdf) | [官方 PDF](https://github.com/stanford-cs336/lectures/blob/main/lecture_03.pdf) |

本次仅获取讲义仓库，未安装讲义运行环境。Python 讲义可直接阅读源码，交互式展示可使用上方官网链接。

## 本地 Assignment 1

- 位置：[labs/assignment1-basics](labs/assignment1-basics/)，作为 Git submodule 保留官方历史；父仓库通过 `.gitmodules` 记录来源，通过 gitlink 记录具体 commit。
- 作业说明：[cs336_assignment1_basics.pdf](labs/assignment1-basics/cs336_assignment1_basics.pdf)
- 环境和数据说明：[README.md](labs/assignment1-basics/README.md)
- 获取日期：2026-09-28
- 获取版本：`main`，CHANGELOG 版本 `26.0.3`（2026-04-07）
- 获取时 commit：`a158843b20107949f1a8d7df1b05cd33b9166712`
- 来源：https://github.com/stanford-cs336/assignment1-basics

本次仅克隆资源，未安装依赖或下载训练数据。

重新克隆本学习目录时，使用 `git clone --recurse-submodules <学习目录仓库地址>`；已有克隆可在根目录运行 `git submodule update --init --recursive` 获取记录的作业版本。

作业改动先在子模块内提交，再在父仓库提交更新后的子模块指针。若要跨机器恢复自己的实现，需把子模块提交推送到自己的远程仓库，并将 `.gitmodules` 的 URL 更新为该仓库地址；仅推送父仓库不会上传子模块的提交。

## VS Code 学习环境

从 VS Code 打开本学习目录根目录，使 `.vscode/` 配置生效。当前默认解释器是 A1 的 `.venv`；已配置 pytest 测试发现和当前 Python 文件的调试入口。项目关闭内联生成建议、Copilot 和 InfCode 自动补全，保留普通 IntelliSense。

本机已安装 Python、Pylance、Python Debugger 和 Jupyter 扩展。Notebook 可在 Python Environments 中选择 `cs336-basics (3.12.13)`（路径为 A1 的 `.venv/bin/python`），或选择已注册的 `CS336 A1 (Python 3.12)` 内核；二者使用同一个环境。已有的 `test.ipynb` 已选择该 Python 环境。

在根目录重建本机环境的命令：

```sh
uv sync --frozen --project courses/cs336/labs/assignment1-basics
uv pip install --python courses/cs336/labs/assignment1-basics/.venv/bin/python ipykernel matplotlib
courses/cs336/labs/assignment1-basics/.venv/bin/python -m ipykernel install --user --name deep-learning-study-cs336-a1 --display-name "CS336 A1 (Python 3.12)"
```

`ipykernel` 和 `matplotlib` 是本地学习工具，没有改动作业的依赖声明或锁文件。以后执行精确的 `uv sync` 可能移除这两个额外依赖；可重新运行上面的安装命令，或使用 `uv sync --frozen --inexact` 保留额外依赖。

## 目录结构

```text
materials/    handout、lecture material 和版本记录
notes/        tokenizer、Transformer、训练和系统优化笔记
labs/         官方 starter code、自己的实现和实验
anki/drafts/  CS336 Anki 卡片草稿
```

核心 TODO 由自己完成，不复制第三方实现或答案。
