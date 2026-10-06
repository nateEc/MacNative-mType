# 本机个人最佳比较与生命周期边界

后续 [账户 PB 账本](PERSONAL_BEST_LEDGER_CONTRACT.md) 与 [本机／标签账本](LOCAL_PERSONAL_BEST_LEDGER_CONTRACT.md) 已独立保存，原生提示、反馈、Pace、表格、奖杯及标签建议已切换。下述历史比较阶段的数字和范围保留；账本跨设备传输、原版标签 ID 与整体等价仍开放。

2026-10-06，本机 PB 的选择、完成反馈、标签反馈、计时／字数 PB 表和历史奖杯使用已保存的精确 WPM，不再先取整数。60.41 → 60.49 是提升，同速或更低速度不会因准确率、Raw 或稳定度较高成为新 PB。旧成绩没有精确值时继续使用其保存的整数，不从回放重算。本轮不实现独立 PB 存储，整体重写目标仍未完成。

## 固定源码规则

参考提交为 `91bd24bb8513785c7364cbea29296ff7adafac41`。[完整 PB 模块](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/pb.ts) 按 mode／mode2，再按 difficulty、language、punctuation、numbers、lazyMode 分组；只有严格更高的 WPM 才替换整条 PB。首次建立和替换时用服务端 `Date.now()`，不是传入的完成日期。Raw、准确率和稳定度只是胜出记录的伴随字段，不是决胜规则。

[mode2 选择](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/utils/misc.ts) 在 time 只取时长、words 只取词数；custom 和 zen 各使用固定字符串。因此本机标签 PB 不因自定义／自由输入的原生完成限制或非活动参数而分裂。引语不获得 PB，Funbox 与 stopOnLetter 资格继续遵守既有准入合同。[普通练习 PB 提示](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/components/pages/test/modes-notice/PbNotice.tsx) 不按当前活动标签筛选；标签节奏目标仍单独按活动标签读取。

[DAL 接受路径](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/dal/user.ts) 只有 `isPb` 为真才持久化工具函数返回的 PB。榜单最佳仅由 time 15／60 且非 lazy 的新输入触发，但候选取同桶的全部已有 PB，包含 lazy 变体；它不是“只选择非 lazy 候选”。原生未来账本不能以更保守的不同算法替代这一实际行为。

## 原生使用链

`RecentAverageSample` 携带精确 WPM，同时保留整数属性供既有平均行为使用。当前 PB 和结果／标签 PB 反馈都比较精确值。PB 表保留胜出记录的精确 WPM、Raw 和准确率；历史奖杯、PB 筛选和详情标记继续复用其 ID。现有 Pace PB 已读取精确值，本轮验证它与普通练习提示选择一致。普通提示不再受活动标签限制，标签 PB 仍独立。

PB 提示、首次 PB 和提升标签在转换成所选速度单位后保留两位小数；PB 表沿用用户的小数显示偏好。首次标签 PB 不再留下空白速度。较小提升换算为 WPS 后可显示 `+0.00 WPS`，但是否提升始终按未格式化的规范 WPM 判断，皇冠不会因此消失。完成图中的既有 PB 规则线也收到精确值。

PB 表和普通提示仍从本机历史派生。同速历史仍按既有完成日期最早优先，表内完全同日再按 UUID 决胜；这只是缺少接受次序的本机回退，不等于原版服务端接受时间。无新增 SwiftData 列、服务字段或协议；归档 27、设置文档 4 和保存分数不变。

## 独立生命周期仍需实现

原版的[删除全部历史](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts) 只删除结果集合，个人 PB 与榜单 PB 保留。用户 DAL 的内部 `resetPb` 仅清个人 PB；`clearPb` 则清两类 PB。[公开 clearPb 控制器](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/user.ts) 还清理日榜。不得把现有原生“开启公开 PB 新纪元”描述为这个公开入口的等价实现。

服务公开资料与全部榜现已使用 [独立账户账本](PERSONAL_BEST_LEDGER_CONTRACT.md)，删历史、重试、重载、真实保存失败和清空均有隔离验证。旧记录不按默认值补分组。本机与标签 PB 仍依赖可删除历史，后续需独立存储并切换提示、反馈、表格、Pace 和其他消费者；不能把服务账户账本计为本机或标签功能完成。

## 验证

新增 12 项核心反例先执行：旧实现 35 个失败（其中 6 个由必要值缺失触发），结果保留在 `/tmp/typebar-pb-precision-red.log`。修复过程中两次编译失败分别为既有速度规范化函数的私有范围，以及旧稳定度测试的整数／小数类型冲突；修正后 64 项相关测试零失败、零跳过，0.209 秒。随后补充五单位反馈、首次／同速展示及坏精度回退三项，共新增 15 项；最终相关 67 项零失败／零跳过，0.207 秒，日志 `/tmp/typebar-pb-precision-focused-complete.log`。

`Scripts/check-source-personal-best.mjs` 在 QA 中动态执行完整固定 PB 和 Funbox 模块，以及四条有界完整 DAL 函数，使用自造速度、选项、时钟和集合适配器：16 组替换、28 组分组、7 步生命周期通过。它不是 MongoDB、完整控制器、队列、日榜清理或窗口验收；没有把参考源码或资产写入生产项目。该检查已加入串行 readiness 门禁。

最终完整串行门禁原生 2996 项／服务 381 项均零失败、零跳过（697.507／9.065 秒），十万词耐久 149.242 秒、九项隔离磁盘迁移 3.896 秒；902 个唯一人工场景仅结构校验、源码审计、原创性及未打开应用包通过。主记录 `/tmp/typebar-pb-precision-readiness.log`，14 份详细日志保留在 `/tmp/typebar-pb-precision-readiness-logs.hYfx4v`。门禁结束后只补文档，不改生产代码或测试。

本会话风险复核未发现新增阻断缺陷；数据格式保持不变，同速历史回退与尚未接入的独立账本明确为剩余边界，不是独立评审或全等价认证。单窗口、布局、VoiceOver、真实网络、旧发行程序、macOS 14／Intel 和完整 PB 生命周期仍待验收。本轮不启动 Typebar GUI、不操作真实 Typebar 库、不部署服务。
