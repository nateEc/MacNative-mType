# 默认俄语独立语料合同

`LANG-RUSSIAN-BASIC-53`。默认 Russian 从 24 个自有词扩到 200 个独立来源的真实字面词形，保留全部旧词。原六档规模语料、缩写／short-form、语言 ID、输入规则和存储格式保持。已有结果按其保存的提示与事件回放，不从新词库重新生成。

## 来源与选择

固定 Russian Wiktionary／Kaikki 原始快照为 `https://kaikki.org/dictionary/downloads/ru/ru-extract.jsonl.gz`，SHA-256 `7e30fc4e4b21ff16cde09a501494f25287ae66f9a0f94e770ae826e5003c7698`。wordfreq 3.1.1 wheel SHA-256 `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`，Russian member SHA-256 `0440613cc765c14a20fb9483225f2fec4d85e66672809076bcec9b29119f9b43`。复用本项目独立准备器的固定读取逻辑，prepare-russian-corpus.py SHA-256 `66c968199417e0d869eabb4af7ce9458c1765f1f8f1491559de308dfacb06a6e`，该文件及其六档制品未改。

只从原样 NFC 词典词形中选择现代小写俄语字母、1–12 字符、wordfreq 中有完整词形观察的候选。合格容量 83,731，按完整词形频率 band、字面拼写排序；保留原 24 个有来源支持的自有词及实际长度边界。Band 不是使用次数。没有复制参考词值、去重音、重写 NFC、改大小写、拼接新词或填充字符。

参考只读取聚合：200 项、长度 1–12、无大写／标点／空格。原生此前为 24 项、长度 3–11；新池 200 项全部唯一、单字段、现代俄语小写字母，长度 1–12。未要求或声称词值、逐长度直方图、顺序、难度、频率分布及语言语义质量等价。

## 发布制品与许可

| 文件 | SHA-256 |
| --- | --- |
| Sources/Typebar/RussianBasicCorpus.generated.swift | 75f09a45a6718aa52be3a2606558dbfeccc87335974b49b3c83290bf9a7a5bdf |
| Resources/RussianBasicCorpusNotices.txt | b9f4d3a8ba642bbbde7d028171fef5e8654c768a018023dacb6c6d5e4c371184 |
| Resources/RussianBasicCorpusSources.txt | 990fb153c05d1299da8d144b671bf2f4a05949d65032e5cc8bf3e375e048231e |
| Compatibility/russian-basic-corpus.json | d05542c347270e03cf6fecd51d2fabd25265f61cd780e92b8c2c230b5fc70f1e |

逐词行映射覆盖全部 200 项，记录 Russian Wiktionary 页面和完整词形 band；署名列 CC BY-SA 4.0 改编及完整 wordfreq release notices。原生许可阅读器新增“Русский · 基础词库”，手工打包及包检查加入这两份新资源并逐字节核对。原六档 notice 描述的是其独立 revision-1 选择，其制品全部保持原 SHA。

## 可重现性与行为证据

Scripts/prepare-russian-basic-corpus.py 使用固定源，不下载或读取参考词值。QA Python 使用 Unicode 15.0.0／msgpack 1.1.2；产品没有这些运行依赖。支持 --self-test、--check-bundled，以及显式提供 --dictionary／--frequency-wheel 的 --check。三个制品和 manifest 都由代码中的不可变 SHA 固定，不能借修改 manifest 给新字节建立信任。

完整固定源 --check 已通过，normal／-O 准备合同各三项通过。隔离复制的正常制品通过；删来源行、改 manifest 的频率要求、改原生模板、改共享读取器均拒绝，记录 /tmp/typebar-russian-basic-mutations-20261030.json。实际来源重建比 bundled 字节检查更强，二者不互相冒充。

先行 /tmp/typebar-russian-basic-red-20261030.log 一项四处失败，实际为 24／200、最短 3／1、最长 11／12；XCTest 1.717 秒、驱动 26.644 秒。实现后 /tmp/typebar-russian-basic-focused-20261030.log：25 项通过、零失败，XCTest 40.406 秒、驱动 130.813 秒，输入保持。包含所有候选的实际工厂／删除／No Space／Backwards／重复、保留旧词、旧 JSON／模型／回放、逐词来源／许可和七个俄语选择的隐藏生产页面；六档原词哈希也保持。

扩大 /tmp/typebar-russian-basic-regression-20261030.log 实际终止，1,222 项通过、零失败／运行时跳过，XCTest 846.921 秒、驱动 862.678 秒，输入保持；同前缀 .evidence.log 正式确认 146 项必需源方法通过。该集合增加默认混排／Polyglot 相关方法，覆盖词池、续批、旧结果和全部既有来源要求。另独立执行通用多语生成与引语方法一项通过（XCTest 0.886 秒、驱动 5.011 秒），并未把它冒充完整客户端。

/tmp/typebar-russian-basic-package-20261030.log 的 Debug 包、严格签名、27 份许可／来源资源逐字节检查及原创性边界通过，驱动 41.718 秒，输入保持，未启动主程序。来源边界脚本不是完整语言审校或穷尽的原创性证明。新增两项人工场景保持待验收，目录结构检查通过（1,454 个唯一场景）。

此前 3781c7b9 的完整 6,870 项／服务端 501 项／Debug 包基线见 CLIENT_BASELINE_20261030.md；它对应旧基本池，不能外推为新语料全套已通过。本轮不为文档诊断独立推送，验证与实质功能改动合为一个开发分支批次；旧红证据与输入哈希保留。

375k 最长 46／49、其他档的撇号／prime、分布和语言质量仍开放；基本池的词值／频率／语义质量也不因计数与边界达标而完成。实体键盘、IME、VoiceOver 和完整 Release／最低设备性能继续验收，整体 goal 保持 active。
