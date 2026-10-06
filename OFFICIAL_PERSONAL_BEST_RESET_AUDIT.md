# 官方个人最佳清空审计

2026-10-06，公开清空已改为删除独立个人 PB、排行榜 PB 和日榜记录，保留成绩、累计练习、周 XP 与徽章。此前只写公开 PB 新纪元且保留榜单的实现不等价，原结论已替换。完整存储和验收范围见 [账户 PB 账本合同](PERSONAL_BEST_LEDGER_CONTRACT.md)。

## 固定来源与目标

- 固定参考提交：Monkeytype `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 参考入口：`frontend/src/ts/components/pages/account-settings/AccountTab.tsx` 与 `components/modals/account-settings/ReauthConfirmModals.tsx`。
- 本审计只记录可观察的用户语义和 Typebar 的原创原生实现；不复制参考代码、账户数据或资产。

参考入口要求重新认证，清空不可撤销。用户 DAL 的 clearPb 清两套 PB，公开控制器另清日榜，不清周 XP；内部 resetPb 只清个人 PB。删除成绩历史不删除任何 PB。

## Typebar 映射

| 参考可见语义 | Typebar 实现 | 保留边界 |
| --- | --- | --- |
| 重置前要求确认身份 | `PreferencesView.swift` 要求密码账户输入当前密码；纯 OAuth 账户先取得一次性重新认证证明。 | 密码错误或证明缺失／重复消费会拒绝请求。 |
| 清空两套 PB 和日榜 | `DELETE /v1/personal-bests` 原子清理当前账户的独立账本与日榜。 | 成绩、累计练习、XP、周榜、徽章与其他账户保留。 |
| 后续成绩建立新的 PB | 新 UUID 按独立分组处理，不用日期截断新输入。 | 同 UUID 重试不能复活已清空 PB；同毫秒的新成绩仍可建立最佳。 |
| 删除成绩保持 PB | 只删除私有历史，账本及首次接受记录保留。 | 重载后仍可显示公开最佳和全部榜。 |
| 历史保持可见 | `LocalPersonalBestTablePolicy`、本机历史图和练习中的 PB 反馈一直从 SwiftData 本机成绩派生。 | 本机 PB 并非远端账户快照，重置远端公开 PB 不篡改、隐藏或重算本机历史。 |

## 本机范围与剩余差异

该入口作用于远端账户，本机历史、PB 表、反馈与节奏仍属于离线分析，不受它清理。本机与标签 PB 仍需独立账本及消费者切换，不能把“不改本机历史”解释成原版全消费者没有遗漏。

新客户端要求 accountPersonalBestLedger=available，拒绝让旧服务执行旧纪元操作却显示完整清空成功；旧服务资料读取仍兼容。升级先备份并停止旧 writer，禁止混写；回退恢复备份，不承诺保留备份之后的新数据。

## 自动化证据

- 服务端 `testClearingPersonalBestsKeepsResultsAndRewardsButRemovesOwnBoardEntry` 保留密码及一次性证明断言，验证自己的旧榜项消失、其他账户保留、结果／XP／徽章保留及新成绩建立 PB。
- PersonalBestLedgerTests 覆盖同毫秒新成绩、删除保留、重载／重试、两套 PB 与日榜清空、周 XP 保留、迁移及真实保存失败。
- 原生 `TypingEngineTests` 覆盖旧／新 `personalBestResetAt` 解码，以及本机个人最佳表、历史筛选和完成结果 PB 反馈的独立派生。

窗口、真实部署、VoiceOver、最低系统和旧发行程序仍待验收。本轮只跑隔离命令行测试，不启动 Typebar GUI，不操作真实用户库；整体重写目标未完成。
