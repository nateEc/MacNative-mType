# Italian 1k／7k 的独立实际词汇

`LANG-ITALIAN-SCALES-36`，起点 `58f33ba0`。本项替换合成词候选，不代表完整重写或全部 Italian 档位完成。

## 数据来源与规则

准备器只读取固定 wordfreq 3.1.1 wheel，SHA-256 为 `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`；成员 `wordfreq/data/large_it.msgpack.gz` 的 SHA-256 为 `0b5500e425a50e0f1fefb256d9125e74f586ac6b2f2a6e41bc96634bd5613cc7`。不读取 Monkeytype 词值，不从参考内容挑选独立词，也不执行 wordfreq Python 代码。

保留频率桶及桶内排序，接受 NFC 小写 Italian 字母，最长 18 字符；单字符限 a／e／i／o／è，按清单排除部分外语功能词、缩写和碎片。302,003 个合格观察 token 中取前 7,154 个；1k 再按 14 字符上限筛出前 1,159 项。五个独立命名编辑将 italia／roma／milano／napoli／sicilia 写为对应专名，不声称大写用法有独立频率。没有追加假词、未排名短语或填充项。

| 入口 | 唯一候选／长度 | 当前大写／非 ASCII | 固定参考大写／非 ASCII | 词数据 SHA-256 |
| --- | --- | --- | --- | --- |
| Italian 1k | 1,159／1–14 | 4／37 | 1／34 | `3147482398398803f2f7416671cc5d7a931fbb2d428a3a89711424424c52257f` |
| Italian 7k | 7,154／1–18 | 5／168 | 2／136 | `75bcab23bddf0011805707c681ca1152194b5d88321cbd7a7f6fdf07888d1dfd` |

当前与参考两档都没有候选内部空格、标点或符号。数量与长度相同不代表词值、难度、词频或内容分布相同；观察语料不是词典认证，专名、品牌、借词、口语或粗俗词仍可能存在。语言质量和全部内容分布仍需审校。60k／280k 继续使用旧合成池，缺口明确保留。

## 交付与兼容

生成 Swift 原生静态数据及独立 manifest，应用不增加 Python、msgpack 或网络词库依赖。仅准备时使用固定 msgpack 1.1.2；脚本无下载或依赖安装。--check 从固定 wheel 重建并逐字节比较，--check-bundled 仅用标准库检查内部结构及哈希，不冒充上游重建。

数据按 CC BY-SA 4.0 提供，保留完整 wordfreq 发布的来源署名和数据许可；编辑贡献同许可。ItalianFrequencyCorpusNotices.txt 随应用交付并在包检查中逐字节比较，不把代码的 Apache 许可误作数据许可。CI 增加离线准备工具及完整性检查，不改变触发规则。

语言 ID、标签、预设／分享、语音／百科、简化输入及未知 Zipf 合同不变。基础 Italian 的 199 个词及哈希 `a62740b4e493c568d143e5b4f4e8b1aa18eb7b820e13be3ddc1a38a9365dd954` 不变，默认四语池不增加 Italian。只改变新练习候选，旧提示、事件、冻结指标不回算；保存及重播继续读捕获内容，无数据库列或归档版本改变。新候选生成仍走原有大小写、标点、无空格、续批和目标缓存管道。

## 验证轨迹

测试初稿错误使用三参数 zip，编译错误单列，不计为产品红测。修正后 `/tmp/typebar-italian-scales-red-v2.log` 五项检查出现 18 处实际失败：词汇缺失、候选仍为合成标记、两档不是所需实际语料子集，真实词无法选入练习。原长练习及旧记录通路在红测中已保留。测试 2.110 秒、驱动 22.904 秒，非 Markdown 输入哈希不变。

接入后 `/tmp/typebar-italian-scales-green.log` 37 项零失败／零跳过，测试 11.858 秒、驱动 90.112 秒。补原生词数据哈希和专名实际输入／重复后，`/tmp/typebar-italian-scales-expanded.log` 38 项零失败／零跳过，测试 11.748 秒、驱动 32.938 秒；均哈希不变。原“匹配参考聚合形状”的合成词测试更名为当前独立词池审计，按真实 manifest 更新大小写及重音数量，不伪造词去保持原统计。

8 项准备工具自测、标准库内部完整性、固定 wheel 三文件逐字节重建、元数据再生和原创边界检查通过。

首次扩大回归 `/tmp/typebar-italian-scales-regression.log` 共 1,693 项、1 处失败、零跳过，测试 747.197 秒、驱动 759.938 秒，输入哈希不变。其中完整 `TypingEngineTests` 的 798 项全通过，364.467 秒。唯一失败来自既有 `PolyglotCandidateTests.testRepeatReshufflesFuturePoolWithoutChangingItsCachedTarget`：夹具使用 words=0，却期望重复缓存耗尽后继续生成。固定 `words-generator.ts` 第 777–805 行仅在 wordIndex < Config.words 等明确条件下允许继续，零值不满足；既有 `GeneratedRepeatedWordPolicy` 及零值来源测试已按此执行。将测试改为尚未生成第三词的 words=3，并另加零值缓存重放后不抽样、明确耗尽的检查；生产重复策略不改。失败轮不算全绿，证据检查器也明确拒绝该轮。

仅修改该测试文件后，`/tmp/typebar-italian-scales-regression-final.log` 重新执行全部必需来源及相关词库、生成、输入、历史、重播消费者，加 Italian 引擎条目，共 920 项零失败、零跳过，测试 366.702 秒、驱动 397.289 秒，输入哈希不变；144 项必需来源证据全部通过。包括修正及新增边界的完整多语类 19 项通过。未重跑此前已通过且生产输入未改动的完整 798 项，不将两轮数字相加宣称单轮全绿。验收表审计 1,429 个唯一场景、diff 空白检查通过。

`/tmp/typebar-italian-scales-package.log` 的 Debug 应用包检查通过，驱动 35.878 秒、输入哈希不变；包括新的 Italian 署名文件逐字节比较、应用资源边界及固定参考原创边界核验。无可见窗口启动，Typebar 主程序进程数为零。仅计划单次开发分支推送；不改变 main、PR 或 CI 触发范围。

仍开放其他合成档位、语言质量／分布、全部修饰器／配置组合、真实键盘／IME、全量 Release 性能和旧库／旧二进制。完整 goal 保持进行。
