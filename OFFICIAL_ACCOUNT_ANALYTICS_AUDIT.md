# 官方账户统计路径审计

固定参考：`91bd24bb8513785c7364cbea29296ff7adafac41`。本审计只记录可观察的统计行为和原生验证线索；不会复制 Monkeytype 的 TypeScript、网页图表配置、样式、词表、账号数据或资产。

| 固定参考路径 | 用户可见行为 | Typebar 原生映射 | 自动化证据 |
| --- | --- | --- | --- |
| `components/pages/account/TestStats.tsx` | 对当前结果筛选显示估算词数、开始/完成、重开比、键入时长，以及 WPM、Raw、准确率、稳定度的最高、总平均和近 10 平均。 | `ResultStatistics` 从本机已完成结果派生同类统计；速度遵循当前 WPM/CPM/WPS/CPS/WPH 显示单位，重开与 AFK 保留本机语义。 | `testResultStatisticsAggregateCompletedTests`、`testCurrentStatisticsUseAnyActiveResultTagButLeaveEmptyStateUnrestricted` |
| `components/pages/account/HistoryChart.tsx` | 显示速度、准确率、10/100 次平均与速度 PB 包络；点按成绩。 | 原生速度和准确率趋势共享最近成绩选择、详情和列表定位；保留独立四轨开关、PB 包络及以实际键入时长估计的进步率。 | `testHistoryChartPolicyMatchesLocalHistoryTracesAndTypingTimeTrend`、`testHistoryChartSelectionChoosesNearestResultAndNewerResultOnEqualDistance`、`testHistoryChartSelectionRevealExpandsRequiredPagesWithoutHidingLoadedRows` |
| `components/pages/account/HistogramChart.tsx` | 以当前速度单位分桶显示完成次数。 | `SpeedHistogram` 在本机结果筛选集上以单位感知的固定区间分桶，并保留空档与导入异常的有界溢出桶。 | `testSpeedHistogramUsesCurrentUnitAndKeepsEveryZeroBasedInterval` |
| `components/pages/account/DailyActivityChart.tsx` | 同一图表以练习分钟柱、平均速度右轴折线和分钟趋势关联每一天；提示展示完成次数、重开比、最高/平均速度、准确率和稳定度。 | “分钟 + 平均速度”原生菜单项在 Swift Charts 中保留同图双轴、分钟趋势和按日详情；其余每日指标仍可单独选择，详细数值由同一原生日期卡呈现。 | `testDailyActivityOverviewScaleAlignsMinutesAndAverageSpeedOnSeparateAxes`、`testTypingMinutesTrendUsesOnlyObservedDaysAndTheirCalendarSpacing`、`testActivityBarSelectionChoosesNearestCalendarPointAndRejectsEmptyInput` |

## 边界

网页参考把这部分数据放在已认证账户的结果集合中；Typebar 以当前 Mac 的 SwiftData 成绩作为可见等价数据源，不要求浏览器、广告或服务器账号。筛选、排序、分页、CSV、个人最佳和活动日历均只读取这个本机集合，不在图表路径发起网络请求。

## 验证

- 本次新增双轴标尺先以缺失符号的编译失败建立红灯，再实现至单测通过；覆盖零起点、裁切起点、WPM、CPM 与空输入。
- 2026-09-21 完整 `swift test`：643 项、0 失败、163.049 秒。CoreData/AddressBook XPC 提示是既有测试环境噪声，XCTest 汇总为准。
- 尚需在真实窗口中人工核对 Swift Charts 的实际像素排版和 VoiceOver 朗读；为遵守当前“不开多个 Typebar”的约束，本次未启动任何 Typebar 图形界面。
