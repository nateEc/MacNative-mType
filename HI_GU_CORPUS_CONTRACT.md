# Hindi／Gujarati 四档独立内容

起点 28c21b2724b42c6fba396ec7b870a64074e5bfee；参考固定 91bd24bb8513785c7364cbea29296ff7adafac41。替换两个按编号构造的索引入口，并扩充仅有旧 24 项的两个基础入口。原版只读取字符集合、数量、长度和类别聚合，不导出词值；原版源码与资产不进入产品。

## 输入能力与内容边界

| 入口 | 唯一数量 | UTF-16 长度 | 最长字素 | 含组合标记 |
| --- | --- | --- | --- | --- |
| Hindi 基础 | 200 | 2–10 | 5 | 193 |
| Hindi 1k | 999 | 1–12 | 6 | 956 |
| Gujarati 基础 | 214 | 1–12 | 6 | 199 |
| Gujarati 1k | 1004 | 1–19 | 12 | 900 |

四档均完整覆盖各自参考字符集合，没有旧词额外字符或长度例外。每个语言的旧 24 项全部保留，新基础池也保留在 1k 中。独立词典的单字符／符号条目明确标为 `dictionary-character`，不声称是完整词汇；其他词项保留词性。Hindi 1k 两项、Gujarati 各档四项属于该字符练习类别。

Gujarati 1k 的 33 个含空格项保留联合类别：带标记的 0／1／2／3 空格项为 868／27／3／2，无标记的 0／1 空格项为 103／1。恰有一个前导空格项和一个尾随空格项，无连续空格。32 个选项是 Tatoeba 原样连续摘录，余下多词项来自词典，不以拼接单词或补空格制造数量。词库保存原样边缘空格；既有正常生成流程修剪边缘、按组件占用词槽，不修改这一行为。

固定 Node v24.19.0／Unicode 17.0 与本机 Swift 对四份完整参考的字素分布逐项聚合一致，记录在工作区外 `hi-gu-grapheme-reference-aggregate.json` 和 `hi-gu-swift-grapheme-reference-aggregate.json`。Hindi 1k 最长为 6，旧占位测试中的 7 不是参考事实；新测试分别检查 UTF-16 与 Swift Character，不混用计分／回放单元。

## 固定独立来源与许可

- [Kaikki Hindi](https://kaikki.org/dictionary/Hindi/index.html)：168373020 字节，SHA-256 f4a417e93e7d494712a974e0ce167d071d01a75898917e194f4ca58ec7817e6c。
- [Kaikki Gujarati](https://kaikki.org/dictionary/Gujarati/index.html)：20496234 字节，SHA-256 8811fd6d77cf380066a01c0b5df4d784651101b923f9e4cf62401f2d0fda8405。
- 两索引报告提取日期 2026-10-30、enwiktionary dump 2026-10-01、Wiktextract 19f9a30／6f96ddf。仅选正确语言的原样 NFC 标题／词形，排除全部义项均错误／非标准的条目、转写、模板和错误形式。English Wiktionary contributors／Kaikki 选择内容按 CC BY-SA 4.0 署名。
- wordfreq 3.1.1 wheel SHA-256 4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473；Hindi 成员 `wordfreq/data/small_hi.msgpack.gz` 为 148115 字节，SHA-256 92ccbf70297d28e97af55a2a517b95c3d8b599e4cc943fb6d4612a3d44a86992，26653 个整词观察。只排序已独立见证的选项，不加入频率独有项；交付完整上游 metadata 许可。Gujarati 不使用 wordfreq，两语言运行时 Zipf 支持仍为未知。
- [Tatoeba hin 导出](https://downloads.tatoeba.org/exports/per_language/hin/)：283479 字节，SHA-256 596c48494d1e76ac7d5954d53a930342628cae9f4c884ae10c080986834bc10f，16475 句／113 个归一作者标识。
- [Tatoeba guj 导出](https://downloads.tatoeba.org/exports/per_language/guj/)：3922 字节，SHA-256 5702f42ba49c53a570f6550285254acea0a4d8dbfb80a9d9d0d6d7652edce04b，168 句／7 个标识。未拥有／未知作者显式记录。

Tatoeba 整词观察及选定原样摘录按 CC BY 2.0 France 分开署名；不交付完整句子集合、译文或音频。字母、数字、组合标记、控制／格式字符、连字符、下划线和撇号保留在匹配边界内，不截出部分词。原始字符串不经归一化来制造观察，一句只计一次，无观察为 NA。来源 TSV 分开记录词形／词性、来源类型、句子 ID／作者及频率 band。band 不是次数。

Gujarati 八个旧词未在选定允许词汇类别中取得见证，明确保留为 `typebar-legacy`：ધીરજ、નોંધપોથી、પર્ણ、પુલ、પ્રયત્ન、વિરામ、સરળતા、હિંમત。不据此声称原始词典所有类别都没有该字符串。

| 入口 | 词典／字符练习／摘录／旧自有 | Tatoeba 有观察 | wordfreq 有观察 |
| --- | --- | --- | --- |
| Hindi 基础 | 200／0／0／0 | 192 | 198 |
| Hindi 1k | 997／2／0／0 | 913 | 995 |
| Gujarati 基础 | 202／4／0／8 | 185 | 不使用 |
| Gujarati 1k | 960／4／32／8 | 245 | 不使用 |

## 证据与未完成项

四项首轮先行测试 30 处失败，其中历史多词回放夹具错误地把整个短语放进一个词槽。核对实际生成规则后修正新测试：正常多词出题按组件计算词槽，边缘空格保持在语料但不强制进入生成目标；历史占位回放使用原有单词槽。未修改产品来迎合这些错误假设。

核准 `hi-gu-corpus-red-verified` 四项 29 处预期失败，原生 1.114 秒、driver 25.089687 秒，非 Markdown 输入不变；明确复现 Hindi 1k 缺少 ि、完整键集／旧词及 Gujarati 空格结构缺口。历史目标回放已通过，不作为本批新修复。

八个产物已接入生产，普通／优化模式各三项生成器测试及固定产物检查通过；从四个固定原始快照和 wordfreq wheel 重建，八个产物逐字节一致。Swift 词项用带引号的数组保存，保留尾随词项空格且不引入源文件行尾空白。

79 项定向测试全部通过，原生 12.410 秒、driver 115.566392 秒，非 Markdown 输入不变。覆盖四档原始字符／数量／组合标记、Gujarati 含边缘空格的原始词项及正常生成组件、真实目标完成／成绩编码／重复、历史占位目标回放、原生许可读取与相邻词库。

扩大回归 733 项全部通过，原生 464.185 秒、driver 481.772629 秒，非 Markdown 输入不变；同日志 152 项固定源码对照证据正式通过。定向／扩大均无运行时跳过。原创边界扫描、参考配置／语言元数据重建及 1494 项唯一人工场景结构审计通过；结构审计不是实体验收。

显式 Release 编译 538.01 秒、包检查 driver 580.413449 秒；严格签名、资源逐字节比较与原创边界检查通过。Release 二进制 SHA-256 a497af701794acaeee6af9ce454ca586e914adb104f524bec49a1afe5baf6892。两个测试诊断标记在 Release 中均不存在、在旧 Debug 对照均可检出；仅两个诊断源文件与旧 Debug 输入相同，不将旧包当作当前全量构建证据。当前全部非 Markdown 输入另与本批定向及 Release 记录逐项一致。

推送前 main 为 8c52fb13028f82fd8e8718d55cb7ed65463b034e，开发分支为本批起点，无开放 PR；Actions 共 826 次，最新 39118939684 completed/success。只合批推送开发分支，不更改工作流或通知设置；实际推送后状态另存工作区外证据。

本批不启动可见主应用。语言质量、难度与频率分布、实际键盘／IME、VoiceOver 和完整等价仍待验收，完整 goal active。
