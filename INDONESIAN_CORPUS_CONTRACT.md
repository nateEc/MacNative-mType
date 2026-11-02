# 印尼语三个档位的独立字面词库

起点 2b42a38f73de72f08b9290023e0f479e47d0bf40。此前基础池仅 30 个自有词，1k／10k 返回 qx、重复 q 和 qz 编号，不是可用词汇。只读读取固定参考的聚合形状，不读取或导出其词值：基础 310／最大 11／无大小写及标点；1k 1020／最大 14／2 个含大写词及 2 个含标点词；10k 13769／最大 13／无大写及 494 个含标点词，最短均为 2。

## 独立来源与选择

English Wiktionary contributors 经 Kaikki.org / Wiktextract 提取的 Indonesian JSONL：
https://kaikki.org/dictionary/Indonesian/kaikki.org-dictionary-Indonesian.jsonl
下载快照 70,005,729 字节，SHA-256 3ebda79fc5ed7abd1995e2a46294362f3f9282bcf74b892b4d9588d76bdc97f5。索引记录 2026-10-30 提取、2026-10-01 enwiktionary dump。仅取 id 语言的声明词类和原样 ASCII 字母／内部连字符形式；排除词缀词类、romanization、模板及提取错误，以及仅有 misspelling／proscribed／nonstandard 义项的条目。不复制释义或例句，不合成前后缀、编号或大小写。

wordfreq 3.1.1 wheel SHA-256 4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473，small_id.msgpack.gz SHA-256 6fd891027cd6395b5c038c0e6402fa7e107ffd8973f862053246b897beb1bcd3。仅用 ASCII 小写整词查找进行编排，显示拼写保持原样；缺失观察不是零，也不以分词估值补齐。基础／1k／10k 各有 310／1018／11143 个整词观察，其余由词典原形提供，不宣称所有词有频率证据。

旧 30 个自有词全部保留在三个池；sejenak 和 hening 未见于本词典快照，明确标为 typebar-legacy，而非词典收录，两者有独立整词频率观察。逐词来源类型、词典标题及可选频率档在 IndonesianCorpusSources.txt 中；完整许可纳入原生署名查看器及签名包。选集与频率数据遵循 CC BY-SA 4.0，保留 wordfreq 完整来源许可说明。

生成器固定输入哈希、输出哈希和确定选择规则；可从独立快照逐字重建，带 bundled 完整性及过滤规则自测，不需产品运行时 Python／Node／网络。三个池保持聚合边界及真实连字符、大小写；1k 允许大写和 14 字母，10k 上限 13 且不含大写，因此不强求三池嵌套。

## 行为与验证

首版选集另有字符集合缺口：虽然大写词计数为 2，实际覆盖 A／J，而固定参考为 I／T。原有聚合形状测试没有捕获该键位差异。该候选的定向和扩大结果不能作为字符覆盖完成证明；新增字符集合断言在 indonesian-character-red 三项中准确失败一处（driver 24.826015 秒）。已将每档允许字符及完整字符集合纳入选择／完整性约束，从词典原样选择 Indonesia／Tuhan 保留 I／T，没有改写字母。最终定向 indonesian-character-focused 通过（driver 55.992914 秒）；固定源逐字重建、bundled 完整性及优化过滤测试重新通过。最终同范围扩大另记。

indonesian-corpus-red：两项共 14 处失败，原生 1.386 秒、driver 26.900130 秒，证明基础数量、合成填充及旧词在大档丢失；非 Markdown 输入保持。indonesian-corpus-focused：10 项零失败／跳过，原生 6.113 秒、driver 114.010267 秒，输入保持。包含原有独立 ID／精确聚合形状检查和许可查看器；实际最长词、连字符与大写词的完整输入、零错、结果 JSON 和重复目标通过，已有合成时期保存目标不被新词库改写。原始语言 ID、分享／JSON、语音区域、Wiki 路由及未知运行时 Zipf 支持保持。

独立固定来源 --check 逐字重建通过；--self-test 及 python -O 各三项过滤测试通过，--check-bundled 固定哈希／内容完整性通过；仓库外副本追加一字节后被明确拒绝。人工清单结构审计通过（1481 个唯一场景），不等同人工验收。

首候选 indonesian-corpus-regression：221 项零失败／跳过，原生 383.606 秒、driver 396.880285 秒，151 项必需源码合同通过，输入保持。因为其后独立发现字符覆盖缺口，该结果保留为历史候选证据，不能冒充最终输入状态的验证。

更正字符集合后的 indonesian-character-focused：11 项零失败／跳过，原生 5.265 秒、driver 55.992914 秒。最终同范围 indonesian-corpus-final-regression：222 项零失败／跳过，原生 385.945 秒、driver 399.060626 秒，151 项必需源码合同全部通过；非 Markdown 输入保持。最终结果包括新词库固定哈希／来源检查、全部三档字符集合及原有精确档位形状。

提交前 Git 暂存区检查发现来源 TSV 用空末列表示缺失观察，会产生行尾制表符；尚未提交／推送。改为明确 NA，不是零，并让校验器拒绝不合法的频率列。练习词形／顺序、源类型／标题和已有频率值不变；来源行与清单哈希更新，固定源逐字重建与 bundled 检查再次通过。暂存区 diff --check 通过，按新输入状态运行 indonesian-publish-regression 和 indonesian-publish-package；上述包与回归保留为更早文件状态的记录，不冒充发布前最终证据。

最终发布前 indonesian-publish-regression：222 项零失败／跳过，原生 385.499 秒、driver 397.977677 秒，151 项必需源码检查通过，非 Markdown 输入保持。逐行核对 13772 条来源记录，变化仅为空频率列改为 NA。indonesian-publish-package 签名、资源字节和原创性通过，driver 43.117164 秒，非 Markdown 输入保持，与发布前回归为同一最终输入。临时 QA 包检查后清理，未启动应用。

indonesian-corpus-package：签名、资源字节和原创性检查通过，driver 45.037360 秒，非 Markdown 输入保持。新许可和逐词来源随临时 QA 包核对后清理，未启动应用，不代表发行包交付。推前 main 为 8c52fb13028f82fd8e8718d55cb7ed65463b034e，开发分支为 2b42a38f73de72f08b9290023e0f479e47d0bf40；无打开 PR，Actions 826 次、最近 39118939684 成功。一次开发分支批次推送，推后另存远端／进程及验证输入匹配证据，不改工作流或通知。

只读具名 ScaleLexicon 属性审计从 104 条／795393 个声明位置变为 102 条／780604 个声明位置，恰好移除 indonesian1kLexicon 和 indonesian10kLexicon 的 14789 个占位位置；这是明确结构范围，不是全部剩余语言缺口。记录 indonesian-scale-audit.json 位于本机持久 QA 目录，迁移后 TypingEngine SHA-256 22c8f55eca8c7edc471dc958468c937ff3f70e3437fac1aa51c395ee904e3a52。

## 开放边界

独立选集不等于原版相同词汇、排序、频率或难度；机械词典过滤不证明每个词的规范性、适用性或语言质量。全部字符频次、实体印尼语键盘／IME、VoiceOver、长时练习与完整分布仍须验收。保留原版元数据及聚合形状不是无功能损失的充分证据，本项保持部分完成，完整重写目标继续 active。
