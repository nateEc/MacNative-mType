# 多语候选池与生成用主语言

后续[多语方向冲突与历史显示保护](POLYGLOT_DIRECTION_CONTRACT.md)已在新会话入口解析方向冲突并记录有效主语言；旧配置与实际目标不补造方向标记。本文件保留候选池阶段证据，设备和完整 Polyglot 仍未等价验证。

Polyglot 的词数和计时主练习现在使用完整自有候选的联合池，而不是把候选拆成独立 token 后按序号加数字或标点。联合池保留每词语言身份，逐词生成使用全局索引、真实前词及实际目标缓存；启用前的主语言作为可选配置元数据随新结果、预设和分享保留。本增量不宣告原版内容、随机分布、全部组合或设备等价。

## 固定源码行为

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。[PolyglotWordset](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/funbox/funbox-functions.ts#L159) 从字符串键映射建联合池并洗牌；[withWords](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/funbox/funbox-functions.ts#L653) 按所选语言次序建映射，重复完整候选保留首位置，但后一个语言覆盖身份。多词候选不预先拆平。JS 字符串键以原始单位区分规范等价但不同编码的词。

[逐词过程](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L809) 先整候选过滤与最近两词重抽，再发出段内词。关闭标点的大小写例外查询拆分后词的实际身份，未命中则用主语言。[Lazy 查询](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L397) 则要求当前字符串在映射中精确存在；小写后、拆分后未命中的词没有语言属性，不自动继承主语言的 Lazy。候选初次比较小写，重抽保留大小写，仍使用相同精确查询。

标点、原标点保留、瑞士德语 ß、数字字形及英式拼写仍按 Config.language 即启用前主语言控制，不按抽中的语言猜测。联合池不预换成英式词库；英式转换在逐词阶段、数字覆盖前处理。缓存重开仍执行建词池步骤，但已生成目标不重新抽取或装饰；缓存后才使用新池。

反写顺序有引用细节：[generateWords](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L655) 先反转主语言数组，再执行 Polyglot 的 withWords。虽然 withWords 忽略传入数组参数，它经由[缓存语言加载](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/json-data.ts#L113) 仍可能读到同一个已反转数组。因此只处理所选池中的主语言子池，不能把整个联合池再反一次；每词文本反写仍执行。

## 独立原生实现

NativePolyglotCandidates 用自有词库、代码候选和四类条目建完整候选映射，采用 UTF-16 单位键，避免 Swift String 规范等价比较合并不同编码。它保存首个词位置、最后的语言属性和独立洗牌。GeneratedCandidateContinuation 共用现有整段过滤、段内余词、Weakspot、实际前词、逐词数字／标点及缓存；Lazy 在精确属性查询后处理，后续变换不再按主语言重复 Lazy。反写只影响主语言子池与输出文本，不反整个联合池。

重复游标在保留目标缓存的同时重新洗牌后续候选池，缓存读取不消耗取词、大小写或装饰随机值。映射去重要求遍历本次联合池，新的主入口不再声称保持旧虚拟拼接池的按需内存属性；旧 PolyglotWordPool 辅助 API 的懒加载测试不能证明此路径的内存性能。

TestConfiguration 增加可选 polyglotBaseLanguage，仅 mixedLanguages 有效；未记录的旧配置保留 nil，不推测历史身份，新生成的缺省主语言为 English。SwiftUI 从既有 polyglotReturnLanguage 记录启用前选择，保存／应用新预设时可恢复这个字段。其他语言、现有两语交替扩展、自定义、引语、外部和特殊生成流不改入口。Polyglot 仍不计入本地 PB，不因新字段放宽资格。

这是可选配置 JSON 的加法，不增 SwiftData 实体列、全局设置键或服务协议。正式归档仍 22，旧配置缺省字段不补造，旧实际提示、日志和固定成绩不重新生成或回算；当前编码、分享与归档往返已测试，但旧二进制忽略新字段时的重建、真实旧库共存及降级未验，不保证降级后新生成语义相同。

## 行为与风险证据

先行一项测试实际两处失败，0.472 秒：旧工厂输出序号数字 1 而不是注入随机值对应的 90，且未消费抽取值，日志 /tmp/typebar-polyglot-candidate-red.log。初始十二项原生测试通过，0.020 秒；实际源码对照随后推翻反写顺序预期，日志 /tmp/typebar-polyglot-candidate-source.log。根因检查追到主语言缓存数组的引用关系，修改所属子池顺序，不把错误预期保留为合同。

扩大回归先有 86 项零失败，55.407 秒，包含全部 446 个可混合身份的有限完成与现有旧辅助 API。风险复核新增重开洗牌、主语言英式／瑞士德语、可移植分享、活动选择文档和 101 词无空格的真实目标／归档／重复。最终十六项新增及相关 89 项零失败，55.199 秒；日志 /tmp/typebar-polyglot-candidate-expanded-final.log。构造活动选择文档的编译夹具修正不计产品红测，两组回归重叠不相加。

Scripts/check-source-code-decoration.mjs 加入完整实际 Lazy 模块，合计十二模块；18 组新 Polyglot 夹具通过（/tmp/typebar-polyglot-candidate-source-second.log）。覆盖完整候选映射、重复身份、UTF-16 不同编码、语言属性查询、整段过滤、主语言装饰、反写子池及已缓存未来词。此前所有代码、普通、缓存、前瞻和英语夹具仍通过；词值、配置、rank、洗牌及 DOM 是明确自有适配，原版代码和词库资产不写入应用。原版浏览器随机数、网络与设备未执行，不把适配洗牌当完整 RNG 证明。

第一次完整门禁客户端 2600 项有两处失败，664.019 秒，未进入服务与打包。失败来自旧来源断言仍要求提前英式换库和俄语缩略词小写，并不接受 Twitch 词逐词小写；定向日志保留实际失败词。修正来源断言以自有原始候选的空格组件和 ASCII 大写触发的小写形式检查，不撤销自有来源、100 词首批与 153 词有限完成要求；另增 Twitch 标点开／关的确定性原生测试和两组实际源码对照。夹具构造曾遇到 Swift 链式 flatMap 的错误重载推断，改为显式集合循环；这是测试构造失败，不算产品红测。

最终 17 项新增与修正旧来源测试合计 18 项零失败，0.710 秒（/tmp/typebar-polyglot-candidate-membership-final.log）；12 模块的 Polyglot 对照增至 20 组（/tmp/typebar-polyglot-candidate-source-final.log）。此前 89 项回归保留阶段证据，与 18 项重叠不相加。实现、夹具和探针再次冻结后完整串行门禁通过：客户端 2601 项零失败、零跳过，663.508 秒；服务端 145 项零失败，1.554 秒；802 条人工场景结构、固定参考与原创性审计、未开窗 macOS 包资源边界检查通过。最终日志 /tmp/typebar-polyglot-candidate-full-gate-second.log；清理前捕获的客户端／服务／打包日志为 /tmp/typebar-polyglot-candidate-second-client-tests.log、second-service-tests.log 与 second-package-check.log（相同前缀）。

同一通过轮的十万词耐久实际 144.120 秒，旧 12000 次组合书写簇退格双投影 0.024845 秒；不是 Polyglot 联合池长期内存、浏览器或实机性能证明。门禁只使用内存库客户端、串行服务测试及未开窗包；不启动 Typebar、不播放声音、不操作账户或部署。人工清单仍待验收；门禁前后图形进程为零，真实背景成绩路径单独检查不存在，没有删除用户背景数据，不用隔离变量替代路径检查。

源码驱动和行为优先检查限定实现；根因调试纠正源码反写顺序误判，会话内风险与迁移复核检查去重身份、二次 Lazy、重复换池和旧缺省字段。文档写作复核区分自动与设备证据；不是独立评审。

## 剩余工作

原版词值与分布、完整 Shuffle／Zipf 概率、浏览器 memoized 语言数组跨多次反转的累计状态、语言加载失败及不足两种时的禁用流程、所选池与主语言方向冲突时的自动切换与终止后重新生成、主语言为代码时的输入键及其他非生成消费者、全部 Funbox／自定义及外部词流、旧整批辅助 API、原始捕获／Unicode／live-cache、GUI／IME／VoiceOver、真实旧库／降级、联合池大规模内存与长期缓存、主题身份及服务部署仍开放。默认正常池和缓存换池的有界对齐不替代这些要求；94 配置键与部分 Funbox 总体覆盖不升级，完整 goal active。
