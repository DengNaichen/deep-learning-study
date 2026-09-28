# Python NUL 字符与字符串显示

操作模式：draft（仅保存草稿，未写入 Anki）。
以下 3 张 Basic 卡片的内容来自 Notebook 输出与学习者复述；`status::verified` 表示知识已核对，不表示已同步。

## 卡片 1

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::unicode
  - source::cs336-a1-notebook
  - type::basic
  - status::verified
```

### Front

Python 的 `chr(0)` 返回什么？其中的 `0` 表示什么？

### Back

返回包含 Unicode 码点 U+0000（NUL 字符）的字符串，表示为 `'\x00'`。`0` 是字符的码点，不是字符串长度；返回值也不是 `None`。

### Source

`courses/cs336/labs/assignment1-basics/cs336_basics/test.ipynb`：`chr(0)` 的输出；2026-09-28 对话中关于 NUL 与码点的讨论。

## 卡片 2

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::python-strings
  - source::cs336-a1-notebook
  - type::basic
  - status::verified
```

### Front

`len(chr(0))` 与 `len("")` 分别是多少？为什么？

### Back

分别是 **1 和 0**。前者包含一个没有可见字形的 NUL 字符，后者没有字符。不可见不等于不存在。

### Source

2026-09-28 学习者复述：“上面的两个是 1 和 0”，并确认空格字符串的长度为 1。

## 卡片 3

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::python-display
  - source::cs336-a1-notebook
  - type::basic
  - status::verified
```

### Front

为什么在 Notebook 中直接查看 `chr(0)` 会显示 `'\x00'`，而 `print(chr(0))` 看起来像空白？

### Back

直接查看时，Notebook 展示类似 `repr()` 的可读表示，用 `\x00` 表示 NUL。`print` 输出实际字符并默认追加换行；NUL 没有可见字形，但仍存在。

### Source

`courses/cs336/labs/assignment1-basics/cs336_basics/test.ipynb`：`chr(0)` 与 `print(chr(0))` 的已保存输出，2026-09-28 核对。
