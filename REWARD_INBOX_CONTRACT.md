# 原生奖励收件箱与周任务交付

## 配置通知、已知换行格式与应用确认增量

固定参考仍为 `91bd24bb8513785c7364cbea29296ff7adafac41`。完整读取通知状态／两处展示、[URL 配置加载函数](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/controllers/url-handler.tsx)、[配置 setters](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/config/setters.ts)、escapeHTML／字符串帮助函数及开发通知回调。固定版本 `useInnerHtml: true` 文本盘点仅三处：URL 配置摘要、趣味拒绝、开发通知；实际格式是转义文字加 br。不是一般富文本链接需求的穷尽证明，动态／未来调用仍开放。

原创 LocalNoticeMessagePresentation／View 在主堆栈和历史共用：br／br/／br / 转原生换行，大小写 BR 可识别；按固定 escapeHTML 的七种输出一次解码，转义出的尖括号不二次解释，原始消息／JSON 复制不变。未标记保持 Text(verbatim:) 纯文本；未知标签、属性或未闭合标签整条原样回退并说明，不半解析、不解释 Markdown、不执行脚本、样式、URL、附件或资源，也不使用 WebView／HTML document importer。它补齐已知生产格式，不声称支持所有 HTML 实体、空白折叠、标签或浏览器布局。设计技能选择保持既有系统材质／文字层级，真正的换行承载摘要结构，不添装饰和外部字体／CSS／资产。

TestConfigurationShareActions 是分享工作表实际使用的同步生产动作：复制检查真实 BOOL；导入继续用现有自有／网页离线解码器，原生 apply 返回确认 Bool，挑战返回 applied／requiresSetup／rejected。只确认应用后发 10 秒成功摘要；拒绝保留窗口并重要提示，格式错误只发固定本地化消息。摘要只保留选择元数据，不记录链接、主机、压缩数据、自定义正文、令牌或 Error 对象。网页全空字段仍执行应用／重开但不制造摘要，部分字段按八槽位原序列举；解码仍原子，旧 preset API 转发新增本机字段掩码，不改变 Codable／归档／偏好／SwiftData／网络协议或真实数据。

原版 loadTestSettingsFromUrl 不检查各 setConfig Bool，可能描述尝试的字段；QA 显式执行返回 false 的适配器证明该函数仍发布成功。原生主窗口 apply 确认 Bool 后，分享回调返回实际应用快照或 nil，成功摘要只读取实际快照而非请求值；这是明确的真实性适配，不冒称逐项错误处理与原版完全相同。第二轮有界审查的请求 60 秒／实际规范化 30 秒反例，在 `/tmp/typebar-configuration-notices-canonical-red.log` 一项两处预期失败（0.645 秒），已改用实际快照并保留反例。自有链接摘要列完整本机测试选择，网页摘要只列非 null 字段；数值／标签为原生本地化，外部引语身份、原有严格接纳与 LZ 格式兼容限制仍沿用既有合同。

趣味组合、模式、标点／数字与高亮拒绝保留原内联说明，并由实际 ConfigurationNoticeFeedback 发 5 秒普通通知；趣味命令遇锁定发 3 秒重要通知，专注时可见。挑战选择不冒称已经开始：脚本和单手后续设置给 requiresSetup，分享关闭后排队展示，普通挑战以实际 apply 结果为准。此次同会话有界决策／风险复核（非独立）发现旧 apply 在字体／脚本拒绝前清掉 practiceReturnPreset，已移到全部拒绝预检之后；静态顺序守卫只证明代码排序，不冒称主窗口状态／工作表已经人工运行。

行为先行 `/tmp/typebar-configuration-notices-red.log` 一项三处预期失败（0.738 秒）仅证明三个生产入口缺失；编译后接线两项通过。新行为用实际 helper、原生链接和网页 LZ 解码器、应用／拒绝／后续设置回调、隐私与原始详情等断言验证。原生 48 项首轮中一个 unexpected 是 QA 自定义文本给成 string，固定 results.ts:54–58 要求非空 string[]；改夹具而不改产品解码，失败保存在 `/tmp/typebar-configuration-notices-focused.log`。改后模型相关 30 项零失败零跳过（0.474 秒）；新增反馈 helper／预检顺序后的最终集中验证另记。

QA-only check-source-configuration-notices.mjs 从只读固定源码执行完整 loadTestSettingsFromUrl、toggleFunbox、开发通知回调以及完整 findGetParameter／escapeHTML／camelCaseToWords／capitalizeFirstLetter。8 组原 URL 分支、拒绝 setter 分支、锁定／冲突分支和 9 组格式化消息与原生对照；真实 lz-ts 1.1.2 来自固定锁文件，仅安装隔离 QA 路径、禁生命周期脚本、不入产品。配置、schema、事件、重开和通知收集仍为自有适配器，不运行实际 Zod、Solid、DOM、HTTP、计时、设备剪贴板或上游整套构建。首轮跨 vm 原型严格比较、函数名前缀误选和回调闭合边界三次 QA 失败分别保留 source.log／source-verified.log／source-final-verified.log（共同前缀 `/tmp/typebar-configuration-notices-`）；修正适配器精确边界，不改生产逻辑或放宽字段断言，最终 source-final.log 通过。Swift 6.2.4／SDK 26.2、Node v22.22.1 已实测；不把执行源码测试等同复用上游实现进产品。

实际快照修正前 `/tmp/typebar-configuration-notices-verified.log` 集中 50 项零失败零跳过（38.084 秒），18 项离屏 37.529 秒；四张新增浅深色堆栈／窄内容历史已逐张检查。它仅是前一修订结果，不用旧绿灯支持新代码。最终快照回调修订后 `/tmp/typebar-configuration-notices-canonical-verified.log` 集中 51 项零失败零跳过（38.628 秒），含配置通知 12、接线／顺序 3、原通知 12、离屏 18、旧链接／趣味回归 6；离屏 38.093 秒。完整冻结门禁另记。

最终冻结完整门禁 `/tmp/typebar-configuration-notices-complete-readiness.log` 退出 0：客户端 3,641 项零失败零跳过（827.896 秒）、服务 501 项零失败零跳过（12.623 秒），十万词耐久实际执行 150.767 秒，16 隔离磁盘冷读 7.231 秒。固定参考／元数据、53 有界表面／原生文件／测试符号、1,071 人工结构与未启动应用包／scheme／严格签名／原创资源边界全部通过。12 个实现／测试／脚本／矩阵冻结哈希 `/tmp/typebar-configuration-notices-frozen.sha256` 前后一致，之后只补三份结果文档，不更改已测代码。

最终 58 日志保存在 `/tmp/typebar-configuration-notices-complete-logs.1ooJv5`，79 张图在 `/tmp/typebar-configuration-notices-complete-render.LoR3V5`；四张新增浅深色堆栈／窄内容历史已逐张复查。不可见串行隔离窗口不激活；历史 360 宽仅是内容组件，不冒称外层 minWidth=420 的真实工作表。已知 macOS CoreData／AddressBook XPC、隔离只读 SwiftData 513、Node 实验性诊断及早期编译 actor-isolation 警告保留，没有声称修复；红测和 QA 失败记录不覆盖。真实点击／关闭／滚动／剪贴板、锁定／字体拒绝、脚本／单手工作表排队、主窗口返回状态、多窗口、键盘／VoiceOver 与 HTTP 仍未人工验收，三项状态不升级。零 Typebar 应用启动，工作区未触及真实账户／库／凭据或部署。

53 表面分类不变，仅扩充 AlertsPopup 生产路径与测试符号；新增三个人工项后 1,071 仍仅结构盘点。全部通知生产者、通用 HTML／链接、原版鼠标专注控制器、动画、完整 Alerts 同屏、多窗口、真实字体／脚本／工作表、网络、键盘／VoiceOver 仍待补齐或验证。无凭据读取、真实账户／数据库访问、部署、后台任务或 Typebar 应用启动；整体 goal active。

## 本机会话通知与历史增量

固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`：只读核对完整 [通知状态模块](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/states/notifications.ts)、error utility、Notifications overlay、NotificationHistory／AlertsPopup 和收件箱 claimRewards。原版临时通知最新在前，历史保留最后 25 条并逆序显示；notice／success 默认 3,000 ms、error 默认不自动关闭，正时长加 250 ms 退出余量，关闭原因 click／timeout／clear。临时关闭不删历史，专注时只留 important，两条以上可见零时长通知才有全部关闭，截图隐藏，详情复制 title／message／details JSON。这不是现有社交通知列表或奖励邮件的另一名称。

原创 `LocalNoticeCenter`／`LocalNoticeStack`／`LocalNoticeHistoryView` 以 Swift 6.2.4、macOS 14 目标原生实现三种级别、可选标题／系统图标、类型化结构详情、响应状态／422 验证详情和错误消息组合、计时器与回调、有限历史、重要性过滤及 JSON 复制反馈。历史最旧在前保存、显示反序，UUID 不复用；计时器弱持有中心、释放取消，延迟取消后的完成不能删除别的通知，超大时长不溢出。清除先退休旧批次再调回调，回调重入新增通知保留。复制详情不制造新历史，失败只在工作表提示；显式 null 与缺省分开，非法非有限数字拒绝编码而非静默改 null。

实际入口：工具栏“通知”菜单区分会话／社交通知，`notification-history` 命令和完成页导出菜单可打开历史；原社交通知与奖励收件箱功能保留，服务公告继续走原公告入口。主练习、完成页和奖励页挂接真实生产通知卡，完成页覆盖层不受庆祝 Canvas 命中拦截（原庆祝层禁 hit testing）；导出图片只渲染既有 ResultSnapshotCard，不含通知堆栈。六类结果复制保留原 exportStatus，同时按真实写入结果发布成功／错误；缺回放／提示、无慢词及坏阈值也可回看，不把已复制的提示／输入正文放入历史。AppKit SDK 26.2 的 NSPasteboard.h 明确 setString／writeObjects 返回 BOOL，原有无条件成功已改为检查实际返回值；测试注入写入器，不接触用户剪贴板。

奖励更新只在既有当前操作／账户范围确认后发布徽章名，邮件中明确选择的未领取徽章才进入提示，5,000 ms／奖励标题／gift；删除、已读或 XP-only 不伪造解锁提醒。读取／更新失败只追加通用错误，不自动捕获响应、Error 对象、邮箱、令牌或输入。原领取／能力／认证／库存与服务真值逻辑不变；模型与静态接线不证明真实 HTTP 领取或 UI 回调已人工执行。

同会话有界决策／风险复核（非独立审查）选择由现有 AccountSession 持有中心，应用窗口共享同一会话；账户 UUID 或原始地址变化清空计时器和历史，相同用户资料／XP 刷新保留。退役账户的回调不执行，防旧回调跨身份副作用。这是比原版全局会话历史更严格的明确隐私适配，不冒称原版也会清空。只在内存中保存，不新增 SwiftData／归档／偏好／服务字段、网络接口、凭据访问、迁移、部署或后台任务；回退无需数据恢复，系统剪贴板是用户主动复制的独立外部效果。

设计技能促使采用系统材质通知卡、三种语义级别和同时可读的 SF Symbol，窄侧栏表达真实级别而非装饰；历史用原生可选择正文、明确复制动作和本机会话说明，无上游字体／图标／CSS／动画资产。明确未完成：当前只接结果复制与奖励页生产者，不是全部原版通知调用点；原版 HTML 富文本／链接目前保留原始文本并标注，未声称格式等价；原生按输入／窗口焦点及活动测试过滤，未重写原版鼠标移动三像素的专注控制器；动画、完整 Alerts 同屏布局、真实多窗口、键盘／VoiceOver／计时与剪贴板、全功能无损仍待验。53 表面仅包括原 52 页面／模态加本次实际 AlertsPopup，不代表其他 popup 已穷尽盘点；整体 goal active。

行为先行 `/tmp/typebar-local-notices-red.log` 实际一项测试三个预期失败（0.818 秒）证明展示／历史／复制入口缺失，静态接线只是接线证据。核心首轮 21 项零失败但一项 QA 依赖测试跳过；`/tmp/typebar-local-notices-source-focused.log` 保留一次性计时器适配器未出队的失败，按实际事件循环先出队后回调修正，生产逻辑不改、断言未放松。合并首次 `/tmp/typebar-local-notices-render-focused.log` 40 项中两处失败／一处 unexpected，均由命令遗漏 TYPEBAR_INBOX_SOURCE_PACKAGE 造成；在隔离 `/tmp/typebar-local-notices-source-runtime.Wf5MVh` 准备锁定 TanStack DB 0.6.8 后原样复跑。最终 `/tmp/typebar-local-notices-render-verified.log` 41 项零失败／零跳过（36.602 秒），含实际等待 continuation、最大时长／释放取消／回调重入／范围退休、真实剪贴板 helper 结果与私密正文不保存、徽章选择及生产离屏表单；五张新增图在不可见隔离窗口生成，不激活、不联网、不调用用户剪贴板。

`check-source-local-notices.mjs` 只在 QA 执行完整实际通知模块／错误工具及实际完整 copyDetails 回调，43 次状态变化逐步与原生对照（仅默认标题本地化），另执行真实 timeout callback 和详情复制成功／失败。store 为自有数组适配、时钟与剪贴板为明确捕获器，不运行 Solid 响应追踪、浏览器、动画、真实计时或设备。探针纳入完整串行门禁，前后检查固定 SHA／干净参考；产品没有 TS／JS 运行时或上游实现／资产。页面矩阵新增真实 AlertsPopup 并登记生产路径／测试符号，三个人工项增至 1,068，仅结构盘点。零 Typebar 应用启动，最终冻结完整门禁另记。

首轮冻结完整门禁 `/tmp/typebar-local-notices-complete-readiness.log` 客户端执行 3,626 项，三处失败全部来自同一旧盘点测试的 52／46 数量与 sourceFiles 精确断言（793.600 秒），不是零失败；服务与打包尚未执行。原日志保存在 `/tmp/typebar-local-notices-complete-logs.wj3TKv`，保留系统 XPC 与隔离只读库诊断。按实际新增 AlertsPopup 更新为 53／47、登记其精确路径，另断言该表面实际存在且有原生映射，未删除守恒／互斥／证据路径／测试符号检查。单项复验 `/tmp/typebar-local-notices-surface-recovery.log` 通过（9.083 秒），随后重新冻结完整门禁；最终结果另记。

修正精确盘点测试后重新冻结的完整门禁 `/tmp/typebar-local-notices-final-readiness.log` 退出 0：客户端 3,626 项零失败／零跳过（819.638 秒），服务 501 项零失败／零跳过（12.994 秒）；十万词耐久实际执行 155.471 秒，16 项隔离磁盘冷读 5.406 秒。固定参考／元数据、53 表面／生产文件／测试符号、1,068 人工结构、未启动应用包／scheme／严格签名／原创资源边界全部通过。15 项冻结实现／测试／脚本／矩阵哈希 `/tmp/typebar-local-notices-verified-frozen.sha256` 前后一致，结果只补本文及人工／页面审计文档，不更改已测代码。

最终 57 份日志保存在 `/tmp/typebar-local-notices-final-logs.oUd2z3`，75 张图在 `/tmp/typebar-local-notices-final-render.RXyJJV`；本次新增五张空历史／长详情浅深色窄组件／完整与专注通知堆栈逐张复查。不可见串行隔离窗口不激活、不联网、不读写用户剪贴板、不打开真实库；360 宽历史仅测试内容组件，不冒称外层 minWidth=420 工作表。已知 macOS CoreData／AddressBook XPC、隔离只读 SwiftData 513 与 Node 实验性诊断保留，没有修复这些系统诊断；首轮与早期失败仍按上文保留。真实点击／滚动／键盘／计时／多窗口／HTTP／VoiceOver 未验，三项新增人工状态不升级；零 Typebar 应用启动，整体 goal active。

只读已知通知 API 名称加左括号文本扫描，在固定 `frontend/src/ts`（排除通知状态模块和测试文件）找到 85 个文件、303 个匹配。它不是 AST 或运行时穷尽盘点，别名／动态调用／包装器未证明覆盖，不作为已完成比例；用于后续生产者补齐，当前只声明结果复制和奖励页入口。

Typebar 已独立接通周任务、持久邮件、一次性领取及 SwiftUI 收件箱。送达不会增加账户 XP；领取才入账，领取 XP 不写回周练习榜。此增量不是完整 Monkeytype 重写完成声明，整个 goal 保持 active。生产代码与文案为自有实现，固定参考只供只读 QA 动态执行，不进入应用包。

[日榜任务与交付](DAILY_LEADERBOARD_SETTLEMENT_CONTRACT.md) 也已沿用此原生收件箱及领取链路；日榜生产与恢复的新增证据见该合同，不将本文件的上一阶段测试汇总当作日榜全量结果。

## 接口与原生入口

| 入口 | 身份要求 | 行为 |
| --- | --- | --- |
| GET v1/inbox | 当前账户会话 | 返回该账户 inbox 与 maxMail |
| PATCH v1/inbox | 当前账户会话 | 领取或删除指定邮件，返回邮箱及刷新后的 user |
| GET v1/moderation/weekly-rewards | 非空部署者审核密钥 | 只读任务状态，不提供外部发奖或触发任务接口 |
| 工具栏收件箱与命令打开奖励收件箱 | 原生登录账户 | 显示邮件、单封或批量领取、无待领取奖励时批量删除 |

PATCH 严格接受可选 mailIdsToMarkRead 和 mailIdsToDelete UUID 数组，允许空对象、重复 ID 和不属于当前账户的未知 ID；显式空数组、null、额外字段及非 UUID 拒绝。认证和配置门禁先于解码，禁用收件箱返回 503。Typebar 使用自有平铺响应及完整账户回执，不是原版返回 null 的 HTTP 协议兼容实现。

原生端要求 v1／typebar 服务明确宣告 rewardInbox available；旧服务、未知能力和禁用配置不会被当作空邮箱。领取没有乐观加分；成功回执才刷新账户。响应写入前同时检查原始地址、会话 token 和账户 scope，错误 user ID 或账户切换后的响应不应用。视图也检查操作身份，切换账户清掉旧列表和删除确认。原生列表按时间降序、当前系统语言区域的标题升序排序，标题相等时自选保持原顺序；零 XP 仍显示待领取。未读奖励行只显示领取，无奖励行显示删除。

原版查询未指定标题 collation，但实际锁定 TanStack DB 0.6.8 继承集合 locale 排序。QA 动态执行该确切 npm 包完整 comparison 模块和集合默认配置函数，原先 UTF-16 实现已被十二组反例推翻。Foundation String.compare 修正后仍复现一处中文重音顺序差异；原生改用公开 CoreFoundation 区域比较，并仅对比较操作数规范到 NFC，保留可见标题与同值原顺序，不引入 JS 运行时。四个显式区域样例对照不等于所有浏览器语言／系统 ICU 版本或完整查询的同值键排序等价。

## 领取与容量规则

[固定用户 DAL](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 的 updateInbox 仅领取未读目标邮件，先取读集合，再取删集合；删除优先，重复 ID 去重。XP 直接相加，不使用成绩奖励的 BSON 低位转换。标记已读同时清空 rewards，删除则移除邮件，重试不再领取。徽章保留原库存先出现的同 ID，再按奖励顺序追加新 ID。

自有 version=1 邮箱状态分离邮件、交付回执、领取账本和徽章库存。同一用户／邮件 UUID 的交付回执在删除或容量淘汰后仍保留，这是明确增加的幂等保证，不冒称原 DAL 也具有此保证。前插并保留 maxMail 封，淘汰未读邮件不领取；启用且容量零不保留邮件。坏状态、重复回执、不安全算术及领取／已读不一致拒绝加载。邮件和领取账本在一次文件提交保存，失败全部回滚。

删除成绩不删除领取信用；账户重置及删除账户清除该账户邮箱、交付、领取和徽章库存，不触及其他账户。全球任务去重记录保留，避免重放已经完成的周交付。邮件 XP 可为负，算术独立限制在 JavaScript 安全整数域；这不等于原 schema 全数值域兼容，后续成绩报告仍受既有上下文校验约束。

自有徽章使用字符串 ID、标题和 SF Symbol，不导入原版数值徽章目录、图片或 selected 资产字段。首次邮箱更新将当前已解锁的自有徽章纳入持久库存，使旧徽章先于新邮件奖励；它不是原版徽章 schema 或账户导入兼容证明。现有好友通知保持原独立机制，不冒充奖励邮箱。

## 实际调度与恢复

新成绩首次获得周缓存名次时，在同一投稿事务保存一个按接受 key 唯一的任务；同 UUID 重试不再安排，旧回执不补造历史任务。due 为 key 加七天加一分钟；首次 worker 扫描到期任务，失败最多尝试 23 次，每次在失败时钟后一小时再试。每次扫描最多处理十个任务，正常服务约每分钟扫描一次，故不承诺恰好到毫秒执行。

结算读取当时配置及尚未过期的原始缓存，而非投稿时冻结配置；原版 worker 不重跑公开查询隐私过滤，Typebar 保留这一私有交付行为，公开榜单仍使用当前隐私护栏。重叠档位取高，单名次取 maxReward，最后舍入，零奖励送未读邮件。启用空档明确失败；收件箱禁用不能掩盖此前的空档错误。空榜、禁用周榜、禁用收件箱或无匹配名次不产生邮件。自有空候选事务成功不证明真实 Mongo 空 bulk 的行为。

每个任务的全部邮件与 complete 状态共享一次原子文件提交。计算失败不留下部分邮件，记录 pending／failed 和不含账户内容的错误码；保存失败不消耗尝试次数，保留原待处理状态，重启后继续。complete 与 failed 记录不删除，这与原版成功／最终失败移除及 LRU 容量 100 的重复安排行为不同。

WeeklyExperienceRewardWorker 是单 writer actor 工作循环，实际 executable 使用 Vapor 4.122.1 的 asyncBoot／asyncShutdown 生命周期启停；重复 start 不生成第二循环，shutdown 取消并等待退出。测试显式注册并通过真实异步 boot／shutdown，不绑定网络端口，不启动 Typebar GUI。同步 boot 的默认协议钩子不运行本 worker，不支持多服务 writer、分布式锁或 BullMQ 兼容部署。

## 部署配置和文件升级

TYPEBAR_INBOX_CONFIGURATION 默认是 Typebar 自选 enabled=true、maxMail=100；原版 base 是 false／0，不宣称线上配置相同。TYPEBAR_WEEKLY_XP_CONFIGURATION 仍默认启用、15 天、空档位，因此实际任务会按规则报空档错误，不会自动猜奖励。部署者应明确配置档位，例如：

```json
{"enabled":true,"expirationTimeInDays":15,"xpRewardBrackets":[{"minRank":1,"maxRank":10,"minReward":50,"maxReward":200}]}
```

升级前备份完整服务 JSON，保持唯一 writer，禁止旧 writer 覆盖新文件。旧缺字段初始化空状态，仅在下一次成功写入时记录托管标记；纯加载不写字节。rewardInboxManaged 或 weeklyRewardJobsManaged 为 true 时对应状态字段缺失拒绝，显式 null／坏版本拒绝；新奖励已标记安排却缺任务也拒绝。标记是误删恢复护栏，不是抵抗任意文件篡改的密码学账本。恢复使用完整备份或向前修复，缺字段读取不证明无损降级。原生 SwiftData 列、归档 26 和设置 4 不变。

## 自动化证据和仍待验收部分

初始两个路由测试产生四处预期失败；禁用门禁和托管邮箱遗漏再产生三处失败。独立周任务标记反例在账户重置后复现一处失败，随后补护栏。初次 mailbox 排序表达式编译失败经具体类型和独立循环修复，不算行为测试红绿证据。

Scripts/check-source-inbox-claims.mjs 在只读固定检出动态执行完整 updateInbox 及其生成的 JavaScript function body，比较 108 组读删选择和 108 次重复操作；Mongo 更新管线为显式观测适配，不是真实 Mongo／BSON 事务。徽章数值 ID 仅在 QA 桥接成自有字符串和元数据，比较库存顺序，不声称原目录兼容。探针已接串行 readiness，前后核对固定 SHA 和干净状态。

聚焦原生九项通过，0.233 秒，含十二组实际依赖区域排序及反向规范等值拼写；服务二十三项通过，0.474 秒，均零失败／零跳过。首批服务十九项曾因缺环境跳过一项源码测试，保留历史但不替代后来补验。排序红阶段十二处差异、初次 Foundation 修正仍有一处差异均保留。HTTP 领取、账户隔离、严格形状、重试、磁盘提交失败、旧形状、任务重启、当时配置、零奖励／容量及异步生命周期均有自有自动化。

最终同一次串行门禁原生 2961 项通过，692.762 秒；服务 338 项通过，7.082 秒，均零失败、零跳过。新增十项原生及二十三项服务测试纳入全量，含领取回执的 XP／徽章联合解码。十万词耐久 148.850 秒，九项隔离磁盘迁移 3.972 秒；887 条人工场景只作结构校验，源码及原创边界审计、未开窗应用包构建和资源边界全部通过。没有削弱旧断言，CoreData XPC 环境诊断不替代最终 XCTest 汇总。构建／测试／打包运行时冻结全部项目文件，门禁后只补记文档。

本轮主日志 /tmp/typebar-inbox-final-readiness.log，完整原生及服务日志 /tmp/typebar-inbox-final-client-tests.log、/tmp/typebar-inbox-final-service-tests.log；唯一临时父目录 /tmp/typebar-inbox-gate.JcwZ5a。归档来自这次运行，不混用旧临时日志。初始红测、迁移反例与排序修正日志保留在 /tmp/typebar-inbox-routes-red.log、/tmp/typebar-inbox-recovery-red.log、/tmp/typebar-inbox-job-recovery-red.log、/tmp/typebar-inbox-order-red.log 及 /tmp/typebar-inbox-native-final-focused.log，后者是仍有一处差异的失败阶段，不作最终通过证据。

源码驱动和行为优先测试使配置、领取与区域排序基于实际源码而非页面猜测；会话内有界决策、风险和迁移复核促成两个独立托管标记及单 writer 边界，不是独立评审。界面设计复核保持原生列表，以等宽奖励条和明确待领取状态区分通知与信用；文档复核保留接口、目录和队列差异，不冒报整体兼容。

没有操作真实账户库、部署或修改系统时钟。单窗口布局、大字体、VoiceOver、原生异步网络实机交互、真实 Mongo／BullMQ、崩溃瞬间 fsync 及多 writer、长期规模、macOS 14／Intel、日榜奖励、premium、完整 PB 缓存和整体功能等价仍未验。不能用候选计算、HTTP 或源码探针通过替代这些验收。
