# Esperanto 十二档独立词形与 X／H 拼写

`LANG-ESPERANTO-SCALES-50`，起点 `022d476d6fddabd3101b4f7af188394112dcd261`。移除十二档 `esperantoScaleLexicon` 的字母编号／重复 q 占位，共 216,619 个候选位置。三个基础入口各 35 项自写词保持原哈希，仍少于参考各 200 项；完整重写目标保持进行。

## 实际来源和候选选择

固定 Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41` 仅供行为、元数据及自动聚合审计，不读取或导出参考词值。独立字典为 [Kaikki Esperanto 下载页](https://kaikki.org/dictionary/Esperanto/index.html) 链接的 English Wiktionary **postprocessed** JSONL：

- `https://kaikki.org/dictionary/Esperanto/kaikki.org-dictionary-Esperanto.jsonl`，2026-10-29 下载，173,562,908 字节。
- SHA-256 `564df5523507921c3d6b2f94c49418a3ace682671e7425ae7aa4652ad5fcfc1b`。不是 Esperanto 版 Wiktionary 原始提取，不把原始下载页的日期当作此文件版本。
- 仅接受 `lang_code=eo`、适用词类和实际 headword／forms，NFC、小写、Latin 字母；排除元数据、模板、romanization、class、error-* 标签和 name／prefix／suffix 等入口。合格字面词形 195,762 个，最长 21 字符。释义、翻译、例句、音频、图像与原始文件不随包发布。

固定 wordfreq 3.1.1 **没有** Esperanto 成员，不能据此声称有通用词频。先核实的 Tatoeba CC0 快照仅 370 句／995 个字典词形交集，不足以支撑十二档，未用于最终产物。实际排名使用 [Tatoeba Esperanto detailed export](https://downloads.tatoeba.org/exports/per_language/epo/)：

- `https://downloads.tatoeba.org/exports/per_language/epo/epo_sentences_detailed.tsv.bz2`，2026-10-29 下载，17,537,801 字节。
- SHA-256 `c7c3d234e5156596028a0a79ed669b137538966a8058373494e0c7836178ea7d`。
- 823,873 个唯一句子 ID；949 个 owner 标识（含未归属 `\N`），5,844,336 个 Latin 字母 token、157,717 个不同 token；与独立字典交集 50,036 个词形。

只选**同时有字典字面形式和实际句子观察**的候选。计数前做 NFC／小写，标点（包括连字符／撇号）分开字母段；不声称这是语言学上完美的词边界。按观察次数降序、同次数字面 headword 优先、最后按拼写排序。保留八个字母练习词，以及已有最短和最长字段，然后重新按同一排序排列。词频只反映这个句子语料，翻译偏差、重复句式、个人贡献集中度和稀有词质量仍待审校。

自写转换将 ĉ／ĝ／ĥ／ĵ／ŝ／ŭ 分别映射为 X 的 cx／gx／hx／jx／sx／ux、H 的 ch／gh／hh／jh／sh／u；H 的 ŭ 不添加 h。H 规则依据 [Akademio 的拼写说明](https://www.w.w.akademio-de-esperanto.org/oficialaj_informoj/oficialaj_informoj_6_2007.html)，没有复制其正文或资产。若输出碰撞，保留排序最优的实际原词及其观察数，**不相加伪造词频，不尝试无歧义反向转换**；不足时失败，绝不补编号。

## 覆盖与明确差距

| 系统 | 档位 | 唯一候选 | 当前最长／参考最长 | 当前非 ASCII 项／参考项 |
| --- | --- | ---: | --- | --- |
| 原字母 | 1k | 1,000 | 15／15 | 140／137 |
| 原字母 | 10k | 10,000 | 17／17 | 1,526／1,560 |
| 原字母 | 25k | 24,998 | 17／17 | 3,924／4,528 |
| 原字母 | 36k | 36,342 | 19／40 | 5,739／6,843 |
| X | 1k | 999 | 15／15 | 0／4 |
| X | 10k | 9,993 | 17／17 | 0／38 |
| X | 25k | 24,970 | 18／18 | 0／213 |
| X | 36k | 36,296 | 19／40 | 0／277 |
| H | 1k | 999 | 15／15 | 0／4 |
| H | 10k | 9,969 | 17／17 | 0／38 |
| H | 25k | 24,922 | 18／18 | 0／213 |
| H | 36k | 36,131 | 19／40 | 0／277 |

各档最短均 1，全部为小写字母，无标点、数字、空格或合成占位。当前合格观察字典池没有六个 Esperanto 字母之外的非 ASCII 字母，因此 X／H 选集为 ASCII；**参考额外重音／其他字母覆盖及大档 40 字符边界未交付**，没有复制原版异常词或造词凑统计。移除占位不等于无功能损失，不能把这些测试改名为原版形状等价。

保留十二个 ID／显示名、Lazy Latin 资格（仅原字母支持）、Zipf supported／unknown 元数据、默认多语排除、既有 en-US 语音／en 百科及引语路由。独立排名不用于擅自改写原版未知 Zipf 声明。历史配置、捕获提示、事件与冻结指标不回算，无数据库迁移。

## 复现和交付

标准库准备器固定 Unicode 15.0.0，不联网、不导入 wordfreq；应用只有按需静态 Swift，无 Python 或词典运行依赖。`Compatibility/esperanto-corpus.json` 记录逐档词数据哈希、来源、形状及可用容量。108,769 个去重的系统／拼写条目有原词、真实词典标题、实测次数和首次观察句子 ID，提供词典贡献者历史及句子页 URL 模板。

词典选择和转换按 [English Wiktionary CC BY-SA 4.0](https://en.wiktionary.org/wiki/Wiktionary:Copyrights) 署名；次数来自 [Tatoeba CC BY 2.0 FR](https://en.wiki.tatoeba.org/articles/show/using-the-tatoeba-corpus)，完整固定快照 owner handles／主页链接及未归属提示随许可文件交付。只分发派生词形和次数，不分发句子。About 新增来源说明，第十四个本地许可文档；来源映射与署名随包，共二十一项资源逐字节比较。

发布 pin 独立于可变 manifest：Swift `9ddab7089c18c3a47975057712629ce0d95b4b592ee325410ca82fe61bf15fb5`，署名 `6f3173797b596e4cb3c69f1cfda4af059f40bb79e20807ca71eeb72ac3b9ce7f`，来源映射 `a69fa7d10e8d4a88c9f58a49bee8ac0b747c172165c77afa2c320bf761058e70`。九项准备合同在正常／优化模式通过；完整固定源重建已通过。正常／优化模式均拒绝截断署名、删除来源项、修改词值后重算 manifest 哈希及错误字典 pin，反例记录 `/tmp/typebar-esperanto-negative-checks-20261029.json`。

## 原生验证进度

旧实现先行一项测试出现 36 处预期失败，十二档均缺 amiko／ĉielo／aŭtuno 的对应拼写，`/tmp/typebar-esperanto-red-20261029.log`：XCTest 2.015 秒、驱动 27.219 秒，非 Markdown 输入哈希保持。

最终定向 `/tmp/typebar-esperanto-green-20261029.log`：12 项零失败／零跳过，XCTest 11.225 秒、驱动 142.174 秒，非 Markdown 输入哈希保持。覆盖全部逐档词数据哈希、三个基础池／默认多语、六字母的实际工厂输入／删除／简化输入资格／No Space／重复、最长字段的 Backwards、153 词续批和旧合成提示 JSON／模型／冻结指标／回放，另含身份元数据和 About。

隐藏生产宿主 `/tmp/typebar-esperanto-host-20261029.log`：一项遍历十二档，XCTest 10.799 秒、驱动 14.671 秒，输入哈希保持。每档 153 词全预览实际调用生产准备器，验证成员关系、原生 NSTextInputClient 首词输入、接收器身份和仅准备一次；defaults 隔离／SwiftData 仅内存，不替代实体输入法。已查看实际隐藏 About 渲染，显著原始版权、Esperanto 独立来源和许可入口可读。

隔离 Debug getter 探针 `/tmp/typebar-esperanto-lazy-probe-20261029.log` 通过，驱动 2.306 秒。初始 RSS 5,760 KiB；原字母 1k 首次 0.000429 秒／6,192 KiB，X 10k 首次 0.003744 秒／7,024 KiB，H 36k 首次 0.013851 秒／10,160 KiB，暖访问约 0.000001084 秒。仅证明独立 getter 的本机测量，不代表全应用首次切换、所有档位、Release 或最低设备。

最终扩大 `/tmp/typebar-esperanto-regression-20261029.log`：1,085 项零失败／零运行时跳过，XCTest 701.814 秒、驱动 716.826 秒；146 项必需固定源码证据通过，全部 1,347 个非 Markdown 输入哈希保持。范围包括十二档 Esperanto／实际隐藏宿主、既有语料和多语、资格／全预览、配置／预设、历史／回放／指标及固定源码对照。它不是完整客户端／服务端全量验收，不改写历史完整客户端的 OCR 红例。

源码原创性自测／固定参考扫描、语言／配置元数据无漂移，以及 47 直接规格／119 原生符号／17 支持规格的行为链接审计通过。人工清单 1,448 项仅结构检查通过，新增两项保留待实体验收。

Debug 包 `/tmp/typebar-esperanto-package-20261029.log` 通过，驱动 43.235 秒、输入哈希保持；严格签名、二十一项资源逐字节比较、包资源边界和固定参考原创性检查通过，没有启动主程序。推送前核对 main 仍为 `8c52fb13028f82fd8e8718d55cb7ed65463b034e`、开发分支仍为起点，无打开的 PR；Actions 总数 826，最新 main 门禁 `39118939684` 成功。

未启动可见 Typebar 应用，真实键盘／IME、VoiceOver、全部组合及完整性能仍待验收。

当前原历史范围仍余 82 个直接合成入口、声明数量之和 438,685；复核 `/tmp/typebar-esperanto-remaining-synthetic-20261029.json`，TypingEngine SHA-256 `3aef72f8d8fb7137a5f9c6f730e0849bc62d55402d25601487907af3777544a8`。这个范围不覆盖全部语言内容问题，基本短词池、其他构造器及语言质量审校仍开放，完整 goal 未完成。

同一输入下扩大结构审计找到当前 139 个直接具名 ScaleLexicon 路由、声明数量之和 2,866,074；其中 57 个不在旧历史表，包含两组 Norwegian 共 1,305,311 个声明位置。具体边界和逐 helper 数量写入 LANGUAGE_CONTENT_BASELINE_20261029.md。该结果改变后续内容迁移优先级，不能把 82 个历史剩余项当作总账。
