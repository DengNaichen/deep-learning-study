# Anki 卡片模板

这些模板用于 Markdown 草稿和写入前预览。字段名映射到 Anki Note Type 时，优先使用目标牌组中已有的字段；不要未经用户要求创建新的 Note Type。

## 通用元数据

每张卡都应尽量包含：

```yaml
deck: CSAPP
note_type: Basic
tags:
  - course::csapp
  - topic::assembly
  - source::csapp-3e-ch03
  - type::basic
  - status::verified
```

`status` 只能使用 `verified`、`verify` 或 `draft`。草稿阶段通常使用 `draft`；经过学习者复述、运行实验或核对教材后再改为 `verified`。

## Basic：概念问答

适合定义、机制、不变量、比较和错误原因。Front 要求一个明确答案，Back 保持短小，并优先使用列表或公式。

```markdown
---
deck: CSAPP
note_type: Basic
tags:
  - course::csapp
  - topic::assembly
  - source::csapp-3e-ch03
  - type::basic
  - status::draft
---

### Front

在 x86-64 中，函数调用时栈指针 `%rsp` 的核心作用是什么？

### Back

`%rsp` 指向当前栈顶，用于定位当前栈帧中的局部数据、保存的返回地址以及通过栈传递的部分参数。`call`、`push`、`pop` 和 `ret` 会改变它。

### Source

CSAPP 第 3 章；需要结合一个最小 C 程序和 GDB 观察验证。
```

## Cloze：从句中回忆

适合一个稳定事实中需要主动回忆的关键术语、条件或公式。每张卡通常只使用一个 `c1`，不要把整段文字挖空。

```markdown
---
deck: CSAPP
note_type: Cloze
tags:
  - course::csapp
  - topic::bits
  - source::csapp-3e-ch02
  - type::cloze
  - status::draft
---

### Text

对于 w 位补码，最高位的权重是 {{c1::-2^{w-1}}}，其余位的权重为正的 2 的幂。

### Extra

用 w=8 验证最小值为 -128，最大值为 127。
```

## Code mechanism：代码机制卡

适合 C、汇编、操作系统、网络协议和数据库中的执行机制。不要把课程 Lab 的完整实现放入 Back；只保留最小片段、状态变化、不变量和验证方法。

```markdown
---
deck: CSAPP
note_type: Basic
tags:
  - course::csapp
  - topic::pointer
  - source::csapp-3e-ch03
  - type::code-mechanism
  - status::draft
---

### Front

为什么 `int *p` 和 `int a[4]` 在表达式中经常表现相似，但它们不是同一种对象？

### Back

- `a` 是数组对象；在大多数表达式中会退化为指向首元素的指针。
- `p` 是独立的指针对象，可以改为指向别处。
- `sizeof(a)` 得到整个数组大小，`sizeof(p)` 得到指针大小。

用 `sizeof` 和一个改变 `p` 的最小程序验证，不要只凭记忆。

### Source

CSAPP 第 3 章；C 语言数组与指针实验。
```

## 生成检查

生成或写入前检查：

- Front 是否可以在 10–20 秒内理解；
- Back 是否回答了 Front，而不是重复题目；
- 是否只考察一个核心概念；
- 公式、代码和术语是否可以追溯到 Source；
- 是否标记了 `status::draft` 或 `status::verify`；
- 是否包含会暴露 Lab 解法的实现细节。
