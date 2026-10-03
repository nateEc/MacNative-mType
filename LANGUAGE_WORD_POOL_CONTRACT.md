# 普通语言逐词装饰与句子状态

376 个普通单语言词库的词数和计时主入口统一使用自有候选游标，保留整候选过滤、段内余词、全局词索引、实际前词和目标缓存。本次补齐语言标点、数字字形及跨重开的西班牙语标记；不声明原版词值、分布、全部 Funbox 或设备行为等价。

## 固定源码行为

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。[逐词生成](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L809) 在候选过滤之后依次处理大小写、Lazy、瑞士德语 ß、标点、英式拼写、数字覆盖及 Funbox。关闭标点时，German、Swiss German、code 和 Klingon 保留 ASCII 大写；Weakspot 取词钩子也保留候选大小写。只有 typing_of_the_dead 的元数据启用 originalPunctuation。

[语言标点](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L42) 按语言身份的首段决定，而不是按字符所属文字系统猜测。French 的问号、叹号、冒号和分号替换整词；Greek 的分号分支替换为句点，问号分支追加分号。Chinese 和 Japanese 使用相应宽字符及括号；Arabic、Persian、Urdu、Kurdish 的问号和逗号分支使用阿拉伯标点，但分号只有 Arabic 和 Kurdish 特殊处理。Nepali、Bangla 和 Hindi 的句点分支使用 danda。Greeklish、Pinyin、Pashto、Sanskrit 和 Urdish 不误入相似语言规则；Romanized 和词库规模变体沿实际身份处理。

首词／前词末尾 .?!؟ 触发大写，Georgian 例外；非 ASCII 句号和逗号不被当成 ASCII 条件。Turkish 在大写分支将所有 ASCII I 转为 İ。Russian 跳过单双引号，Ukrainian 和 Slovak 跳过单引号，但对应概率仍消耗。终止、括号和其余概率门槛及选择顺序保留此前公共规则。

Spanish 的标记在源码中属于模块运行态：开句抽取严格大于 0.9 时使用 ¿ 和待闭合问号，大于 0.8 时使用 ¡ 和待闭合叹号；未开启新标记不清除旧标记。终止分支只消耗门槛，不额外抽取终止符；存在标记时追加并清除，没有标记则原词不变。新生成、其他语言和缓存重复不自动重置该标记。

[数字覆盖](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L957) 仅在随机值小于 0.1 时替换整词。Kurdish 使用 Arabic Indic、Nepali 和 Hindi 使用 Devanagari、Bangla 使用 Bengali 数字；Arabic、Persian 和 Urdu 仍是 ASCII 数字。转换辅助函数位于固定 utils/misc.ts；独立实现用 Unicode 数字区段，不导入上游内容表。

## 原生运行态与兼容边界

GeneratedCandidateContinuation 从现有自有 IndexedLexicon 取词；四类条目仍使用完整自有候选段，不退回扁平 token。其余普通池按自有形态发出段内词，候选比较先 Lazy，瑞士德语转换在装饰之前。两种混合语言、自有特殊生成流、引语、自定义和外部文本仍保留各自入口，旧辅助 API 不因此宣告全部重写。

PoolWordDecorationState 是值拥有的短暂标记。游标每次生成更新它，缓存读取不更新；TypingSession 暴露最新状态，工厂即使首批有限词耗尽、游标被丢弃也保留它。SwiftUI 的运行态在重置、外部内容替换和重复练习时携带最新标记；旧缓存目标不重新装饰，缓存耗尽后的新词使用最新标记。不使用共享可变单例，也不将标记持久化或在应用重启后恢复。

无设置字段、SwiftData 模型、服务协议或归档版本变化，正式归档仍为 22。旧保存提示和固定成绩不重新生成或回算。本次影响未来练习的生成过程，不需要数据迁移；真实旧库、旧二进制共存和降级未验。

## 行为与复核证据

先行七项测试编译夹具修正后实际产生 492 处失败断言，0.688 秒，日志 /tmp/typebar-language-pool-red.log；编译错误不算产品红测。接入后的相关 61 项零失败，8.362 秒。风险复核扩充至十三项新增，含 376 个普通身份的确定数字路由、标点替换与排除、Turkish／Georgian、German／Swiss German／Klingon 大写、Lazy 比较、西班牙语跨语言／跨重开／缓存／数字覆盖状态，以及 Hindi 101 词无空格的实际目标完成、归档和重复。扩大回归 60 项零失败，58.479 秒，新增十三项 0.205 秒；两个相关集合重叠，不相加。日志 /tmp/typebar-language-pool-focused.log 和 /tmp/typebar-language-pool-expanded.log。

Scripts/check-source-code-decoration.mjs 执行完整实际 utils/misc 模块，合计十一模块；新增 62 组语言夹具通过（/tmp/typebar-language-pool-source.log），此前所有代码、条目、缓存、前瞻和英语夹具仍通过。词字符串、rank、配置、输入队列和 DOM 依赖是明确自有适配，其他未用依赖调用会抛错；源码及词库资产不保存进原生项目。探针不是完整浏览器、上游测试套件或设备验收。

实现、夹具和探针冻结后的完整串行门禁成功退出：客户端 2584 项零失败，471.207 秒，其中可选十万词耐久默认跳过一项；服务端 145 项零失败，1.460 秒。随后以 TYPEBAR_ENDURANCE_TESTS=1 显式单独执行该项，十万词实际完成，零失败／零跳过，145.189 秒；不把默认跳过冒称为门禁内执行。旧回放 12000 次组合字形删除双投影为 0.025275 秒。这是自定义顺序流与旧回放的有界基线，不证明新普通语言游标的十万词缓存内存或性能。日志 /tmp/typebar-language-pool-full-gate.log、/tmp/typebar-language-pool-client-complete.log、/tmp/typebar-language-pool-service-complete.log 和 /tmp/typebar-language-pool-endurance.log。

固定参考、元数据、原创边界、801 个唯一人工场景结构与未打开应用包检查通过。只使用内存库客户端、串行服务测试及未开窗包，不启动 Typebar、不播放声音、不操作账户或部署；人工场景仍待验收。Swift 6.2.4、macOS 26.1（25B78）、arm64；真实背景成绩路径单独检查，环境隔离变量不替代这项检查。完整检查后仅更新说明，没有改被测代码或夹具。十一模块装饰探针最终重跑通过（/tmp/typebar-language-pool-source-final.log），4＋9＋10 组反池与生成顺序探针也通过（/tmp/typebar-language-pool-order-final.log）。

源码驱动、行为优先与局部简洁实现限定本次改动；会话内决策、迁移和风险复核重点检查有限首批丢游标、旧缓存覆盖新标记、身份前缀误匹配和数字覆盖之后的标记。本次没有独立评审。文档写作复核保留自动证据与人工待验收的区别。

## 剩余工作

源词值／分布、原版 66 个多词池的内容身份、Polyglot 和外部／自定义流、旧整批辅助 API、全部 Funbox 组合、英式字典身份、原始捕获／Unicode／live-cache 与浏览器异步、GUI／IME／VoiceOver、真实旧库／降级、长期缓存内存与性能、主题身份及服务部署仍开放。376 个入口接线不是完整内容或设备等价；94 配置键与部分 Funbox 总体覆盖不升级，完整 goal active。
