# 账户个人最佳账本与公开清空

## 公开资料英语全部时间榜名次

固定 [UserProfile.LeaderboardPosition](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/profile/UserProfile.tsx) 显示英语 15／60 秒的全部时间榜名次，第一名显示 GOAT，其余由 [formatTopPercentage](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/misc.ts) 计算两位舍入、无强制尾零的百分位。此前原生资料只有 PB 卡，没有排名区域。本阶段原生独立实现，中文名次与“前…%”是显示本地化，不复制 JSX／样式／源码或资产。

自建服务详细 `GET /v1/profiles/{id}` 新增可选 `allTimeLbs.time.{15,60}.english`，每个存在项只含 rank／count；公开资料另提供可选 `leaderboardOptedOut`。复用现有全部时间英语榜的完整独立排行榜 PB、资格筛选与排序，不从可删除历史、个人 PB 最大值、分页或好友榜推名次，两个档独立计算。函数在同一个 AuthStore actor 调用内无 await，名次与人数来自同一组记录；没有另建缓存、奖项或写入。搜索、通知、好友／审核等轻量资料不附排名，不对每条嵌套资料扫描全榜。原版 Mongo 排名刷新／缓存时序尚未等价证明，不把自建即时快照冒充原版服务。

退榜／封禁不附排名，原生也显式防止这两个标记下的排名显示；退榜显示提示，封禁不显示新区域。其他用户的退榜、限制及最低练习时长资格会同时改变名次和人数。退榜清除排行榜 PB，重新入榜不复活旧名次；只有后续合格新 PB 才能重新建立。个人 PB 存在、英语之外的成绩、30 秒或未触发榜单的 lazy PB 都不能冒充英语 15／60 名次。无名次不发送零，已知空的两个桶与旧服务完全缺字段保持可区分。客户端按固定 schema 接受非负整数 count 和可缺 rank，不接受负数／小数／坏类型；零 count 且非冠军的异常来源保留未知百分位，不绘制 NaN／Infinity，服务自身不生成这种排名项。

界面沿用系统字体、等宽名次、语义颜色和既有二列卡片，两个档保持顺序、缺档不补名次，静态内容合并辅助功能读取。四张实际生产组件离屏图（正常浅色、大名次深色、未知名次、退榜提示）已逐张检查，见 `/tmp/typebar-profile-rank-render.K8bmPx`；五项渲染回归包括已有 PB 的 13 张图，所有测试窗口始终不可见。本阶段不启动 Typebar 应用，真实完整资料窗口、VoiceOver、设备、账户页专属入口与官方协议仍需后续验证，SOC-01／RANK-01 保持部分兼容，完整 goal active。

服务有效先行两项／四断言失败（0 unexpected，0.661 秒，`/tmp/typebar-profile-rank-server-valid-red.log`），原生实际解码先行一项／两断言失败（0.516 秒，`/tmp/typebar-profile-rank-native-red.log`）。第一轮服务测试调用签名编译错误不算产品红测。首轮实现回归的一处失败是测试错误地要求重新入榜复活旧名次；根因确认已有退榜清账逻辑后，改为断言不复活并提交新的更好成绩，未改旧生产语义，见 `/tmp/typebar-profile-rank-server-focused.log` 和 `/tmp/typebar-profile-rank-server-fixed.log`。新增原生五项模型／源码回归和一项渲染、服务六项含真实 HTTP；服务六项零失败（0.042 秒），原生五项零失败（0.354 秒），渲染五项零失败（5.039 秒）。QA 动态执行固定完整 getAllTimeLbs／formatTopPercentage／roundTo2，25 组自有 DAL 查询和 24 个格式案例；并未执行 MongoDB、Solid、JSX、DOM、官方 HTTP 或全页。脚本只在产品外读取参考 checkout，已接入完整门禁。

这是只读响应加法：旧客户端忽略新字段，新客户端缺字段隐藏排名、退榜状态保持未知；新客户端／旧服务和旧客户端／新服务不需要写入协商。归档 33、设置 5、偏好 v3、五实体／32 成绩列、CSV 41 列及服务持久文件不变，无回填、旧 writer 变化、部署或真实账户调用。回退只移除新界面和响应派生，不清成绩／PB／目录，不承诺已有其他迁移的降级安全。源码驱动、行为先行、兼容迁移、原生设计、根因排查及同会话有界决策／风险复核影响本轮；不是独立审查。剩余风险包括大榜全排序的成本、原版缓存刷新时序、真实窗口和正式设备，不能用少量夹具升级整体功能等价结论。

排名阶段最终相关 111 项零失败零跳过（18.543 秒），见 `/tmp/typebar-profile-rank-related.log`。随后完整串行门禁退出码 0：原生 3,489／服务 483 项零失败零跳过（1,816.584／10.938 秒），十万词耐久 150.975 秒，16 项隔离磁盘迁移／冷读 7.374 秒；1,035 条唯一人工场景仅结构通过，三条新人工场景保持待验。原版固定源码、原创性、未开窗应用包及严格签名／资源检查通过，十个冻结代码／测试／脚本／矩阵文件哈希全部一致。主日志 `/tmp/typebar-profile-rank-final-readiness.log`，45 份分项保留于 `/tmp/typebar-profile-rank-final-logs.sa2O5E`，参考 checkout 仍干净且固定于上述提交；零 Typebar 应用启动。

门禁等待期间对话中断但原进程未停止，续接同一执行句柄后正常完成，没有重启或并行构建。原生本轮耗时明显较长，日志中 `testNorwegianBokmalScaleChoicesPreserveIndependentIDsAndPinnedAggregateShapes` 为 896.409 秒，是长耗时主要部分；采样命令到达时进程已正常退出，没有取得调用栈，根因未定位，不据全绿宣称性能已达标。完整命令结束后仅补文档，不再改冻结代码／测试／脚本／矩阵。整体功能、原版缓存时序、性能热点、实机和辅助功能仍开放，完整 goal active。

## 公开资料原生离屏渲染取证

本阶段没有新增产品行为：仅将已有 `PublicProfilePersonalBestDetails` 从文件私有改为模块内可测试，四项新测试挂载真实生产摘要／详情 SwiftUI 组件，而不是另造静态界面。每个测试独占一个从不显示的 NSWindow，结束解除内容并关闭；隔离 UserDefaults 使用唯一 suite 并清理，反馈声音注入无声替身，不使用真实账户、网络、Keychain 或用户数据库，不启动 Typebar 应用。

测试覆盖 420 点摘要的正常浅色、最大规范速度 WPH 深色、空账本，以及 168 点窄列的最大值和旧未知字段。同一已挂载摘要观察单位变化，主值不受小数开关影响；同一详情观察小数和 CPS 变化，恢复偏好后 PNG 字节恢复，资料序列化保持不变。截图断言验证窗口不可见、尺寸有界、存在绘制内容及 AppKit／SwiftUI 外观一致。13 张组件截图已逐张检查，见 `/tmp/typebar-profile-pb-render-verified.E9M4NL`，四项零失败（3.979 秒），日志 `/tmp/typebar-profile-pb-render-verified.log`。这不是原版与原生的像素等价、所有单位渲染或完整资料页滚动验收；其余单位／格式由已有模型和固定源码对照覆盖。

探索夹具最初把 Raw 设为 500，违反完整精确快照 0–420 的已有准入，导致解码失败；只改自有夹具为 420，未放宽生产协议，不算产品红灯。隐藏挂载的公开辅助功能 API 只返回一个根节点，故未宣称真实 DisclosureGroup 点击、键盘或 VoiceOver 已执行；详情组件直接挂载仅验证其布局与设置观察。逐张检查又发现部分测试强制浅色 SwiftUI，却继承系统深色 AppKit 背景；新增外观／背景亮度断言先产生两项、16 处预期失败（3.025 秒，`/tmp/typebar-profile-pb-appearance-red.log`），再将测试窗口默认固定浅色、深色用例显式覆盖。修正前截图及其通过日志不作为最终视觉证据，未因此改变产品配色逻辑。

源码驱动、行为先行、原生设计和根因排查用于此轮 QA；沿用已有系统字体／语义颜色、二列卡片，不增资产、依赖、迁移或服务行为。页面证据矩阵补登记四个实际渲染测试符号，不升级映射或功能等价结论。SOC-01／MET-43 仍部分兼容；PROFILE-PB-01／02／03 仍待唯一隔离候选完成真实网络、完整窗口、键盘、VoiceOver 和目标设备验收，完整 goal active。下方完整 3,479／477 门禁仅为上一产品阶段证据，本阶段验证结果另记。

本阶段最终相关 105 项零失败、零跳过（17.110 秒），见 `/tmp/typebar-profile-pb-render-related.log`；包含四项新渲染、资料摘要／完整表、精确指标、历史／每日／单条图表、自定义节奏迁移及实际页面证据审计，趋势插件使用此前已验证归档。52 个页面／弹窗的证据审计、1,032 条唯一人工场景结构、原创性边界和 diff 空白检查通过；未开窗应用包、签名及包内原创性检查通过，日志 `/tmp/typebar-profile-pb-render-package.log`。参考 checkout 仍干净并固定于上述提交，进程检查没有 Typebar 应用实例。本轮未重跑完整客户端、服务或耐久套件：产品仅改变已有组件的模块内可测试性、没有运行逻辑或服务变更，采用相关回归与打包取证；不把上轮 3,479／477 计为本轮执行。测试资源清理、偏好隔离、外观一致和证据边界已作同会话有界风险复核，无剩余可操作发现，不是独立评审；完整窗口／辅助功能缺口保持开放。

## 公开资料八档摘要

资料页此前直接把完整快照数组铺成卡片，并把速度固定写成 WPM；标准空档缺失、同档不同配置没有摘要选择。当前原生独立实现 [UserProfile.PbCard](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/profile/UserProfile.tsx) 的八个固定槽：计时 15／30／60／120，字数 10／25／50／100。每槽跨语言／选项取严格最高保存精确 WPM，同速保留首先出现的整条快照，零速度不选入；正小数不先舍入，未知参数或非规范旧键不冒充标准槽。空档仍在固定位置，以“—”表示，不假造零速度或准确率。

摘要与完整披露分开：现有所有公开记录保留在原生可展开列表中，包括非标准档、custom／zen、零速度、参数未知及旧重复结果 UUID。列表只以当前不可变响应的索引区分显示项，保存 ID、顺序和全部伴随字段不变；这层完整披露是既有 Typebar 扩展，不声称原版公开页也有完整表入口。已知空独立账本不复活旧摘要，旧服务只按明确参数显示已知标准值，Raw／配置未知保持未知，不从本机、当前设置或历史补造。

榜单和命令搜索打开的资料页均显式传入同一个 AppSettings。摘要大字速度和准确率固定无小数，准确率向下取整；展开详情遵循五种单位和小数偏好，Raw 同步换算。详情保留语言、保存配置、接受日期与时分、旧基线标记；最高速度主指标也使用当前单位，规范值不改。对照 [Formatting](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/format.ts) 的小数与准确率规则，不套用特殊 100% 简写。封禁资料不展示新 PB 区域；原有网络加载、身份、累计统计、徽章和活动路径未改，不把本阶段当成整页隐私／协议等价证明。

设计沿用系统字体、语义颜色和等宽速度，两组各四槽的二列卡片适应既有 420 点窗口；原生 DisclosureGroup 让配置详情不依赖 hover，完整记录保持延迟列表。没有新图像、字体、依赖、动画、网络请求、缓存或存储字段；现有归档 33／设置 5／偏好 v3、五实体／32 成绩列、CSV 41 列及服务协议不变。可回退只读界面，不需要迁移或旧 writer 恢复。macOS 14 目标以现有 SDK 编译，不等于最低设备布局或 VoiceOver 已验收。

实际旧资料卡投影先提取到视图所用函数、保留原行为；两项测试随后六个预期断言失败（0 unexpected，0.496 秒），见 `/tmp/typebar-profile-pb-summary-valid-red.log`，修正后通过。最初夹具把 98.75 精确准确率配成整数 98，导致两项解码异常，见 `/tmp/typebar-profile-pb-summary-red.log`；仅改夹具为协议要求的 99，未放宽生产准入，该错误不算产品红灯。新增八项，相关 47 项零失败零跳过（0.774 秒），见 `/tmp/typebar-profile-pb-summary-focused.log`；覆盖八槽、精确排序／同速伴随字段、已知空、旧未知／非规范键、重复 ID 完整披露及零／正小数。

QA 动态执行固定源码中完整 createMemo 声明及其 map／reduce 回调，16 组自造资料覆盖 0／1／8／25／80 条、新账本、旧响应、缺 mode2 和已知空不回退；另执行完整 Formatting 类、单位转换模块及完整 roundTo2，80 组五单位／两种小数／空值与边界对照。不是完整 PbCard JSX、Solid 响应性、DOM、hover、HTTP 或截图验收；原版代码仅在只读参考 checkout 上动态运行，不写入生产或资产。源码驱动、行为先行、原生设计及同会话有界风险复核影响实现，不是独立评审。SOC-01、MET-43 仍部分兼容，三条新人工场景待唯一隔离候选的真实窗口、键盘、VoiceOver、网络与设备验收；本轮零 Typebar GUI 启动，完整 goal active。

公开资料摘要最终相关 50 项零失败零跳过（5.843 秒），见 `/tmp/typebar-profile-pb-summary-final-focused.log`；包含实际页面／弹窗证据审计、搜索策略、旧资料／封禁标记解码、八项新增及账户完整表／精确指标回归。摘要准确率另有明确辅助功能标签，未合并或隐藏可交互展开控件；实际 VoiceOver 朗读仍待验收。

扩大边界复核后另发现共用 WPS／CPS 的计算顺序缺口：原生按除法／先乘五后除六十，固定单位模块按系数乘法；24.18 WPM 的 CPS 在二进制中分别为 2.015 和 2.0149999999999997，最终两位显示 2.02／2.01。真实 Swift 先行回归一项三断言失败（0 unexpected，0.544 秒），见 `/tmp/typebar-profile-pb-unit-boundary-red.log`。现只修正 `TypingSpeedUnit.converted` 两个显示分支的运算顺序，规范 WPM、计分、保存和输入反向转换不改；资料、历史和图表共享修正，而不是只在新卡片掩盖。显示单位也用于门槛编辑预览，因此纳入 CustomPaceSpeedMigrationTests；仍没有存储迁移或第三方依赖（QA 摘要用系统 CryptoKit）。

新增总数为九项，最终相关 101 项零失败零跳过（13.201 秒），见 `/tmp/typebar-profile-pb-summary-final2-focused.log`，覆盖账户图表、每日活动、单条图表和自定义节奏迁移。前一相关 101 项因未传趋势插件归档跳过一项，见 `/tmp/typebar-profile-pb-summary-boundary-focused.log`；补齐同一已验证归档后完整重跑，不计为最终零跳过证据。源码显式格式化增至 100 组（加入 24.18／24.66），另对五单位各 0–420 WPM、0.01 步进的 210,005 个规范值／单位组合，比较整数与两位显示的 SHA-256 摘要；五组全部一致，不只比较数学近似值。此范围不等于任意浮点、所有旧格式化消费者或 UI 像素等价。

因上述边界，本阶段第一轮完整门禁在测试仍运行时由本会话主动停止，仅向已验证属于该轮的 swift-test／xctest 两个 PID 发送 TERM，确认命令退出码 1、两个子进程消失后才编辑。原生套件未结束，服务和打包未运行，不作为最终通过证据；主日志 `/tmp/typebar-profile-pb-summary-final-readiness.log`，42 份分项从确切自有临时目录复制至已确认空的 `/tmp/typebar-profile-pb-summary-final-logs.uPlF7I` 保留。随后重新冻结九个文件并另起完整串行门禁；未终止其他测试或 Typebar 进程。共用转换的兼容性、排序与未知边界经过同会话有界决策／风险复核，不是独立评审；完整 goal active。

本阶段第二轮最终完整串行门禁退出码 0：原生 3,479／服务 477 项零失败零跳过，分别 762.391／10.846 秒；十万词耐久 152.191 秒，16 项隔离磁盘迁移／冷读 6.633 秒。1,032 条唯一人工场景仅结构通过，真实验收状态不升级。原版固定源码、原创性、未开窗应用包和签名检查通过，九个冻结文件哈希一致，参考 checkout 仍干净且固定于上述提交。主日志 `/tmp/typebar-profile-pb-summary-final2-readiness.log`，44 份分项保留于 `/tmp/typebar-profile-pb-summary-final2-logs.DAdqLz`。完整命令终止后只补文档，不再改代码、测试、脚本和机器矩阵；第一轮主动停止记录不作为最终通过证据。本轮无真实账户写入、部署或 Typebar 图形启动，真实窗口、VoiceOver、设备及整体功能等价仍开放，goal active。

## 原生账户个人最佳表

账户历史新增“账户个人最佳…”入口，按计时／字数／自定义／禅切换，展示该账户独立 PB 快照的全部配置，不受已载入一千条历史、近期二十条、当前筛选或历史删除影响。既有本机最佳表和公开资料卡保留；账户表不混入本机账本、标签 PB、排行榜 PB 或当前设置。它读取现有公开资料端点中当前账户的 `personalBestSnapshots`，不重算、投稿、授奖或改写任何缓存；端点仍是用户连接的 Typebar 服务，不使用官方账号协议。

固定参考 [PbTablesModal.buildRows](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/modals/PbTablesModal.tsx) 按 mode2 分组，遵循 JavaScript Object.keys 的整数键顺序，每组按保存 WPM 降序且同速稳定，首行标记组开始。[UserProfile](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/profile/UserProfile.tsx) 仅在账户页提供完整表入口。原生独立实现这些行为；额外提供四种模式切换，不复制 TSX、样式或资产。Raw、准确率、稳定度、语言、难度、标点、数字、lazy 与接受日期都保留，速度／Raw 使用已有五单位和小数偏好；日期含本地时分，完整快照取服务器接受毫秒，旧基线保留已知完成日期并标记旧历史。旧服务标准档摘要明确标为不完整，缺 Raw／配置保持未知；已知空账本不复活旧摘要。旧响应只有明确 duration／wordLimit 时可建立数值分组，不反推未知参数。

请求固定调用时的 API 地址，开始和返回均检查取消、账户／服务器与共享会话代次，并验证响应用户 UUID；注销重登同账户或地址离开再返回也拒绝旧响应。视图真实 task identity 和缓存可见性同时包含代次与刷新 UUID，旧任务的迟到成功／失败不能覆盖新视图，也不能清除新任务忙状态。普通同账户资料刷新不使表失效。关闭 sheet 由 SwiftUI 取消 task，真实窗口生命周期和 URLSession 仍待验收。

界面采用现有系统字体和动态语义颜色，组首参数作为导航锚点，速度等宽突出、配置与时间次要，原生 List 延迟行、模式分段和明确刷新；无图像、动画或新依赖。没有有效的无窗口 UI 先行红测，因此以固定完整源码函数、模型、实际 AccountSession 和编译取证；不将缺类型编译错误计作产品红灯。SDK 的既有 List／task／Picker 路径和 macOS 14 目标编译通过，不等于最低设备或 VoiceOver 验收。

新增十一项测试，相关 66 项零失败零跳过（4.061 秒），日志 `/tmp/typebar-account-pb-table-final-focused.log`。真实视图任务标识的原表达式提取后，一项一个失败断言复现同账户 ABA，见 `/tmp/typebar-account-pb-table-identity-red.log`；旧参数排序先行一项四断言失败，见 `/tmp/typebar-account-pb-table-legacy-red.log`，随后两处均修正。另覆盖失败重试、错误 UUID、过期点击无请求、取消忽略替身、服务地址 ABA、缓存／XP 不变、分数与同速伴随字段。首次编译因 TestMode 没有 Identifiable 失败，明确 id 修正；初次两个夹具把零／超大参数伪装成完整服务 PB，单独复现于 `/tmp/typebar-account-pb-table-fixture-repro.log` 后按实际协议修正，未放宽生产准入。该夹具错误不算功能红灯。

QA 仅动态执行只读固定源码的完整 buildRows，在自有 DB.getSnapshot 适配器上进行 24 组模式／规模／旧响应对照，包含 0／1／8／25 条、不同配置、精确速度／同速、整数键与超大旧键顺序、旧响应缺 mode2；缺快照／缺模式返回空也验证。不是完整 Solid、DataTable、DOM、真实 HTTP 或官方 schema 准入，假数据不包含原版正文。源码／测试脚本不随产品打包；现有格式仍归档 33、设置 5、偏好 v3、五实体／32 成绩列、CSV 41 列，服务协议／数据文件不变，无迁移、回填或旧 writer 改动。回退只移除新只读入口，不改变成绩或账本。

首轮完整门禁原生 3,470 项／两处断言失败（750.953 秒）：新十一项均通过，页面／弹窗证据审计仍硬编码只读 TypingEngineTests 与 HealthRouteTests，故误判新文件的两个已存在测试符号缺失。命令行审计本来就扫描完整测试目录；XCTest 现按相同两个测试根递归读取 Swift 文件，原有分区、数量、路径和缺符号拒绝断言不变。修正后相关 67 项零失败零跳过（9.024 秒），见 `/tmp/typebar-account-pb-table-audit-focused.log`。失败轮没有进入服务测试或打包，不算最终结果；总日志 `/tmp/typebar-account-pb-table-final-readiness.log`，41 份分项从确切自有临时目录单独复制到原空目录 `/tmp/typebar-account-pb-table-final-logs.SDQ02i` 保留。修正只在运行终止后进行，随后另行冻结并完整重跑。

源码驱动、行为先行、原生设计、迁移边界与同会话有界决策／风险复核影响该实现；不是独立评审。MET-43 与整体功能等价仍部分兼容，真实网络、布局、焦点、键盘、VoiceOver、旧发行和设备仍开放，完整 goal active。本轮零 Typebar 图形启动；下方是此前账本阶段记录。

2026-10-06，服务账户的个人 PB 与排行榜 PB 已从可删除历史分离，接入首次接受、公开／好友资料、全部时间速度榜及 English 60 秒分布。原生资料卡显示完整分组、Raw 和记录日期；后续 [本机与标签账本](LOCAL_PERSONAL_BEST_LEDGER_CONTRACT.md) 也已独立保存并接通原生归档 28 传输，真实双机、官方协议与原版标签 ID 仍开放。完整 Monkeytype 重写目标仍 active。

本阶段最终完整串行门禁退出码 0：原生 3,470 项／服务 477 项零失败、零跳过，分别 751.818／10.841 秒；十万词耐久 151.148 秒，16 项隔离磁盘冷读 6.369 秒。1,029 个唯一人工场景仅结构通过，状态未升级。固定源码、原创性、未开窗应用包及签名检查通过，八个冻结文件哈希一致，参考仓库仍为上述固定提交且干净。主记录 `/tmp/typebar-account-pb-table-final2-readiness.log`，43 份分项日志保留于 `/tmp/typebar-account-pb-table-final2-logs.U6U6Ow`。先前失败轮不计入最终通过证据；完整命令终止后只补文档，不再改变代码、测试、脚本或机器矩阵。本轮无真实账户写入、部署或 Typebar GUI 启动，完整 goal 保持 active。

## 固定源码规则

参考固定于 `91bd24bb8513785c7364cbea29296ff7adafac41`。[完整 PB 工具](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/pb.ts) 按 mode、mode2、difficulty、language、punctuation、numbers、lazyMode 分组。custom／zen 各用固定 mode2；只有严格更高 WPM 才替换整条快照，同速不因 Raw、准确率或稳定性更好替换。记录日期取接受时服务器毫秒，不取客户端完成时间。

[用户 DAL](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 只在创建个人 PB 后保存变化。新输入是非 lazy 的 time 15／60 才触发榜单 PB 更新，但随后从同桶所有语言、所有选项的已有个人 PB 选择，包括 lazy 候选；榜单 PB 也只接受严格提升。内部 resetPb 只清个人 PB，公开 clearPb 清两套 PB。[公开控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/user.ts) 另清日榜，不清周 XP；退榜清榜单 PB，保留个人 PB。引语、中止和不合 PB 资格的输入沿用已有独立准入规则。

## 存储与消费者

PersonalBestLedger v1 保存两套数值快照。新成绩在原子保存中写入不可变 PersonalBestReceipt，绑定账户、UUID、配置、速度、准确率和接收时钟；可见快照必须与首次接受记录一致。仍存在的历史另绑定语言、mode2、伴随指标和完成日期，有精确日期的记录不能用旧整秒容差。这是数据一致性检查，不是防篡改签名。

删历史不删两套 PB；重复 UUID 不重建历史、不换快照、不再奖励。公开清空后重试旧 UUID 不能复活 PB。下一条不同 UUID 的成绩即使与清空使用相同日期，也可建立新 PB。持久日榜按账户清理；旧构造入口的历史日榜按成绩身份排除，避免同毫秒旧记录回来或新记录被隐藏。清空保留成绩、累计练习、XP、周榜和徽章。账户重置／删除清除对应账本，保存失败沿用全状态回滚。

公开资料增加 personalBestLedgerVersion=1、personalBestHistoryComplete 和 personalBestSnapshots。三者须同时存在；部分缺失、显式 null、未知版本、坏快照或重复分组拒绝，不能降级成旧服务。已知空数组不回退到旧 personalBests；后者仍提供八个标准档供旧客户端使用，原生资料卡使用完整快照，包括 custom／zen。公开 Raw、准确率、稳定性和配置是 PB 伴随字段；提示、回放、按键计数、标签、邮箱和凭据仍不公开。

all 的官方 time 15／60 读取独立榜单 PB；其他参数／模式的 all 和历史 week 速度榜是既有 Typebar 扩展，不声称原版榜单身份兼容。好友、隐身、封禁、限制和最低练习时长筛选保留。公开最高稳定性保留此前可见历史中的较高值，不把较慢成绩的稳定性改写到最快 PB 快照；删历史后至少保留账本的伴随稳定性。

客户端清空前确认 v1/typebar 的 accountPersonalBestLedger=available；旧服务和未知／partial／planned 能力拒绝发送破坏性请求，提示升级。能力请求和重新认证后复核账户、令牌与服务地址。资料读取兼容完全没有新版字段的旧服务。界面沿用原生资料卡、系统字体，仅调整分组和数值层次，不改主题或增加动画。

## 旧数据迁移与回退

缺整个账本且没有新 PB 回执的旧文件，按可见历史冻结基线，不重新计分。旧公开重置边界用于个人基线，旧全部榜可见值单独保留。已删除历史无法恢复，缺配置、参数、两位速度和精确接受日期不补造。所有旧账户标记历史不完整，快照 origin=legacyHistory，接受毫秒留空。加载不写文件，下一次普通保存才提交基线；坏字段、管理标记下丢账本或新回执下丢账本拒绝加载且保留原字节。

缺配置是独立未知分组，不等于 normal/false。旧 Typebar 客户端缺配置的 time 15／60 可更新自身未知分组榜项，但不借此提升已知 lazy 候选；这是兼容扩展，不是原版准入证明。旧成绩缺词数保留 unknown 分桶，显示“词数未知”，不补成 10／25。明确新输入的完整分组按源码更新。

账户阶段没有改变 SwiftData 本机实体、归档 27 或设置文档 4；后续本机账本新增第五实体，归档与设置尚不运输账本。账户升级需备份服务文件、停止旧 writer，先服务后客户端；禁止混写。回退恢复升级前备份或向前修复，备份后新增数据可能丢失，不承诺无损降级。本阶段没有部署或操作真实用户库。

## 验证与剩余范围

原生先行 3 项产生 18 个失败断言，服务先行 5 项产生 17 个失败断言。新增原生 8 项、服务 15 项覆盖完整／未知分组、首次同速快照、删除重载、清空重试、原子失败、并发重复、损坏／丢失／错误账户、迁移、实际 HTTP、退榜和日期。另一个精确日期反例先复现 1 个失败，再修复。两项旧迁移夹具移除新账本字段，继续验证旧格式，而不允许损坏新账本加载。

最终原生相关 30 项零失败／零跳过（0.330 秒），服务 PB 15 项零失败／零跳过（0.362 秒）。前一服务全量 419 项通过（9.780 秒），之后新增精确日期反例并修正对应检查；完整门禁作为最终全量依据。

最终完整串行门禁原生 3022 项／服务 420 项均零失败、零跳过，分别 699.882／9.731 秒；十万词耐久 149.872 秒，九项隔离磁盘迁移 4.051 秒。911 个唯一人工场景仅结构通过；固定源码审计、原创性及未打开应用包与签名检查通过。主记录 `/tmp/typebar-pb-ledger-readiness.log`，十五份详细日志保留于 `/tmp/typebar-pb-ledger-readiness-logs.p5gaZQ`。门禁结束后只更新文档，不改生产或测试文件。

QA 动态执行固定完整 PB／Funbox 模块和四条有界完整 DAL 函数，自造集合适配器输出 42 步变化，Swift 对照两套账本的数值、分组和记录毫秒；既有 16 组替换、28 组分组、7 步生命周期保留。不是 MongoDB、完整控制器、队列或图形验收，没有复制参考源码或资产到生产。

本会话风险复核检查接受、迁移、删除、清空、授权和回滚，不是独立评审或整体等价认证。三条 PB 账本人工场景待单窗口、真实网络及 VoiceOver 验收。本机／标签账本跨设备传输、原版标签 ID 目录、全量内容与主题身份、原协议、真实旧发行、macOS 14／Intel 和完整功能等价仍开放。Typebar GUI 启动数为零。
