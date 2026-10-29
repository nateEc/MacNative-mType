# Norwegian 两种书面语十档实际词形与输入类别

`LANG-NORWEGIAN-SCALES-51`，起点 `b212c6d72aa0656d9ccb9311540c7d6ce423dbc0`。移除 Bokmål／Nynorsk 各五档的词根拼编号、重复字母和伪装大小写，共 1,305,311 个候选位置。两种书面语使用各自字典和频率数据；该轮原基本池 28／32 项自写词保持哈希，仍少于固定参考的 200／250 项，不把规模档当作整个语言已对齐。基本池后续扩充见 NORWEGIAN_BASIC_CORPUS_CONTRACT.md，十档制品保持本合同哈希。

## 固定独立来源

Monkeytype 参考固定 `91bd24bb8513785c7364cbea29296ff7adafac41`，只读取行为、元数据和自动聚合属性；不导出参考词值／顺序。实际词形直接来自官方 [Norsk ordbank Bokmål](https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-5/) 和 [Norsk ordbank Nynorsk](https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-41/) 的 **2022-02-01** 快照，2026-10-29 是本次下载日，不冒充当前在线规范数据库。

| 标准 | 官方字典压缩文件／字节 | SHA-256 |
| --- | --- | --- |
| nob | `20220201_norsk_ordbank_nob_2005.tar.gz`／15,288,065 | `57d91cb3f17b85befa50a3b56fcaed9800ca665b39486fe97b668add914d5f60` |
| nno | `20220201_norsk_ordbank_nno_2012.tar.gz`／8,954,350 | `32987494b77c54b5c3890e891b99e35d5a45a16643a5c1820cd5e02fd55b1b8d` |

均来自 `https://www.nb.no/sbfil/leksikalske_databaser/ordbank/`。只读取固定 tar 成员，不解包执行：Bokmål 的 `fullformsliste.txt` SHA-256 `45a648b51ed22741acc3e4fc8d17178dfcce0e9622ea2ce12204f11d8c6bcfaf`；Nynorsk 的 `fullformer_2012.txt` SHA-256 `654bcfcf11374947a0be0d27173a94a4f7d75671d792de439bea1fba07ef8e36`。两者 ISO-8859-1、tab 表，只接受 `NORMERING=normert` 且 `TILDATO=4000` 的实际 OPPSLAG，保留 LEMMA_ID／LOEPENR；同字面多归属取数字最小的 ID 对，不改写拼写或造词。

官方目录明确说明：全词形也包含语法上可构成、实际很少甚至从未使用的形式。因此这些是数据库字面词形，**不等于全部已有真实用例或母语者质量审校**。过滤后（NFC、Latin 字母／数字／内部连字符／撇号／单空格，无控制字、引号、反斜线、首尾连字符）Bokmål／Nynorsk 分别可用 616,914／412,288 个字面形式。

频率分别来自官方 CC0 [Bokmål unigram](https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-12/) 和 [Nynorsk unigram](https://www.nb.no/sprakbanken/ressurskatalog/oai-nb-no-sbr-8/)，不是受限原始新闻全文，也不以 Bokmål 频率冒充 Nynorsk：

| 标准 | 压缩文件／字节 | ZIP SHA-256 | 成员／成员 SHA-256 |
| --- | --- | --- | --- |
| nob | `1gram_nob_f1_freq.zip`／15,198,030 | `cda1477a11fc98bcf61e8152fe1a09a4d5f9ae04b16c4ed9dc86ee224c2284e3` | `1gram_nob_f1_freq.frk`／`acb8b7c20d61628f10a4a9b229dffdea0d43ab285f97ac93b7b1e3ddb717e44d` |
| nno | `1gram_nno_f1_freq.zip`／2,155,822 | `2c53d0073b0b7036e94029251e51e58fc98d7e1adbc1d390f191e5d30c291cee` | `1gram_nno_f1_f.frk`／`375a5726670950500bd94e4baea3ede88aeab8e3f366926a43cf9a269068ead6` |

下载目录 `https://www.nb.no/sbfil/tekst/`，本次固定成员分别有 3,307,461／472,256 行，按降序的正整数频次读取；NFC／casefold 后合并原大小写变体。只保留所需字典键／分段键的计数，匹配 345,121／126,421 个 casefold 键；这些包括排名分段键，不能称为实际被选的词数。它是历史语料频率，不是 2026 年使用分布。

## 选择规则与输入覆盖

按大小写 C、标点 P、多词 S、数字 N 的组合分层；每层数量、最短／最长字段、字段数和单字段长度来自参考**聚合约束**，不使用原版词值。实际源中每层容量均足够；选择整词有观察者优先，其次所有分段均有观察时取最罕见连字符／撇号／空格分段作估计，最后才是未观察词形的字面排序。估计与整词次数分开记录；次数 0 表示本快照未观察到，不能说成实际使用频率测得为零。

在真实候选内保留五个字母练习词、各层已有最短／最长字段、最多连字符／字段／字段长度，以及容量允许的撇号和 Unicode 单独大写。一个词可同时覆盖多个边界，避免为了重复边界挤掉正常高频候选；配额不足时失败，不填编号、不机械改大小写或添加数字／标点。

| 标准／档位 | 唯一候选 | 长度 | 大写项 | 标点项 | 数字项 | 多词项 | 当前／参考非 ASCII 项 |
| --- | ---: | --- | ---: | ---: | ---: | ---: | --- |
| Bokmål 1k | 1,000 | 1–15 | 0 | 0 | 0 | 0 | 141／136 |
| Bokmål 5k | 5,000 | 1–28 | 0 | 0 | 0 | 0 | 659／654 |
| Bokmål 10k | 10,000 | 1–28 | 1 | 0 | 0 | 0 | 1,381／1,383 |
| Bokmål 150k | 142,938 | 1–30 | 100 | 1,247 | 1 | 0 | 25,652／28,688 |
| Bokmål 600k | 614,970 | 1–33 | 10,291 | 9,700 | 143 | 0 | 122,574／123,229 |
| Nynorsk 1k | 1,000 | 1–18 | 0 | 0 | 0 | 0 | 123／132 |
| Nynorsk 5k | 5,000 | 1–27 | 0 | 0 | 0 | 0 | 649／714 |
| Nynorsk 10k | 9,939 | 1–27 | 0 | 0 | 0 | 0 | 1,377／1,492 |
| Nynorsk 100k | 104,745 | 1–29 | 28 | 676 | 1 | 0 | 18,134／21,255 |
| Nynorsk 400k | 410,719 | 1–31 | 6,774 | 4,040 | 143 | 19 | 81,730／82,101 |

数量、长度、大小写／标点／数字／多词的各类交集均满足聚合合同；不是靠总数掩盖交集错位。Bokmål 大档每类最长 L／C／CP／P／CPN／PN 分别为 33／23／29／28／17／18；Nynorsk 对应 31／23／22／31／17／19。Nynorsk 多词有三字段、最多 18 字符字段的真实候选。最多连字符分别为三／四，首尾无连字符；没有把旧假词的末尾连字符继续伪装成原版行为。

字符比例、标点总标量数与参考仍有差异：Bokmål 150k 的连字符为 1,335／参考 1,373，600k 为 10,323／10,324；Nynorsk 100k 为 757／752，400k 为 4,420／4,421，撇号为 8／6。保留真实边界不等于词值、词频、难度、拼写规范或分布已经等价；所有选词和语言质量仍需独立审校。

## 原生交付与可复现保护

静态 Swift 十个 getter 按需初始化，不需要 Python、解压器、网络词典或频率库运行依赖。标准库准备器仅在 QA 要求 Unicode 15.0.0。两组旧基础池、十个 ID／显示名、nb-NO／nn-NO 语音、no／nn 百科、引语路由、Lazy Latin 资格、Zipf supported／unknown 和默认多语排除保持；捕获旧提示、事件与冻结指标不回算，无数据库迁移。

1,025,689 个去重标准／词形条目记录字典 lemma ID／全词形行 ID、整词次数及分段估计；大档未选的某些小档最长字段也独立有来源记录，位置数之和不是去重词汇数。按官方字典 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 和 unigram CC0 保留标题、Nasjonalbiblioteket／Språkbanken／Språkrådet／UiB 来源、固定文件和修改说明。About 增加说明，第十五个本地许可文档；完整映射随包，不整段挂入 SwiftUI 文本布局。包检查新增两项，共二十三项逐字节比较。

独立发布 pin：Swift `ad94ff044a09eebcd871f7d2e28dfe392c3af0f73c87d14db52cdf149e50f523`，署名 `9f4f38944278f000ce2176fb072e66c6c8d2f68360a8349878f8f2f77a381df7`，来源映射 `0ac83d52fecc28a648daca9bcdf9c3480b6b474b084abbff8cd8a234d69ad6b3`。准备器十二项自测在正常／优化模式通过，包含边界配额复用和官方频率表 NBSP token 的解析回归。此前失败的首次解析和冗余边界选择未计为有效产物。

最终源复现 `/tmp/typebar-norwegian-source-check-20261029.log` 通过，79.477 秒。正常／优化模式均接受有效样本并拒绝截断署名、删除来源项、修改词值后重算 manifest 文件哈希及错误字典 pin，`/tmp/typebar-norwegian-negative-checks-20261029.json`，71.895 秒。Bundled 检查只验证已发布数据，不能替代源复现。

## 原生证据与剩余范围

先行一项测试有 30 处预期失败，十档均缺对应的 ikke／ikkje、menneske、språk，`/tmp/typebar-norwegian-red-20261029.log`：XCTest 6.078 秒、驱动 30.848 秒，非 Markdown 输入哈希保持。

最终定向 `/tmp/typebar-norwegian-green-20261029.log`：17 项零失败／零跳过，XCTest 105.171 秒、驱动 208.214 秒，输入哈希保持。包括十档全部词数据哈希、28／32 项基础池哈希和默认多语排除、æ／ø／å 的工厂／Lazy Latin、全部 15,663 个标点项的输入／删除／No Space／重复、全部数字项在数字选项关闭时仍作为字面词、19 个 Nynorsk 多词及有限截断、各类别最长字段／Backwards、Unicode 单独大写与 ASCII 大写规则、153 词续批／重复、旧合成提示 JSON／模型／冻结指标／回放及 About。已查看实际隐藏 About 像素，原显著版权、Norwegian 来源和许可入口可读。

隐藏宿主 `/tmp/typebar-norwegian-host-20261029.log`：一项遍历十档，XCTest 13.148 秒、驱动 17.026 秒，输入哈希保持。逐档 153 词全预览使用生产准备器，验证真实候选成员、NSTextInputClient 首词输入、接收器身份及仅准备一次；窗口隐藏，defaults 隔离、SwiftData 仅内存，不代替实体键盘／IME。

独立 Debug getter 探针 `/tmp/typebar-norwegian-lazy-probe-20261029.log` 通过，驱动 3.173 秒、输入哈希保持。初始 RSS 5,776 KiB；Bokmål 1k 首次 0.000374 秒／6,240 KiB，Nynorsk 10k 首次 0.003741 秒／7,216 KiB，Bokmål 600k 首次 0.290875 秒／66,016 KiB，暖访问约 0.000000750 秒。仅证明独立数据 getter 的本机成本，不代表全应用启动、主线程首次切换、所有档位、Release 或最低设备性能。

首次扩大回归 `/tmp/typebar-norwegian-regression-20261029.log` 在 450 项通过后以 SIGTRAP 退出，驱动 341.781 秒，输入未变，未执行源证据汇总。系统崩溃报告 `xctest-2026-10-29-192050.ips` 的主线程经过 SwiftData／SwiftUI 的保存通知，到 `OrdinarySourceUnitStatsTests.testInMemoryEntityKeepsTrimmedStatsAndRawTerminalReplayTogether` 第 253 行；没有把这次中断计为回归通过。

只运行 Norwegian 隐藏宿主和该独立内存保存测试，同样崩溃，`/tmp/typebar-norwegian-swiftdata-repro-20261029.log`，驱动 17.028 秒。临时添加在宿主同一测试方法内的保存对照通过，不能重现跨方法问题，已移除；其历史文件名包含 `host-lifecycle-red`，实际退出码为零，不是红证据。仅替换空根并同步布局、延长容器生命的 v2 仍失败，40.785 秒。

最终宿主清理在容器存活期间替换空根，推进实际主循环，最多一秒等待 `onDisappear`，并断言回调已发生，再完成布局、移除视图及关闭隐藏窗口。没有跳过或修改独立保存测试、模式和断言。原最小两方法复现 v3 通过，`/tmp/typebar-norwegian-swiftdata-repro-v3-20261029.log`：两项零失败，XCTest 13.279 秒、驱动 36.645 秒，输入未变；十档均通过卸载断言。这支持测试宿主卸载时序与容器生命周期的修复，不声称已识别 SwiftData 私有断言或证明生产应用存在同一崩溃。[NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview) 与 [withExtendedLifetime](https://developer.apple.com/documentation/swift/withextendedlifetime%28_%3A_%3A%29-4mmpv) 的公开约束用于设计清理；实际回调和原复现用于验收。

相同过滤命令的扩大回归 v2 `/tmp/typebar-norwegian-regression-v2-20261029.log`：1,100 项零失败／零跳过，XCTest 767.384 秒、驱动 782.057 秒，1,354 个非 Markdown 输入哈希保持。包括原崩溃的独立保存测试和原有语言、真实宿主、输入、字段、回放、图表、配置及存储合同；后续源证据检查确认 146 项所需测试全部通过。首次失败运行、同方法通过对照和最终通过运行分别保留，不能合并为一次从未失败的执行。

未开窗 Debug 包检查 `/tmp/typebar-norwegian-package-20261029.log` 通过，43.179 秒，1,354 个输入哈希保持；严格签名、二十三项资源逐字节一致以及固定参考原创性边界均通过。临时包随检查清理，没有启动应用。推送前核对 main 仍为 `8c52fb13028f82fd8e8718d55cb7ed65463b034e`、开发分支前序为 `b212c6d72aa0656d9ccb9311540c7d6ce423dbc0`，开放 PR 为零，Actions 总数 826、最新 main 运行 39118939684 成功。本批只提交到 `native-parity-next`，工作流触发范围保持；不重跑 CI、不屏蔽通知。

原创性自测／固定参考扫描、配置和语言元数据无漂移、47 直接规格／119 原生符号／17 支持规格的行为链接审计通过；人工清单 1,450 项仅结构检查通过，新增两项仍待实体与语言审校。未运行可见 Typebar 应用，物理键盘／IME、VoiceOver、全部组合与完整性能仍开放。此次不是完整客户端 6,751 项复跑，既有完整等价与性能缺口不随本批回归通过升级。

同方法的当前具名 ScaleLexicon 结构路由从 139 项／2,866,074 个声明位置降为 129 项／1,560,763 个，核对 `/tmp/typebar-norwegian-all-scale-helper-audit-20261029.json`。TypingEngine SHA-256 `eec384229642daca1185d31e9c6bac08360f5211bff39fd481bc0ea03a7dcbad`，无未解析数量或未找到的生产路由。原历史范围的 82 项／438,685 不变，因为 Norwegian 属于此前扩展发现的额外路由；其余额外路由为 47 项／1,122,078。范围仍不覆盖全部构造器、基础短词池及语言质量，完整 goal 保持进行。
