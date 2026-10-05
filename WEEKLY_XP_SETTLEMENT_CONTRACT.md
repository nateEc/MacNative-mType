# 周 XP 奖励配置与结算准备

当前实际任务、邮件持久化与原生领取已接通，见 [奖励收件箱与周任务交付](REWARD_INBOX_CONTRACT.md)。以下保留先前配置准备阶段的源码规则和验证记录，其“尚未接入”描述是历史状态；实际运行、迁移和差异以新合同为准，完整重写 goal 仍 active。

## 固定源码的奖励规则

[固定 worker](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/workers/later-worker.ts) 读取结算时配置和指定上周缓存。取所有档位中最大的 maxRank 作为查询数量；空榜不送邮件。符合名次区间的奖励从 maxReward 向 minReward 插值，再裁切到两端之间；重叠档位取最高值，单名次档取 maxReward。最后对奖励作非负半数向上舍入；零奖励仍生成邮件，不匹配的名次不生成。

启用且档位为空时，源码的 length 小于零检查不能保护 Math.max 空数组。查询收到负无穷而报错，即使收件箱禁用也如此；不能伪装成成功的零奖励。maxRank 为零时原查询会读到整个榜，但没有正名次匹配零名次档；Typebar 计划直接产生空候选，输出相同，不声称查询过程相同。

[档位 schema](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/schemas/src/configuration.ts) 要求四个非负整数且拒绝额外字段，却不限制端点顺序。Typebar 保留倒置名次区间及升序奖励端点，但独立限制整数不超过 9,007,199,254,740,991；源码整数 schema 及 isSafeNumber 并未提供这个安全整数上界。该更严格的数值域是明确差异，不宣称整个配置域等价。

## 调度与邮件不是自动入账

[固定 LaterQueue](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/queues/later-queue.ts) 使用本地周 key，目标时间为 key 加七天加一分钟；原始 delay 可以为负。任务最多尝试 23 次，失败间隔一小时，成功和最终失败均移除。LRU 版本 11.5.1、容量 100 抑制重复安排，超过容量后可再次入队。Typebar 描述保留时间和重试参数，使用自有身份 weekly-experience 加 key，不复制队列代码；这些属性不是一个可恢复队列。

[MonkeyQueue](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/queues/monkey-queue.ts) 没有初始化连接时 add 不执行，LaterQueue 仍记入 LRU；探针保留这个反例。未来 Typebar 持久任务须显式处理失败和恢复，不把这条源码观察当作可靠交付保证。原版实际 BullMQ 1.91.1 的调度、锁、失败重试和分布式竞态尚未运行。

[用户 DAL](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 将奖励放进未读邮件；读取或删除未读邮件时才领取，已读邮件不可再次领取。插入在收件箱开关关闭时不执行，开启时前插并按 maxMail 截断；maxMail 为零仍发出 Mongo push，但不保留邮件。容量丢弃不是主动删除领取。Typebar 尚未接入这条数据链，不能复用现有关系通知冒充奖励收件箱。

[用户接口合同](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/contracts/src/users.ts) 的 GET 和 PATCH inbox 均要求收件箱启用；仅查看控制器函数会遗漏该门禁。未来领取不能复用成绩奖励的 BSON 低位转换：DAL 的邮件领取使用当前 XP 加奖励，且不写回周榜。真实 Mongo 空 bulk、部分写入失败及重试行为仍待验证，观测适配不能保证空候选的执行成功。

## 当前独立实现与迁移边界

WeeklyExperienceSettlementPlanner 只读已有有效缓存条目，按原始分数及反向 UUID 同分排序，使用全局公开分数投影，保留活动秒数，计算未领取候选。禁用周榜返回空计划，启用空档抛出明确错误；收件箱禁用在查询准备之后抑制输出。计划不修改缓存、账本、账户或磁盘。时间描述保留已捕获 key，不在重试时重算周分区。

TYPEBAR_WEEKLY_XP_CONFIGURATION 现在保留 xpRewardBrackets，例如：

```json
{"enabled":true,"expirationTimeInDays":15,"xpRewardBrackets":[{"minRank":1,"maxRank":10,"minReward":50,"maxReward":200}]}
```

旧 JSON 缺档位时读取为空，不猜测历史奖励；显式 null、错误形状、负值及不安全整数拒绝。新投稿的现有 weeklyCacheReceipt 配置保存档位，重复投稿不覆盖首次配置。冻结投稿配置不代表未来结算使用该配置：固定 worker 使用结算时配置，该差异必须在接通任务时保持清楚。

Typebar 默认仍启用、保留 15 天、无档位；固定 base 配置是禁用、零天、空档位，收件箱默认禁用且容量零。这不是线上配置声明。由于计划尚未调度，默认空档位不会改变现有成绩接受或账户 XP；未来运行结算须显式配置并显示失败，不能默认悄悄发奖。

现有原生协议、SwiftData 列、归档 26 和设置 4 均不变。单服务 writer 升级前备份完整 JSON；旧 writer 会丢弃新配置字段，不允许混写或直接覆盖唯一新文件。缺字段兼容读取不是无损降级证明，恢复使用完整旧备份或向前修复。未操作真实库、真实部署或系统时钟。

## 自动化证据与未完成验收

配置红阶段在生产改动前执行，两个测试出现五条预期断言失败：档位被丢弃，非法显式档位被忽略；日志 /tmp/typebar-week-rewards-configuration-red.log。独立实现后十二项聚焦测试零失败、零跳过，0.540 秒；日志 /tmp/typebar-week-rewards-focused-green.log。实际 AuthStore 文件往返补验后，配置五项零失败、零跳过，0.019 秒，验证新配置冻结、旧缺字段不回填和读取字节不改；日志 /tmp/typebar-week-rewards-migration-green.log。

Scripts/check-source-weekly-xp-rewards.mjs 动态读取完整原版 worker、队列、周榜服务、数字及日期工具、邮件构造器，以及完整 addToInboxBulk 函数。它在隔离 Unix socket Redis 6.2.6 执行完整 get-results Lua，使用实际 LRU 11.5.1，观测 12 组时钟、56 组奖励计算和 16 组 worker 场景，再与独立 Swift 比较。固定参考提交及干净工作树前后检查，不复制源码到生产、不输出原版邮件文案、不启动 GUI。

BullMQ 和 Mongo 使用明确观测适配，schema、格式化及日志也有 QA 边界。Mongo push 的位置和容量被观测，真实数据库截断、部分失败、事务、任务锁、幂等交付、邮件领取和原生消费者均未验证。该探针不是原版整站启动。新增检查及隔离依赖准备接入串行 readiness，未弱化旧门禁。

本轮完整串行门禁通过：原生 2951 项，687.838 秒；服务 315 项，6.907 秒，均零失败、零跳过。十万词逐词耐久 148.992 秒，九项隔离磁盘迁移 3.846 秒；884 条人工清单只通过结构检查，原有源码差分、新奖励探针及未开窗应用包／原创边界检查通过。CoreData XPC 警告不作为测试结论，以上以 XCTest 最终断言汇总为准。门禁期间冻结文件，结束后仅补记文档；没有 Typebar GUI、真实用户库或部署。主日志 /tmp/typebar-week-rewards-final-readiness.log，完整测试日志 /tmp/typebar-week-rewards-final-client-tests.log 与 /tmp/typebar-week-rewards-final-service-tests.log，来自本轮唯一临时目录而非旧日志。

完整奖励任务、收件箱、日榜奖励、premium、PB 缓存、真实恢复和规模、macOS 14／Intel、单窗口人工验收及整体功能等价继续开放。当前程序不会因这个阶段自动送出或领取周榜奖励。
