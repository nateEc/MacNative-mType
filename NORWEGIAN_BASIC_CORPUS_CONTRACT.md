# 默认挪威语两种书面语独立语料合同

`LANG-NORWEGIAN-BASIC-54`。默认 Bokmål 从 28 扩到 200 项，Nynorsk 从 32 扩到 250 项；使用各自固定 Norsk ordbank 字典及 Nasjonalbiblioteket unigram 观察。原十档规模词库、共享读取器、语言 ID、输入规则及存储格式保持。已有结果按保存的提示与事件回放。

## 固定来源与选择

四个输入的下载位置、归属、原始归档及成员 SHA 记录于 Compatibility/norwegian-basic-corpus.json 和 Resources/NorwegianBasicCorpusNotices.txt。读取器 Scripts/prepare-norwegian-corpus.py 固定 SHA 为 `0df8e1a39edb41f69ca82278660409846494ac4cf1543da2007403b5afee1082`；该文件及原十档制品不改。

只选 normert、TILDATO=4000、原样 NFC、现代小写字母 abcdefghijklmnopqrstuvwxyzæøå、各自快照有正数整词观察的词典字面形式。Bokmål 限长 1–9，合格容量 107,498；Nynorsk 限长 1–10，合格容量 75,259。按本标准的整词次数和字面形式排序，保留合格旧自有词、原有必需拼写和实际长度边界；不借另一标准的次数，不以分段估计冒充整词观察。

Bokmål 保留 26／28 个旧词；oppmerksomhet 和 tålmodighet 超过新基础池长度边界。Nynorsk 保留 31／32 个旧词，andning 在该 unigram 快照无整词观察。这三项不进入新练习的基础候选；旧结果、指标及回放保留原文。未声称全部 60 项旧候选保留。

参考仅取聚合：200／250 项、长度 1–9／1–10，无大写／标点／空格；不读取或复制参考词值。新池全部唯一、单字段；含非 ASCII 项分别 33／34。不把数量和边界相同等同于词值、顺序、难度、直方图、频率分布或语言质量等价。

## 制品与许可

| 文件 | SHA-256 |
| --- | --- |
| Sources/Typebar/NorwegianBasicCorpus.generated.swift | 65fa72315466d52b2f8fe2e38913f8cc90b7153323702f99c371eb2cc719dbd3 |
| Resources/NorwegianBasicCorpusNotices.txt | 76ff513a994df50d6ec757f201ade440675279570b9f2c36db17489e84829489 |
| Resources/NorwegianBasicCorpusSources.txt | 1cc2314b9f241acba2b077dbdc4604a03c837c3bd26a2725ec522bf11ae5fcdf |
| Compatibility/norwegian-basic-corpus.json | 7979abbcfdca66cc3351e28a4681ea5af4e81e4b5afa533b747608a2efe1e6aa |

逐词 450 行记录标准、字面形式、lemma ID、fullform 行 ID 和本标准整词次数。字典选择注明 CC BY 4.0 改编及原机构，unigram 注明 CC0 1.0；新增原生“Norsk · 基础词库”许可入口，两份资源随包逐字节核对。原规模档许可描述其原有 revision，不改旧制品。

## 验证边界

Scripts/prepare-norwegian-basic-corpus.py 支持 --self-test、--check-bundled 和显式提供四个固定归档的 --check；准备使用 Unicode 15.0.0，产品无 Python／原始归档运行依赖。三份制品与 manifest 均由代码内不可变 SHA 固定。完整源重建通过；normal／-O 合同各三项通过。隔离制品正常样本通过，删来源行、修改 manifest、原生模板、共享读取器四类改动在 -O 下均拒绝，证据 /tmp/typebar-norwegian-basic-mutations-20261030.json。

先行 /tmp/typebar-norwegian-basic-red-20261030.log 一项八处失败，驱动 24.978 秒、XCTest 1.256 秒。首次实现定向记录 /tmp/typebar-norwegian-basic-focused-20261030.log：21 项中 16 项通过，含原十档哈希／行为、12 个默认与规模选择的隐藏生产页面及四项许可测试；新 Lazy Latin 测试的三组断言误将既有简化提示当作原字母提示，共 36 处失败。TypingEngine.swift 的 transformedWord 本来就先转为 lazyLatin，未修改产品规则，只纠正这三组测试预期；失败证据保留。

纠正后 /tmp/typebar-norwegian-basic-focused-green-20261030.log 五项通过、零失败，XCTest 1.369 秒、驱动 23.799 秒，非 Markdown 输入保持。覆盖 450 个实际工厂候选的输入／删除／No Space／Backwards／重复、各标准 Nordic／Lazy 拼写、逐词来源／署名，以及退出新池的旧词 JSON／模型／回放原文。

首次扩大 /tmp/typebar-norwegian-basic-regression-20261030.log 实际终止，1,228 项中 1,227 通过、一项失败，XCTest 855.680 秒、驱动 870.753 秒，输入保持。失败是既有弱点练习测试固定旧池首个 æ 候选 vær；现有 topRankedWords 按字符分数、同分按池顺序，独立频率新池先选 være。保留排序实现，更正字面预期并新增完整错误评分 [æ: 1] 断言，确保输入的 a 不被当作目标错误字符。/tmp/typebar-norwegian-basic-weakspot-20261030.log 单项重验通过（XCTest 0.008 秒、驱动 49.205 秒、输入保持）。原扩大红证据保留，不将失败运行写成通过。

同一选择集重跑 /tmp/typebar-norwegian-basic-regression-final-20261030.log 已实际退出成功：1,228 项通过、零失败／运行时跳过，XCTest 845.775 秒、驱动 861.364 秒，非 Markdown 输入保持；同前缀 .evidence.log 正式确认全部 146 项必需源方法通过。包含默认混排／Polyglot、通用多语生成与引语、弱点练习、全部既有语言宿主／来源要求及结果／回放相关集合。该扩大集合不是完整客户端套件；此前 3781c7b9 的 6,870 项全套与服务端 501 项见 CLIENT_BASELINE_20261030.md，其旧基础池结果不外推到本批数据。

/tmp/typebar-norwegian-basic-package-20261030.log 的 Debug 包、严格签名、新增两份资源的字节比对及原创性边界检查通过，驱动 44.209 秒，输入保持，未启动主程序。此边界脚本不构成穷尽的原创性证明。人工目录新增两项并保持待验收，结构检查通过（1,456 个唯一场景）。推送前 main 仍为 8c52fb13028f82fd8e8718d55cb7ed65463b034e，无开放 PR，Actions 共 826 次，最新 39118939684 成功；本批不改门禁或通知设置，只在本机全部验证后合并推送开发分支一次。

固定 2022 字典并非实时规范库，历史使用次数不证明当下流行度或词汇质量；实体键盘、IME、VoiceOver、语言审校及完整 Release／最低设备性能仍待验收，整体 goal 保持 active。
