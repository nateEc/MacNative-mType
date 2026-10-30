# 当前语言内容的合成占位清单

`LANG-CONTENT-BASELINE-40`，只读审计起点 `1ee242d7f74be670025afa7018c106263558f7ec`。语言 ID／元数据映射、候选数量或长度形状通过，不足以证明可用实际词汇已交付。本项记录未完成工作，不是替换实现或内容质量验收。

## 后续迁移状态

最新 `LANG-GREEK-LITERAL-58` 移除现代希腊语四档 40,728 个合成位置，基础 30→209；全部五池使用带完整整词观察的原样词典形式，NFC 拼写、声调、分音符和词尾 sigma 不改。保留 Koine／Greeklish 与旧历史。当前直接具名 ScaleLexicon 路由余 112 项／927,283 个声明位置；复核 /tmp/typebar-greek-scale-audit-20261030.json，TypingEngine SHA `e00e18c77373113887d9c0a35c1c4237b6799f46ef358c5476f34d2c1d79f68b`。语言／分布质量、实体输入及性能仍开放，详见 GREEK_CORPUS_CONTRACT.md。

上一批 `LANG-UKRAINIAN-LATYNKA-57` 将 Latynka 三档 60,989 个 qz 占位位置替换为独立乌克兰语形式的明确拉丁化改编，基础 27→199。保留西里尔原词、注音改编及原词频率范围，不冒充 Latin 使用观察。当前直接具名 ScaleLexicon 路由余 116 项／968,011 个声明位置；只读复核 /tmp/typebar-latynka-scale-audit-20261030.json，TypingEngine SHA `899c34a31d7c56f7e38e2851d185da64f80a16eee230fb1ee576c3dac7fe8a15`。细粒度字符频次、分布、语言质量及实体／性能仍开放，详见 UKRAINIAN_LATYNKA_CORPUS_CONTRACT.md。

上一批 `LANG-UKRAINIAN-CYRILLIC-56` 移除西里尔乌克兰语三档 60,989 个合成位置，使用两版词典的 uk 词条及有出处的少量文本形式，基础 27→199；注音改编保留原始追踪。当前直接具名 ScaleLexicon 属性路由余 119 项／1,029,000 个声明位置，复核 /tmp/typebar-ukrainian-scale-audit-20261030.json，TypingEngine SHA-256 `f5297d0810d61931d59f2569c66d6a7ed998498515025555d98936bc40bb1cda`。50k 的双撇号＋连字符组合已由独立文本原样补齐；分布及语言质量仍开放，详见 UKRAINIAN_CORPUS_CONTRACT.md。该结构范围不覆盖全部构造器、基础池或实际词数；下文保留迁移时的历史数字。

此前 `LANG-ENGLISH-FIVE-55` 移除五字母英语 1k 的编号合成，并将基础 40 项扩为 201 项，使用字典与整词观察交集。该阶段直接具名 ScaleLexicon 属性路由余 122 项／1,089,989 个声明位置，复核 /tmp/typebar-english-five-letter-scale-audit-20261030.json；TypingEngine SHA-256 `d763249482238ea6cf67db68549bec1c710a4a013c0e0a26b8a7734086c96025`。详情见 ENGLISH_FIVE_LETTER_CORPUS_CONTRACT.md。默认俄语和挪威语基础池的后续扩充分别见各 BASIC 合同。

此前 `LANG-RUSSIAN-SCALES-52` 移除 Russian 六档 469,774 个编号／重复字符占位位置，改用独立字典词形和 wordfreq，专名、多词、5k 句点及各类字段有实际候选。375k 长词 46／参考 49、撇号／prime、分布／语言质量仍开放，基本池后续单列 RUSSIAN_BASIC_CORPUS_CONTRACT.md。该阶段扩大具名范围余 123 项／1,090,989，旧历史范围 82 项／438,685 不变；复核 `/tmp/typebar-russian-all-scale-helper-audit-20261029.json`，TypingEngine SHA-256 `97b14206b658597f5ac75d86dc95012220a9fac22cbc14ec1fec8aa39fb2dd92`。详情见 RUSSIAN_SCALES_CORPUS_CONTRACT.md。

此前 `LANG-NORWEGIAN-SCALES-51` 移除两种 Norwegian 各五档、共 1,305,311 个词根编号占位位置。独立官方字典及各自 unigram 选集保留真实字面大小写、数字／标点／多词交集和最长字段；基本池与历史保持，分布／语言质量仍开放。该阶段扩大具名路由范围余 129 项、声明数量之和 1,560,763；旧历史范围仍为 82 项／438,685，因为本轮十项来自之前扩展发现的额外路由。复核 `/tmp/typebar-norwegian-all-scale-helper-audit-20261029.json`，TypingEngine SHA-256 `eec384229642daca1185d31e9c6bac08360f5211bff39fd481bc0ea03a7dcbad`。详情见 NORWEGIAN_SCALES_CORPUS_CONTRACT.md；以下保留各自阶段数字。

此前 `LANG-ESPERANTO-SCALES-50` 已移除 Esperanto 十二档的 216,619 个占位位置，使用同时有独立字典和 Tatoeba 观察的实际词形，包含 X／H 拼写。原历史范围当前余 82 个直接合成入口，声明数量之和 438,685；复核 `/tmp/typebar-esperanto-remaining-synthetic-20261029.json`，TypingEngine SHA-256 `3aef72f8d8fb7137a5f9c6f730e0849bc62d55402d25601487907af3777544a8`。大档长字段、X／H 额外字母及词频／难度／质量差距仍开放，见 ESPERANTO_SCALES_CORPUS_CONTRACT.md。以下数字按各迁移阶段保留，不能混用为当前总数。

`LANG-ENGLISH-LARGE-43` 已将 English 450k 的 450,029 个合成候选替换为独立实际来源选集，移除 `englishScaleLexicon`；来源、原生输入、旧记录及署名边界见 ENGLISH_LARGE_CORPUS_CONTRACT.md。按下列历史 118 项逐入口复核，目前同范围仍有 117 个直接合成入口，声明数量之和为 3,740,882。复核记录 `/tmp/typebar-english-large-remaining-synthetic-20261029.json`，当前 TypingEngine SHA-256 `ed4df6fd2ff445465c6708c51c148b22d1e23c17f6b494311e3008cf54fa240d`。该数字不是全部语言缺口总量。

随后 `LANG-GERMAN-SCALES-44` 将 German 1k／10k／250k 的 250,225 个候选迁至独立字面词形，移除 `germanScaleLexicon`，来源和实际输入见 GERMAN_SCALES_CORPUS_CONTRACT.md。当前同一历史范围余 114 个直接合成入口，声明数量之和 3,490,657；复核 `/tmp/typebar-german-remaining-synthetic-20261029.json`，当前 TypingEngine SHA-256 `a62cc92a8867e9429d997b0262ed153c2f484924a197424485c77ff71e06db40`。

随后 `LANG-FRENCH-LARGE-45` 将 French 600k 的 633,941 个候选迁至独立词典形式／有词典对应的实际观察拼写，移除 `frenchScaleLexicon`。当前同范围余 113 个直接合成入口，声明数量之和 2,856,716；复核 `/tmp/typebar-french-large-remaining-synthetic-20261029.json`，当前 TypingEngine SHA-256 `780143d6df4742232172ba58b68690702dba1228bbcdb7a5c0f1b4f98d549bd8`。以上 English／German 数字保留为各自迁移时的阶段证据。

随后 `LANG-SPANISH-LARGE-46` 移除 Spanish 650k 的合成构造器，使用 646,566 个独立字面词形和 13 个明确标注的书写／排版练习改编。同范围余 112 个直接合成入口，声明数量之和 2,210,137；复核 `/tmp/typebar-spanish-large-remaining-synthetic-20261029.json`，TypingEngine SHA-256 `b4b596d35c331deeaffcf08de9577712e528d30ed03fdc53dd287b8d2685b620`。来源与限制见 SPANISH_LARGE_CORPUS_CONTRACT.md。

随后 `LANG-ROMANIAN-SCALES-47` 将 Romanian 七个规模档的 391,000 个候选位置迁至独立字面词形，移除 `romanianScaleLexicon`，严格过滤提取模板及错误标签。同范围余 105 个直接合成入口，声明数量之和 1,819,137；复核 `/tmp/typebar-romanian-remaining-synthetic-20261029.json`，TypingEngine SHA-256 `04f785a056480c738095941fcbc0851bbee73a8b2c2b3f664b7519327ac1b161`。200k 最长 47／原版 50 和多连字符／标点覆盖差异仍开放，见 ROMANIAN_SCALES_CORPUS_CONTRACT.md；移除占位不等于达到无功能损失。

随后 `LANG-POLISH-SCALES-48` 将 Polish 六档的 277,317 个候选位置迁至独立字面词形，移除 `polishScaleLexicon`。2k 的真实句点缩写和 2k／200k 单独的专名长度边界均保留，不能只看整体长度绿灯。该阶段同范围余 99 个直接合成入口，声明数量之和 1,541,820；复核 `/tmp/typebar-polish-remaining-synthetic-20261029.json`，TypingEngine SHA-256 `0403e5d776d3fca32521da707191d4a13fe0d63b612b00d410e7987e62d0b481`。来源、先行红例和分布差异见 POLISH_SCALES_CORPUS_CONTRACT.md。

`LANG-PORTUGUESE-SCALES-49` 移除五档 Portuguese 合成器，共 886,516 个候选位置，改用独立字典、观察 token 和两个明确自写单位练习。当前同范围余 94 个直接合成入口，声明数量之和 655,304；复核 `/tmp/typebar-portuguese-remaining-synthetic-20261029.json`，TypingEngine SHA-256 `258cfef2746e395ed42e38ac6f0269c6f2271818aae2f2a27ce051caa5211bd1`。大档标点／多连字符仍有差距，基本 24／重音 67 项仍少于参考 201／1,999 项。来源、独立输入资格红例与验证边界见 PORTUGUESE_SCALES_CORPUS_CONTRACT.md；下表保留原始 118 项历史范围。

以下 118 项表及此前临时候选过程保留为固定起点的历史证据，不再代表全部当前实现；English、German、French、Spanish 大档、Romanian 七档、Polish 六档、Portuguese 五档及 Esperanto 十二档已移除对应合成器，但语言质量、词频／难度和分布等价仍未验收。其余历史项继续开放。

## 历史起点确认的范围

### 2026-10-29 的扩大结构复核（Norwegian 迁移前阶段）

在 `LANG-ESPERANTO-SCALES-50` 的不可变输入期间，另行读取当前 TypingEngine（SHA-256 `3aef72f8d8fb7137a5f9c6f730e0849bc62d55402d25601487907af3777544a8`），扫描**所有** `static var <selection>Lexicon: IndexedLexicon` 属性中直接调用具名 `*ScaleLexicon(...)` 的路由，不再要求被调用函数显式出现旧审计的两个字母编号函数名。逐属性配对花括号取函数体，提取具名字面 count，并核对 `case .<selection>: StarterLexicon.<selection>Lexicon` 生产路由。

结果为 **139 个入口、声明数量之和 2,866,074**，无未解析 count 或未找到的生产路由。旧历史范围当前 82 个只是其中一部分；另有 **57 个入口、声明数量之和 2,427,389** 以前未进入该历史表。完整只读报告 `/tmp/typebar-esperanto-all-scale-helper-audit-20261029.json`；这是结构路由审计，不是逐词质量认证或全部语言内容缺口总账。

| 原历史表之外的具名 helper | 当前入口 | 声明数量之和 |
| --- | ---: | ---: |
| simplifiedChineseScaleLexicon | 4 | 66,000 |
| traditionalChineseScaleLexicon | 4 | 65,890 |
| russianScaleLexicon | 6 | 469,774 |
| ukrainianScaleLexicon | 3 | 60,989 |
| tatarScaleLexicon | 3 | 15,039 |
| crimeanTatarCyrillicScaleLexicon | 4 | 31,082 |
| greekScaleLexicon | 4 | 40,728 |
| hebrewScaleLexicon | 3 | 16,000 |
| plainArabicScriptScaleLexicon | 2 | 6,000 |
| thaiScaleLexicon | 6 | 144,737 |
| belarusianScaleLexicon | 6 | 200,097 |
| kurdishCentralScaleLexicon | 2 | 5,742 |
| norwegianBokmalScaleLexicon | 5 | 773,908 |
| norwegianNynorskScaleLexicon | 5 | 531,403 |

实际读取 Chinese、Russian、Ukrainian、Greek、Bokmål 的 helper 已确认有按编号编码字符、重复字符强行制造最长项或给词根拼编号等生产行为；Bokmål／Nynorsk 两组的声明数量之和已达 1,305,311，后续需要取得独立真实数据，不能被旧 82 项数字掩盖。其他具名路由需继续逐组核实。该扩展仍不覆盖匿名 `IndexedLexicon(count:)` 生成器、未以 ScaleLexicon 命名的函数、基础短词池、形态变化正确性或所有语言质量问题，不能把未匹配路由判成真实完整内容。

### 原历史表

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
| spanish650k（已迁移，见 LANG-SPANISH-LARGE-46） | 646579 | 历史 spanishScaleLexicon | qzv |
| french600k（已迁移，见 LANG-FRENCH-LARGE-45） | 633941 | 历史 frenchScaleLexicon | qvfr |
| german1k（已迁移，见 LANG-GERMAN-SCALES-44） | 988 | 历史 germanScaleLexicon | qgd |
| german10k（已迁移，见 LANG-GERMAN-SCALES-44） | 9994 | 历史 germanScaleLexicon | wgd |
| german250k（已迁移，见 LANG-GERMAN-SCALES-44） | 239243 | 历史 germanScaleLexicon | xgd |
| romanian1k（已移除占位，见 LANG-ROMANIAN-SCALES-47） | 1000 | 历史 romanianScaleLexicon | qro |
| romanian5k（已移除占位，见 LANG-ROMANIAN-SCALES-47） | 5000 | 历史 romanianScaleLexicon | wro |
| romanian10k（已移除占位，见 LANG-ROMANIAN-SCALES-47） | 10000 | 历史 romanianScaleLexicon | xro |
| romanian25k（已移除占位，见 LANG-ROMANIAN-SCALES-47） | 25000 | 历史 romanianScaleLexicon | zro |
| romanian50k（已移除占位，见 LANG-ROMANIAN-SCALES-47） | 50000 | 历史 romanianScaleLexicon | vro |
| romanian100k（已移除占位，见 LANG-ROMANIAN-SCALES-47） | 100000 | 历史 romanianScaleLexicon | jro |
| romanian200k（已移除占位，见 LANG-ROMANIAN-SCALES-47） | 200000 | 历史 romanianScaleLexicon | kro |
| polish2k（已移除占位，见 LANG-POLISH-SCALES-48） | 2338 | 历史 polishScaleLexicon | qpl |
| polish5k（已移除占位，见 LANG-POLISH-SCALES-48） | 5000 | 历史 polishScaleLexicon | wpl |
| polish10k（已移除占位，见 LANG-POLISH-SCALES-48） | 10000 | 历史 polishScaleLexicon | xpl |
| polish20k（已移除占位，见 LANG-POLISH-SCALES-48） | 20000 | 历史 polishScaleLexicon | zpl |
| polish40k（已移除占位，见 LANG-POLISH-SCALES-48） | 40000 | 历史 polishScaleLexicon | vpl |
| polish200k（已移除占位，见 LANG-POLISH-SCALES-48） | 199979 | 历史 polishScaleLexicon | kpl |
| ukrainianLatynka1k | 1000 | ukrainianLatynkaScaleLexicon | 未提取 |
| ukrainianLatynka10k | 9998 | ukrainianLatynkaScaleLexicon | 未提取 |
| ukrainianLatynka50k | 49991 | ukrainianLatynkaScaleLexicon | 未提取 |
| swissGerman1k | 1000 | swissGermanScaleLexicon | 未提取 |
| swissGerman2k | 2000 | swissGermanScaleLexicon | 未提取 |
| afrikaans1k | 1000 | afrikaansScaleLexicon | 未提取 |
| afrikaans10k | 8164 | afrikaansScaleLexicon | 未提取 |
| esperanto1k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 1000 | 历史 esperantoScaleLexicon | a |
| esperanto10k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 10000 | 历史 esperantoScaleLexicon | b |
| esperanto25k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 24998 | 历史 esperantoScaleLexicon | c |
| esperanto36k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 36342 | 历史 esperantoScaleLexicon | d |
| esperantoXSystem1k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 999 | 历史 esperantoScaleLexicon | e |
| esperantoXSystem10k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 9993 | 历史 esperantoScaleLexicon | f |
| esperantoXSystem25k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 24970 | 历史 esperantoScaleLexicon | g |
| esperantoXSystem36k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 36296 | 历史 esperantoScaleLexicon | h |
| esperantoHSystem1k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 999 | 历史 esperantoScaleLexicon | i |
| esperantoHSystem10k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 9969 | 历史 esperantoScaleLexicon | j |
| esperantoHSystem25k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 24922 | 历史 esperantoScaleLexicon | k |
| esperantoHSystem36k（已移除占位，见 LANG-ESPERANTO-SCALES-50） | 36131 | 历史 esperantoScaleLexicon | l |
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
| portuguese1k（已移除占位，见 LANG-PORTUGUESE-SCALES-49） | 1000 | 历史 portugueseScaleLexicon | qpt |
| portuguese3k（已移除占位，见 LANG-PORTUGUESE-SCALES-49） | 3043 | 历史 portugueseScaleLexicon | wpt |
| portuguese5k（已移除占位，见 LANG-PORTUGUESE-SCALES-49） | 5665 | 历史 portugueseScaleLexicon | xpt |
| portuguese320k（已移除占位，见 LANG-PORTUGUESE-SCALES-49） | 318601 | 历史 portugueseScaleLexicon | zpt |
| portuguese550k（已移除占位，见 LANG-PORTUGUESE-SCALES-49） | 558207 | 历史 portugueseScaleLexicon | vpt |

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

## Norwegian 的来源可用性准备（迁移前阶段）

扩大回归保持不可变输入时，仅在临时目录下载并读取官方 [Bokmål 2005](https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-5/) 和 [Nynorsk 2012](https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-41/) 的 **2022-02-01 Norsk ordbank** 快照。官方目录的许可链接为 CC BY 4.0；该日期是数据库快照日期，2026-10-29 只是下载日，不冒充当前规范数据库。目录明确指出全词形也包括语法可构成但实际很少或从未使用的形式，因此不能将数据库容量说成实测频率或完整语言质量认证。

| 官方下载文件 | 压缩字节 | SHA-256 |
| --- | ---: | --- |
| `20220201_norsk_ordbank_nob_2005.tar.gz` | 15,288,065 | `57d91cb3f17b85befa50a3b56fcaed9800ca665b39486fe97b668add914d5f60` |
| `20220201_norsk_ordbank_nno_2012.tar.gz` | 8,954,350 | `32987494b77c54b5c3890e891b99e35d5a45a16643a5c1820cd5e02fd55b1b8d` |

文件均来自 `https://www.nb.no/sbfil/leksikalske_databaser/ordbank/`。只读 tar 成员，不解包／执行脚本。Bokmål 的 `fullformsliste.txt` 为 102,410,706 字节、SHA-256 `45a648b51ed22741acc3e4fc8d17178dfcce0e9622ea2ce12204f11d8c6bcfaf`；Nynorsk 实际成员名是 `fullformer_2012.txt`，48,498,975 字节、SHA-256 `654bcfcf11374947a0be0d27173a94a4f7d75671d792de439bea1fba07ef8e36`。最初误用相同成员名而失败的统计不计作有效证据，改按各自清单后重新读取。两者 ISO-8859-1、tab 表；有效运行使用 Unicode 15.0.0，9.379 秒。

| 只读统计 | Bokmål | Nynorsk |
| --- | ---: | ---: |
| 全词形行 | 1,143,887 | 584,298 |
| 唯一字面形式 | 619,067 | 415,085 |
| NFC Latin 字母形式 | 606,054 | 407,087 |
| 其中字面小写／大小写 | 600,831／5,223 | 401,803／5,284 |
| 含标点／空格形式 | 12,011／1,186 | 6,930／1,330 |
| 纯字母最长 | 33 | 31 |

当前快照所有行均 `NORMERING=normert`、`TILDATO=4000`；这只是源字段筛选事实。报告 `/tmp/typebar-norwegian-ordbank-availability-20261029.json` 保留各长度界限容量，尚未选词、核实词频、逐字段形状覆盖、编写原生数据或接入新许可。受限的新闻文本语料没有被混入本批。可用性证明下一批有独立字面来源路径，**不代表 Norwegian 已交付**。

后续 `LANG-NORWEGIAN-SCALES-51` 已按更严格的实际输入类别筛选并接入这两个固定字典与各自的官方 CC0 unigram；最终选集、发布 pin、原生证据和分布边界见 NORWEGIAN_SCALES_CORPUS_CONTRACT.md。以上原始可用性数字仍保留为此前准备证据，不能冒充最终词数或完整质量验收。
