# BPE 预分词与特殊 token 边界

操作模式：write（2026-09-30 已写入本机 Anki 的 CS336 牌组）。
7 张 Basic 卡片。正面考察一般规律，背面保留已讨论的例子；不收录 `train_bpe` 的实现代码。
`status::verified` 表示内容已通过学习者实验、实现、断言或核对 handout；`status::verify` 表示还需学习者自己运行确认。

写入前已检查现有 CS336 卡片，无重复。写入后通过 `notesInfo` 和 `cardsInfo` 核对字段、标签和牌组；卡片 1–7 的 note ID 分别为 `1790771680262`、`1790771680264`、`1790771680265`、`1790771680266`、`1790771680267`、`1790771680268`、`1790771680269`。未执行 AnkiWeb 同步。

## 卡片 1

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::tokenizer
  - source::cs336-a1-sec2-4
  - type::basic
  - status::verified
```

### Front

BPE 训练在计算合并之前，为什么要先对语料做预分词（pre-tokenization）？

### Back

- **省计算**：同一个块只统计一次，数相邻对时按出现次数累加，不用每轮扫描整个语料；
- **避免只差标点的 token**：合并不跨越块的边界，标点和单词分在不同块里，不会出现 `dog!`、`dog.` 这种 token。

### Source

CS336 A1 §2.4 Pre-tokenization；学习者用 `PAT` 切分 `"dog! dog."` 等文本的实验。

## 卡片 2

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::tokenizer
  - source::cs336-a1-sec2-4
  - type::basic
  - status::verified
```

### Front

用 GPT-2 预分词正则切分时，为什么 `'low'` 和 `' low'` 是两种不同的块？

### Back

正则把空格附在词的**前面**（` ?\p{L}+`），所以句中的词带前导空格；文本或文档开头的词前面没有空格。

例如，`"low low low lower"` 切成 `['low', ' low', ' low', ' lower']`，计数时 `'low'` 和 `' low'` 要分开算。

### Source

CS336 A1 §2.4；学习者在 `test.ipynb` 中对 `"low low low lower"` 的切分结果。

## 卡片 3

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::tokenizer
  - source::cs336-a1-sec2-4
  - type::basic
  - status::verified
```

### Front

BPE 训练的预分词频率表为什么用 `dict[tuple[bytes, ...], int]`，键是"单字节元组"？

### Back

- 值是这个块出现的次数，相同的块只存一份；
- 元组里的每个元素是这个块**当前**被切成的一个 token，合并后会变粗，例如 `(l, o, w)` → `(l, ow)`；
- 用元组而不是列表，是因为字典的键必须不可变，列表不能当键。

### Source

CS336 A1 §2.4 bpe_example；学习者实现频率表并通过断言。

## 卡片 4

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::tokenizer
  - source::cs336-a1-sec2-5
  - type::basic
  - status::verified
```

### Front

训练 BPE 时，为什么要在预分词之前先按特殊 token（如 `<|endoftext|>`）切分文本？

### Back

特殊 token 是硬边界。直接对整段文本跑预分词正则会出现两个问题：

- 块会跨越文档边界，例如 `"dog.<|endoftext|>The"` 会切出 `'.<|'`；
- 特殊 token 本身被拆开，并参与计数。

所以先按特殊 token 切段，每段分别预分词，再把计数加总；特殊 token 自身不计数。

### Source

CS336 A1 §2.5 Removing special tokens before pre-tokenization；学习者的切分实验和断言。

## 卡片 5

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::python-regex
  - source::cs336-a1-sec2-5
  - type::basic
  - status::verified
```

### Front

用 `re.split` 按 `<|endoftext|>` 这类特殊 token 切分时，为什么要先 `re.escape`？

### Back

`|` 在正则里表示"或"。未转义的 `<|endoftext|>` 会被理解成"`<` 或 `endoftext` 或 `>`"：

`re.split("<|endoftext|>", "a<|endoftext|>b")` 得到 `['a', '|', '|', 'b']`。

转义后只匹配字面上完全相同的字符串。多个 token 之间再用不转义的 `"|"` 连接，表示"匹配其中任意一个"。

### Source

CS336 A1 §2.5；2026-09-30 关于分隔符构造的讨论，示例输出在作业环境运行核对。

## 卡片 6

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::python-regex
  - source::cs336-a1-sec2-5
  - type::basic
  - status::verify
```

### Front

特殊 token 列表为空时，为什么不能直接用 `"|".join(...)` 的结果去 `re.split`？

### Back

空列表 `join` 得到空字符串，而 `re.split("", s)` 会在每个字符之间切一刀：

`re.split("", "low low")` 得到 `['', 'l', 'o', 'w', ' ', 'l', 'o', 'w', '']`。

不会报错，但后续计数全错。没有特殊 token 时，应把整段文本当作唯一的一段。

### Source

CS336 A1 §2.5；2026-09-30 编写按特殊 token 切分的函数时的讨论。`re.split("", ...)` 的行为需学习者自己运行确认。

## 卡片 7

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::python-scope
  - source::cs336-a1-sec2-5
  - type::basic
  - status::verified
```

### Front

Python 函数里，变量只在 `if` 分支中赋值，条件不成立时后面再使用它会怎样？

### Back

报 `UnboundLocalError`：这个局部变量在这条执行路径上从未被赋值。

每条执行路径都要给它赋值，例如补上 `else` 分支。

### Source

2026-09-30 学习者在按特殊 token 切分的函数中遇到该报错，补上 `else` 分支后断言通过。
