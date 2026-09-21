# 官方个人最佳重置审计

## 固定来源与目标

- 固定参考提交：Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 参考入口：`frontend/src/ts/components/pages/account-settings/AccountTab.tsx` 与 `components/modals/account-settings/ReauthConfirmModals.tsx`。
- 本审计只记录可观察的用户语义和 Typebar 的原创原生实现；不复制参考代码、账户数据或资产。

参考入口要求用户重新认证后清空账户的个人最佳快照，明确保留成绩历史且不能撤销。它不是“删除成绩”或“重新计算／改写历史图”。

## Typebar 映射

| 参考可见语义 | Typebar 实现 | 保留边界 |
| --- | --- | --- |
| 重置前要求确认身份 | `PreferencesView.swift` 要求密码账户输入当前密码；纯 OAuth 账户先取得一次性重新认证证明。 | 密码错误或证明缺失／重复消费会拒绝请求。 |
| 清空账户公开 PB，保留成绩 | `DELETE /v1/personal-bests` 在 `AuthStore.resetPersonalBests` 写入新的 `personalBestResetAt`。 | 成绩、XP、徽章和排行榜不删除。 |
| 后续成绩建立新的 PB | 公共资料派生 PB 时仅采用 `acceptedAt > resetAt` 的服务端成绩。 | 历史成绩仍可由私有成绩路由读取；未来新接收成绩才参与公开 PB。 |
| 历史保持可见 | `LocalPersonalBestTablePolicy`、本机历史图和练习中的 PB 反馈一直从 SwiftData 本机成绩派生。 | 本机 PB 并非远端账户快照，重置远端公开 PB 不篡改、隐藏或重算本机历史。 |

## 决策：不新增本机 PB 断代

将 `personalBestResetAt` 写进 `AppSettings` 并用它截断本机 PB，会错误改变保留成绩后的本机历史表、奖杯筛选、趋势 PB 包络与节奏引导，也会把账户作用域的破坏性动作混入设置导入／同步冲突规则。固定来源没有要求该改变。

因此，Typebar 的正确等价是重置自建服务的公开账户 PB，同时保持离线优先的本机分析不变。它不是功能遗漏；本机与远端资料的所有权边界在界面和服务契约中明确显示。

## 自动化证据

- 服务端 `testResettingPersonalBestsStartsANewEpochWithoutDeletingResultsOrRewards` 覆盖重新认证、重置、结果／XP／徽章保留、公开 PB 清空、重新认证证明一次性消费、持久化读取及下一条已接收成绩建立新 PB。
- 原生 `TypingEngineTests` 覆盖旧／新 `personalBestResetAt` 解码，以及本机个人最佳表、历史筛选和完成结果 PB 反馈的独立派生。

真实服务人工验收仍需在部署者控制的账户与凭据下完成；本次未启动 Typebar 图形界面。
