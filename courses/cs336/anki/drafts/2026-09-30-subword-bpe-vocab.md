# 子词切分与 BPE 词表初始化

操作模式：write（2026-09-30 已写入本机 Anki 的 CS336 牌组）。
6 张 Basic 卡片。正面考察一般规律，背面保留已讨论的例子；不收录 `train_bpe` 的实现代码。
`status::verified` 表示内容已通过学习者实验、复述或核对 handout；`status::verify` 表示还需学习者自己运行确认。

写入前已检查现有 CS336 卡片，无重复。写入后通过 `notesInfo` 和 `cardsInfo` 核对字段、标签和牌组；卡片 1–6 的 note ID 分别为 `1790756579374`、`1790756579381`、`1790756579382`、`1790756579383`、`1790756579384`、`1790756579385`。未执行 AnkiWeb 同步。

## 卡片 1

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::tokenizer
  - source::cs336-a1-sec2-3
  - type::basic
  - status::verified
```

### Front

按词切分（word-level tokenization）有哪些主要问题？

### Back

- 训练时没见过的词只能变成 `<unk>`（OOV），信息丢失；
- 词表要几十万项，仍然覆盖不全；
- 相关的词互不相干，例如 `cat` 与 `cats`、`happy` 与 `unhappy` 是不同条目。

### Source

CS336 A1 §2.3；学习者在 `test.ipynb` 中用 `"the cats are unhappy"` 写下的比较笔记。

## 卡片 2

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::tokenizer
  - source::cs336-a1-sec2-3
  - type::basic
  - status::verified
```

### Front

按字节切分（byte-level tokenization）不会遇到 OOV，它的主要代价是什么？

### Back

序列变长：每个字节一个 token，英文大约是按词切分的 5 倍。

- 模型每一步要处理更多位置，计算量更大；
- 相关信息在序列中离得更远，模型还要先学会把字节拼成词。

例如，`"the cats are unhappy"` 按词切是 4 个 token，按字节切是 20 个。

### Source

CS336 A1 §2.3；学习者在 `test.ipynb` 中的比较笔记。

## 卡片 3

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::tokenizer
  - source::cs336-a1-sec2-3
  - type::basic
  - status::verified
```

### Front

子词 tokenizer（如 byte-level BPE）如何在按词切分和按字节切分之间折中？

### Back

- 保留 256 个单字节作为基础，因此仍然不会遇到 OOV；
- 把高频字节串加入词表，作为单个 token，因此序列变短；
- 代价是词表变大，`vocab_size` 成为需要权衡的超参数。

例如，`the the the` 按字节是 11 个 token；把 `t h`、`th e` 依次加入词表后是 5 个。

### Source

CS336 A1 §2.3；学习者在 `test.ipynb` 中的比较笔记。

## 卡片 4

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

byte-level BPE 训练开始时，词表里有哪些项？训练结束时词表大小怎么算？

### Back

开始时：256 个单字节 token，加上特殊 token；每一项都是 `bytes`。

每合并一次，词表增加一项，因此：

最终大小 = 256 + 特殊 token 数 + 合并次数

例如，handout 的例子有 1 个特殊 token，起始 257 项，合并 6 次后是 263 项。

### Source

CS336 A1 §2.4 Vocabulary initialization 与 bpe_example；学习者在 `test.ipynb` 中实现初始词表，并通过 0、1、2 个特殊 token 三组断言。

## 卡片 5

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

为什么 `<|endoftext|>` 这类特殊 token 必须作为一个整体放进词表，而不按普通文本切分？

### Back

它表达的是控制信号（例如文档边界、生成结束），不是正文内容。

- 如果被拆成多个 token，会和普通文本里的相同字符混淆；
- 生成时模型要连续输出多个 token 才能表达"结束"，不可靠。

所以它在词表中只占一项，有固定 ID，并且不参与 BPE 的合并统计。

### Source

CS336 A1 §2.4 Special tokens；2026-09-30 关于特殊 token 的讨论。

## 卡片 6

```yaml
deck: CS336
note_type: Basic
tags:
  - course::cs336
  - topic::python-bytes
  - source::cs336-a1-sec2-4
  - type::basic
  - status::verify
```

### Front

Python 中，`bytes(0)` 和 `bytes([0])` 有什么区别？

### Back

- `bytes(n)` 创建 n 个零字节，所以 `bytes(0)` 是 `b''`，`bytes(3)` 是 `b'\x00\x00\x00'`；
- `bytes([...])` 把列表中的每个整数当作一个字节值，所以 `bytes([0])` 是 `b'\x00'`。

要把 0～255 的整数 `i` 变成单字节 `bytes`，用 `bytes([i])`。整数没有 `encode` 方法，`encode` 只用于把 `str` 按编码规则转成字节。

### Source

CS336 A1 §2.4 初始化词表时的练习；学习者运行过 `bytes([0])`、`bytes([1])`，并遇到 `int` 没有 `encode` 的报错。`bytes(n)` 的行为需学习者自己运行确认。
