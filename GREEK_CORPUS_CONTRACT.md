# 现代希腊语独立原样语料

`LANG-GREEK-LITERAL-58`，起点 4e1af8d6，固定参考 91bd24bb8513785c7364cbea29296ff7adafac41。将四档 40,728 个含古字母 ϙ 的合成位置替换为独立词典中的原样现代希腊语形式，基础 30→209，全部 30 个旧自写词保留。五池共 40,937 个位置，基础⊂1k⊂5k⊂10k⊂25k。语言 ID、配置、引语和历史格式不改；Koine 与 Greeklish 的基本数组、Greeklish 生成器和四个规模入口逐字节保持，见 /tmp/typebar-greek-protected-variants-20261030.json。

## 固定来源与拼写边界

English Wiktionary 经 Kaikki／Wiktextract 后处理的 Greek JSONL：
https://kaikki.org/dictionary/Greek/kaikki.org-dictionary-Greek.jsonl
221,294,549 字节，SHA `acd0c0ead297157e4092934198bebd525f4cef6d4aea8361a56a6ecaadfb9696`，实际读取 85,425 个条目。https://kaikki.org/dictionary/Greek/index.html 报告 2026-10-25 提取、enwiktionary 2026-10-01 dump 和 81,938 个不同词头。词头数、读取条目数和展开的词形数是不同口径，不把后处理文件冒充完整原始 Wiktextract。

wordfreq 3.1.1 wheel SHA `4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473`，成员 wordfreq/data/small_el.msgpack.gz SHA `9ec327293a1657eac51518d6506e387dda453b548e506f47ef6e720592c1d9c9`。核对该固定发布的 preprocess.py／tokens.py：希腊语 NFC 文本按 Unicode casefold 建立查找键，故词尾 ς→σ，ΐ 的查找键会分解为 iota＋分音符＋声调。这里只对频率查询使用 casefold，不改写词表或未经修改器变换的提示；用户明确选择 Lazy／Backwards 时仍按既有规则变换。先行可行性脚本最初用原样 key 少计词尾 sigma 的观察，核对发布代码后纠正查找；不因此改写源词拼写。

仅取 lang_code=el 及明确的词汇词性，拒绝 romanization、模板和提取错误项；明确标为 misspelling／proscribed／nonstandard 的词形不选，全部词义均带这些标签的条目也不能提供普通练习词，有其他正常词义的条目仍可选。仅选择所需现代小写希腊字母，原样通过 NFC 检查；不做去声调、重新组合、多调制转单调制、大小写转换、词尾 sigma 替换、音译、合成词缀或长度填充。基础字符集为 32 项，1k 为 34 项，后三档为 35 项；各集合及每档最短／最长边界均达到只读保存的参考聚合。参考只读取身份、语言元数据、字符类别与集合、数量和长度，不读取或导出其词值。

初次仅按字母／长度预筛有 249,369 个字面形式，29,226 个有 casefold 后的整词观察；见 /tmp/typebar-greek-feasibility-20261030.json。新增明示标签排除后有 249,301 个字面候选。实际发布五池全部有整词观察，但这不是使用次数、语义质量或与参考分布相同的证明。选择先保留旧词／较小池，再按可观察 band 及字面顺序选集，并以真实词覆盖缺少的字符与长度边界，绝不修改词本身。

| 池 | 位置与整词观察数 | 原样字段范围 | 字符集大小 |
| --- | ---: | --- | ---: |
| basic | 209 | 1–12 | 32 |
| 1k | 993 | 1–16 | 34 |
| 5k | 4,963 | 1–20 | 35 |
| 10k | 9,936 | 1–21 | 35 |
| 25k | 24,836 | 1–21 | 35 |

逐词映射三列为 word、English Wiktionary sourceTitle、wholeTokenBand，保留原样词及词典词头出处；链接为 https://en.wiktionary.org/wiki/ 加 percent-encoded sourceTitle。band 不是次数，不以零或分段估计补缺失。当前全部 band 非空，不新增 TSV 行尾空白例外。许可页、About 和打包资源保留 English Wiktionary contributors／Kaikki.org 及 CC BY-SA 4.0 归属，并附固定 wordfreq 发布的完整许可。

## 不可变制品与验证

| 文件 | SHA-256 |
| --- | --- |
| Sources/Typebar/GreekCorpus.generated.swift | 09c349f3439d6fd802034fa3d5298ab89ba197e26e8318475699484a5b9b8034 |
| Resources/GreekCorpusSources.txt | d4293d9beacfb0f55073de7fbc97a9d3646aa88b78e7c2212fb9b6f823d455a2 |
| Resources/GreekCorpusNotices.txt | 6114b322cfea791f73db6deda897225cbe6b33889b6f83be1e51006573787ab2 |
| Compatibility/greek-corpus.json | 3ae9f0cf45b7d6770d38e11f1b41e0d5adf967d3dcfb9b6b95ae60af2f0243f4 |

Scripts/prepare-greek-corpus.py 提供普通／-O 八项合同、--check-bundled 及给定固定词典／wheel 的 --check。Unicode 15.0.0、msgpack 1.1.2 用于准备，不是应用运行依赖。代码内锁定所有制品及整个 manifest 的 SHA，修改 manifest 不能建立新信任。固定源完整重建比较通过，普通／优化模式八项合同分别通过；正常隔离副本接受，删除映射行、改 manifest、原生模板及许可四类篡改在 -O 下均拒绝，见 /tmp/typebar-greek-quality-mutations-20261030.json。

先行 /tmp/typebar-greek-red-20261030.log 一项六处失败：基础数量／唯一数 30／209，四档包含所需现代字母集外的合成标记；XCTest 1.111 秒、驱动 24.298 秒，输入保持。初次实现 /tmp/typebar-greek-focused-20261030.log 的 40 项全部通过、零失败／跳过，XCTest 66.789 秒、驱动 163.467 秒，非 Markdown 输入保持。覆盖所有基础词的输入／删除／重复、每个字符与长短边界的 No Space／Backwards／Lazy 输入、五池嵌套／指纹／原样来源和完整许可、五档旧提示 JSON／模型／回放；原有希腊布局、标点／数字／句子规则、Koine 及拉丁化乌克兰语回归也通过。五个真实隐藏希腊语生产页面分别完成 153 词准备及首词输入，没有启动主程序或可见窗口。

补充逐词标签审计在初稿中发现四个仅有被拒绝标签支持的来源对：βράδι／βράδυ、οχι／οχι、παππά／παππάς、παππάς／παππάς。/tmp/typebar-greek-quality-red-20261030.log 新增一项四处失败（XCTest 1.214 秒、驱动 24.143 秒），准备规则先行八项中的两项失败，见 /tmp/typebar-greek-quality-rules-red-20261030.log。随后修正读取器的形式标签与全坏词义过滤，保留混合有效词义的正向控制，不纠正或重写字面词形。固定源重新构建、八项普通／优化规则、捆绑检查与四类篡改拒绝均通过；/tmp/typebar-greek-quality-tag-audit-20261030.json 对最终 24,836 个来源的再审计未发现仅由这三类标签支持的匹配。这些机械检查仍不认证全部语义及规范质量。

最终 /tmp/typebar-greek-focused-quality-20261030.log 实际退出成功，41 项零失败／跳过，XCTest 67.064 秒、驱动 116.122 秒，输入保持。包含上面的新质量回归及所有既有定向范围。初稿 /tmp/typebar-greek-regression-20261030.log 虽有 1,268 项通过（XCTest 932.703 秒、驱动 948.857 秒），其制品含上述四个来源问题，不计为最终数据的验收；当前新一轮扩大运行将另记录。

当前真实隐藏 About 组件截图 /tmp/typebar-greek-about-20261030.png，SHA `8e2b93b0f956791de969435148a87b8c908de81dbd72d1c66d80e6bd7947648d`，已目视确认新增 Ελληνικά 来源与原样拼写说明可见，原 UKACD 显著归属保持；下方完整许可入口在此初始裁切边缘，截图不证明实体滚动、系统 sheet 或辅助功能验收。

最终扩大 /tmp/typebar-greek-regression-quality-20261030.log 实际退出成功：1,269 项零失败／运行时跳过，XCTest 918.263 秒、驱动 934.546 秒，非 Markdown 输入保持。同前缀 .evidence.log 正式确认 146 项必需来源方法通过。涵盖既有多语言语料／隐藏宿主、混排、弱点、候选／缓存、输入统计、历史／回放及配置／来源检查；不等于整个客户端或当前服务端的全部通过，旧完整基线不外推此次制品。

/tmp/typebar-greek-package-20261030.log 的当前 Debug 包、严格签名、37 份来源／许可资源逐字节核对及原创性边界检查通过，驱动 43.327 秒，输入保持。最终定向、扩大及打包三个成功作业的输入指纹再次与当前文件逐项比较一致，当前原生及主程序进程均为零。推送前 main=8c52fb13028f82fd8e8718d55cb7ed65463b034e、开发分支=4e1af8d622c59a5c53464b01d2575e18c75a4b97、开放 PR=0；Actions 共 826 次、最新 39118939684 成功。只合批推送开发分支一次，不改 main、CI 触发或通知偏好。人工键盘／IME、VoiceOver、实际字形与选择器、全部标点和修改器组合、语言／难度／分布质量及完整 Release 性能仍开放，不由数量或局部原生测试宣布等价。结构扫描 /tmp/typebar-greek-scale-audit-20261030.json 余 112 个直接具名 ScaleLexicon 路由、927,283 个声明位置，TypingEngine SHA `e00e18c77373113887d9c0a35c1c4237b6799f46ef358c5476f34d2c1d79f68b`；该扫描不覆盖全部构造器、基础池或实际词数。整体重写 goal 保持 active。
