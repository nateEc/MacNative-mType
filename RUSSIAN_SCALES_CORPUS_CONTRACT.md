# Russian 六档独立词库与输入边界

`LANG-RUSSIAN-SCALES-52`。参考仅在隔离脚本中产生聚合／行为证据，不输出或移植词值。删除六档 `russianScaleLexicon` 的编号、重复字符、尾连字符和拼接短语占位，共 469,774 个候选位置，改用独立 Russian Wiktionary 字面词形及 wordfreq 编排。移除占位不证明完整词汇、难度、分布或功能等价。

## 固定独立来源

原始俄语版 Wiktionary 提取：`https://kaikki.org/dictionary/downloads/ru/ru-extract.jsonl.gz`，2026-10-29 获取，308,932,274 字节，SHA-256 `7e30fc4e4b21ff16cde09a501494f25287ae66f9a0f94e770ae826e5003c7698`。固定文件共 2,729,136 行；筛选 `lang_code=ru`、实词／短语／缩写等词性及字面 headword／form 后，614,218 个候选。保留实际 NFC Cyrillic、单空格、大小写及允许的标点；拒绝模板、元数据／romanization／error 标签、孤立词缀、数字、首尾连字符、组合重音和非 NFC。没有去重音、改大小写或 Unicode 改写来制造新字面词形。

许可依据为 [Kaikki 俄语版版权说明](https://kaikki.org/ruwiktionary/) 和 [Russian Wiktionary 实际页面页脚](https://ru.wiktionary.org/wiki/время)，后者指向 CC BY-SA 4.0；选编按同许可提供，保留贡献者、页面／历史 URL 模板、Kaikki／Wiktextract 及修改说明。[Wikimedia 条款第七节](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use#7._Licensing_of_Content) 用于核对署名和修改边界。直接版权页和 siteinfo 请求曾不可用，没有拿音频／图片单项许可替代文字许可。原始日志观察到 `ruwiktionary-20261001-pages-articles.xml.bz2`；复现以实际字节 pin 为准，不把 English 版或后处理页面的提取日期／代码版本移作本文件版本。

频率来自固定 `wordfreq-3.1.1-py3-none-any.whl`，SHA-256 `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`；仅读取 `wordfreq/data/large_ru.msgpack.gz`，成员 SHA-256 `0440613cc765c14a20fb9483225f2fec4d85e66672809076bcec9b29119f9b43`。cB v1 共 713,447 个 token，发行版完整数据许可／来源说明保留。准备期要求 Unicode 15.0.0／msgpack 1.1.2；应用没有这些依赖，也不联网下载词库。

排序依次为 casefold 整词 band、所有分段均存在时的最稀有分段 band 估计、未知字面顺序。band 是量化桶索引，不是实测次数；来源四列区分实际拼写、页面、整词 band 和分段估计，`-` 为不可用。379,491 个去重拼写均有源页面标题，跨档位置会重叠。保留五个独立选择的常用练习词及源中已有的 Россия／Москва，不转换小写词来伪造专名。部分词典形式没有 wordfreq 使用观察，语言质量、拼写／时代、词频及难度仍需审校。

## 实际类别与未完成边界

C 为大写项、P 为标点、S 为单空格多字段、L 为无额外属性的字母项。逐交集核对数量、最短／最长、字段数和最长字段，不用全局长度代替各类边界。

| 档位 | 数量 | 实际类别：数量／最短–最长 |
| --- | ---: | --- |
| 1k | 996 | C 2／6–6；L 993／1–15；P 1／6–6 |
| 5k | 4,971 | C 40／2–10；CS 2／14–20、两字段／最长字段 10；L 4,927／1–17；P 2／3–9 |
| 10k | 9,996 | L 9,934／1–21；P 62／5–24 |
| 25k | 26,037 | C 1,209／2–17；CP 9／8–16；L 24,306／1–24；P 513／3–34 |
| 50k | 51,682 | C 2,377／2–17；CP 19／8–18；L 48,253／1–24；P 1,033／3–34 |
| 375k | 376,092 | L 376,058／1–46；P 34／5–16 |

375k 的 L 最长词／字段为 46、参考为 49；其余上述类别数量及字段边界满足固定聚合合同。最多连字符依次 1／1／1／3／3／2。5k 两个标点项分别保留句点缩写和连字符词；初始原型的贪心边界选择漏掉句点，已增加小配额联合覆盖合同后重选，原型不计为发布制品。

标点标量实际／参考仍有差异：25k 连字符 544／543、ASCII 撇号 0／1；50k 连字符 1,089／1,086、撇号 0／2；375k 连字符 39／33、prime（U+2032）0／2。1k／5k／10k 的标点种类与标量数满足合同。没有用其他档额外句点掩盖缺失撇号／prime，也没有把这些缺口称为完成。词值、顺序、使用观察、标点分布和全部输入组合仍开放。

六档发布时基本池保持 24 项，SHA-256 `c1efe8fabc0aaf6ce2f1617e30875220c830a7afd0d5f02134b2c0ffc42494e2`，当时未缩小参考 200 项的缺口。其后独立的基础池改编见 RUSSIAN_BASIC_CORPUS_CONTRACT.md；六档制品不随之改变。缩写和 short-form 目录未改，也未随六档结果宣称完整审校。

## 原生交付与源复现

六个静态 getter 按需加载；IndexedLexicon 保持独立入口与数量，不提前物化所有档。ID、名称、ru-RU 朗读／ru 百科、Zipf supported／unknown、Lazy Latin 资格及默认多语排除保持。现有 ё／е／ASCII e 等价和非 ASCII 大写规则直接用于实际词形。无数据库迁移，历史提示、冻结指标和原事件保持原样。

发布 pin：Swift `b8d9d14b0d087522bb5a5ca8f75937e469a0922bd985566dfa0296142f3a048a`，署名 `c37063392a3eed9ad77d8ba25d3c1f727a413c05dd420341bf1c6ff83d5cc4f7`，来源 `e39ccaf5e7e7d31989b91265b721e9d131b93ed07787cd8ccbd778b68c8204ab`。准备器独立硬编码发布 pin，不接受只改 manifest 的自洽哈希。

准备器十项合同在正常／优化模式通过。完整固定源复现 `/tmp/typebar-russian-source-check-20261029.log` 通过，77.650 秒，脚本及制品输入保持。正常／优化模式均接受有效制品并拒绝截断署名、缺少来源行、修改词后重算 manifest 哈希、错误源 pin 及隐瞒长度缺口，`/tmp/typebar-russian-negative-checks-20261029.json`，45.150 秒。Bundled 检查不能替代源复现：

```sh
python3.12 Scripts/prepare-russian-corpus.py \
  --dictionary /path/to/ru-extract.jsonl.gz \
  --frequency-wheel /path/to/wordfreq-3.1.1-py3-none-any.whl --check
```

About 增加来源说明及第十六个本地许可入口，完整来源映射随包但不整段挂入 SwiftUI 文本；包检查新增两项，共二十五项逐字节资源比较。已查看本次实际隐藏 About 像素，原显著英文版权、Russian 说明及许可入口可读；未启动可见应用。

## 原生证据与后续

先行 `/tmp/typebar-russian-red-20261029.log`：一项测试 24 处预期失败，六档均缺所检常用实词；XCTest 1.940 秒、驱动 26.249 秒，输入保持。最终定向 `/tmp/typebar-russian-green-20261029.log`：20 项零失败／零跳过，XCTest 28.642 秒、驱动 131.273 秒，1,361 个非 Markdown 输入未变。包含全部发布词哈希、基础池、类别交集、全部 1,673 个标点项输入／删除／No Space／重复、5k 两个短语与截断、专名大小写、ё 工厂和别名输入、各类最长字段／Backwards、153 词续批及重复、旧提示 JSON／模型／冻结指标／回放、元数据和 About。

隐藏生产页面 `/tmp/typebar-russian-host-20261029.log`：一项遍历六档，XCTest 8.643 秒、驱动 12.160 秒，输入保持。153 词全预览走生产准备器，验证实际成员、NSTextInputClient 首词输入、接收器身份、仅准备一次和实际卸载回调；defaults 隔离、SwiftData 仅内存、窗口始终隐藏，保留上一批的容器生命和主循环卸载保护。

独立 Debug getter 探针 `/tmp/typebar-russian-lazy-probe-20261029.log` 通过，驱动 3.474 秒，输入未变。初始 RSS 5,776 KiB；1k 首次 0.000510 秒／6,304 KiB，5k 0.002535 秒／6,960 KiB，375k 0.255888 秒／59,392 KiB，暖访问 0.000020 秒／59,424 KiB。仅证明独立 getter 的本机成本，不是全应用启动、首次主线程切换、全部档位、Release 或最低设备性能。

扩大回归 `/tmp/typebar-russian-regression-20261029.log`：1,117 项零失败／零跳过，XCTest 823.217 秒、驱动 839.000 秒，1,361 个非 Markdown 输入保持。既有语言、隐藏页面、输入、字段、回放、图表、配置、存储及新增 Russian 全部通过；原跨测试保存场景也通过。源证据检查确认 146 项所需测试全部通过。

未开窗 Debug 包检查 `/tmp/typebar-russian-package-20261029.log` 通过，44.568 秒，1,361 个输入哈希保持；严格签名、二十五项资源逐字节比较及固定参考原创性检查通过。临时包随检查清理，没有启动应用。推送前 main 为 `8c52fb13028f82fd8e8718d55cb7ed65463b034e`，开发分支前序 `bfe929cda8aa1b9d79ad162180e5d06b89b920b1`；开放 PR 为零，Actions 总数 826、最新 main 运行 39118939684 成功。本批只向 `native-parity-next` 批量提交，保留现有触发范围，不重跑 CI 或屏蔽通知。

原创性自测及固定参考扫描、配置／语言元数据无漂移、47 直接规格／119 原生符号／17 支持规格的行为链接审计通过；人工清单 1,452 项仅结构检查通过。实体键盘／IME、VoiceOver、全部组合和完整性能仍开放；不是完整客户端 6,751 项复跑，也不外推服务端通过，goal active。

相同扩大结构扫描下，具名 ScaleLexicon 路由由 129 项／1,560,763 声明位置降为 123 项／1,090,989，`/tmp/typebar-russian-all-scale-helper-audit-20261029.json`，TypingEngine SHA-256 `97b14206b658597f5ac75d86dc95012220a9fac22cbc14ec1fec8aa39fb2dd92`；无未解析数量或缺失生产路由。旧历史范围 82 项／438,685 不变，旧表之外余 41 项／652,304。此范围仍不覆盖其他构造器、基本池和语言质量，不能称为全部内容缺口总数。
