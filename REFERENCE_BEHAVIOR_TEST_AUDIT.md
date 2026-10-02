# 固定参考行为测试盘点

2026-10-02 手动词回改边界增量（最终门禁已通过）：固定 [删除前守卫](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/before-delete.ts#L15-L73)、[删除事件](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/delete.ts#L11-L91) 与 [回开前词](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/word-navigation.ts#L98-L138) 以实际拼写保护正确已提交词。原生普通词回改改用已有精确身份，规范等价但不同拼写的错误词不再被锁住；有来源的安全 no-space 词界参与手动退格／整词删除，整词删除只清当前词或经守卫允许回开的前词，不再沿空格扫描清掉整个扁平历史。历史尝试错误不解锁已经正确重打的词。confidence on 禁止跨词回开、max 禁止手动删除，freedom 允许正确词回开；固定 [设置覆盖](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/config/metadata.tsx#L465-L558) 证明正常 freedom／confidence 互斥，保留既有配置规范化，不把人为冲突运行态当正常用户反例。

新增 `WordBoundaryDeletionTests` 最终 17 项；首轮 14 项有 45 个有效先行失败断言，无编译／非法组合夹具错误。首版相关 174 项零跳过／零失败（约 2.31 秒），有界复核补旧长度词界、实时切换和百词后回开，最终相关 243 项零跳过／零失败（约 3.25 秒），新 17 项约 0.04 秒；本过滤不含十万词，不据环境变量声称耐力已执行。最终完整门禁通过：客户端 1701 项零跳过／零失败（约 357.73 秒）、服务端 131 项零失败（约 1.38 秒）、固定参考／原创性及兼容审计、687 个唯一人工场景清单和未开窗应用包检查全部通过；显式十万词实际执行约 37.83 秒。涵盖预组合／分解／重排／Angstrom 错误词回开、正确词和纠正后的保护、no-space 当前／前词清理、confidence／freedom、空目标 Morse 屏障、旧长度元数据、真实 factory／重复／百词续读、回放／正式归档及不开窗原生 NSResponder 删除命令。两个人工场景增加到 687 个，仍待设备验收。

固定原版实际 onBeforeDelete、onDelete 和 goToPreviousWord 在只读检出的 Node v24.19.0 内存探针执行：é 对 e＋重音错误词允许回开且保留 é；正确 ab 的 no-space 回开被拒，ab／cx 的整词回开和 ab／c 的当前词清理都保留 ab；confidence on 拒绝错误前词回开，合法 freedom off-confidence 允许正确前词清理。DOM 值／假前导空格、事件历史、UI 与活动索引依赖显式提供，不是完整浏览器、上游 Vitest、物理键盘或设备证据。原版守卫在冲突 max＋freedom 状态的优先序也观察到，但正常设置互斥，未改变导入／实时设置政策。

迁移／有界会话内决策和风险复核：复用既有真实词界、自动删除机械动作与逐删除回放格式；无字段、配置、结果、回放、归档或 SwiftData 版本变化，不写真实库、不回算旧快照。不伪造已丢失的词界，不关闭无元数据融合、不同 UTF-16 长度的错误输入导航、逐单元视觉替换／停止／删除恢复、整词删除的原版事件粒度、半代理／CRLF、原版滚出 DOM 的前词可用性、IME／设备缺口。自动硬删除、代码反缩进和空目标屏障由相关回归保留；新增人工场景只是清单，不是设备验收。未启动 GUI、不部署、不复用参考代码／数据／资产，Morse／Under／Backwards 及 94 配置键 91／2／1 的部分状态不升级，整体 goal active。使用行为优先测试、源码驱动、根因调试、决策／迁移／风险复核，不冒称独立评审。

2026-10-02 输入文本精确身份增量（最终门禁已通过）：固定 [输入拆分与验证](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts#L133-L374)、[显式视觉替换](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/strings.ts#L289-L351)、[精确词判定](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/validation.ts#L13-L98) 与 [难度／完成](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/fail-or-finish.ts#L48-L141) 不把 Unicode 规范等价自动加入替换表。原生独立比较实际 Unicode 标量／UTF-16 拼写，去除 Swift Character／String／Set 的规范等价泄漏；输入、错误显示、描述统计、词历史、提交守卫、难度与组合完成预判共用精确身份。已有 UTF-16 尝试统计不重复实现，明确允许的标点、空格、俄语替换及源准备 NFC 规则保持不变，Zen 保留自己的输入。

新增 `InputTextIdentityTests` 最终 21 项。首轮夹具遗漏 rules 的编译错误不计产品反例；校正词停止保留分隔符后，13 项有 123 个先行失败，其中 12 个来自整字符 no-space 停止夹具，不能证明原版逐单元语义，已弃用而不计缺口证据；其余 111 个为有效先行断言。首版相关 68 项有 1 个词历史夹具失败：正确重打不抹掉历史尝试错误，已保留历史并增加正确字形断言，不改产品迁就夹具。扩展相关 206 项零跳过／零失败通过（约 1.42 秒），初始有界复核 18 项通过（约 0.04 秒）；相关过滤不含十万词，不能据环境变量声称耐力已运行。覆盖预组合／分解重音、组合标记顺序、Angstrom、普通／custom 最终词、master／expert、同宽 no-space 提交、停止／删除错误、明确替换、quick-end、Zen、预判、纠正、回放及正式归档。固定原版实际 normalizeData、isCharCorrect、shouldGoToNextWord、难度／完成函数以及 onInsertText 在只读检出中用 Node v24.19.0 内存运行：自有 é 对 e＋重音保留原始错误输入，master 失败、expert 提交失败、word 停止保留错误分隔符、letter 停止拒绝、两类删除记录自动事件。输入 DOM／事件缓存、导航、UI 和 before-insert 守卫依赖显式桩；不是完整上游 Vitest、浏览器或真实 IME／设备证据。

随后第三次有界复核运行原版实际 onInsertText：自有规范等价重排 a＋两种重音＋末组合标记的四个单元判定为 true／false／false／true，master 仍 active。新增 3 项终端边界产生 3 个真实先行失败；独立引擎沿用已有准确率单元比较，仅把 master 终端检查改为最后单元，保留整字符的错误诊断。累计有效先行失败 114 个。最终相关 238 项零跳过／零失败通过（约 2.52 秒），包括已有 master／batch 测试；逐单元停止／删除恢复仍不关闭。首轮完整门禁客户端 1681 项零失败（约 358.20 秒）、服务端 131 项（约 1.42 秒）、685 场景清单及不开窗包通过，十万词实际约 37.89 秒，但在随后 master 修正之前，不替代最终门禁，最终完整重跑已通过：客户端 1684 项零跳过／零失败（约 357.50 秒）、服务端 131 项零失败（约 1.39 秒）、固定参考／原创性及兼容审计、685 个唯一人工场景清单和未开窗应用包全部通过；最终十万词实际执行约 37.84 秒。人工清单通过不是设备验收，早期门禁和失败夹具不混为最终证据。

迁移／有界会话内决策及风险复核：无字段、协议、回放、归档或 SwiftData 版本变化，不写真实库、不回算保存的旧统计；重新生成的回放字形／词诊断采用精确身份，不能声称所有历史派生显示毫无变化。原生仍以完整书写簇接收输入，这里不关闭不同 UTF-16 长度的游标、逐单元视觉替换／停止恢复、半代理、跨词融合／CRLF、完整 no-space 计数／历史、真实 IME 和设备缺口。未启动 GUI、不部署、不复制参考代码／数据／资产，人工清单待设备验收；Morse／Under／Backwards 部分状态和 94 配置键 91／2／1 分区不升级，整体 goal active。使用行为优先测试、源码驱动、根因调试及迁移／决策／风险复核，不冒称独立评审。

2026-10-02 引语融合续词与初始控制信号增量（最终门禁已通过）：复现 no-space 引语丢失安全书写簇词界后卡在第 102 个已生成词的问题。独立引擎在无分段元数据时，不再用零词索引判断预读预算；仅当实际可见前缀耗尽才请求一个新目标，正常安全词界仍按原有逐词窗口处理，空目标屏障仍先阻止扩展。没有把未知词界伪造成偏移或逐词历史。初始和续批时失去元数据的限定连续输入均可完成原始词池，实际目标、重复、回放与归档保持一致。

按固定 [初始化信号](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L475-L542)、[生成时控制符检测](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L721-L730)、[后续补词](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L571-L659) 和 [Return 守卫](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/before-insert-text.ts#L38-L40)，拥有原始池的引语只使用“选中原始源控制符＋实际初始生成控制符”的信号；在最终提交裁切之前记录，后续消息变换新造 LF 不改变信号。仅一个消息末词即使显示时移除 LF，初始信号仍为真；raw 未来 LF／Tab 保持可用，未选中源不泄漏，重试清理并重新记录初始生成信号。非引语及已准备外部流保留既有动态行为，Zen 原有规则不改。这是固定参考的可观察时序，不暗中把原版后续 LF 的拒绝规则改成另一个产品行为。

新增 `QuoteBoundaryContinuationTests` 16 项。先行 11 项有 128 个失败断言，其中 no-space 与 toPush 不兼容的夹具不计合法窗口证据；按固定组合规则改为合法的 uppercase／doubled／rot13，并补裁切前信号后，12 项有 137 个有效先行失败，无编译夹具错误。实现后 49 项通过；扩展相关 201 项零跳过／零失败通过（约 32.72 秒），最终有界风险复核 16 项通过（约 0.62 秒）；相关过滤不含十万词测试，不能凭环境变量声称耐力已执行。最终完整门禁通过：客户端 1663 项（零跳过／零失败，约 354.66 秒）、服务端 131 项（零失败，约 1.40 秒）、固定参考／原创性与兼容审计、683 个唯一人工场景清单及未开窗 macOS 应用包全部通过；本次显式十万词实际执行约 37.61 秒。清单通过不是设备验收，先行失败与夹具错误不计最终绿灯。覆盖超过百词连续／分次完成、纠错重开、晚期无效源的输入时间及重试、正式成绩／归档、Jamo／区域指示符／ZWJ、后续消息 LF、初始最终 LF 裁切及不开窗原生 Return 路由。固定原版 Words、addWord、控制检测及 before-insert 实际片段在只读检出的 Node v24.19.0 内存探针运行：未来 tail LF 显示时初始信号仍 false 且 Return 被拒；最终 ab LF 裁切后信号仍 true。原版 nospace 提交判定／addWord 的自有 205 词驱动完成全部提交与生成，拼接目标一致。依赖显式提供；首个控制探针缺少局部 quote 绑定的 ReferenceError 不计产品红测，修正后才取证。没有完整 getNextWord／上游 Vitest／DOM／物理键盘或设备证据。

迁移／风险边界：仅未来练习运行态计算改变，新增布尔量属于值拥有的生成游标，不是持久字段；无设置、成绩、回放、分享、归档或 SwiftData 格式／版本变化，不重算旧快照和源偏移、不写真实库。不声称未分段状态的逐词计数／历史／突发速度、分次跨词界融合／半代理／IME 与完整 UTF-16 导航等价，全部 Funbox／标点／数字、完整英式词典、原版重选模态／异步 UI、真实设备仍开放。使用行为优先测试、源码驱动、根因调试和有界会话内决策／迁移／风险复核，不冒称独立评审；未启动 Typebar 窗口、不部署、不引入参考代码／数据／资产，Morse／Under／Backwards 部分状态及配置 91／2／1 分区不升级，goal active。本条只取代此前已列两个风险的上述机制缺口，不宣告完整引语等价。

2026-10-02 引语按需生成增量（最终门禁已通过）：独立 `QuoteWordStream` 保存自有原始词池。按固定 [初始预算](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L428-L491)、[逐次补词](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L571-L659) 和 [全源控制符](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L721-L730)，默认首批 100 词；showAll 展开全部，toPush 1–4 优先覆盖。实际向前提交才补一个词，重开旧词不重复抽样，最终非空词只移除一个字面提交标量。初始前词用变换后的 raw，后续用去提交后的 text；随机大小写重复练习从同一原始池重新抽样。进度以整池总量显示，不以当前缓冲量代替。Return／Tab 的能力检查实际选中词池和已生成提示，未显现控制符不误触快速重启，未选中的原文／备用文不泄漏到重试或快捷键。

验证阶段：新增 `QuoteStreamingTests` 29 项；最初 20 项有 43 个有效失败断言，首版相关 85 项通过。会话内有界风险审查增加重复抽样、末词进度与 Unicode 融合反例，发现并最小复现 1 个真实错误时钟，沿补词链传输入时间修正。相关 174 项阶段仅 1 个旧夹具仍要求全量初始 Under 引语，按固定首批规则更新而保留全量完成与计数／错误断言。未来换行另有 1 个真实先行失败，已接入全源能力及不开窗原生按键测试；其后 46 项阶段仅 2 个命令面板快捷键夹具断言失败：错误地选择 Tab 快速重启却要求 Esc 快速重启下的 Shift-Tab，按实际快捷键政策更正，不改产品迁就夹具。相关 185 项首次零失败通过（约 32.24 秒）；最终复核区分“允许换行”与“源含换行”，避免改变 Zen 卷带显示，调整后的相关 185 项零跳过／零失败通过（约 32.12 秒）；完整门禁待执行。该过滤不含十万词测试，不能由环境变量声称耐力已执行。首轮完整客户端 1646 项（约 331.99 秒）有 3 个旧语言目录夹具断言失败，均要求超过百词引语初始完整呈现；已按固定规则增加默认首批、showAll 全量及完整输入后原文／完成／零错误验证，保留 376 个可用语言和全部长度覆盖。首轮十万词实际执行通过（约 37.15 秒），但服务与打包尚未执行，该失败门禁不计通过；随后语言目录及新增引语复验 30 项零跳过／零失败通过（约 56.26 秒）；第二轮完整门禁通过：客户端 1646 项零失败（约 354.22 秒）、服务端 131 项（约 1.40 秒）、681 场景清单及不开窗应用包。之后复核发现全源控制符范围错误地合并了未选中原文；实际 getQuoteWordList 内存探针确认只检查选中池，新增 1 项产生 6 个真实失败后修正。此前完整绿灯不作最终修正证据；修正后的 37 项定向零跳过／零失败通过（约 0.18 秒），包含最终 29 项引语游标测试及原生 Return；第三轮最终完整门禁通过：客户端 1647 项（零跳过／零失败，约 354.12 秒）、服务端 131 项（零失败，约 1.42 秒）、固定参考／原创性与兼容审计、681 个唯一人工场景清单及未开窗 macOS 应用包全部通过；本轮显式十万词实际执行约 37.45 秒。清单通过不是设备验收，中间失败与修正前完整绿灯保留但不计最终修正证据。阶段失败不计最终通过。固定原版 getLimit、Words.push、getQuoteWordList 与英式 replace 在只读检出的内存探针运行，Node v24.19.0，依赖显式提供；没有完整上游 Vitest／DOM／异步 UI／设备证据。

迁移与边界：仅未来练习生成和活跃引语进度改变，无设置、成绩、回放、分享、归档、SwiftData 字段或版本变化；旧成绩快照不重新生成、原文及偏移不回写。已有英式有限 14 家庭不等于完整字典；全部标点／数字／Funbox 组合（含后续新造控制符与原版初始化信号范围）、原版初始化三次重选及错误模态／异步显示、Unicode／半代理／CRLF 导航、真实 IME／设备仍开放。Morse／Under／Backwards 部分状态及 94 配置键 91／2／1 分区不升级。使用行为优先测试、源码驱动、根因调试及有界决策／迁移／风险复核，不冒称独立评审。不写真实库、不启动 GUI、不部署、不引入参考代码／数据／资产；整体 goal active。本条仅取代此前已列引语初始预算、后续前词提交和延后空候选机制缺口，不宣称完整引语等价。

2026-10-02 英式逐词生成增量（最终门禁已通过）：依据固定 [逐词转换](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/british-english.ts#L5-L67)、[English 门控及备用引语绕过](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L381-L399)、[前词清理](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L815-L823) 和 [变换顺序](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L946-L977)，接入独立 `BritishEnglishPolicy`，由 `GeneratedWordChunk` 和段游标共用，先 lazy、后英式、再 Funbox、最后提交。普通引语、词数／计时、自定义 pipe／非 pipe、顺序续批、长原文续批和外部词源进入该生成阶段；非空备用引语不再替换，美式与非 English 源不启用，Wordle／Pig Latin 不因内容像英文而误启用。现有拼写选择器对 13 个实际 English 源身份可用，未创建新设置。

拼写家庭是独立编写的有限 14 个普通词形，覆盖自有词库中的常用拼写及 tire／tyre 上下文；没有导入、翻译或打包参考替换表、词库、引语或代码。未知词不猜测转换。ASCII 双引号改单引号、连字符空组件保留、ASCII word 边缘／内部字符、首字母与全大写规则保留；引语例外使用已经 Funbox 变换的前词，按限定标点去除和小写处理，单引号／下划线／换行不会被当成可删除标点。规则覆盖不等于完整词典等价；新增引语无备用源的通用机制，但完整替换表覆盖仍开放。

新增 `BritishWordGenerationTests` 28 项。初始 20 项夹具的边界 trim 与短原文调用问题已更正，修正后的先行阶段有 45 个有效失败断言；夹具错误不计产品缺口。首轮实现相关 48 项通过；扩大后的 140 项阶段有 1 个消息词末标点夹具失败和 1 个默认耐力跳过，不计完整通过。最小复现定位到夹具缺少句号；改成实际词末标点输入后单项通过，不改产品实现迁就预期。最终相关 142 项零失败通过（约 64.96 秒），显式十万词实际执行（约 37.16 秒）；最终完整门禁通过：客户端 1618 项（零跳过／零失败，约 307.34 秒）、服务端 131 项（零失败，约 1.45 秒）、固定参考／原创性与兼容审计、679 个唯一人工场景清单及未开窗 macOS 应用包全部通过；本次显式十万词实际执行约 37.22 秒。清单通过不是设备验收，失败／跳过阶段保留但不计最终通过。本条取代此前逐词机制完全缺失的限定结论，不把有限规则升级为完整词典等价。覆盖实际 factory 输入完成、改变词长后的 no-space／Under／Morse 目标、逐词前序、百词续接、超过一万字原文续批、源字段进度映射、重复、便携记录与正式归档。固定原版 replace 实际函数及其表只在只读参考检出的内存探针运行，Node v24.19.0；模式和 capitalization 依赖显式提供，未运行完整上游 Vitest／DOM／设备，不把探针当应用验收。

迁移／有界会话内决策及风险审查：只影响未来提示生成，不改设置、成绩、回放、分享、归档或 SwiftData 格式／版本，不回算旧成绩或源偏移；原文源仍不被写回成英式目标。完整词典、百词后引语异常／前词提交边界、全部原始换行与 Unicode／半代理导航、混排源门控、真实选择器／IME／设备仍需补证。Morse／Under／Backwards 部分状态及配置映射计数不升级；不写真实库、不启动 GUI、不部署，人工场景清单不是设备验收；整体 goal active。

2026-10-02 英式备用引语增量（最终门禁已通过）：固定 [备用源选择](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L570-L599)、[跳过再次拼写替换](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L381-L399)、[空候选错误](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L901-L916)、[生成失败终态](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L350-L367) 和 [LF 提交](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L990-L999) 确认：非空 `britishText` 直接拆 ASCII 词池，不套普通引语清理；缺失／空字符串回退普通文本。原生 `OfflineQuote` 增加非持久可选备用源，现有 `englishVariant` 接入真实 factory；新增原创 Colour study 美式／英式配对，可从原有目录选择。原文、长度／搜索／收藏／评分身份不切换。普通源处理、已准备外部源与自定义源保持独立。

新增 `BritishQuoteSourceTests` 17 项。模型仅加无行为字段后，首批 14 项有 47 个有效先行失败；选择接入后还有 1 个真实 CRLF 提交失败。已用末 Unicode 标量判断 LF，不让 Swift 将 CRLF 书写簇误判为非 LF 并追加空格。后续内存旧／新成绩夹具的类型名编译错误不计产品红测。最终相关 93 项零失败通过（约 0.63 秒），最终完整门禁通过：客户端 1590 项（零失败，约 305.55 秒）、服务端 131 项（零失败，约 1.39 秒）、固定参考／原创性与兼容审计、677 个唯一人工场景清单及未开窗 macOS 应用包全部通过；显式十万词耐力已实际执行，约 37.43 秒。清单通过不等于设备验收，失败阶段不计通过，本轮没有启动 Typebar。涵盖美式、缺失／空备用源、字面省略号与限定原始标量、CR／CRLF／LF 目标结构、非英语元数据选择、无二次替换、无效 ASCII 空字段、反序／大小写／Under／Morse、重复、回放／便携结果、正式归档及内存 SwiftData 新旧记录共存。

已在内存执行固定 `getQuoteWordList` 和 `appendCommitCharacter` 的实际函数，使用已安装 Node v24.19.0，依赖只为显式的配置／选择／loader／nospace 桩；独立文本证明美式／英式／空字符串分支、双 ASCII 空格产生空候选和 CRLF 提交差异。不是完整上游 Vitest、DOM、重试 UI 或设备证据。选中的无效短备用词池显示生成错误并禁用输入，不降级成普通源；该会话没有开始、结果或可保存成绩，重复仍保留错误。这里只关闭所列短源错误语义，不声称原版随机初始化三次重抽、长引语在百词后的错误时机或模态呈现已等价。

风险／迁移复核限定未来引语生成，不改结果、回放、设置、分享、归档或 SwiftData 格式／版本；旧英式结果按快照保留，不回算历史。引用源元数据与反馈 ID 保持原文身份；搜索只查原文／标题，不把备用文本另当引语。仍开放无备用源的通用英式词替换／前词例外、原始内部换行的全部字段导航、半代理／融合词界、长引语预取、网络备用字段、初始化恢复 UI、全部组合与设备。Morse／Under／Backwards 部分状态不提升；不写真实库、不部署或开 GUI。进行了有界会话内反例审查，不冒称独立审查；整体 goal active。


2026-10-02 最终门禁（Morse 空目标词）：客户端 1573 项（零失败，约 304.95 秒）、服务端 131 项（零失败）、固定参考／原创性与兼容审计、675 个唯一人工场景清单及未开窗 macOS 应用包全部通过。显式十万词耐力已实际执行，约 37.11 秒；不据此声称十万空词或全部 Unicode 已验证。新增 21 项、最终相关 153 项通过；首轮完整测试的 2 个失败及更正的旧字面分词夹具保留阶段性质，本条替代对应本轮最终“待执行”。不提升 Funbox 部分状态，不把人工清单检查当作设备验收；仅当前会话状态变化，无真实库、历史回算、GUI 或服务部署，goal active。

2026-10-02 Morse 空目标词增量（最终门禁已通过）：固定 `input/helpers/util.ts`、`validation.ts`、`handlers/before-insert-text.ts`、`handlers/insert-text.ts`、`helpers/word-navigation.ts` 与 `helpers/fail-or-finish.ts` 确认：逐词变换后的空目标没有可触发无空格提交的末字符，不能自动跳过或用后续词字形完成。使用已安装的 Node v24.19.0 在内存中执行只读固定 util／validation 的纯函数；ASCII 探针的 space／Funbox／Config 依赖明确提供，不是完整上游 Vitest、DOM 或设备证明。原生独立保留安全拼接批次中的空词身份，缓存首个空字段，错误输入留在该字段，不计后续词数／正确词信用，不自动完成或越过空字段预取；段进度改用会话内的逻辑词结束序号。

新增 `EmptyNoSpaceTargetTests` 21 项。首批 14 项 64 个失败中有 1 个 AFK 夹具预期错误，63 个为有效先行失败；夹具编译错误不计产品红测。持续输入夹具保留原 AFK 判定，19 项阶段与相关 90 项通过；呈现归属补测 2 项另有 7 个有效先行失败，137 项阶段通过；首轮完整客户端 1573 项有 2 个失败（约 305.35 秒），该轮不计通过且未进入服务端／打包。最小复现旧 `CustomLiteralDelimiterTests` 的 2 个空词元数据断言，按固定输入契约改成精确空词及结束位置断言，融合字形拒绝不变。最终相关 153 项（零失败／零跳过）通过，最终完整门禁已通过，前述失败阶段不计通过。覆盖首／中／末／连续／全空词、ASCII 二十 UTF-16 单位字段限制、四种自定义完成、pipe／非 pipe 段进度、百词续批、软／硬删除、letter／word-stop、master／expert、删除恢复、接受事件进度、重复、回放／便携结果及空词呈现归属。空词不伪造占位目标或提交键，普通融合书写簇仍拒绝不安全词界。

本条只取代已列安全 Morse 空目标词的输入与呈现模型缺口，不升级 Morse／Under／Backwards 的部分状态。拒绝输入的字段历史、原文／其他词池所有路径、任意 Unicode／半代理／融合词界、实际 DOM 行高阻挡、空字段原生光标布局／IME／实体键盘与设备仍开放。新增状态仅在当前会话内，结果／回放／设置／归档／库版本不变，不回算旧成绩或进度，不写真实库，不运行 GUI；旧二进制降级未实测。进行了有界会话内兼容性／迁移／风险反例审查，不冒称独立审查。goal active。


2026-10-02 最终门禁（原文有限末提交）：客户端 1552 项（零失败／零跳过，约 300.37 秒）、服务端 131 项（零失败／零跳过）、固定参考／原创性及兼容审计、673 个唯一人工场景清单与未开窗 macOS 应用包验证全部通过；完整门禁显式启用十万词耐力。新增 9 项，先行 28 个有效失败及后续 3 个末空目标失败；旧末 LF 夹具更正后最终聚焦 44 项通过，首轮相关 285 项的 3 个旧夹具失败保留阶段性质，不计该批全部通过。仅关闭列出的原文有限末词单提交裁切／空目标保护，TST-04／Funbox 保持部分状态；原文 CR／CRLF、连续尾空格、完整 Funbox／Unicode／拒绝历史／IME／设备仍开放。未启动 GUI、不写真实库、不回填原文／偏移／成绩、不改变版本或部署；清单不是设备验收，goal active。

2026-10-02 原文有限目标末提交增量（实施与阶段证据，最终结果见上文）：固定 [初始化裁切](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L540-L542)、[续批裁切](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L654-L657) 与 [非空词保护](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-words.ts#L79-L89) 表明：仅全部生成后移除非空末词的 ASCII 空格／LF 提交，不移除空词唯一 LF。原文有限工厂与最终续块现于文本变换之后独立裁切练习目标，并同步已有无空格目标元数据；中间块仍需真实提交，原文游标、字符偏移与持久数据不裁切。

新增 `FiniteFinalCommitTests` 9 项：有效首轮 8 项／28 个失败断言，原始脚本夹具违反既有清理／摘要校验的一项 contentMismatch 不计产品反例；纠正夹具后仍有同样 28 个有效失败，0 意外错误。8 项修复后通过；有界会话内风险复核再产生 1 项／3 个无空格最后空目标失败，已修复，首轮相关 285 项有 1 个旧末 LF 夹具的 3 个失败断言（新增 9 项全部通过，实际十万词约 35.98 秒通过），不能称该批全部通过。按固定源纠正其渲染目标与实际会话进度断言，并增加零错误、原始块不变守卫；最终聚焦 44 项零失败／零跳过通过（约 0.91 秒）。完整门禁结果见上文。覆盖三难度、关闭 Quick End、内部与最终 LF、空槽保留、错词进度、原文跨 10,000 字符块与独立分块、noSpaces／uppercase、重复和正式结果／回放／归档；脚本验证保持原有规范化与摘要，不据此声称原始 LF 脚本会被保留。

本条只关闭已列非空末词单提交裁切与空目标保护，不关闭完整原文 CR／CRLF、连续尾空格、零目标／跨换行／变换重排 Funbox、全部 Unicode 导航、拒绝输入历史、IME／实体键盘／设备。政策级空目标元数据用例不等于全部 Funbox 或设备验证。仅未来原文有限练习的渲染目标改变，保存原文、旧成绩／回放、游标和版本不回填；旧二进制行为兼容未实测。不写真实库、不部署、未启动 Typebar；兼容与风险技能限定变更边界，不冒称独立评审，TST-04／Funbox 仍为部分状态，goal active。

2026-10-02 最终门禁（长文本输入历史进度）：客户端 1543 项（零失败／零跳过，约 301.32 秒）、服务端 131 项（零失败／零跳过）、固定参考／原创性及兼容审计、671 个唯一人工场景清单、未开窗 macOS 应用包验证全部通过。相关 276 项包含新增 22 项及实际十万词耐力用例（约 36.39 秒），完整门禁同样显式启用耐力。有效先行证据为首批 21 个断言失败及后续 1 个旗帜删除失败；编译和空白终态／映射夹具错误另记，不计产品反例。只关闭列出的输入历史进度证据，不升级 TST-04／Funbox 部分状态；原文控制符、非空末词 LF、拒绝事件、完整 Unicode／组合／IME／设备继续开放。未启动 GUI、不写真实库、不回填历史、不改变持久格式或部署；671 清单不是设备验收，goal active。本条替代下文本轮的最终“待执行”，早期阶段与旧匹配工具证据保留其边界。

2026-10-02 长文本输入历史进度增量（实施与阶段证据，最终结果见上文）：实际桌面的中止／失败／AFK 路径不再使用匹配前缀；独立投影既有原生接受输入与删除事件，按已尝试字段数推进原文偏移，仅扣除最后一个 UTF-16 长度不足显示目标的字段。错词无需文字相等，ASCII 提交可留在快照中，必需 LF／下划线后缀属于显示长度；严格或 word-stop 保留的分隔符不伪造导航。删除后的空未来字段保留历史身份；组合标记与跨事件旗帜重组按实际删除标量撤销。无空格路径复用现有原词目标及边界，仅有已列 ASCII 用例证据。

证据：新增 `LongTextInputHistoryProgressTests` 22 项。先以无行为变化的会话重载接线建立实际调用路径反例：18 项／21 个有效先行失败；首轮编译夹具错误排除。18 项修复后通过，风险复核另有 1 个真实旗帜删除失败；原始空白夹具的终态／输入映射错误不计产品反例，修剪边界改为明确的政策级测试，不冒称 NBSP／BOM 原样输入。最终 21 项聚焦通过后补充 10,001 LF 连续跨块守卫；相关 276 项零失败／零跳过通过（约 68.33 秒），包含全部新增 22 项；日志确认 `CustomSequentialStreamingTests.testOptionalHundredThousandWordEndurance` 已实际运行并通过（约 36.39 秒），不只依据环境变量。完整门禁结果见上文。内存 SwiftData／正式归档覆盖错词新偏移、旧记录不变、结果／回放及去重／删除保护。

本条只替代下文列出路径的“错误词历史、严格／停止／删除进度仍开放”结论，不关闭全部组合。原文 CR／CRLF、非空末词 LF 裁切、拒绝输入的空字段、零目标／跨换行 Funbox、所有 Unicode 导航／IME／实体键盘和设备仍开放；结果终态与字形映射不因本轮更改，不能把政策测试当作实际 DOM 或设备证据。旧 `typed:` 匹配工具保留独立契约，不作为桌面进度等价证据。仅未来练习结束时计算，不改导航／计分／回放格式、持久字段或版本，不回算旧原文／成绩／进度，不写真实库或部署；旧二进制降级未实测。有界会话内风险／迁移复核，不冒称独立评审；TST-04／Funbox 保持部分状态，goal active，未启动 GUI。

2026-10-02 最终门禁（长文本 LF 空槽）：客户端 1521 项（零跳过／零失败，约 303.50 秒，显式十万词已执行）、服务端 131 项（零跳过／零失败）、固定参考／原创性及兼容审计、669 个唯一人工场景清单和未开窗应用包检查全部通过。新增 13 项，首轮 11 项有 28 个有效先行失败；相关 85 项的旧 LF 夹具失败已按固定源纠正，最终聚焦 14 项零失败／零跳过。只关闭列出的准入、完整 LF 块与 normal 匹配前缀进度证据；错误词历史、严格／停止／删除后导航、原文 CR／CRLF、完整控制符／Funbox／Unicode／IME／设备仍开放。未启动 GUI、不写真实库、不迁移或回算旧原文／成绩／偏移；人工清单通过不是设备验收，TST-04／Funbox 部分状态不升级，goal active。本条替代下文对应本轮长文本空槽的最终“待执行”。

2026-10-02 长文本 LF 空槽增量（最终门禁待执行）：明确保存的长文本不再拒绝纯换行，完整词块使用实际 ASCII 空格／LF 边界并保留原文；Tab 不作为分块或进度分隔符。LF 空槽可以跨 10,000 字符块继续，剩余纯 LF 不被加载入口误判完成后归零，进度标签计入空槽。按固定 [长文本进度与必需 LF](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L987-L1028)，中止时未输入的 LF 不获进度，普通 ASCII 空格提交仍可隐含。独立字符偏移实现不复用原版词数组存储；没有字段、归档版本、旧偏移回算或真实库写入。

新增 `LongBlankTextProgressTests` 13 项；首轮 11 项有 28 个有效失败，无编译夹具错误；另两项恢复／Tab 边界守卫在修复后补充。聚焦 13 项通过，相关 85 项仅有 1 个旧夹具的未输入 LF 预期失败，按固定源修正并增加已输入 LF 的断言；最终聚焦和全门禁待执行。证据包括 29,999 个 LF 块重构、10,001 槽连续完成与重试、101 槽中止／恢复、普通词与 Tab、资源上限、内存 SwiftData、正式归档合并与删除保护；导入及恢复按钮的接线仅有源码／构建证据，不冒称设备操作。

边界：不把本轮当作完整长文本进度等价。原版按输入历史长度计算错误词进度，本项目仍只推进匹配前缀，错误词／强制误键进度待对齐；本轮长文本引擎证据限 normal，严格／停止／删除规则后的导航和进度仍待完整核验；原始 CR／CRLF、全部控制符、完整 Funbox／Unicode 融合／IME／设备仍开放。不能以普通模式的 CR 清理测试替代原文长文本验证。只改变未来练习计算和候选准入，不迁移或改写旧原文、结果、偏移；旧二进制可能拒绝新准入的纯 LF 长文本，跨二进制降级未实测。会话内有界风险／迁移复核，不冒称独立评审；TST-04／Funbox 部分状态不升级，goal active，未启动 GUI。

2026-10-02 最终门禁（普通非管道候选队列）：客户端 1508 项（零跳过／零失败，约 299.56 秒，显式十万词已执行）、服务端 131 项（零跳过／零失败）、固定参考与原创性／兼容审计、667 个唯一人工场景清单及未开窗应用包验证全部通过。相关 114 项通过；扩展 64 项的参考路径跳过及首轮完整 4 个夹具失败仍作为阶段记录，不混作最终证据。新增 13 项、53 个有效先行产品失败，仅关闭已列普通候选准备／预算／续批；纯空行长文本、完整控制符／Funbox／Unicode／IME／设备等仍开放。未启动 GUI、不写真实库、不改历史或部署；667 项清单通过不等于设备操作完成，TST-04／Funbox 部分状态不升级，goal active。本条替代下文对应候选队列的最终“待执行／待重跑”。

验证阶段记录：相关 114 项零跳过／零失败（含显式十万词）；首轮完整客户端 1508 项有 4 个旧夹具断言失败，约 299.34 秒，因而服务与打包未执行，不能称该门禁通过。失败分别是有限 finish 预览把 101 词一次全部呈现、1／10 词挑战强制要求续批，以及普通自定义误要求保留重复空格；更新以固定源预算／准备规则为依据，并增加实际完成、零错误和剩余一词断言。中间 46 项以及显式长程的扩展 64 项均零失败，但各有 1 个因未传 TYPEBAR_REFERENCE_ROOT 而跳过的参考脚本测试，不能作为零跳过证据；完整门禁显式长程并传入固定参考路径，待重跑。

2026-10-02 普通非管道候选队列增量（最终门禁待执行）：按固定 [候选准备](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/modals/CustomTextModal.tsx#L174-L185)、[百词与剩余预算](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L675-L715) 和 [提交及最终裁切](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/words-generator.ts#L983-L1023)，普通自定义四种完成方式与三种排序共用已有独立字面候选游标：保留 LF 空槽，NFC／映射空格／重复 ASCII 空格和 CR／CRLF 准备一致，Tab 留在候选内。完成依实际生成队列，不以忽略空槽的通用词数提前结束；未完成批末保留提交，输入后立即续批。短篇非连续长文本入口显式传原始 chunk，与连续长文本、已验证脚本分流，不将普通源清理套到原文进度。

新增 `CustomCandidateQueueTests` 13 项：首轮 10 项产生 50 个有效失败；随后两批独立输入探针再产生 3 个真实续批失败，修复后 13 项通过。可选闭包编译错误不计产品反例；早期相关测试越界崩溃不是有效通过，既有夹具的批首空格、双空格与额外 99 词预取预期经固定源码纠正，未跳过测试或取消计数／错误／结果／回放断言。覆盖 101 空槽、混合源、70 种代码语言、限时／无限 205 槽、严格最终 LF、重复与正式结果往返。续批保留稳定分隔符进度缓存；遇可能融合的书写簇仍回退扫描。最终相关与全门禁结果见后续总结，单次十万词通过不等于所有性能或设备证明。

本条替代此前“普通非管道候选准备／空槽预算仍开放”的限定结论，仅对上述路径成立。没有字段、协议或归档版本变化，不写真实库、回算历史或改旧结果；旧二进制兼容未实测。通用非自定义出题、Funbox 的 toPush／零目标／跨换行、纯空行长文本进度、全部控制符输入、英式备用引语、Unicode 融合／IME／设备仍开放；TST-04 和 Funbox 部分状态不升级，goal active。使用行为优先测试和会话内有界风险／迁移复核，不冒称独立评审；未启动 GUI，人工清单通过不是设备验收。

## 目的与边界

- 固定参考提交为 `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 本文盘点参考前端 `frontend/__tests__` 的 39 个规格测试文件、后端 `backend/__tests__/api/controllers` 的 14 个 controller 规格测试文件，以及 `packages/contracts`、`packages/funbox`、`packages/schemas`、`packages/util` 的 11 个包级规格测试：合计 47 个直接约束用户可见的练习、配置、展示、账户或远端数据行为，17 个只是网页/服务运行时内部或运营专用测试。
- 清单只保留路径、领域、Typebar 证据路径和原生测试函数名；不复制测试步骤、参考代码、词表、视觉资产或线上数据。
- `Compatibility/official-reference-behavior-specs.json` 是机器可读来源；每个直接规格都附有可定位的 `nativeTests` 函数名。`zsh Scripts/check-reference-behavior-audit.sh /absolute/path/to/monkeytype-reference` 会核对固定提交、64 个路径的完备分类、直接行为的原生证据路径和函数符号，以及本文覆盖。

2026-10-01 按键时序证据更正：`frontend/__tests__/test/events/data.spec.ts` 和 `frontend/__tests__/test/events/stats.spec.ts` 的原生证据增加 `PhysicalKeyTiming.swift`、`PhysicalKeyTimingTests.swift` 与 `PhysicalKeyTimingOrderingTests.swift`。先修正旧“只统计已释放键”的契约，再用独立排序反例修正同时间释放优先、时长所属按下重绑定、开始前释放清理及未关闭重叠。新增排序类共 9 项；首批 8 项复现 7 个失败断言，修正后与既有时序共 23 项聚焦回归通过，包括归档和匿名发送。固定参考完整结果链会先补齐释放再计算结果；此处只索引行为证据，不导入参考测试、实现或日志，也不声称执行了参考工程的差分测试。实体键盘及真实呈现仍待验收，见 `FUNCTIONAL_INVENTORY.md`，`direct` 分类不代表该规格的所有用例或人工验收已经完成。

## 直接用户行为规格

| 参考规格路径 | 可观察领域 | Typebar 原生证据 |
| --- | --- | --- |
| `frontend/__tests__/commandline/util.spec.ts`、`frontend/__tests__/root/config-metadata.spec.ts` | 命令面板目录、可搜索设置、枚举和输入约束 | `CommandPalette.swift` 与 `TypingEngineTests.swift` 的命令目录、严格 ID、数值输入和设置路由回归。 |
| `frontend/__tests__/components/pages/account/utils.spec.ts`、`frontend/__tests__/elements/test-activity-calendar.spec.ts`、`frontend/__tests__/utils/date-and-time.spec.ts` | 历史指标、活动日历、首日和跨月/年边界 | `ResultsAnalytics.swift`、`CloudSyncView.swift` 与 `TypingEngineTests.swift` 的活动、趋势、连续天数、日界，以及随系统首日设置调整热力图周列/跨月标签的回归。 |
| `frontend/__tests__/components/pages/test/keymapConverter.spec.ts`、`frontend/__tests__/test/layout-emulator.spec.ts`、`frontend/__tests__/utils/key-converter.spec.ts` | 键盘图、物理键位、ISO/ANSI 和布局模拟 | `KeyboardGuide.swift`、`KeyboardLayoutEmulator.swift` 与 `TypingEngineTests.swift` 的 239 项布局、层、反查和输入模拟回归。 |
| `frontend/__tests__/components/ui/form/utils.spec.ts` | 自定义参数的有效性与提示 | `TestLimitEditor.swift`、`TypingEngineTests.swift` 的安全整数、边界和取消/确认策略回归。 |
| `frontend/__tests__/controllers/preset-controller.spec.ts` | 完整/部分预设与标签作用域 | `PresetApplicationPolicy.swift`、`TypingEngineTests.swift` 的分组应用、标签和旧格式回归。 |
| `frontend/__tests__/controllers/url-handler.spec.ts` | 可分享测试选择、旧版 `testSettings` 压缩元组及非法链接拒绝 | `TestConfigurationShare.swift`、`LegacyTestSettingsLinkImporter.swift`、`TypingEngineTests.swift` 的自有链接往返、固定版本真实 URI 向量、旧版自定义文本、funbox 边界和离线拒绝回归。 |
| `frontend/__tests__/input/handlers/insert-text.spec.ts`、`frontend/__tests__/input/helpers/fail-or-finish.spec.ts`、`frontend/__tests__/input/helpers/util.spec.ts`、`frontend/__tests__/input/helpers/validation.spec.ts` | 输入接受、错误策略、完成/失败、词边界 | `TypingEngine.swift`、`ResultsAnalytics.swift`、`ResultCelebration.swift`、`ResultPersistence.swift`、`RemoteAccount.swift`、`DataTransfer.swift`、`TypebarApp.swift`、自建服务端的结果模型与 `TypingEngineTests.swift`/`HealthRouteTests.swift` 的逐字符状态、难度、停止/删除错误、阈值和完成回归；阈值失败仍会呈现本次可检查的结果，但不会保存为完成成绩；完成但过短、同提示词重测、异常速度/Raw 或未达准确率门槛的结果同样可复盘，却不会进入本机历史、同步或发布；所有已终止结果（含阈值失败、主动中止和 AFK 无效）都会以已扣除闲置时间计入本次会话的今日练习累计；零速度且持续至少 5 秒的终止结果会显示原生重试提示，难度失败则保留其失败原因；参照 `frontend/src/ts/test/result.ts`，新 PB 或符合条件的零速度结果会从左右各发射 5 个代码绘制粒子，持续 125ms，且遵从 Typebar 与系统的降低动效偏好；同一快照的标签会在所有终止结果中只读展示，只有已保存结果可编辑标签；无压力结果模式仅在本次启动期间隐藏结果详情，不写入任何设置或成绩数据；参照 `frontend/src/ts/test/test-logic.ts`、`frontend/src/ts/test/events/stats.ts`、`frontend/src/ts/db.ts` 与 `frontend/src/ts/collections/results.ts`，保存成绩前的重开、阈值失败或非引文重测会只累计有效键入秒数和重开次数，随后在一条可保存成绩中进入历史与日活动统计；原生端以不可变前序时长快照实现该行为，旧归档/本机记录缺字段时归零，结果页与当前进程今日摘要仍只展示最后一段测试；自建服务通过可选、版本化的能力协商载荷把最终局和前序局的有效秒数用于个人/公开练习统计与 CSV，缺字段的历史记录保持墙钟回退；该载荷不参与排行榜资格、WPM 或经验值计算。 |
| `frontend/__tests__/root/config.spec.ts`、`frontend/__tests__/utils/config.spec.ts` | 设置写入、冲突归一化、持久化和旧值迁移 | `AppSettings.swift`、`TypingEngineTests.swift` 的快照、JSON、配置锁、迁移，以及字体大小保留有限正数、将非正或非有限导入值归一化的回归。 |
| `frontend/__tests__/stores/notifications.spec.ts` | 连接状态与短暂状态提示 | `TypebarApp.swift`、`TypingEngineTests.swift` 的离线横幅、真实恢复提示和终止状态回归；网页 Toast 内部历史不作为 macOS UI 架构目标。 |
| `frontend/__tests__/test/british-english.spec.ts`、`frontend/__tests__/test/lazy-mode.spec.ts` | 专项英语与简化输入 | `OfflineContent.swift`、`TypingEngine.swift`、`TypingEngineTests.swift` 的独立词流、语言特例和 Unicode 简化回归。 |
| `frontend/__tests__/test/events/data.spec.ts`、`frontend/__tests__/test/events/helpers.spec.ts`、`frontend/__tests__/test/events/stats.spec.ts`、`frontend/__tests__/test/test-words.spec.ts` | 输入事件、统计、提示词段和提交分隔符 | `TypingEngine.swift`、`TypingEngineTests.swift` 的重放、WPM/Raw/准确率、文本段和完成回归。 |
| `frontend/__tests__/test/funbox.spec.ts`、`frontend/__tests__/test/funbox/funbox-validation.spec.ts` | Funbox 注册、冲突和配置限制 | `CommandPalette.swift`、`TypingEngine.swift`、`TypingEngineTests.swift` 的 48 项目录、互斥和归一化回归。 |
| `frontend/__tests__/utils/colors.spec.ts` | 自定义主题颜色解析和显示 | `AppTheme.swift`、`TypingEngineTests.swift` 的颜色、主题持久化和回退回归。 |
| `frontend/__tests__/utils/format.spec.ts`、`frontend/__tests__/utils/date-and-time.spec.ts`、`frontend/__tests__/utils/misc.spec.ts` | WPM、准确率、结果用时与计数 | `AppSettings.swift`、`TypingEngine.swift`、`ResultsAnalytics.swift`、`ResultPersistence.swift` 与 `TypingEngineTests.swift`：单位换算后在普通展示中取整；完成结果的主速度在 1000 WPM 起显示“无限”，Raw 保持数值；准确率默认向下取整、普通百分比四舍五入；结果页开启小数时保留未取整速度和非满分准确率至两位、满分仍显示 `100%`，并让稳定度也固定两位；总用时按参考的 61 秒阈值在四舍五入秒数、两位小数和时钟格式间切换，且验证 JSON/本机记录往返；计数和结果摘要保持回归。 |
| `frontend/__tests__/utils/numbers.spec.ts` | XP 与公开统计数字呈现 | `ExperiencePresentation.swift`、`PublicPracticeStatistics.swift`、`CloudSyncView.swift`、`AboutTypebar.swift`、`TypingEngineTests.swift` 将千以上 XP 紧凑呈现为一位小数的 `k/m/b…`；公开统计以两位小数内的数量级卡显示次数；两者均回归边界、舍入及不可信负数处理。 |
| `frontend/__tests__/utils/generate.spec.ts`、`frontend/__tests__/utils/ip-addresses.spec.ts` | 生成的符号流、IPv4/IPv6 格式 | `OfflineContent.swift`、`TypingEngineTests.swift` 的原创符号流、CIDR 网络位与 IPv6 压缩格式回归。 |
| `frontend/__tests__/utils/strings.spec.ts` | Unicode 词界、RTL 和视觉等价输入 | `TypingEngine.swift`、`TypingEngineTests.swift` 的组合文本、等价标点、空白、俄语和双向文本回归。 |

## 自建服务的 controller 行为规格

| 参考规格路径 | 可观察领域 | Typebar 原生证据 |
| --- | --- | --- |
| `backend/__tests__/api/controllers/admin.spec.ts` | 审核队列、资料/账户治理与权限边界 | `Routes.swift`、`AuthStore.swift` 与 `HealthRouteTests.swift` 的审核部署密钥、资料审核和账户暂停回归。 |
| `backend/__tests__/api/controllers/ape-key.spec.ts` | 开发者访问密钥的创建、作用域和撤销 | 同一自建服务路由与测试守护哈希保存、仅限本人结果、撤销后失效。 |
| `backend/__tests__/api/controllers/config.spec.ts`、`backend/__tests__/api/controllers/preset.spec.ts` | 账户配置和预设的版本化保存/同步 | 自建同步路由以用户作用域版本和分页 cursor 同步归档；测试守护无跳页和隔离。 |
| `backend/__tests__/api/controllers/connections.spec.ts` | 好友请求、接受、删除与屏蔽 | 自建连接路由和测试守护关系状态、用户隔离及屏蔽时的清理。 |
| `backend/__tests__/api/controllers/leaderboard.spec.ts` | 全局/好友榜、分页和个人可见范围 | 自建榜单路由和测试守护稳定分页、总数、offset 与仅已接受好友的范围。 |
| `backend/__tests__/api/controllers/psa.spec.ts` | 服务公告的公开读取和部署者发布/撤销 | 自建公告路由和测试守护公开读取、部署密钥与删除。 |
| `backend/__tests__/api/controllers/public.spec.ts` | 匿名公开资料和公共练习统计 | 自建公开路由只返回允许字段，测试守护邮箱隐藏和可分享的聚合统计。 |
| `backend/__tests__/api/controllers/quotes.spec.ts` | 社区引语提交、审核和公开读取 | 自建引语路由和测试守护内容校验、待审状态、审核与仅公开已批准条目。 |
| `backend/__tests__/api/controllers/result.spec.ts` | 成绩提交、历史和榜单写入 | 自建结果路由和测试守护认证、幂等提交、资格排序和榜单响应。 |
| `backend/__tests__/api/controllers/user.spec.ts` | 注册、登录与删除账户 | 自建身份路由和测试守护独立会话、密码验证及级联清理。 |

## 包级可观察行为规格

| 参考规格路径 | 可观察领域 | Typebar 原生证据 |
| --- | --- | --- |
| `packages/contracts/__test__/validation/validation.spec.ts` | 远端请求值、成绩与时间证据的有效边界 | 自建结果模型和路由拒绝不可能或格式错误的成绩；旧客户端仍可省略可选时间证据。 |
| `packages/funbox/__test__/validation.spec.ts` | Funbox 组合与冲突规则 | 原生输入引擎以独立矩阵拒绝冲突项、保留当前有效组合并覆盖词源组合。 |
| `packages/schemas/__tests__/config.spec.ts` | 设置 ID、枚举值和归档配置边界 | 原生命令面板与设置归档拒绝未知值，并守护全部可用选择的往返。 |

## 网页运行时支持规格

以下文件被完整枚举但不直接映射为独立 macOS 用户任务：`frontend/__tests__/hooks/createEvent.spec.ts`、`frontend/__tests__/hooks/createSignalWithSetters.spec.ts`、`frontend/__tests__/utils/local-storage-with-schema.spec.ts`、`frontend/__tests__/utils/sanitize.spec.ts`、`frontend/__tests__/utils/tag-builder.spec.ts`、`frontend/__tests__/utils/zod.spec.ts`，以及 `backend/__tests__/api/controllers/configuration.spec.ts`、`backend/__tests__/api/controllers/dev.spec.ts`、`backend/__tests__/api/controllers/webhooks.spec.ts`、`packages/schemas/__tests__/util.spec.ts`、`packages/util/__test__/arrays.spec.ts`、`packages/util/__test__/date-and-time.spec.ts`、`packages/util/__test__/json.spec.ts`、`packages/util/__test__/numbers.spec.ts`、`packages/util/__test__/predicates.spec.ts`、`packages/util/__test__/strings.spec.ts`、`packages/util/__test__/trycatch.spec.ts`。前六项验证 Solid/DOM/Zod/LocalStorage 的网页内部实现，后三项是部署配置、开发接口或上游发布 webhook，余下八项是可由 Swift 标准库/SwiftData 原生替代的 schema 或通用工具；Typebar 以 Swift observation、SwiftData、Codable、自建部署配置与版本资料替代，没有复制这些实现。任何未来从这些支持层暴露为新用户任务的行为，都必须移入上表、添加原生证据并更新验收。

## 验收结论

该盘点补充页面/模态、配置、输入、Funbox、语言和服务面审计：它证明固定参考的测试证据面没有被只按文件名的 UI 盘点遗漏，并拒绝指向不存在原生测试函数的伪证据。它不替代真实 macOS 窗口、IME、辅助功能、网络或多设备手工验收；这些仍按 `MANUAL_ACCEPTANCE.md` 和各专项审计保持未完成状态。
