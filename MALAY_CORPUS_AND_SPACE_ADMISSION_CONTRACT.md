# 马来语字面词池与空格接纳

起点 4fc9a238c2a1536ed63a9fb4ff722f3d4e8714fb；固定 Monkeytype 参考 91bd24bb8513785c7364cbea29296ff7adafac41。语言词值不从参考导出，只读取聚合形状和字符集合。

## 内容来源和边界

原有基础池 30 个自有词，1k 使用 qz 编号、重复 q、Q 及尾连字符填充。现在基础 228 项、1k 1000 项，最短均为 2，最长分别 12／16。基础字符集合 abcdefghijklmnoprstuwy；1k 为相同范围扩展的 v／z、大写 S、连字符和空格，保持原版完整字符集合。1k 恰有 1 个大写词、12 个带连字符词、1 个带单空格词，三类不重叠。

字典：English Wiktionary contributors，经 Kaikki.org / Wiktextract 提取。
https://kaikki.org/dictionary/Malay/kaikki.org-dictionary-Malay.jsonl
28,867,677 字节，SHA-256 d4b211c01a2206ae4136a6b35ca0cd1412e053cf95bcb639837a4f4559d3c592；索引记录 2026-10-30 提取、2026-10-01 dump。仅取 ms 的声明词类及原样 ASCII 字母／内部连字符／单空格短语；排除词缀、提取错误／模板／romanization 及仅有错误／不规范义项的条目。字典数据与选集遵循 CC BY-SA 4.0，不复制释义或例句。

观察频率：Tatoeba standard Malay zsm contributors。
https://downloads.tatoeba.org/exports/per_language/zsm/zsm_sentences_detailed.tsv.bz2
166,148 字节，SHA-256 3e4701bc8b673a278a30a084be3c87deaa449da9ed011082a06bda1e27821d20，7791 句，71 个公开作者标识，CC BY 2.0 France；未知／无主作者显式保留。只匹配完整 ASCII 词，保留内部连字符；短语必须在原句相邻词间有恰好一个 ASCII 空格，不跨标点、双空格或新行，也不把重音词截为 ASCII 残片。查找小写化不改显示原形，不以印尼语数据代替。

全部旧 30 词保留；latihan、harapan 未见于此字典快照，单列旧自有词来源。基础／1k 分别有 226／997 个选项在本句子快照有整词观察，其他项的频率和句子 ID 为 NA，不冒充零使用频率。逐词标题、源类型、观察次数及首条句子 ID 随包交付，原生许可查看器可读取完整说明。原文句子、翻译、音频和原版词表不装入产品。脚本固定来源／产物哈希，可离线重建并验证。

## 源行为纠偏与产品修正

生成器的候选字符串可以含空格，但固定源 getNextWord 会压缩／去掉边缘空格并拆成 section，逐词消费；不是一个可任意完整输入的字段。最初 factory 测试错误要求 1 词练习保留整段候选。已按源代码纠正：1 词仅取首分量，2 词保留两个分量；默认无标点时普通马来语大写会小写化，开启标点仍可练大写。没有为了错误测试预期修改原生生成器。

新增内部空格源码探针使用自有中性字段（内部单空格、双空格和开头空格），8 种输入、3 档停止错误和逐键／整段调用，共 144 场景。执行完整固定输入／验证／导航／事件模块，目录和 UI 为明确适配器；与原有 LF 探针共用原生比较器，旧 144 个 LF 夹具保持。比较开始／终态、活动字段、UTF-16 输入和逐事件位置／正确性／停止／提交。此为普通 words 模式 ASCII 行为证据，不是实际浏览器／IME 或所有马来语特有规则的证明。

有效反例：当目标本身以空格开头时，原生曾允许普通空输入的 Space 开始计时并进入目标；源 before-insert-text 在空输入时直接忽略 Space，只有 strictSpace、非 normal 难度或 hard delete 可放行。移除原生“目标也是空格则例外”的条件，保持严格／难度／hard-delete 的既有分支；Return、Zen 和 noSpace 的独立入口不改。忽略的 Space 不产生一次已开始尝试或输入事件。

## 验证记录

malay-corpus-red 最初因 rules 参数顺序编译失败，driver 15.945364 秒，不当作产品红测。修正后 malay-corpus-behavior-red：4 项共 540 处失败，原生 2.074 秒、driver 26.273095 秒；其中 526 处为内部空格探针对开头空格的实际接纳差异，另含错误的候选完整字段测试假设和旧占位缺口。输入保持。

malay-corpus-focused：16 项零失败／跳过，原生 6.029 秒、driver 108.212811 秒，非 Markdown 输入保持。包括两个 144 场景的空格／LF 源输入对照、固定来源完整性、原有精确马来语形状、印尼语回归及许可查看器。新词库通过实际 factory 的短语拆词、最长词／连字符／大写条件、完整输入、零错、JSON 和重复目标检查。

独立固定来源逐字重建、bundled 哈希和普通／优化过滤自测各 3 项通过。扩大、签名包及剩余占位审计另记。实体马来语输入／IME、VoiceOver、词汇规范性与难度、频率分布和完整性能仍开放，独立选集不等同原版相同词汇／排序；两个功能项均保持部分完成，完整重写目标继续 active。

结构审计 malay-scale-audit.json：移除 malay1kLexicon 内联构造器 1000 个占位位置；该路径不属于直接具名 ScaleLexicon 属性范围，后者仍为 102 条／780604 个声明位置，不重复扣减。当前 TypingEngine SHA-256 69c41f84825314a754ac986000dd71dfba0ab6cf5becd598e1a15b4346286775。

首轮扩大 malay-corpus-regression：611 项中一个用例两处断言失败，原生 457.271 秒、driver 471.440021 秒，输入保持。CodeFieldIndentationTests 的空白前词删除夹具使用 normal 模式第二个 Space 建立空白词，这正是源 before-insert 拒绝的输入；不能保留错误例外来让它通过。夹具改用源明确允许的 letterHard 条件建立空白词，删除及回放断言保持；新增普通模式 Space 不生成缩进、输入事件或额外尝试统计的独立回归。malay-source-space-focused：25 项零失败／跳过，原生 1.041 秒、driver 25.739232 秒，输入保持。最终同范围扩大另记，首轮失败不当作通过。

最终同范围 malay-corpus-final-regression：612 项零失败／跳过，原生 464.095 秒、driver 477.886096 秒，152 项必需源码合同通过，非 Markdown 输入保持。覆盖空格／分隔、代码缩进和延迟输入、终态字段、原始单元、停止错误、盲打、Zen、反向 Shift、长空白文本、有限末词、实际 factory、语言词池与完整必需源码集合；不是全部项目测试或实体输入验收。人工清单审计通过（1483 个唯一场景）；仓库外来源副本追加一字节后被 pin 校验拒绝，仓库数据不改。

malay-corpus-package：签名、资源字节及原创性检查通过，driver 48.645485 秒，非 Markdown 输入保持，与最终回归匹配。新增完整许可／逐词来源随临时 QA 包检查并清理，未启动 Typebar 应用，不代表发行包交付。推前 main 为 8c52fb13028f82fd8e8718d55cb7ed65463b034e，开发分支为 4fc9a238c2a1536ed63a9fb4ff722f3d4e8714fb；无打开 PR，Actions 826 次，最近 39118939684 成功。一次开发分支批次推送，推后另存远端／进程和验证输入匹配证据，不改工作流或通知。
