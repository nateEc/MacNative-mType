# 乌克兰语 Latynka 独立改编语料

`LANG-UKRAINIAN-LATYNKA-57`，起点 fd6759ff；固定参考 91bd24bb8513785c7364cbea29296ff7adafac41。基础 27→199；1k／10k／50k 的 60,989 个 qz 占位位置替换为有出处的真实乌克兰语词形的明确拉丁化改编。总计四池 61,188 个位置，基础⊂1k⊂10k⊂50k，保留原语言身份、配置与回放格式。这里不是将拉丁形式冒充独立观察的原语料，也不宣称完整重写已完成。

## 规则与来源

独立阅读 Maksym O. Vakulenko 的研究《Reversible transliteration of the historical Ukrainian alphabets in the context of heritage preservation and linguistic technologies development》，DOI 10.32388/VH8DLJ，https://www.qeios.com/read/VH8DLJ/pdf 。Table 9 的现代字母部分位于 PDF 第 34–35 页；下载研究文件 810,616 字节，SHA-256 `b1cfb854a93130a2d8f0bea4c08d7e997a8568e8885b7bd1e9a6c520cf601fe0`。不把论文或其表格作为产品资源打包，不声称获得完整 DSTU 标准的认证。

自行实现现代字母转换，含 г→ğ、ґ→g、ї→ï、ж→ž、ч→č、ш→š、щ→ŝ、х→x 及 є／ю／я 的双字母形式。保留 й／ь 与上下文的区别：辅音后接 й、以及 й／ь 后接 а／е／у 时显式加分隔符。明确改编为 ASCII U+0027 标记，保留原文的 ASCII 撇号、数字和连字符；不将其说成论文印刷标点的字节复制。孤立软音符输出有独立标记，因不在练习字母集中而不选入；同样不选参考聚合字母集以外的其他大写附加符。前置可行性扫描 468,627 个独立来源形式，467,855 个合字母条件候选中未观察到转换重名，见 /tmp/typebar-latynka-feasibility-20261030.json；这不构成对任意文本可逆性的证明。

复用固定的独立两版 Wiktionary／Kaikki uk 词条读取器，而非参考项目的转换器或词值。读取器 SHA-256 `cc669764a43586326a9997356c34aa9254052510c68f6f7ee50828baa9fb0f13`，其两份原始下载、wordfreq wheel、注音重音移除策略与完整许可见 UKRAINIAN_CORPUS_CONTRACT.md。新增准备器不修改这些来源、已有西里尔词池或两种词尾池。参考仅读取身份／禁用简化输入标志、数量、字符交集及长度聚合，未导出参考词值。

另外核对《Місцеве самоврядування в Україні》所显示修订 oldid=48586475 中的 `адміністративно-територіальними`，转换后为 31 字符 ASCII `administratyvno-terytorialjnymy`。独立短摘录、原样词形与来源链接保存在 Compatibility/ukrainian-latynka-boundary-evidence.json；它不是完整下载页面或拉丁文字面用例，不通过拼接、变形或填充制造边界。字典与文本词形的选集改编保留 CC BY-SA 4.0、English／Russian Wiktionary 及 Ukrainian Wikipedia contributors 归属。

逐词映射七列为 Latin word、选入的 Cyrillic form、evidence kind、source title／URL、未改编原形、原西里尔整词 band、原西里尔分段 band。所有 Latin 形式均为改编；两种 band 都不是 Latin 使用观察，也不是次数。空字段表示无观察，不能补零。基本池 199 项的西里尔来源全是原样、整词有观察的形式，含原有 27 个自写西里尔提示的正确转换；旧 ASCII `bereh／yizha／spokii` 不继续冒充本规则拼写，但历史结果保留原文。

| 池 | 位置数 | 原西里尔整词有观察 | 原词注音改编 | 文本来源 |
| --- | ---: | ---: | ---: | ---: |
| basic | 199 | 199 | 0 | 0 |
| 1k | 1,000 | 1,000 | 32 | 0 |
| 10k | 9,998 | 9,997 | 2,600 | 0 |
| 50k | 49,991 | 49,767 | 25,135 | 3 |

四池各字符类别／ASCII 交集的数量及其最短最长边界与保存的参考聚合一致；元数据完整比对仍由原有 TypingEngineTests 保持。不同词值的具体字母频次、标点子组合、逐长度分布、真实 Latynka 使用习惯、语言质量及难度不据此宣布等价。例如原聚合有两个大写 Ğ，本池一个；不能用字母集存在或总数通过隐去此差异。

## 不可变制品与证据

| 文件 | SHA-256 |
| --- | --- |
| Sources/Typebar/UkrainianLatynkaCorpus.generated.swift | d7d132e094293c8833add720ef3cd48cec8a7a736f1d1ab2734f5c6d47b54ad4 |
| Resources/UkrainianLatynkaCorpusSources.txt | a05734486714c45d357d3262a184a2849deb3fbf4aac2404c5dd451a9cef9d49 |
| Resources/UkrainianLatynkaCorpusNotices.txt | db53b0d8054b33f20541dd93e85055667f315ee2f33ec73e0498312e90cf9666 |
| Compatibility/ukrainian-latynka-corpus.json | 709863e534fef4619c12ff87753f5abe1aa01744fefb4ec1773b48f5b5b277df |

Scripts/prepare-ukrainian-latynka-corpus.py 提供普通／-O 六项规则合同、--check-bundled 和显式固定两份词典及 wheel 的 --check。所有制品及整个 manifest 固定 SHA，另锁定读取器和短摘录；manifest 本身不建立新信任。完整固定源重建已通过；正常隔离副本接受，来源行删除、manifest、原生模板和短摘录四类篡改在 -O 下均拒绝，见 /tmp/typebar-latynka-mutations-20261030.json。TSV 空 band 的末尾分隔符通过 .gitattributes 仅对该映射文件保留，其他文件行尾检查未放宽。

先行 /tmp/typebar-latynka-red-20261030.log 一项 24 处失败，证明旧池基础数量与六个有独立来源的正确 Latynka 拼写缺失；XCTest 1.273 秒、驱动 25.286 秒，输入保持。第一次实现运行遇到新增测试误用 String.text 的编译错误，不计产品行为反例。下一次 24 项运行的 108 处失败为新测试错误地期待所有词保留原始大写；核对固定 words-generator.ts 确认普通未开标点练习仅在 /[A-Z]/ 命中时整词转小写。保留产品逻辑，纠正预期并补充十个大写词的普通／自定义／回放路径。

最终 /tmp/typebar-latynka-focused-verified-20261030.log 的 25 项通过、零失败／跳过，XCTest 56.987 秒、驱动 79.911 秒，非 Markdown 输入保持。覆盖四档／所有标点词实际输入、删除、No Space、Backwards、重复；全部基础词、各类别边界、嵌套与指纹、七列原词追踪和完整许可、旧 ASCII／合成提示 JSON／模型／回放。一个宿主方法依次挂载八个真实隐藏生产页面（含既有西里尔四档），各完成 153 词准备与首词输入。没有启动主程序或可见窗口。

额外 /tmp/typebar-latynka-source-case-20261030.log 用固定参考的完整函数执行 22 组来源轨迹：十个独立新词及一个自写的非 ASCII 大写控制，分别普通及倒序。实际结果确认上面的 ASCII 大写条件；候选、随机及运行平台仍为明确隔离适配器，不声称原词值、随机分布或浏览器绘制等价。

当前真实隐藏 About 组件截图 /tmp/typebar-latynka-about-20261030.png，SHA `ba98409801261c686e5f9bc4610fc5f79d43906ef66365aca120ee776c5234e4`，已目视确认 Latynka 改编及仅西里尔频率说明、完整许可入口可见，原 UKACD 显著归属保持。它不构成实体窗口／系统 sheet、VoiceOver 或全部许可页的人工验收。

扩大 /tmp/typebar-latynka-regression-20261030.log 已实际退出成功：1,253 项零失败／运行时跳过，XCTest 924.895 秒、驱动 940.791 秒，非 Markdown 输入保持；同前缀 .evidence.log 正式确认 146 项必需来源方法通过。包含既有多语言语料／隐藏宿主、混排、弱点、候选／缓存、原始输入统计、历史／回放、配置与来源检查。它不是整个客户端或当前服务端的全部通过；旧完整基线不能外推成此次制品的完整验收。

/tmp/typebar-latynka-package-20261030.log 的当前 Debug 包、严格签名、35 份许可／来源资源逐字节核对及原创性边界检查通过，驱动 42.833 秒，输入保持。定向、扩大及打包三个成功作业的输入指纹再次与当前文件比较一致；当前原生及主程序进程均为零。推送前 main=8c52fb13028f82fd8e8718d55cb7ed65463b034e、开发分支=fd6759ffbf63d1ee531f6a6ccd48449fdbbf29a5、开放 PR=0，Actions 共 826 次、最新 39118939684 成功。只合批推送开发分支一次，不改 main、CI 触发或通知偏好。人工键盘／IME、VoiceOver、真实选择器及显示、完整 Release／性能和其余语言内容仍开放。结构扫描 /tmp/typebar-latynka-scale-audit-20261030.json 现有 116 个直接具名 ScaleLexicon 路由、968,011 个声明位置，TypingEngine SHA `899c34a31d7c56f7e38e2851d185da64f80a16eee230fb1ee576c3dac7fe8a15`；它不覆盖全部构造器、基础池或实际词数。
