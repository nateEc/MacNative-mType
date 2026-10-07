# 账户个人最佳账本与公开清空

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
