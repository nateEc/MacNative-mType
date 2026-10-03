# 完成统计提交与历史边界

本轮补齐自建服务的按键稳定度保存与读取，以及完成请求中的独立 WPM 稳定度。固定原版只保存输入节奏和按键稳定度，不保存 WPM 稳定度；因此不为它新增本机固定值或升级归档。上一轮把“WPM 固定保存”列成原版缺口的结论在此纠正。完整重写目标保持进行中。

## 固定原版的数据链

参考提交为 91bd24bb8513785c7364cbea29296ff7adafac41。[完成事件构造](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L725) 独立计算三个百分比，[完成事件 schema](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/packages/schemas/src/results.ts#L123) 要求瞬时 wpmConsistency。[数据库构造函数](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/result.ts#L19) 明确投影保存字段，[控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts#L655) 将它交给 DAL 插入，未再追加 WPM 指标。

| 指标 | 完成请求 | 原版数据库 | 原生处理 |
| --- | --- | --- | --- |
| consistency | Burst 输入节奏 | 保存 | 保持已有字段和消费者 |
| keyConsistency | 真实间隔去掉最后一项 | 保存 | 协商扩展并保存可选历史值 |
| wpmConsistency | 整场累计正确速度 | 不保存 | 后台计算并仅瞬时提交 |

Scripts/check-source-result-consistency-boundary.mjs 只读运行完整 backend/src/utils/result.ts。四组自有完成事件证明构造保留前两项、排除 WPM 项且不改输入事件。ObjectId 与擦除类型是显式适配；不执行 MongoDB、控制器、Zod schema、完整完成生命周期或闭源反作弊。源 schema 和调用链是阅读证据，不冒充运行证据。原版结果页没有独立 WPM 标签；已有 Typebar 详情与本机 CSV 是原生补充，不计为原版 UI 或持久字段覆盖。

## 自建服务协议与消费者

沿用自有 /v1 路由而非官方线上协议。只有 apiVersion=v1、service=typebar、resultConsistency=available 全部明确匹配，客户端才增加匿名 resultConsistency 对象。version=1 与 keyConsistency 必填，wpmConsistency 可选；缺少可靠字段的旧回放不猜 WPM，也不写假零。旧服务、未知版本／身份或 partial／planned 状态保持原请求，且不启动新 WPM 计算。其他输入计量、有效时长和物理证据能力继续各自协商，不降低 v2 计量要求。

WPM 使用上一轮编译器检查的值快照后台计算，不传 SwiftData 模型或使用 @unchecked Sendable。准备前与后台完成后检查取消；AccountSession 在等待之后、POST 之前再次核对原账户和服务范围。已取消的准备不返回可提交正文；不发送提示、回放、原始间隔数组、物理键码或目标目录。请求计算仍有长场成本，账户切换的真实 UI 和网络生命周期尚待验收。

服务校验指标版本和有限的 0–100 百分比，非法值不静默忽略。这只是客户端自报统计的形状检查，不是防作弊或真实物理测量证明。既有速度、准确率、时间、认证、资格与输入计量校验保持。新 StoredResult 只保存可选 keyConsistency，账户自己的列表／详情和标签更新共用同一响应投影；wpmConsistency 与整个瞬时对象不进入服务文件或历史响应。重复 UUID 沿用首次保存的按键值，不能以重试正文覆盖。

RemoteAccountResult 接受缺失按键值并拒绝损坏百分比。历史行沿现有 caption 样式显示按键稳定度，旧服务值缺失时显示不可用；远端 CSV 只在原 17 列之后追加 key_consistency_percent，缺失留空，已有列身份、顺序及值保持。远端 CSV 不新增 WPM 列，也不把本机派生值混入远端历史。

## 迁移与回退

本机 CompletedTestResult、归档版本 22、SwiftData 实体及其 JSON 均不变，不回算或回写旧成绩。自建服务文件增加可选 JSON 键，没有回填；真正旧服务文件和旧客户端提交缺字段仍可读写，混合记录保存重载已在独立临时文件验证。新客户端对旧服务保持旧形状；旧客户端对新服务仍可提交但没有按键指标，新服务不补造。

没有执行真实部署、旧二进制降级、数据库迁移或多版本并行服务。降级前须保留服务原始文件副本：旧程序可能忽略新增键并在重写时丢失按键值，不能保证可逆。没有删列、回填、批量历史重发或改变同步归档协议。能力只表示这项自建功能的本机实现，不升级整个 resultSubmission／resultHistory、官方配置、主题、词库或 Funbox 的部分状态。

## 行为证据与复核

客户端四项先行测试七处预期失败（0.462 秒），服务端三项六处预期失败（0.552 秒），明确复现统计被忽略和非法值未拒绝。实现后相关客户端 66 项零失败（2.101 秒）、服务端 22 项零失败（0.081 秒）。补入合作取消、非法历史、百分比端点、非有限直接值、混合文件／重启／幂等与认证 HTTP 路由后，八项客户端和七项服务新增回归分别纳入相关 70 项（2.103 秒）和 26 项（0.097 秒）；再包含旧远端 CSV 分页／变化保护后最终定向客户端 71 项零失败（2.107 秒）。没有削弱旧列或分页断言。

HTTP 证据来自进程内 XCTVapor 测试，不监听真实端口、不请求真实账户或外部服务。保存证据来自测试创建并清理的 UUID 临时文件，不是用户数据库；实际源码构造四组对照单独通过。Swift 6／macOS 14 包目标与已锁定 Vapor 4.122.1 继续沿用，无依赖变化。源码驱动、行为优先及会话内有界决策／风险／迁移复核决定瞬时与保存边界；设计技能保持现有原生行样式，文档技能纠正错误缺口。这不是独立评审或完整功能等价证明。

冻结源码后的最终串行门禁已通过：客户端 2,439 项零失败（585.631 秒），服务端 145 项零失败（1.451 秒）；本轮实际十万词耐久通过（144.282 秒），不是沿用上一轮结果。未打开应用包的构建、签名与资源边界检查均通过，固定参考目录保持干净。完整门禁日志为 /tmp/typebar-consistency-publication-final-full-gate.log，完整客户端与服务端日志分别保留在 /tmp/typebar-consistency-publication-final-client-complete.log、/tmp/typebar-consistency-publication-final-service-complete.log；通过耐久后另存的 through-endurance 日志只是中途快照，不冒充完整日志。Typebar GUI 保持为零，真实背景练习路径不存在；人工验收仍待实机，完整 goal active。
