# 乌克兰语西里尔基础与规模语料合同

`LANG-UKRAINIAN-CYRILLIC-56`，起点 835be7b69e7abbfe067a4ae4f6ad5b8691fe8241。移除三档重复字符／编号合成器，发布 1,000／9,998／49,991 个独立来源候选；基础池 27→199，保留所有旧 27 词。四池共 61,188 个位置，小池包含于后续大池。语言 ID、输入规则、存储格式及旧提示／指标／回放保持；Latynka 与词尾练习不在本批替换范围。

## 来源与改编

English Wiktionary 经 Kaikki／Wiktextract 后处理的 Ukrainian JSONL：
https://kaikki.org/dictionary/Ukrainian/kaikki.org-dictionary-Ukrainian.jsonl
下载 322,795,063 字节，SHA-256 `31e8e39f48feae391478f1fe2c37d003053cf88f2dd4f2d97d5d19c7bc432a90`。索引报告 2026-10-25 提取、enwiktionary 2026-10-01 dump；索引本地快照 SHA `3d5736062015a8fc35401211fdb026979764d1646d4a334ac17fcb7c311b9ced`。不把后处理数据称作原始 Wiktextract 全量。

另一固定源为 Russian Wiktionary 原始提取 https://kaikki.org/dictionary/downloads/ru/ru-extract.jsonl.gz，SHA `7e30fc4e4b21ff16cde09a501494f25287ae66f9a0f94e770ae826e5003c7698`。仅读取两份数据中 lang_code=uk 的词条，不把俄语词汇混入乌克兰语。逐词映射区分 English／Russian edition 的标题及原始形式，分别链接 en.wiktionary.org／ru.wiktionary.org 的贡献者。

wordfreq 3.1.1 wheel SHA `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`，wordfreq/data/large_uk.msgpack.gz SHA `0a7d525ef5b9d2c84cd3ccd1064b02eb6a07232e5d1e465df40cc00168fdaac2`。完整词形观察、分段估计、未知三者分开；band 不是次数。按整词观察优先、其后分段估计、最后无观察词典形式和字面顺序确定选集。不能将词典屈折表当作实际使用次数。

明确改编：只移除直接接在乌克兰语元音后的 U+0301 注音重音，逐词保留变更前原始形式；不泛化去重音，不改写 ї／й／є／ґ，不重排 NFC、不改大小写、不拼造词缀或填充长度。拒绝非现代乌克兰字母、错误／模板及罗马化形式。基础 199 项全是原样、有整词观察的字典形式，不使用注音改编。

另外手工核对了三个 Wikipedia 页面所标示固定修订中的五个原样 token，含长复合词及数字形式。Compatibility/ukrainian-boundary-evidence.json 保存短摘录、原样拼写、来源与 oldid，SHA `3b603794d5f1869f79c0253f4498d9dbdad369bc0e44083a6490f537a096f60e`。它是网页阅读器核实后的人工摘录，不是完整页面下载或可独立重建的完整语料库；直接下载曾返回 403，未把它当作成功。字典已覆盖的词仍保留字典出处，50k 实际新增文本来源四项。摘录及原词来自 Ukrainian Wikipedia contributors，保留 CC BY-SA 4.0 归属。

## 范围与已知差距

参考只读取数量、字符类别交集、长度边界及标点聚合，不读取参考词值。四池的独立类别数量／最短最长边界达到固定聚合；包括大小写、数字及标点交集和最长 18／30／31 字段。1k 撇号／连字符分别 13／2，10k 分别 130／85，与聚合一致。

50k 新增 Пізнання 页面原样出现的 `суб'єктно-об'єктне`（18 字符，两个撇号及一个连字符）；该页面页脚标示 oldid=48450573，固定 URL 单独读取返回 cache miss，未声称下载其快照。由此关闭此前保留的组合缺口；当前撇号 661、连字符 1,371，与参考聚合一致。其他组合的逐长度分布也未声称等价。数量或总体长度通过不能代替完整词值、频率分布、难度、现代规范或语义质量验收。

| 池 | 注音改编项 | 有整词观察项 | 文本补充项 |
| --- | ---: | ---: | ---: |
| basic | 0 | 199 | 0 |
| 1k | 35 | 998 | 0 |
| 10k | 2,611 | 9,914 | 0 |
| 50k | 24,815 | 48,642 | 4 |

字典与文本改编选集标 CC BY-SA 4.0，完整 wordfreq 发行许可继续保留；新增原生 Українська 许可入口及 About 来源说明。49,991 行映射覆盖大池全部词形，小池均在其中，列出证据类型、标题／URL、原始带注音形式、整词 band 和分段估计 band。原始词典、Python／msgpack 和参考文件不随产品运行。

## 固定制品

| 文件 | SHA-256 |
| --- | --- |
| Sources/Typebar/UkrainianCorpus.generated.swift | ea61bdd683ce82cdac4b0e096cbb67f33c65728a784b25890fbabc2ef1d2b26a |
| Resources/UkrainianCorpusNotices.txt | 8e306cbe3ea0e4f2c7516331fcf06d93e819fd84dca35fc0bc46f15f764089a8 |
| Resources/UkrainianCorpusSources.txt | 6a27d86a644e250081c5c4e58d81513dfe79dd6f45f54005df30a2252d269e7a |
| Compatibility/ukrainian-corpus.json | be4982820a261d75f717464bc3aa4c9fd61a2277f6eb23fe666bd9fbed4730be |

Scripts/prepare-ukrainian-corpus.py 支持 normal／-O 六项合同、--check-bundled，以及显式提供两份字典、wheel 和边界摘录的 --check。Unicode 15.0.0／msgpack 1.1.2 仅用于准备。制品、整个 manifest 及摘录均有代码内不可变 SHA，修改 manifest 不会建立新信任。完整固定源重建已通过，normal／-O 六项合同分别通过；隔离正常样本通过，删除来源行、改 manifest、原生模板、边界摘录四类篡改在 -O 下均拒绝，见 /tmp/typebar-ukrainian-mutations-20261030.json。

## 双撇号组合后续修复

以原始页面已观察摘录补入 `суб'єктно-об'єктне`，不拼接、扩写或直化标点。仍为 49,991 个唯一候选；50k 仅替换一个词，基础／1k／10k 的内容及顺序逐项保持，见 /tmp/typebar-ukrainian-combination-delta-20261030.json。新词有字面文本出处，但没有整词频率观察；因此整词观察数量从 48,643 减为 48,642，未知不冒充零或已观察。参考只使用上一轮保存的聚合，不读取其词值。

先行 /tmp/typebar-ukrainian-combination-red-20261030.log 一项一处失败，实际证明该独立文本词缺失，驱动 24.995 秒、输入保持。更新生成文件后第一次 17 项运行仅旧 50k 指纹预期失败；核对确为一个词替换并更新指纹后，同组 /tmp/typebar-ukrainian-combination-focused-final-20261030.log 实际退出成功，17 项零失败／跳过，XCTest 32.010 秒、驱动 55.086 秒，非 Markdown 输入保持。覆盖每个标点词的实际输入／删除／No Space／Backwards／重复、逐词原样来源、四个隐藏生产页面、许可与原有 Ukrainian／Latynka 元数据。没有启动主程序。

两份字典、wordfreq wheel 与新摘录完整重建比较通过，normal／-O 六项合同及 --check-bundled 通过；三个较小池的 SHA 保持。人工目录仍为 1,460 个唯一场景，实体双撇号输入及许可审校保留待验收。下列 1,245 项扩大回归及旧篡改、截图、打包记录属于上一轮 5bd0fc9f，不冒充此次输入上的运行结果。

此次 /tmp/typebar-ukrainian-combination-package-20261030.log 的 Debug 打包、严格签名、33 份来源／许可资源逐字节比较和原创性边界检查通过，驱动 43.104 秒，输入保持。作业终态后再次确认原生及主程序进程为零。推送前 main=8c52fb13、开发分支=5bd0fc9f、开放 PR=0；Actions 总数 826、最新 39118939684 成功。此次只向开发分支推送一次，不更改 CI、通知偏好或 main。

## 上轮实现行为证据（5bd0fc9f）

先行 /tmp/typebar-ukrainian-red-20261030.log 一项五处失败：基础数量／唯一数 27／199，三档含非现代占位字符；XCTest 1.545 秒、驱动 25.305 秒，输入保持。

实现后 /tmp/typebar-ukrainian-focused-20261030.log 的 16 项全部通过、零失败／跳过，XCTest 32.126 秒、驱动 124.243 秒，输入保持。执行每个标点及数字词形的实际输入／删除／No Space／Backwards／重复、全部基础词、各类别长短边界、逐词原始形式追踪、完整许可、四种旧配置 JSON／模型／合成提示原文回放；原有布局、语言元数据（含未改 Latynka）和弱点练习亦通过。四个真实隐藏生产页面均完成 153 词准备及首词输入，没有启动主程序。

本批 About 实际隐藏组件截图另存 /tmp/typebar-ukrainian-about-20261030.png，SHA `cf771053cd2baa3c79f00f80c9cd1c886e4472d1835938210339912252fe44fd`，已目视核对新增乌克兰语来源／改编说明及完整许可入口可见；不将其视作系统 sheet、实体屏幕或辅助功能验收。

扩大 /tmp/typebar-ukrainian-regression-20261030.log 已实际退出成功：1,245 项通过、零失败／运行时跳过，XCTest 885.110 秒、驱动 900.988 秒，非 Markdown 输入保持；同前缀 .evidence.log 正式确认 146 项必需来源方法通过。包括全部既有来源检查、语言宿主、默认混排／Polyglot、候选／续批、弱点、旧结果／回放及乌克兰语原有元数据。它不是完整客户端套件；此前完整客户端 6,870／服务端 501 基线及上一批 1,234 扩大结果均不外推本批。

本轮原生作业终态后仅补充 .gitattributes：精确针对 UkrainianCorpusSources.txt 的 TSV 空末字段保留行尾 delimiter，空 band 表示无观察，不是零。没有改动其字节、制品 SHA 或输入代码；其他文件的行尾空白检查保持。隔离 Git 样本验证了未设属性时 TSV／Swift 均拒绝、设置后仅允许有意义的空 TSV 字段而仍拒绝 Swift 行尾空白，修正 Swift 后通过，记录 /tmp/typebar-ukrainian-tsv-whitespace-20261030.json。最终打包另在含该元数据的输入上执行。

/tmp/typebar-ukrainian-package-20261030.log 的 Debug 包、严格签名、33 份许可／来源资源逐字节核对及原创性边界通过，驱动 43.921 秒，输入保持，未启动主程序。此边界检查不构成穷尽的原创性证明。人工清单新增两项保留待验收，目录结构检查通过（1,460 个唯一场景）。推送前 main 仍为 8c52fb13028f82fd8e8718d55cb7ed65463b034e，开发分支仍为本批起点，无开放 PR；Actions 共 826 次，最新 39118939684 成功。本批本机验证后只合并推送开发分支一次，不改 CI 或通知设置。

结构复核 /tmp/typebar-ukrainian-scale-audit-20261030.json：TypingEngine SHA `f5297d0810d61931d59f2569c66d6a7ed998498515025555d98936bc40bb1cda`，直接具名 ScaleLexicon 属性路由余 119 项／1,029,000 个声明位置。该扫描不是全部构造器、实际词数或语言质量证明。实体键盘／IME、VoiceOver、语言审校、完整 Release／最低设备性能继续开放，整体 goal active。
