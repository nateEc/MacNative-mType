# 日榜榜尾速度与未上榜提示

2026-10-06，原生客户端和自建服务已接通日榜 minWpm：它是当前筛选与用户范围内的榜尾速度，不是新的投稿拒绝规则。完整范围先确定榜尾，再分页；好友榜不使用全局榜尾。旧服务缺字段保持未知，空的新日榜明确返回 0。原生只在已加载、未上榜且没有更优先账户限制说明时显示入榜参考。

## 固定源码行为

参考固定于 91bd24bb8513785c7364cbea29296ff7adafac41。[完整日榜读取](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/daily-leaderboards.ts#L111) 从 Redis 的 minScore 解出 minWpm；[完整读取 Lua](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/redis-scripts/get-results.lua) 在分页前确定全局或好友过滤人口的最低分，显式空好友数组直接返回 0。页码超出范围仍可返回非零榜尾，不以当前页最后一行代替。

[控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/leaderboard.ts#L129) 将该字段随列表返回；[原生参照的用户名次组件](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/leaderboard/UserRank.tsx#L67) 在退出排行榜、封禁及练习时长不足之后显示最低速度说明。读取字段与设置中的最低练习速度不是同一功能，也不能用这个字段重新判定成绩准入。

源实现先将 WPM 打包舍入，再解出榜尾，小数条目 59.995 对应 minWpm 60，而不是照搬条目 WPM。Typebar 现有成绩与缓存生产仍使用整数 WPM，所以在当前整数域中从完整可见人口取得最低 WPM 与解分数结果一致。本轮客户端保留 Double 元数据并按现有五种单位转换，不宣称已接通小数 WPM 投稿、缓存或整个源参数域。

## 原生生产链路

AuthStore 的公开列表与好友列表使用同一既有日榜选择、隐私过滤和最佳条目规则，在截取页面前计算 minWpm。今天与昨天各自取接受日缓存，淘汰、隐私清除和过期会更新榜尾；删除历史不删除缓存快照。无缓存的历史回退、全时期和周榜不伪造日榜字段。未指定精确模式的 Typebar 聚合筛选返回其既有可见人口的榜尾，不声称这是原版精确分区协议。

RemoteLeaderboardPage 的字段为可选 Double，缺失保持 nil；显式 null、类型错误、负值或非有限值拒绝，不能降级成旧服务未知。旧客户端忽略这个新增响应字段，旧服务不需要立即升级。minWpm 不保存到归档、SwiftData、账户文件或名次记忆；归档仍 27、设置仍 4，没有数据回填或新 writer。

CloudSyncView 沿用已有请求代次和账户范围检查，保存页面后才读取其字段。已上榜、未加载、退出排行榜、封禁、名称要求、受限或练习时长不足时不显示榜尾作为缺席原因。有效未上榜提示使用当前速度单位、两位小数与等宽数字，并注明“入榜参考”；同速时仍需比较准确率和时间，榜尾不是保证入榜的配置门槛。旧服务或非日榜没有该提示。

## 行为证据

改生产前，客户端三项测试出现 8 个预期断言失败，服务两项出现 10 个预期断言失败：字段缺失、坏显式字段被忽略、分页与好友范围没有榜尾。反例日志 /tmp/typebar-minimum-native-red.log 与 /tmp/typebar-minimum-service-red.log。

原生定向 10 项零失败、零跳过（0.004 秒），含新增六项：旧缺失、零与小数往返、显式损坏、日榜提示、非日榜与非有限边界、五种速度单位。相关服务 43 项零失败、零跳过（1.601 秒），含新增六项：完整人口与越界页、好友人口、参数与历史回退、删历史与重载读不改文件、淘汰与隐私清除、实际 HTTP；原缓存、奖励和引语分区回归同时执行。

QA 执行完整固定日榜服务和 Redis 6.2.6 Lua，新增九组整数榜尾读取及一个小数打包边界。九组覆盖首页、中间页、越界、两种非空好友范围、无成绩好友、显式空好友、清除尾成员和全空；独立 Swift 缓存复建、过滤与分页结果逐组对照。既有 120 分数、36 正则、16 生命周期、15 模式映射和六个分区仍验证。schema／队列适配仍是明确 QA 边界，不是完整原版 HTTP 解码或部署。

本轮使用行为优先、源码驱动、迁移安全及会话内风险复核；不是独立评审。字段只读、无持久化改变，旧服务未知不补零，避免把分页最后一行或全局榜尾误作好友门槛。定向日志 /tmp/typebar-minimum-native-focused.log、/tmp/typebar-minimum-service-verified.log，源码探针 /tmp/typebar-minimum-source.log。

最终完整串行门禁成功终止：原生 2981 项、700.499 秒，服务 381 项、9.073 秒，均零失败、零跳过，新增十二项全部纳入全量。十万词实际通过（150.023 秒），九项隔离磁盘迁移通过（3.918 秒）；899 条唯一人工场景仅结构检查通过。固定源码、原创性、元数据、行为对照及未打开 macOS 应用包检查通过。主日志 /tmp/typebar-minimum-readiness.log，13 份详细日志保留于 /tmp/typebar-minimum-readiness-logs.axEsCl，不重复累加定向数量或宣称性能全面提高。

门禁期间没有编辑文件，测试、磁盘 writer 与打包串行；终止后只更新文档证据，生产和测试代码未再改动。没有 Typebar GUI、真实 Typebar 库写入、服务部署或系统时钟修改。Core Data 系统诊断与 XCTest 断言失败分别记录；包检查不代替实际窗口、最低系统或整体功能验收。

## 剩余验收

三条新人工场景全部待单窗口、VoiceOver 和真实网络验收。本轮不启动 Typebar GUI，使用内存 Typebar 库、隔离服务文件和自有 Redis 子进程。小数成绩生产、premium、完整 PB 缓存、原协议和内容身份、原版 Discord 渠道、最低系统与旧发行迁移、崩溃瞬间、多 writer 和完整功能等价仍开放；整体目标未完成。
