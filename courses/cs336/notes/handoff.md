# CS336 交接记录

每次学习结束时更新，下次会话从这里接着做。

**更新日期**：2026-09-30

## 当前位置

CS336 Assignment 1，§2.4–2.5 BPE 训练。

| 步骤 | 内容 | 状态 |
|---|---|---|
| ① 初始化词表 | 256 个单字节 + 特殊 token | ✅ 完成，断言通过 |
| ② 预分词 | `PAT` 切块 → 频率表；按特殊 token 切段后加总 | ✅ 完成，断言通过 |
| ③ 计算合并 | 统计相邻对 → 选最频繁 → 合并 → 更新词表和合并记录 | ⬜ **下一步** |
| 串成 `train_bpe` | 读文件 + ① + ② + ③，返回 `(vocab, merges)` | ⬜ |
| 接入官方测试 | `tests/adapters.py` 的 `run_train_bpe`，运行 `uv run pytest tests/test_train_bpe.py` | ⬜ |
| 提速 | 按 §2.5 的建议优化，然后训练 TinyStories | ⬜ |

§2.1–2.3 的概念已学完，并在 notebook 中做过实验。

## 已完成的代码

都在 `courses/cs336/labs/assignment1-basics/cs336_basics/test.ipynb`，每个函数下方都有一个断言 cell：

| 函数 | cell id | 断言 cell | 说明 |
|---|---|---|---|
| `init_vocab(special_tokens) -> dict[int, bytes]` | `3edad04d` | `5e69b6e0` | 字节 `i` 的 ID 就是 `i`，特殊 token 从 256 开始编号 |
| `count_pretokens(text) -> dict[tuple[bytes, ...], int]` | `0959db43` | `1ec6c76a` | 键是单字节元组，例如 `(b' ', b'l', b'o', b'w')` |
| `count_all_pretokens(text, special_tokens)` | `814cdf7b` | `4a0f90c7` | 用 `re.escape` 转义后 `re.split`；列表为空时整段文本作为唯一一段 |

几条待办的小事：

- `count_pretokens` 目前用的是 `findall`。搬到 `.py` 文件、准备处理真实语料时，改成 handout 要求的 `finditer`。
- `count_all_pretokens` 的变量名还没改：`split_text` → `segments`，`per_text` → `segment`，`counts` → `segment_counts`，`total` → `total_counts`，`key` → `pretoken`，另外补上类型标注。学习者准备自己改。
- 所有代码目前都只在 notebook 里，还没有搬进 `cs336_basics/` 下的 `.py` 文件。

## 下一步：第三步 计算合并

1. **热身**：先手算 handout bpe_example 的前 6 次合并，结果应为 `s t`、`e st`、`o w`、`l ow`、`w est`、`n e`。第 1、3、5 轮有并列，按"字典序更大"决定。
2. 拆成几个小函数，每写完一个就补一组断言：
   - a. 在频率表里统计相邻对，每对的次数按所在块的出现次数加权；
   - b. 选出现次数最多的一对，并列时取字典序更大的（直接比较 `(bytes, bytes)` 元组即可）；
   - c. 把频率表中所有该相邻对合并成一个新 token，出现次数不变；
   - d. 词表新增一项，合并记录追加 `(token1, token2)`。
3. 循环次数 = `vocab_size` − 256 − 特殊 token 数量。
4. 可以用 handout 的例子做测试，但要注意：例子为了简单，是按空格预分词的；用 `PAT` 预分词时，句中的词带前导空格。

## 学习者的情况与偏好

- 希望一步一步来，每次只讲一小块；概念问题直接回答，少追问（见根目录 `AGENTS.md` 的回答方式）。
- Python 生疏：`str` / `bytes` / `int` 的互相转换、字典的赋值和累加、缩进、只在 `if` 分支里赋值的变量，这些都卡过。思路基本都是对的，出错主要在语法细节。
- 习惯是：学习者写函数，助教补断言 cell，并先用参考实现验证断言本身没写错。
- 核心实现由学习者自己写。卡得太久、学习者明确要求时，可以直接给语法层面的修正（例如补一个 `else` 分支）。
- 喜欢在每个阶段结束时做 Anki 卡片，流程见 `.agents/skills/anki/SKILL.md`。

## 未完成的状态

- **Git**：父仓库比 `origin/main` 领先 3 个提交，还没推送。另有未提交的改动：`debt.md`、`courses/cs336/anki/drafts/2026-09-30-pretokenization.md`，以及本文件。
- **子模块**：`test.ipynb` 是 A1 子模块里未跟踪的文件，还没有保存方案。直接在子模块里提交的话，因为子模块指向官方仓库，提交推送不上去；需要先把子模块的远程改成学习者自己的仓库（见 `courses/cs336/README.md`）。
- **Anki**：CS336 牌组共 20 张卡，未同步 AnkiWeb。其中两张是 `status::verify`，等学习者亲手运行确认后改为 `verified`：
  - `1790756579385`：`bytes(0)` 与 `bytes([0])` 的区别；
  - `1790771680268`：`re.split("", s)` 会在每个字符之间切分。
- **待补知识**：`debt.md` 里有两条（ASCII / Unicode / UTF；Python `str` 与 `bytes`），计划在 CS336 §2.6 和 CSAPP 第 2 章时回补。
- **规则冲突**：A1 子模块里有官方的 `AGENTS.md` 和 `CLAUDE.md`（两者内容相同），要求 agent 先反问、不写代码，和根目录 `AGENTS.md` 冲突，尚未处理。
