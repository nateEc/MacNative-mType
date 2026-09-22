# 官方公开练习统计审计

## 固定参考与边界

- 参考仓库固定提交：`91bd24bb8513785c7364cbea29296ff7adafac41`。
- 本审计只盘点用户可见行为；不复制参考项目的 TypeScript、接口路径、响应名称、数据库结构、词表、成绩或任何资产。
- Typebar 使用独立的 Swift/Vapor 实现和其自建服务中已有的用户与已接受成绩；不会读取或导入 Monkeytype 的线上数据。

## 参考行为证据

| 参考位置 | 可观察行为 | Typebar 的独立映射 |
| --- | --- | --- |
| `frontend/src/ts/components/pages/AboutPage.tsx` | About 页面显示全站开始测试数、总输入时长、完成测试数和速度直方图；查询只在 About 打开时启用。 | 独立“关于 Typebar”窗口打开时读取自建服务汇总，并提供用户主动的“重新读取”；不会在应用启动时请求，也不轮询。 |
| `frontend/src/ts/queries/public.ts`、`frontend/src/ts/utils/numbers.ts` | 开始／完成数在数量很大时以小数数量级主值和完整总数说明保持可读。 | `PublicPracticeStatisticsPresentation` 以 Typebar 自有的中文数量级卡展示 1,000 以上的公开次数；原始整数仅供辅助功能读取，不改写服务响应或本机数据。 |
| `frontend/src/ts/queries/public.ts` | 速度图固定查询 English／time／60，按缺失的相邻十 WPM 桶补零。 | `/v1/public/speed-distribution` 固定汇总 English、60 秒、time 成绩；原生图表只补相邻空桶，不制造任何成绩记录。 |
| `packages/contracts/src/public.ts` | 直方图是按十 WPM 分组的用户个人最佳计数；总览含开始数、完成数和输入时长。 | 每个允许公开统计的 Typebar 账户最多贡献一次最高 WPM；总览返回完成成绩数、已开始测试数和实际输入秒数。 |
| `backend/src/dal/public.ts` | 完成一次成绩时累加开始次数、完成数和时间，并读取已有直方图汇总。 | Typebar 从自己的持久化结果即时派生，不新增数据表或迁移；首次接受成绩时既有 `restartCount + 1` 已作为开始次数保存。 |

## 自建契约与隐私

- `GET /v1/public/practice-stats` 无需认证，返回 `completedResultCount`、`startedTestCount` 和 `totalTypingSeconds`。
- `GET /v1/public/speed-distribution` 无需认证，返回十 WPM 桶大小和非空桶；它只考虑 English、60 秒、time、存在输入事件的已接受成绩，并为每个账户取最高 WPM。
- 两个响应都不包含账户 ID、展示名、邮箱、提示文本、实际输入、回放、令牌、单条时间戳或单条成绩。
- 选择 `leaderboardOptedOut` 的账户，以及处于排行榜限制、显示名整改或账户封禁状态的账户，均不会对这两个汇总贡献数据；状态撤销后，既有合格数据才会重新纳入。
- 原生客户端不发送 Bearer 令牌；仅在 About 窗口打开或用户按“重新读取”时发起两个只读请求。服务地址在请求中途改变时，响应会被拒绝，防止旧地址的结果覆盖当前地址。
- 较旧的自建服务会返回不可用或不支持状态；本机 About 仍可正常使用，且不会用本地成绩伪造全局汇总。

## 自动化与人工验收

- 服务端：`HealthRouteTests/testPublicPracticeStatsExposeShareableSummaryAndEnglishMinutePersonalBestBuckets` 验证匿名总览、重开计数、每账户个人最佳及隐身账户完全排除。
- 服务端：`HealthRouteTests/testCapabilitiesDescribeTheActualServiceScope` 验证 `publicPracticeStatistics=available` 仅在实际路由已配置时声明。
- 原生：`TypingEngineTests/testPublicSpeedDistributionFillsOnlyGapsBetweenReportedBuckets` 验证图表只补两条已报告桶之间的十 WPM 空档，并保持真实参与账户总数。
- 原生：`TypingEngineTests/testPublicPracticeStatisticCountsUseReadableMagnitudeCards` 验证公开次数的零值／千／百万边界、两位小数、整数量级舍入与负值回退，且保留完整计数。
- 部署人工验收：在可访问的自建服务创建可公开的两个账户、提交 English 60 秒成绩并打开 About；确认三项总览、柱形图和“每账户仅一条最佳”说明。随后让其中一个账户开启隐身并重新读取，确认其成绩和柱形贡献同时消失；将客户端指向未升级服务，确认只显示不可用说明，不影响离线练习或 About 其余内容。
