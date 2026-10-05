# 日榜任务与奖励交付

正式自建服务现已将 time／words 日榜投稿接到持久结算任务、原生奖励收件箱和原生榜首公告。任务与邮件及公告一起提交，重启或重试不重复交付；奖励仍需领取才能进入账户 XP。完整功能等价尚未成立，尤其原版 Discord 公告渠道没有实现，本地公告不是该渠道的替代验收。

## 原版行为与独立实现

参考提交为 91bd24bb8513785c7364cbea29296ff7adafac41。[完整日榜服务](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/daily-leaderboards.ts) 在有效投稿匹配 scheduleRewardsModeRules 时安排任务，不以返回名次作为条件。同速未变更、零容量淘汰或立即过期仍安排；本实现按接受日和具体语言、模式、限制值保存一个任务，首次回执记录是否已安排，同 UUID 重试不会重新安排。

[完整 later 队列](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/queues/later-queue.ts) 在 UTC 次日一分钟后执行，失败按一小时重试，最多 23 次。[完整 worker](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/workers/later-worker.ts) 使用结算时配置，读取公告人数和奖励档位最大名次中的较大值。日榜空档位仍可公告，不存在周任务的空档位页大小错误；收件箱禁用仅抑制发信，不抑制公告。零 XP 档位也生成未领取邮件，未匹配名次不发信。

Swift 复用独立奖励插值实现，保持重叠取最大、先插值后舍入与获胜缓存排序。删除成绩历史不删除缓存，不用当前昵称重建获胜快照，也不把领取 XP 写回日榜或周榜。过期或清空的桶、结算时禁用的日榜完成为空任务，不补造历史或以后补发。

## 配置与服务入口

TYPEBAR_DAILY_LEADERBOARD_CONFIGURATION 新增三个字段。旧缺字段默认空奖励规则、公告一人和空奖励档位，因此升级不会自动对旧投稿安排任务；显式 null、公告人数零、非法正则和非法档位拒绝。默认仍启用缓存，但没有奖励规则，不安排任务。要启用交付，部署者须显式提供匹配规则和所需 XP 档位。

```json
{"enabled":true,"expirationTimeInDays":2,"maxResults":1000,"validModeRules":[{"language":"english","mode":"words","mode2":"25"}],"scheduleRewardsModeRules":[{"language":"english","mode":"words","mode2":"25"}],"topResultsToAnnounce":1,"xpRewardBrackets":[{"minRank":1,"maxRank":10,"minReward":50,"maxReward":100}]}
```

原有唯一生命周期循环同时处理周任务和日任务，没有新增服务 writer、Typebar 窗口或外部连接。GET v1/moderation/daily-rewards 需要非空部署者密钥，只读任务状态，不提供匿名或用户触发发奖的接口。日奖励沿用 GET／PATCH v1/inbox 和现有原生入口；榜首中文纯文本进入 GET v1/announcements，沿用原生展示和本机关闭功能，日期明确标 UTC。名单公开前检查当前 opt-out、封禁、限制与昵称整改；无邮件、邮箱、设备或私人历史字段。

## 持久化与恢复

服务文件增加 dailyRewardJobs、dailyRewardJobsManaged；dailyCacheReceipt 新增可选 settlementScheduled，缺失表示旧来源未知，不推测安排过任务。旧缺任务且没有明确已安排回执时仅初始化空任务，纯加载不写文件。托管标记为真却丢失任务、显式 null、重复身份、坏版本、非法计数或已安排回执缺对应任务均拒绝，原字节不变；账户重置后标记仍保护完成任务状态。

每个任务的邮件、公告及完成状态只做一次文件提交。保存失败回滚到未尝试任务，无部分邮件或公告；恢复完整备份后重试。计算错误保留原状态并记录一小时后的重试，23 次后终止。当前直接验证了重试状态边界，没有通过真实计算故障执行 23 次 worker；真实文件保存失败验证的是回滚，而非计算错误的计数路径。

升级及恢复须完整备份、唯一 writer，禁止新旧二进制混写。已完成任务保留去重记录，即使账户重置也不重新交付；原版 LRU 容量 100、BullMQ 完成及失败移除策略没有被声明等价。没有跨进程锁、多服务容错或目录 fsync 的崩溃证明。原生 SwiftData、归档 26 和设置 4 不变。

## 验证与未完成工作

生产改动前，现有生命周期反例出现三处预期失败，分别是无日奖励邮件、无奖励条目及无榜首公告。接线后 14 项聚焦测试通过，覆盖实际投稿、接受日与具体模式身份、未变更／淘汰／过期、结算配置切换、历史删除、零 XP、收件箱禁用与容量零、并发、真实 rename 失败、重启、损坏拒绝、旧数据不补发、公开可见性和受控 HTTP 状态查询；增加两种损坏断言后再由本批服务全量补验，不混用早期聚焦结果。

源码探针动态执行完整 later worker、日榜服务、later／MonkeyQueue／George 队列、数字及日期工具和邮件构造器，以及完整 addToInboxBulk 函数；Redis 6.2.6 执行原 get-results Lua，LRU 11.5.1 执行去重。12 组日时钟、18 组日结算与公告选择对比独立 Swift，既有 12 组周时钟、56 组奖励计算和 16 组周 worker 继续验证。schema、BullMQ、Mongo 和日志等边界为明确 QA 适配，不证明真实队列或数据库运行。

本次会话内决策和风险复核选择共用生命周期、事务提交及明确旧来源；文档复核区分原生公告接入与尚未实现的 Discord 交付，不是独立评审。测试使用隔离服务文件和内存 Typebar 库，没有运行 GUI、修改系统时钟或部署。人工单窗口、键盘／VoiceOver、最低系统／Intel、真实网络、旧发行迁移、长期规模和崩溃瞬间未验。全部模式、小数 WPM、原协议、完整 PB／premium 以及 Discord 公告渠道继续追踪，整体 goal active。

## 本批最终验证

完整串行门禁终止成功：原生 2965 项，549.450 秒，零失败但有一次可选十万词跳过；服务 368 项，8.742 秒，零失败零跳过。调试核对原因是本次启动遗漏 TYPEBAR_ENDURANCE_TESTS=1，未修改产品或削弱断言。待原门禁及未开窗包结束、核对没有旧测试进程后，只补跑该单项，149.848 秒零失败零跳过。原生覆盖合计仍是 2965 个不同用例，不能将这次分段验证写成单次全量零跳过或 2966 个不同用例。

九项隔离磁盘迁移 3.708 秒通过；893 条人工场景仅结构通过。源码探针、签名、资源边界与原创边界均通过，生产和测试文件在整个门禁及耐久补验期间冻结，结束后仅补文档记录。CoreData XPC 环境诊断不作为 XCTest 失败或实机验证结论。

主日志为 /tmp/typebar-daily-reward-final-readiness.log，原生／服务／源码／应用包明细保存于 /tmp/typebar-daily-reward-readiness-logs.BrypSW，耐久补验为 /tmp/typebar-daily-reward-endurance.log；反例为 /tmp/typebar-daily-reward-red.log，14 项聚焦为 /tmp/typebar-daily-reward-focused-final.log。新增可选 TYPEBAR_READINESS_LOG_DIRECTORY 仅接收已存在的空绝对目录，结束时保留本次明细，不覆盖前次证据；正常无该选项时沿用原清理行为。
