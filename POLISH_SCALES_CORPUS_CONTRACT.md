# Polish 六档的独立词形、缩写与专名边界

`LANG-POLISH-SCALES-48`，起点 `0d2766e971172e72d2446669443d69a5da766fe7`。移除六档 `polishScaleLexicon` 的词根／编号、重复字母和伪装大小写，共 277,317 个候选位置。基本 Polish 仍保留原有 24 个自写词；它与参考基本池 183 项的内容差距仍开放，不把本轮规模档证据外推为整个语言已经对齐。

## 参考行为与独立数据

参考固定 Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41`，只读取行为和自动聚合属性，不导出／复制词值。原版各规模档无空格或数字；2k 有三个小写缩写、四个句点，两项各一个句点、一项两个句点，均末尾有句点且无开头句点。旧实现只给假词添加连字符，没有交付这类缩写输入。

参考 2k／200k 分别有 50／38,649 个含大写的候选，其最长分别 10／22 字符；整体最长为 17／33。仅满足整体长度和大小写数量不能证明专名长度边界已交付。固定 `frontend/src/ts/test/words-generator.ts` 的 ASCII 大写条件及 lazy-mode.ts 证明：关闭标点时，非 German／Swiss German／Klingon／代码语言的含 ASCII 大写词先转小写；仅含 Unicode 大写的词不走此分支，然后再做有限 Lazy Latin 替换。例如 Polska → polska、Kraków → kraków／krakow，而 Łódź → Łódź／Lodz。原生既有规则保持。

独立来源为 [Kaikki 原始提取下载](https://kaikki.org/dictionary/rawdata.html) 的 Polish Wiktionary／Wikisłownik 版：

- 文件 `https://kaikki.org/dictionary/downloads/pl/pl-extract.jsonl.gz`，2026-10-29 下载，137,850,838 字节。
- SHA-256 `15bfa944d77f8cc25b3597c4c08c26025f33fbdc60b9f68be16b84874042453e`。
- 本次使用 pl 版原始数据，**不是** Kaikki English 版 Polish 网页所用的 postprocessed 文件；不能用该网页的提取日期给此快照背书。

排名来自固定 wordfreq 3.1.1 wheel，SHA-256 `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`；`wordfreq/data/large_pl.msgpack.gz` 有 453,320 个观察 token，成员 SHA-256 `fac63e49c49ea2e39dd8a48152d7e54cec0920abbc59993088063ed5d9b528c2`。不执行 wheel 内代码，仅用 msgpack 读取固定成员及 release credits。查排名时 case-fold，不改变词典拼写；无整体排名时用最罕见句点分段作估计，未知排后，不是纯频率截断。

只接受 `lang_code=pl` 的适用词类、NFC Latin 字母 headword／实际 forms，过滤元数据、模板、romanization、class 和 error-* 标签。小写和原有大小写形式分池，**不把小写词机械首字母大写成专名**；每个值归属真实 entry lemma，多归属按标题长度和字面序确定。释义、例句、发音、图像、音频和原始提取文件不随应用发布。

合格小写形式 879,810、原有大小写形式 69,422，足以支撑六档。2k 独立选用字典 headword `np.`、`m.in.`、`itd.`，不通过追加句点制造缩写；专名池明确保留 Polska／Warszawa／Kraków／Łódź。除整体最长字母词，还单独保留已有专名长度边界：2k 的 `Internecie` 为 10 字符，200k 的 `Południowoafrykańczycy` 为 22。200k 的真实最长字母词 `dziewięćdziesięciodziewięciolatce` 为 33 字符，没有合成拼接。

| 档位 | 唯一候选 | 当前长度 | 大写项／最长大写字段 | 句点候选／字符 | 当前非 ASCII 项 |
| --- | ---: | --- | --- | --- | ---: |
| 2k | 2,338 | 1–17 | 50／10 | 3／4 | 946 |
| 5k | 5,000 | 1–18 | 0／0 | 0／0 | 2,101 |
| 10k | 10,000 | 1–18 | 0／0 | 0／0 | 4,278 |
| 20k | 20,000 | 1–21 | 0／0 | 0／0 | 8,692 |
| 40k | 40,000 | 1–21 | 0／0 | 0／0 | 17,575 |
| 200k | 199,979 | 1–33 | 38,649／22 | 0／0 | 82,095 |

数量、长度、大小写和缩写字符形状与参考一致，不代表词值、词频、难度或分布等价；参考六档非 ASCII 项依次为 1,078／2,386／4,698／9,204／18,318／76,066，没有伪装成这些比例。提取错误、古词、借词、专名、口语和冒犯词仍可能存在，完整语言质量和分布验收开放。

| 产物 | SHA-256 |
| --- | --- |
| 原生 Swift | `b76a7a9539d0e1160c88ed80cc637fabaacaab9ffe1e630c4148c38f89c787ce` |
| 完整署名 | `0fbf25994170d9616c82a1379643a826f27c3783ee39c03ecff5daa4dd7d1a99` |
| 199,982 个唯一练习值的来源页映射 | `ab2970669aefae320181ddba3d516fb1f240298635797aabbf33e9262162f523` |

各档换行词数据 SHA-256 固定在 `Compatibility/polish-corpus.json` 和独立原生断言中。并集比 200k 多三个缩写；各档数量和不是去重词汇数。

## 原生交付和复现

版本 `kaikki-pl-20261029-wordfreq-3.1.1-v1`，准备器 SHA-256 `2e017f112ac962a14aa8ba301bf0cfaca2554328d2b90f74e9f508ee06fc80e2`。源准备要求 Unicode 15.0.0（本次 Python 3.12）、msgpack 1.1.2，不联网、下载或安装依赖：

```sh
python Scripts/prepare-polish-corpus.py --dictionary /absolute/pl-extract.jsonl.gz --wordfreq-wheel /absolute/wordfreq-3.1.1-py3-none-any.whl --check
```

逐字节重建四个产物；标准库 `--check-bundled` 仅作内部完整性校验，不代替来源重建。Kaikki 地址定期轮换，复现需要保存的该精确快照；不匹配新哈希时拒绝，不宣称该精确快照将长期在线保留。各档静态属性单独按需解析，应用运行不需要 Python、msgpack 或网络词典。

保留六个 ID／显示名、配置／预设／分享、pl-PL 语音／百科、未知 Zipf、Lazy Latin 和原有生成／大小写规则。24 项基本池 SHA-256 保持 `d1ea1c50df63426e521fc1bb5bf5a4fc66697a72df13139f68cf5350b689e711`，默认多语资格保持，不加入规模档。旧捕获提示、事件和冻结指标不回算，无数据库迁移。

按 [Wikisłownik 页脚所链接的 CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/deed.pl) 保留改编说明、署名、原页／贡献者历史 URL 模板和完整 wordfreq 来源说明；逐词映射使用 Polish 源页标题。About 新增 Polish 署名，许可阅读器新增第十二个 Polski 规模词库文档；大型映射不整段挂入 SwiftUI 文本布局。署名和映射哈希独立于可变 manifest 固定，不能靠重算清单掩盖截断署名。

## 先行证据和未完成范围

旧实现 `/tmp/typebar-polish-red-20261029.log`：一项测试 18 处预期失败，六档均缺 jest／się／człowiek；XCTest 2.520 秒、驱动 26.415 秒，输入哈希保持。

首次独立选集 `/tmp/typebar-polish-green-20261029.log` 的 14 项通过，XCTest 11.966 秒、驱动 118.921 秒，但按大写子池再审计发现最长仅 8／20，低于参考 10／22。新增独立用例在该选集出现四处真实失败，`/tmp/typebar-polish-cased-bound-red-20261029.log`：XCTest 1.639 秒、驱动 24.032 秒，输入保持；不是把已有绿灯当完成。随后保留已有长专名并强化准备／清单合同，九项自测在正常／优化模式通过。

完整 goal 保持进行；移除六个历史占位入口后，同范围余 99 个直接合成入口，声明数量之和 1,541,820。基本池、其余语言、词汇／难度／分布、全部组合、实体输入及完整性能等原目标范围继续开放。

最终定向 `/tmp/typebar-polish-green-v2-20261029.log`：15 项零失败／零跳过，XCTest 11.707 秒、驱动 62.176 秒，输入哈希保持。覆盖六档全部词数据哈希、基本池／默认多语、Polish 重音／ł、ASCII 与 Unicode 单独大写规则、三个句点缩写的输入／删除／No Space／Backwards／重复、整体及专名最长字段、六档 153 词续批／重复，以及旧合成提示 JSON／模型／冻结指标／回放。

`/tmp/typebar-polish-host-20261029.log`：一项通过（遍历六档），XCTest 5.954 秒、驱动 9.555 秒，输入哈希保持。每档 153 词全预览实际调用生产准备器，验证配置／按已发布 ASCII 规则处理后的候选成员、NSTextInputClient 首词输入、接收器身份及只准备一次。窗口隐藏，defaults 隔离、SwiftData 仅内存，不使用真实账号，不替代物理键盘／IME 终验。

独立 Debug 数据 getter 探针 `/tmp/typebar-polish-lazy-probe-20261029.log` 通过：初始 RSS 5,824 KiB；2k 首次 0.001017 秒／6,400 KiB，10k 首次 0.004794 秒／7,168 KiB，200k 首次 0.101868 秒／27,552 KiB，暖访问约 0.000001125 秒。仅证明测得小档 getter 不初始化大档及本机数据成本；不代表全应用启动、主线程首次切换、全部档位、Release 或最低设备性能。

最终固定源重建 `/tmp/typebar-polish-source-check-v2-20261029.log` 通过，30.868 秒；正常／优化模式的有效样本、截断署名、删除来源项、改词值后重算文件哈希、错误来源 pin 反例均符合预期，记录 `/tmp/typebar-polish-negative-checks-v2-20261029.json`。第一版的 33.095 秒重建和旧反例记录保留为阶段证据，不用于最终产物背书。

源码原创性自测／固定参考扫描、语言／配置元数据无漂移，以及 47 个直接规格／119 个原生符号／17 个支持规格的行为链接审计通过。人工清单 1,443 项仅结构检查通过；新增两项均保留待验收。已查看隐藏 About 的实际渲染，原显著版权、Polish 来源及许可入口完整。

最终扩大 `/tmp/typebar-polish-regression-20261029.log`：1,039 项零失败／零运行时跳过，XCTest 575.634 秒、驱动 592.178 秒；145 项必需固定源码证据通过，全部 1,332 个非 Markdown 输入哈希保持。包括 Polish 六档／实际宿主、既有语言池、身份元数据、生成／续批、多语、输入／修饰器、旧历史／回放、配置及固定源码轨迹；不代表完整客户端／服务端全量验收，也不改写历史完整客户端的 OCR 红例。

Debug 包 `/tmp/typebar-polish-package-20261029.log` 检查通过，驱动 42.458 秒，输入哈希保持；严格签名、17 个署名／来源资源逐字节比较及固定参考源码／包资源原创边界通过。全部 Swift 测试、数据探针及打包严格串行，未启动 Typebar 主程序；结束后 Typebar／xctest／swift-test 均无进程。

推送前零个打开的 PR；main 保持 `8c52fb13028f82fd8e8718d55cb7ed65463b034e`，开发分支起点 `0d2766e9`。只读 Actions 请求首次 TLS 失败后，同一地址有界重试成功，没有关闭证书验证；总数仍为 826，最新 main 运行 `39118939684` 成功。工作流只追加三条 Polish 准备／完整性检查，触发条件与通知偏好不变；仅集中推开发分支，不创建 PR、不手动重跑远端任务。
