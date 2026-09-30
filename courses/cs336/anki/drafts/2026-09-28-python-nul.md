# Python 码点、不可见字符与字符串显示

操作模式：write（2026-09-29 已写入本机 Anki 的 CS336 牌组）。
以下 3 张 Basic 卡片的内容来自 Notebook 输出与学习者复述。正面考察一般规律，背面保留已验证的例子。

写入前已检查现有 CS336 卡片，无重复。写入后通过 `notesInfo` 和 `findCards` 核对字段、标签和牌组；卡片 1–3 的 note ID 分别为 `1790653541622`、`1790653541627`、`1790653541630`。未执行 AnkiWeb 同步。

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

Python 的 `chr(n)` 中，整数 `n` 与返回的字符是什么关系？

### Back

对合法码点，`n` 是 Unicode 码点，`chr(n)` 返回包含对应字符的长度为 1 的字符串。码点数值不是字符串长度。

例如：`chr(29275)` 是 `'牛'`；`chr(0)` 是 `'\x00'`（NUL），二者长度都是 1。

### Source

`courses/cs336/labs/assignment1-basics/cs336_basics/test.ipynb`：`ord("牛")`、`chr(29275)` 与 `chr(0)` 的输出；2026-09-28 关于码点与长度的讨论。

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

为什么不能通过 `print(s)` 看起来是否空白，判断 Python 字符串 `s` 是否为空？

### Back

空字符串没有字符；非空字符串也可能只包含空格或没有可见字形的字符。应检查 `len(s) == 0` 或 `s == ""`。

例如：`len(" ")` 和 `len(chr(0))` 都是 1，`len("")` 才是 0。不可见不等于不存在。

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

查看 Python 字符串的 `repr` 表示，与用 `print` 输出该字符串，有什么区别？

### Back

`repr` 提供便于检查的表示：加上引号，并用转义形式展示某些不可见字符。`print` 输出字符串的实际内容，默认再追加换行；显示效果取决于输出环境。

例如：Notebook 直接查看 NUL 字符串显示 `'\x00'`，而 `print` 时 NUL 没有可见字形。`\x00` 在这里表示一个字符，不是四个字符。

### Source

`courses/cs336/labs/assignment1-basics/cs336_basics/test.ipynb`：`chr(0)` 与 `print(chr(0))` 的已保存输出，2026-09-28 核对。
