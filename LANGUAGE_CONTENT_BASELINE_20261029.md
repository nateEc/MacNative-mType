# 当前语言内容的合成占位清单

`LANG-CONTENT-BASELINE-40`，只读审计起点 `1ee242d7f74be670025afa7018c106263558f7ec`。语言 ID／元数据映射、候选数量或长度形状通过，不足以证明可用实际词汇已交付。本项记录未完成工作，不是替换实现或内容质量验收。

## 后续迁移状态

`LANG-ENGLISH-LARGE-43` 已将 English 450k 的 450,029 个合成候选替换为独立实际来源选集，移除 `englishScaleLexicon`；来源、原生输入、旧记录及署名边界见 ENGLISH_LARGE_CORPUS_CONTRACT.md。按下列历史 118 项逐入口复核，目前同范围仍有 117 个直接合成入口，声明数量之和为 3,740,882。复核记录 `/tmp/typebar-english-large-remaining-synthetic-20261029.json`，当前 TypingEngine SHA-256 `ed4df6fd2ff445465c6708c51c148b22d1e23c17f6b494311e3008cf54fa240d`。该数字不是全部语言缺口总量。

随后 `LANG-GERMAN-SCALES-44` 将 German 1k／10k／250k 的 250,225 个候选迁至独立字面词形，移除 `germanScaleLexicon`，来源和实际输入见 GERMAN_SCALES_CORPUS_CONTRACT.md。当前同一历史范围余 114 个直接合成入口，声明数量之和 3,490,657；复核 `/tmp/typebar-german-remaining-synthetic-20261029.json`，当前 TypingEngine SHA-256 `a62cc92a8867e9429d997b0262ed153c2f484924a197424485c77ff71e06db40`。

随后 `LANG-FRENCH-LARGE-45` 将 French 600k 的 633,941 个候选迁至独立词典形式／有词典对应的实际观察拼写，移除 `frenchScaleLexicon`。当前同范围余 113 个直接合成入口，声明数量之和 2,856,716；复核 `/tmp/typebar-french-large-remaining-synthetic-20261029.json`，当前 TypingEngine SHA-256 `780143d6df4742232172ba58b68690702dba1228bbcdb7a5c0f1b4f98d549bd8`。以上 English／German 数字保留为各自迁移时的阶段证据。

以下 118 项表及此前临时候选过程保留为固定起点的历史证据，不再代表全部当前实现；English、German 与 French 行已迁移，但语言质量、词频／难度和分布等价仍未验收。其余历史项继续开放。

## 历史起点确认的范围

审计 `Sources/Typebar/TypingEngine.swift`，SHA-256 为 `5ae7e4b0d62c0f791b6a5e6b33f9945c5eb58e43802843e110ca467399bd305c`。只识别直接调用 `*ScaleLexicon` 且函数内显式使用 alphabeticIndex／paddedAlphabeticIndex 拼接的声明；118 个匹配声明均可找到生产 `StarterLexicon.<selection>Lexicon` 路由。结果保存于 `/tmp/typebar-current-synthetic-scale-audit.json`。

这些入口声明数量之和为 4,190,911，不是去重词汇数、真实词汇数或完整语言缺口总量。审计没有覆盖其他构造器、文字体系生成器、短基础列表或全部语言质量问题。未匹配的入口不能据此判为真实完整内容；446 个语言身份与内容完成度须分开验收。

| 当前构造器 | 识别的入口数 |
| --- | --- |
| europeanScaleLexicon | 57 |
| esperantoScaleLexicon | 12 |
| romanianScaleLexicon | 7 |
| polishScaleLexicon | 6 |
| portugueseScaleLexicon | 5 |
| crimeanTatarLatinScaleLexicon | 4 |
| occitanScaleLexicon | 4 |
| kabyleScaleLexicon | 4 |
| greeklishScaleLexicon | 4 |
| germanScaleLexicon | 3 |
| ukrainianLatynkaScaleLexicon | 3 |
| swissGermanScaleLexicon | 2 |
| afrikaansScaleLexicon | 2 |
| indonesianScaleLexicon | 2 |
| englishScaleLexicon | 1 |
| spanishScaleLexicon | 1 |
| frenchScaleLexicon | 1 |

例如 English 450k 声明 450,029 项（marker yu），Spanish 650k 为 646,579 项（qzv），French 600k 为 633,941 项（qvfr）；源码实际以 marker、少量自写词根和字母编号拼接，再局部伪装长度、大小写或标点统计。它们不应被视为已交付原版规模的实际语言练习。English 五字母 1k 也仍经 europeanScaleLexicon 生成，不能因为入口标签为英文就漏检。

Italian 四档已经改用独立实际观察语料，相关数据、编辑、复现、许可和分布差异见 ITALIAN_SCALES_CORPUS_CONTRACT.md／ITALIAN_LARGE_CORPUS_CONTRACT.md；本清单不否定这些已验证替换，但也不把其证据外推到其他语言。

## 可逐入口追踪的历史占位清单

以下记录固定历史起点自有实现的入口、声明数量及构造器，不含参考项目词值。当时每一行均未完成；后续替换以实际语料证据逐项迁移，不能只删除本表记录。当前迁移状态见上节及 English 行注记。marker 未提取不代表没有合成内容。

| 入口 | 声明数量 | 当前构造器 | marker |
| --- | ---: | --- | --- |
| english450k（后续已迁移，见 LANG-ENGLISH-LARGE-43） | 450029 | 历史 englishScaleLexicon | yu |
| spanish650k | 646579 | spanishScaleLexicon | qzv |
| french600k（已迁移，见 LANG-FRENCH-LARGE-45） | 633941 | 历史 frenchScaleLexicon | qvfr |
| german1k（已迁移，见 LANG-GERMAN-SCALES-44） | 988 | 历史 germanScaleLexicon | qgd |
| german10k（已迁移，见 LANG-GERMAN-SCALES-44） | 9994 | 历史 germanScaleLexicon | wgd |
| german250k（已迁移，见 LANG-GERMAN-SCALES-44） | 239243 | 历史 germanScaleLexicon | xgd |
| romanian1k | 1000 | romanianScaleLexicon | qro |
| romanian5k | 5000 | romanianScaleLexicon | wro |
| romanian10k | 10000 | romanianScaleLexicon | xro |
| romanian25k | 25000 | romanianScaleLexicon | zro |
| romanian50k | 50000 | romanianScaleLexicon | vro |
| romanian100k | 100000 | romanianScaleLexicon | jro |
| romanian200k | 200000 | romanianScaleLexicon | kro |
| polish2k | 2338 | polishScaleLexicon | qpl |
| polish5k | 5000 | polishScaleLexicon | wpl |
| polish10k | 10000 | polishScaleLexicon | xpl |
| polish20k | 20000 | polishScaleLexicon | zpl |
| polish40k | 40000 | polishScaleLexicon | vpl |
| polish200k | 199979 | polishScaleLexicon | kpl |
| ukrainianLatynka1k | 1000 | ukrainianLatynkaScaleLexicon | 未提取 |
| ukrainianLatynka10k | 9998 | ukrainianLatynkaScaleLexicon | 未提取 |
| ukrainianLatynka50k | 49991 | ukrainianLatynkaScaleLexicon | 未提取 |
| swissGerman1k | 1000 | swissGermanScaleLexicon | 未提取 |
| swissGerman2k | 2000 | swissGermanScaleLexicon | 未提取 |
| afrikaans1k | 1000 | afrikaansScaleLexicon | 未提取 |
| afrikaans10k | 8164 | afrikaansScaleLexicon | 未提取 |
| esperanto1k | 1000 | esperantoScaleLexicon | a |
| esperanto10k | 10000 | esperantoScaleLexicon | b |
| esperanto25k | 24998 | esperantoScaleLexicon | c |
| esperanto36k | 36342 | esperantoScaleLexicon | d |
| esperantoXSystem1k | 999 | esperantoScaleLexicon | e |
| esperantoXSystem10k | 9993 | esperantoScaleLexicon | f |
| esperantoXSystem25k | 24970 | esperantoScaleLexicon | g |
| esperantoXSystem36k | 36296 | esperantoScaleLexicon | h |
| esperantoHSystem1k | 999 | esperantoScaleLexicon | i |
| esperantoHSystem10k | 9969 | esperantoScaleLexicon | j |
| esperantoHSystem25k | 24922 | esperantoScaleLexicon | k |
| esperantoHSystem36k | 36131 | esperantoScaleLexicon | l |
| tatarCrimean1k | 1000 | crimeanTatarLatinScaleLexicon | a |
| tatarCrimean5k | 5000 | crimeanTatarLatinScaleLexicon | b |
| tatarCrimean10k | 10000 | crimeanTatarLatinScaleLexicon | c |
| tatarCrimean15k | 15082 | crimeanTatarLatinScaleLexicon | d |
| occitan1k | 1000 | occitanScaleLexicon | a |
| occitan2k | 2000 | occitanScaleLexicon | b |
| occitan5k | 5000 | occitanScaleLexicon | c |
| occitan10k | 10000 | occitanScaleLexicon | d |
| kabyle1k | 1000 | kabyleScaleLexicon | a |
| kabyle2k | 2000 | kabyleScaleLexicon | b |
| kabyle5k | 5000 | kabyleScaleLexicon | c |
| kabyle10k | 10000 | kabyleScaleLexicon | d |
| greeklish1k | 990 | greeklishScaleLexicon | a |
| greeklish5k | 4926 | greeklishScaleLexicon | b |
| greeklish10k | 9808 | greeklishScaleLexicon | c |
| greeklish25k | 24273 | greeklishScaleLexicon | d |
| indonesian1k | 1020 | indonesianScaleLexicon | 未提取 |
| indonesian10k | 13769 | indonesianScaleLexicon | 未提取 |
| czech1k | 899 | europeanScaleLexicon | ƈ |
| czech10k | 9629 | europeanScaleLexicon | ƌ |
| slovak1k | 1001 | europeanScaleLexicon | ƕ |
| slovak10k | 9944 | europeanScaleLexicon | ƥ |
| slovenian1k | 1023 | europeanScaleLexicon | ƣ |
| slovenian5k | 4971 | europeanScaleLexicon | ƿ |
| croatian1k | 1108 | europeanScaleLexicon | ƭ |
| dutch1k | 1000 | europeanScaleLexicon | ƚ |
| dutch10k | 9998 | europeanScaleLexicon | ƨ |
| danish1k | 954 | europeanScaleLexicon | ƶ |
| danish10k | 9624 | europeanScaleLexicon | ƴ |
| swedish1k | 994 | europeanScaleLexicon | ƹ |
| finnish1k | 1000 | europeanScaleLexicon | ɂ |
| finnish10k | 9906 | europeanScaleLexicon | ɇ |
| estonian1k | 1000 | europeanScaleLexicon | ƙ |
| estonian5k | 5000 | europeanScaleLexicon | ƽ |
| estonian10k | 10000 | europeanScaleLexicon | ƞ |
| icelandic1k | 1000 | europeanScaleLexicon | ƒ |
| irish1k | 1000 | europeanScaleLexicon | q́ |
| filipino1k | 1000 | europeanScaleLexicon | q |
| hungarian1k | 1000 | europeanScaleLexicon | ƣ |
| hungarian2k | 2452 | europeanScaleLexicon | ʉ |
| welsh1k | 1000 | europeanScaleLexicon | ƿ |
| lithuanian1k | 990 | europeanScaleLexicon | ɬ |
| lithuanian3k | 2978 | europeanScaleLexicon | ɫ |
| latvian1k | 930 | europeanScaleLexicon | ƚ |
| maltese1k | 927 | europeanScaleLexicon | ɦ |
| vietnamese1k | 1000 | europeanScaleLexicon | ƌ |
| vietnamese5k | 5000 | europeanScaleLexicon | ɖ |
| pinyin1k | 612 | europeanScaleLexicon | ɐ |
| pinyin10k | 1293 | europeanScaleLexicon | ɜ |
| hausa1k | 829 | europeanScaleLexicon | ɠ |
| bemba1k | 1001 | europeanScaleLexicon | q |
| bemba10k | 10001 | europeanScaleLexicon | ɥ |
| catalan1k | 1000 | europeanScaleLexicon | ɲ |
| frisian1k | 909 | europeanScaleLexicon | ɡ |
| serbianLatin10k | 10000 | europeanScaleLexicon | ɣ |
| serbian10k | 10000 | europeanScaleLexicon | ӽ |
| bulgarian1k | 1172 | europeanScaleLexicon | ӄ |
| bulgarianLatin1k | 1169 | europeanScaleLexicon | x |
| bosnian4k | 3816 | europeanScaleLexicon | ɯ |
| albanian1k | 896 | europeanScaleLexicon | ɤ |
| macedonian1k | 901 | europeanScaleLexicon | q |
| macedonian10k | 10000 | europeanScaleLexicon | ӌ |
| macedonian75k | 75000 | europeanScaleLexicon | ԑ |
| amharic1k | 1001 | europeanScaleLexicon | ፐ |
| armenian1k | 1000 | europeanScaleLexicon | ֆ |
| armenianWestern1k | 1000 | europeanScaleLexicon | ք |
| belarusianLacinka1k | 997 | europeanScaleLexicon | ɤ |
| hawaiian1k | 1000 | europeanScaleLexicon | ɽ |
| japaneseRomaji1k | 987 | europeanScaleLexicon | q |
| klingon1k | 1001 | europeanScaleLexicon | q |
| oromo1k | 1000 | europeanScaleLexicon | q |
| oromo5k | 5000 | europeanScaleLexicon | x |
| shona1k | 816 | europeanScaleLexicon | q |
| englishFiveLetter1k | 1000 | europeanScaleLexicon | q |
| xhosa3k | 2935 | europeanScaleLexicon | q |
| portuguese1k | 1000 | portugueseScaleLexicon | qpt |
| portuguese3k | 3043 | portugueseScaleLexicon | wpt |
| portuguese5k | 5665 | portugueseScaleLexicon | xpt |
| portuguese320k | 318601 | portugueseScaleLexicon | zpt |
| portuguese550k | 558207 | portugueseScaleLexicon | vpt |

## English 450k 的来源可用性准备

在客户端冻结期间，仅在临时目录恢复既有固定 SCOWL rel-2026.02.25 提交 `7e99edab8e32f9f9ea2b15f249ca8d4d67237410`，路径 `/tmp/typebar-english450k-scowl-source`，从完整源创建新的临时数据库。该 checkout 保持干净；没有读取 Monkeytype 词值、改动项目词库或并行启动另一原生测试作业。

ASCII 字母及内部单引号／连字符、长度不超过 31 的只读可用性统计：size 80／A／1 有 247,568 个形式；size 95／A／1 有 306,111 个形式、298,233 个大小写折叠键。size 95 的 A,B,Z,C／9 也仅 324,849 个形式，不能把词典本身说成足量 450k。首次多拼写参数误写为 ABZC 被 CLI 拒绝，改为文档规定的逗号列表后才取得后者统计；不将失败准备动作计为有效数据。

固定既有 wordfreq 3.1.1 wheel 提供 288,998 个符合 ASCII 单词规则的 English 观察 token，其中 170,225 个不在上述美式词典的折叠键中，联合折叠键为 468,458。可用性结果在 `/tmp/typebar-english450k-scowl-audit/availability.json`。该数量说明存在继续设计独立真实来源选集的路径，**不是最终选集、拼写认证、难度／分布等价或生产验收**；不为凑数追加合成词。

既有 SCOWL Copyright 明确指出大于 size 80 的生成列表还须保留并显著展示 UK Advanced Cryptics Dictionary 的署名及原文通知。后续若采用该来源范围，应同时实现可复现准备、完整通知及应用内可见署名，不能仅修改数量或复制旧小词库的许可说明。基础 200 词及 1k／5k／10k／25k 的既有数据哈希仍须保留。

## 后续验收要求

### English 450k 独立候选的实际选集

在随后完整客户端重跑期间，只在仓库外生成 `/tmp/typebar-english450k-candidate-v1`，生产 English 450k 仍使用占位构造器，本表的 118 个入口没有减少。

改用固定 SCOWL 的 size 95、A,B,Z,C 标准变体 level 1、默认 category，并显式启用 hyphen 与 dot=True。初次直接比对数据库时，654 个导出形式无法在原数据库逐字匹配，查明全部来自导出器默认去除末尾句点；该次选择在写出前失败。随后保留源拼写，并验证全部词典候选逐字存在于同一固定数据库查询中。没有补造词形或以去掉标点后的串冒充原始词典拼写。

候选由 282,593 个词典词形和 167,436 个不在词典中的 English 观察 token 构成，后者来自固定 wordfreq English 频率桶，不能称为经过词典认证的 English 单词。合计 450,029 个不同字符串、443,056 个大小写折叠键、33,021 个含大写词形、176 个标点词形，长度 1–31；标点由实际源中的 44 个撇号、44 个连字符和 88 个末尾句点词形组成。观察词桶及词典 size／拼写构成确定性顺序，未观测词不会被赋予虚构词频，English 450k 的 Zipf 不支持状态应保持。

候选文本共 4,131,017 字节，SHA-256 为 `1f2c60a9b29bbba89efba82227248ee06797804f533ce81736fc5fb4b3ba476a`。保留字面标点的 SCOWL 导出 SHA-256 为 `c8f999c724e322801d94348a90f940e28f8bbbd19e53a4ffed18346d83ae52ad`；完整 Copyright 为 `090575a131b4260926c7a6b30a90aca0f5db5fbb5c46778e0c5855227bf6ebc3`。源 wheel／English member 哈希沿用既有固定版本。选择报告、完整源许可及词值只在临时目录，没有修改基础 200 词或 1k／5k／10k／25k 数据，没有读取参考项目词值挑选替代词。

随后 `/tmp/typebar-english450k-fresh-repro-driver.py` 从干净固定源重新创建全新 SCOWL 数据库、显式字面导出并重新选择；39.715 秒后词值、选择报告、完整 SCOWL Copyright 与 wordfreq 数据通知四项均逐字节一致，源 checkout 保持干净。记录位于 `/tmp/typebar-english450k-fresh-repro-20261029/record.json`，该次选择器 SHA-256 为 `2870cdf8a7bb1261f9cba85247385b8a7e1e043a6ce51302d22b708720355db4`。这是候选的来源复现，不是原生生产路径验收。

临时选择器也对“仅有两个源词”和“注入数据库中不存在的字母词形”两个反例执行了实际命令，均非零退出且未创建输出目录，记录 `/tmp/typebar-english450k-candidate-negative-checks.json`。这些候选脚本目前使用 Python assert，不能直接当作正式准备工具发布；后续必须采用优化运行也不可绕过的显式验证、正式自测及打包／原生验证。

后续在 `/tmp/typebar-english-large-prepared/Scripts/prepare-english-large-corpus.py` 准备了正式工具，尚未写入项目。运行时验证改为显式 ValueError，普通及 Python 优化模式分别通过八项自测；覆盖原样词形、输入顺序独立、来源不足、词频污染、非法配额、词典外重复串过滤及写出前完整检查已有目标。标准库完整性检查不依赖 msgpack，损坏 wheel 也在源数据库准备前失败且不创建输出。

质量抽查发现第一版词典外观察 token 包含 sooooo／hahahahaha 等延长或重复形式。第二版只对词典外观察候选排除 4 个以上相同字母连续出现，或 1–5 字母模式完整重复至少四次的 token，保留词典确实收录的原始词形；共排除 629 个，仍有 168,135 个候选供选择，不以造词补位。最终词典 282,593、观察 167,436、总数 450,029、含大写 33,021、标点 176、长度 1–31 均保持；聚合形状不是质量结论。

第二版在 `/tmp/typebar-english-large-prepared-artifacts-v2` 生成 Swift 数据、清单及完整通知，并从新鲜固定源执行 --check 逐字节通过。词值 SHA-256 为 `5ed42403f79db93db4db581fe3388d3992e7f648b630c8a14408a451176bbd59`；原生数据文件为 `cf4cdc05997b14696b5b55942eac6de89d4c64bab930d8f7e092ce9f9d9092c8`；通知为 `7bbca2ef448dcad490837886e2f6748afe7e1315a887676299b2189d34abf048`。四种损坏产物（词值、固定来源、形状清单、即使同时改写摘要的 UKACD 署名截断）在普通／优化模式均被拒绝；记录 `/tmp/typebar-english-large-integrity-negative-checks-v2.json` 带有先行有效产物正对照。完整 SCOWL Copyright 的摘要还固定到源提交对应值，不能靠重写清单为截断通知背书。

原生署名／许可阅读器草稿也只位于临时目录，未编译或挂载。生产词库、About 与打包脚本仍未改动，故 118 项缺口保持开放。词形数量及聚合形状不是语言质量、难度或分布等价证明；应用内显著署名、原生实际生成／输入／修饰器／重复、懒加载／性能及旧记录验收仍须在生产替换前完成。

逐入口取得可分发的独立来源，固定版本／哈希、选择及编辑规则、完整署名和准备复现，禁止读取或按参考项目词值挑选替代内容。数量不足不能填假词；存在大小写、变音、复合词、短语、数字或符号练习能力时必须逐项保留并验证，不以简单过滤后的统计冒充功能等价。

新候选须走实际生成、续批、修饰器、输入及重复路径；旧记录必须继续使用捕获的提示、事件和冻结成绩。保留基础词库、语言 ID、配置／分享、语音／百科和多语归属的兼容证据。语言审校、词频／难度及内容分布的未证明差异保持开放。

客户端冻结基线已结束，6,750 项中六个方法失败，详见 CLIENT_BASELINE_20261029.md。本审计没有修改生产代码、清单或词数据，也未启动并行原生作业。不得因后续测试通过而关闭这里的内容缺口，完整 goal 仍未达成。
