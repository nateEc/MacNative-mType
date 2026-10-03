# 生成词前瞻队列与逐词补题

普通词、代码和四类普通条目、自有生成流现在默认生成 100 词，成功词导航时补一个词，而不再等到 200／500 词批次边界。专注当前词与未来词模式覆盖首批为 1–4 词；重复练习继续复用实际已生成目标。本增量对齐模型的补题窗口，不宣称浏览器异步时序或全部词源等价。

## 固定源码合同

只读参考固定为 91bd24bb8513785c7364cbea29296ff7adafac41。[getLimit](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L428) 默认 100，有限词数截断；显示全部有限词使用完整预算，toPush 属性之后覆盖为 1–4，再受预算限制。[addWord](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L571) 使用导航之前的活动词索引：队列词数减去该索引加一，只有严格大于前瞻 bound 才跳过，否则在有预算时取一个词。默认 bound 为 100，toPush 为首批量减一；全部生成后移除最后词的提交符。

[词导航](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/word-navigation.ts#L34) 发起补题后推进活动词，仅队列末词等待补题完成。这是发起与完成的区别，不把同步原生路径称为微任务／DOM 时序等价。pullSection 的不足 20 词补整段另有分支，本轮未对齐。

## 独立原生实现

GeneratedPromptChunkPolicy 默认上限改为 100，限时不再按估算 WPM 生成 300–500 词，visibility 优先覆盖 1–4。有限完整预览保留十万词内存上限及超限提示。普通词／生成流工厂单词续接，不再 priming 第二批；代码／条目正常初始化生成首批，导航请求 maximumWordCount 为一，段内余词保留。

TypingSession 在有效输入完成实际词导航后、终端 Burst 判断之前，使用导航前索引核对 bound 并追加一词。新生成读取刚更新的 Weakspot 簿，缓存不取样或变换。普通首批与非末词保留提交 SPACE；代码游标的批首 SPACE 在前一个提交已存在时只去掉这一枚，避免空字段。末词不加多余 SPACE，下划线／无空格保留实际目标和隐藏目录。单词续接保留最近两词，不能丢掉较早词。

前进到空 Morse 目标仍执行本次前瞻补题，但不跳过当前空词，后续尝试不能假装完成它。既有末端回退保留给不安全字形边界或手工短提示，不伪造成功导航。外部提供者和自定义词流未套用本生成游标，仍须分别对齐。

## 行为与风险证据

GeneratedLookaheadTests 新增十三项。首轮九项有 38 个有效失败断言（/tmp/typebar-generated-lookahead-red.log），首版九项通过。扩大回归暴露旧 200／500 首批期望，并因旧索引越界退出；不把退出称为通过。按固定合同更新七份旧夹具，保留完成、错误、词界、归档和重开断言。手工代码游标显式生成开头，避免零生成计数与四词提示混用。修正后 133 项零失败，17.219 秒。

复核另外检查回退重提交的闭区间边界，以及 1001 词无空格完成和缓存重开。四处初始失败来自把整词删除误当只删提交符，改用实际单字符退格，不计产品反例。空 Morse 字段两处断言独立复现（/tmp/typebar-generated-lookahead-empty-red.log），根因为导航后套用禁止在当前空词尝试的守卫；仅移除补题入口守卫，不改空词输入保护。最终十三项与相关 209 项零失败，24.802 秒（/tmp/typebar-generated-lookahead-expanded-final.log）。1001 词完成及重开用例 7.524 秒，仅证明该有界引擎路径，不是长期键盘、缓存内存或单词补题后长程性能验收。

Scripts/check-source-code-decoration.mjs 完整载入九个实际模块，新加入 test-logic 和 word-navigation。启动事件、DOM、队列、索引和 rank 为明确自有适配，不执行浏览器或实体捕获。14 组新夹具验证默认／有限／whole／visibility 限制、闭区间前瞻、单词追加、导航／末词等待及最终耗尽。前三次未完成执行定位到 getCurrent、纯视觉 Funbox 无函数对象及最后提交符适配缺项；补齐适配后原断言通过，不计产品红测。既有 48＋15＋12＋4＋4 组保留通过（/tmp/typebar-generated-lookahead-source-fourth.log），不复制源码或词值进原生应用。

首次完整门禁实际运行客户端 2558 项，三项旧夹具共九处失败，618.211 秒；服务和打包未继续运行。137／153 词夹具把首批当全部，501 词夹具把两次输入当完整测试。已按真实总预算输入满 137／153／501 词，保留零错误、全部源词、终词和归档断言；501 词的尾词提取改用已输入长度而非开头长度，初次修改仍有五处夹具失败，不计产品反例。最后 28 项定向回归零失败，10.743 秒（/tmp/typebar-generated-lookahead-post-full-focus-final.log）。首次门禁与完整客户端失败日志为 /tmp/typebar-generated-lookahead-full-gate.log 和 /tmp/typebar-generated-lookahead-client-first-complete.log，不掩盖为通过。

修正夹具后的完整串行门禁成功退出：客户端 2558 项零失败，617.538 秒；显式十万词耐久 144.628 秒，旧回放 12000 次组合字形删除的双投影基准 0.026051 秒。服务端 145 项零失败，1.562 秒；固定参考、元数据、原创边界、799 项唯一人工场景结构和未打开应用包检查通过。完整日志为 /tmp/typebar-generated-lookahead-full-gate-final.log、/tmp/typebar-generated-lookahead-client-complete.log 和 /tmp/typebar-generated-lookahead-service-complete.log。本轮性能数字不证明生成词长期缓存内存或混合路径性能等价。

只用内存库客户端测试、串行服务测试及未打开应用包；不启动 GUI、不播放设备音频、不操作账户、不部署。真实 local-practice-background 路径单独检查；799 项人工清单仅新增待验收场景，结构校验不是设备通过。Swift 6.2.4、macOS 26.1、arm64；完整门禁之后仅更新说明，未改被测实现、探针或夹具。九模块探针重跑通过（/tmp/typebar-generated-lookahead-source-final.log），另保留 4＋9＋10 组生成顺序／代码池探针（/tmp/typebar-generated-lookahead-order-final.log）；人工清单、原创边界及差异格式复查通过，参考固定且干净、Typebar 图形进程为零、真实背景成绩路径不存在。

## 兼容与剩余工作

没有新增持久设置、SwiftData 字段、评分保存、服务协议或归档字段，正式格式仍 22。新内存尝试使用新窗口，旧提示、日志和固定成绩不回算。恢复旧实现只回退新会话生成策略，无数据迁移；真实旧库／旧二进制混用或降级未验。

源码驱动、行为优先、简洁局部实现及会话内决策／迁移／风险复核限定本增量；根因调试区分旧期望、适配缺项和空词守卫缺陷，写作复核区分导航发起与异步完成。不是独立审查。

后续优先核对普通候选取样、逐词标点与数字装饰，避免把初始整批格式化规则用于每次一词续接。其他普通多词源、外部／Polyglot、自定义词流、pullSection、原始 live-cache、Unicode／半代理及完整 Funbox 组合未关闭。GUI／IME／VoiceOver、浏览器微任务、旧库／降级、长期缓存内存与长程性能、源词库／随机分布、主题身份和服务部署仍开放。94 配置键及部分 Funbox 总体覆盖不升级，完整 goal active。
