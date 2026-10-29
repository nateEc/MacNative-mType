# Romanian 七档的独立字面词形

`LANG-ROMANIAN-SCALES-47`，起点 `6e943334c766ab8cf56d0c4bceda84f2ddb0a076`。七个规模档移除 `romanianScaleLexicon` 的词根／编号和重复字母占位，共 391,000 个候选位置。基本 Romanian 仍是原有 30 个自写词，不把本轮证据扩展为基本池已完整对齐；完整重写目标继续进行。

## 独立来源与选择

固定 Monkeytype 为 `91bd24bb8513785c7364cbea29296ff7adafac41`，仅审计实际行为和自动聚合属性，不导出词值。七档原版均小写、无空格／数字，非字母字符只含 ASCII 连字符；除了普通复合词，还包括末尾连字符和多个连字符。原版 200k 的最长纯字母字段为 31，最长连字符字段为 50，最多八个连字符。旧合成器只往假词末尾追加一个连字符，形状测试不能证明实际训练已交付。

来源为 [Kaikki Romanian 词典](https://kaikki.org/dictionary/Romanian/index.html) 的英文版 Wiktionary 提取。采用公开语言专用 **postprocessed** 文件 `https://kaikki.org/dictionary/Romanian/kaikki.org-dictionary-Romanian.jsonl`，不是原始全语 dump。2026-10-29 下载，434,336,969 字节，SHA-256 `ffe246750b41118a22f10f9a3e38fd2811528b6a850bf433104da297d1767b9d`。来源页标注 2026-10-25 提取、enwiktionary dump 日期 2026-10-01；后处理源可能有附加信息，本项目只使用字面词形和其条目标题，不复用释义／例句／图像／音频／发音或后处理的其他内容。

独立排名仍使用固定 wordfreq 3.1.1 wheel，SHA-256 `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`；本语言只有 `wordfreq/data/small_ro.msgpack.gz`，43,413 个观察 token，成员 SHA-256 `c17fe82952ed209bb45b95c56cb5c7f077ca921a84578c3807d48ddc1dd842e2`。大小写折叠仅用于查排名，不改原拼写；缺失整体排名时，以最罕见连字符组成部分作估计，未知排后，不能把 200k 都说成实际频率观察词。

词典只接收 `lang_code=ro` 的适用词类、NFC 小写 Latin 字母、内部或单个末尾连字符、长度不超过 50。过滤 table-tags、inflection-template、romanization、class 和所有 error-* 词形，排除开头／连续连字符、空格和数字。英文提取器的 `source=declension/conjugation` 表示表类型，**不是 wiki 页标题**；每个实际词形归属其真实 entry lemma，多个候选标题按长度和字面序确定，不受遍历顺序影响。

早期未过滤扫描得到 726,901 个值，含元数据和错误标记，不能视为可用词汇。最终规则排除 395,611 个元数据／错误出现记录，得到 598,095 个字母形式和 1,762 个带连字符形式。另一次只读 French 原始提取资格扫描得到 25,323 个 Romanian 形式，不进入最终选集或归属映射。

每档按独立观察／估计排序选字面形式；明确保留七个已有连字符例子 `într-o`、`s-a`、`mi-a`、`dă-mi`、`n-am`、`anti-`、`cha-cha-cha-uri` 及该长度上限内已有最长字母形式。这是公开的训练选集编辑，不是新造拼写或纯频率截断。标点来源不够时使用全部合格字面候选，再用真实字母形式达到总数量；不添加假词或拼接词根。

| 档位 | 候选 | 当前最长 | 当前连字符项 | 当前非 ASCII 项 | 原版最长／连字符项 |
| --- | ---: | ---: | ---: | ---: | --- |
| 1k | 1,000 | 19 | 21 | 285 | 19／21 |
| 5k | 5,000 | 23 | 95 | 1,749 | 23／95 |
| 10k | 10,000 | 25 | 202 | 3,622 | 25／202 |
| 25k | 25,000 | 34 | 474 | 9,473 | 34／474 |
| 50k | 50,000 | 25 | 957 | 19,810 | 25／957 |
| 100k | 100,000 | 31 | 1,762 | 41,701 | 31／1,912 |
| 200k | 200,000 | 47 | 1,762 | 93,148 | 50／3,891 |

每档唯一、小写、最短 1、无空格／数字，保留末尾及三个连字符的真实形式。200k 的 47 字符来自字典字面 `pneumonoultramicroscopicsilicovolcaniconiozelor`。**原版 50 字符、四／六／八个连字符字段、100k／200k 标点覆盖及词值／难度／分布等价仍未达到**；当前最长和标点差异不可说成没有功能损失。提取错误、古词、专名、借词、口语或冒犯词仍可能存在，语言审校开放。通用输入不因这次数据选择增加长度限制；独立长自定义输入支持不替代原版对应词汇练习验收。

| 产物 | SHA-256 |
| --- | --- |
| 原生 Swift | `a358ae630c5851339649ff054571d2eb068037dc531a7ac8f058e7848181f4a4` |
| 完整署名 | `10f2182bae65b351531bd71fabff0f2cb5b9d7d9265b397c8f00f2bbc5c5a36b` |
| 200,002 个唯一练习值的来源页映射 | `6e09fd1384e5a807584b21a573298c195593bcc707f8c88d1db35013b1f76d15` |

各档换行词数据 SHA-256 在 `Compatibility/romanian-corpus.json` 及独立原生断言中固定。并集多出两项是小档保留的实际长词不在 200k 的排名截断中，不把各档数量和当成去重词汇数。

## 原生交付、许可和复现

版本 `kaikki-en-ro-20261029-wordfreq-3.1.1-v1`，准备器 SHA-256 `5f43e106bef72ed13eb3d4d1dfb3b41f1804ef8ad1042fac16717a56ec977a22`。源准备要求 Unicode 15.0.0（本次 Python 3.12）、msgpack 1.1.2，不联网或安装依赖：

```sh
python Scripts/prepare-romanian-corpus.py --dictionary /absolute/kaikki.org-dictionary-Romanian.jsonl --wordfreq-wheel /absolute/wordfreq-3.1.1-py3-none-any.whl --check
```

逐字节重建四个产物，标准库 `--check-bundled` 只作内部完整性验证。Kaikki URL 会轮换，复现需保留该精确快照，拒绝不匹配新文件，不宣称在线长期留存已验证。原生运行不需要 Python、msgpack、网络词典或原始提取文件。各档单独静态属性按需解析，小档不初始化 200k。

完整 [English Wiktionary 许可说明](https://en.wiktionary.org/wiki/Wiktionary:Copyrights)、CC BY-SA 4.0 改编说明、wordfreq release credits 和逐词来源页／贡献者历史 URL 模板随包交付。来源映射用真实 entry lemma；About 新增 Romanian 署名，原生许可阅读器新增第十一个 Română 规模词库选项。映射不整段挂入 SwiftUI 文本布局。许可及映射哈希独立固定，不能靠重算 manifest 为截断署名背书。

保留七个语言 ID／显示名、配置／预设／分享、ro-RO 语音／百科、未知 Zipf 和 Lazy Latin；30 项基本池的 SHA-256 保持 `f671c8647acd6dc2581e0c94eb6ce739c1d8f4f349435262d1cf2950c7717128`，默认多语仍使用基本 Romanian，不加入规模档。旧捕获提示／事件／冻结指标不回算，无数据库迁移。

## 验证与未完成范围

旧实现 `/tmp/typebar-romanian-red-20261029.log`：一项测试 21 处预期失败，七档均缺少 și／țară／cuvânt，XCTest 6.382 秒、驱动 32.578 秒，全部非 Markdown 输入哈希不变。准备器八项自测在正常及优化模式通过。

完整 goal 保持进行；本轮只移除七个历史占位入口，剩余同范围 105 个直接合成入口、声明数量之和 1,819,137；范围外基本池／其他生成器和全量语言质量仍需逐项验收。

定向 `/tmp/typebar-romanian-green-20261029.log`：13 项零失败／零跳过，XCTest 33.585 秒、驱动 143.227 秒（含编译），全部输入哈希保持。包括七档全部词数据哈希、基本池／默认多语、所有 5,273 个跨档连字符候选位置的实际输入／删除／No Space／重复、ș／ț／ă／â 的原字形和 Lazy Latin、各档最长真实字段 Backwards／No Space、七档 153 词续批／重复及旧合成提示的 JSON／模型／冻结指标／回放。

`/tmp/typebar-romanian-host-20261029.log`：一项通过（遍历七个档位），XCTest 5.820 秒、驱动 9.380 秒，输入哈希保持。每档 153 词实际全预览调用生产准备器，验证配置／候选成员、NSTextInputClient 首词输入、输入接收器身份及仅准备一次。窗口隐藏，defaults 隔离、SwiftData 仅内存；不启动 Typebar 主程序或连接真实账号，不能替代物理输入／IME 终验。

独立 Debug 数据 getter 探针 `/tmp/typebar-romanian-lazy-probe-20261029.log` 通过，起始 RSS 5,744 KiB；1k 首次 0.000394 秒／6,288 KiB、10k 首次 0.003662 秒／7,168 KiB、200k 首次 0.089170 秒／28,064 KiB，暖访问约 0.000001 秒。证明测得小档 getter 不初始化 200k；不代表其他档的完整性能、整应用冷启动、主线程首次切换、Release 或最低设备。

固定源重建 `/tmp/typebar-romanian-source-check-20261029.log` 通过，24.434 秒；正常／优化模式的有效样本、截断署名、删除来源项、改词值后重算文件哈希、错误来源 pin 反例均符合预期，见 `/tmp/typebar-romanian-negative-checks-20261029.json`。发布归属 pin 不依赖可变 manifest 的自洽摘要。

源码原创性自测／固定参考扫描、配置／语言元数据无漂移、47 个直接规格／119 个原生符号／17 个支持规格行为链接审计通过。人工清单 1,441 项仅结构通过，新增两项保持待验收；已查看隐藏 About 的实际渲染图，既有显著版权及新增 Romanian 署名／许可入口完整。

扩大 `/tmp/typebar-romanian-regression-20261029.log`：1,026 项零失败／零运行时跳过，XCTest 548.775 秒、驱动 563.063 秒；145 项必需固定源码证据通过，全部 1,325 个非 Markdown 输入哈希保持。覆盖 Romanian 七档／实际隐藏宿主、既有语言池、身份元数据、生成／续批、多语、输入／修饰器、捕获历史／回放、配置及固定源码轨迹；不是完整客户端／服务端全量验收，历史完整客户端 OCR 红例不被本轮选择性回归改写。

Debug 包 `/tmp/typebar-romanian-package-20261029.log` 检查通过，驱动 40.465 秒，输入哈希保持；严格签名、15 个署名／来源资源逐字节比较及固定参考源码／包资源原创性边界通过。全部 Swift 测试、探针及打包严格串行，未启动 Typebar 主程序，结束后 Typebar／xctest／swift-test 均无进程。

推送前零个打开的 PR；main 保持 `8c52fb13028f82fd8e8718d55cb7ed65463b034e`，开发分支起点 `6e943334`。Actions 总数仍 826，最新 main 运行 `39118939684` 成功。工作流仅追加三条 Romanian 准备／离线完整性检查，触发条件和通知偏好不变；只集中推开发分支，不创建 PR、不手动重跑远端任务。
