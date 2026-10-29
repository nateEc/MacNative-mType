# 当前语言内容的合成占位清单

`LANG-CONTENT-BASELINE-40`，只读审计起点 `1ee242d7f74be670025afa7018c106263558f7ec`。语言 ID／元数据映射、候选数量或长度形状通过，不足以证明可用实际词汇已交付。本项记录未完成工作，不是替换实现或内容质量验收。

## 已确认的范围

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

## 可逐入口追踪的当前占位清单

以下仅记录当前自有实现的入口、声明数量及构造器，不含参考项目词值。每一行都保持未完成；未来替换应以实际语料证据逐项迁移，不能只删除本表记录。marker 未提取不代表没有合成内容。

| 入口 | 声明数量 | 当前构造器 | marker |
| --- | ---: | --- | --- |
| english450k | 450029 | englishScaleLexicon | yu |
| spanish650k | 646579 | spanishScaleLexicon | qzv |
| french600k | 633941 | frenchScaleLexicon | qvfr |
| german1k | 988 | germanScaleLexicon | qgd |
| german10k | 9994 | germanScaleLexicon | wgd |
| german250k | 239243 | germanScaleLexicon | xgd |
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

逐入口取得可分发的独立来源，固定版本／哈希、选择及编辑规则、完整署名和准备复现，禁止读取或按参考项目词值挑选替代内容。数量不足不能填假词；存在大小写、变音、复合词、短语、数字或符号练习能力时必须逐项保留并验证，不以简单过滤后的统计冒充功能等价。

新候选须走实际生成、续批、修饰器、输入及重复路径；旧记录必须继续使用捕获的提示、事件和冻结成绩。保留基础词库、语言 ID、配置／分享、语音／百科和多语归属的兼容证据。语言审校、词频／难度及内容分布的未证明差异保持开放。

客户端冻结基线已结束，6,750 项中六个方法失败，详见 CLIENT_BASELINE_20261029.md。本审计没有修改生产代码、清单或词数据，也未启动并行原生作业。不得因后续测试通过而关闭这里的内容缺口，完整 goal 仍未达成。
