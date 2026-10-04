# 终止计时和 Bail Out 保存缺口

结束计时已进入独立原生实现，见 [原生结束计时与旧成绩保护](TERMINAL_TIMING_CONTRACT.md)；BailOut 保存资格仍未等价。本文件保留 9075114 的历史反例、源码证据与适配限制，不能把当时“未剪裁”的描述当作当前实现状态。原版有效 BailOut 可以进入保存流程，只是不参与挑战、PB 与排行榜；原生仍一律拒绝保存，这不是有意缩小重写范围，而是待修复缺口。

## 原版证据

参考固定在 91bd24bb8513785c7364cbea29296ff7adafac41，保持只读干净。Scripts/check-source-terminal-timing.mjs 在内存执行完整 test-logic、events/data、events/stats、events/helpers、events/live-cache、strings、numbers、util/numbers、handlers/keydown 和 backend/utils/validation，未抽取或改写行为函数。仅移除单文件类型擦除不能识别的 CharCounts 导入。自己的输入夹具通过实际日志存储、强制释放、清理、统计、buildCompletedEvent 和 finish，再观察结果更新及保存资格。

计时依据 [getTestDurationMs](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/stats.ts#L280-L324)。Zen 或 bailedOut 的尾部间隔以毫秒保留两位后判断严格小于 7000；非 custom 最终时长再取秒的两位小数，custom 保留精度。无物理按键时不从输入日志推断末键。公开 Zen 的 startToFirstKey 和 lastKeyToEnd 都为零，并不表示内部尾部剪裁也为零。图表边界同样剪裁；AFK 判定统计 insertText，AFK 时长统计 keydown 或 input，两者不能互换。

[onKeydown](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/keydown.ts#L122-L173) 先忽略重复，再实际记录 Enter，然后调用结束。ShiftLeft、Backspace、NumpadEnter 和普通 ArrowLeft 不在本探针对照的 keysToTrack 中，不能悄悄推迟计时末键。日志清理保留最后一个开始前 keydown、删除结束后的 keydown；估计释放不延长末键。

[finish](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/test-logic.ts#L887-L1092) 对 Bail Out 关闭 AFK 拒绝，不一律禁止保存。未登录时有效结果存入 signed-out 待认领状态；登录时通过普通 saveResult 请求，但跳过挑战验证。前端有限 time／words／custom 可能保留不足十五秒的 Bail Out，随后被后端 [isTestTooShort](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/utils/validation.ts#L3-L48) 拒绝。后端 [PB 和排行榜限制](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/backend/src/api/controllers/result.ts#L455-L466) 及同文件 L523–529 为静态读取证据，未在本探针执行完整后端保存。

## 历史反例和剩余差异

| 自有夹具 | 完整原版执行 | 9075114 的原生诊断 |
| --- | --- | --- |
| 0 秒输入 a，15 秒物理按键并输入 b，16 秒用命令结束 Zen | 测量时长 15 秒，WPM／Raw 1.6，AFK 13 秒 | WPM／Raw 1.5，未剪裁 |
| 同一输入，21.99999 秒用命令结束 Zen | 剪裁后仍为 15 秒，非 AFK 无效，AFK 时长 13 秒 | invalidAFK，AFK 时长 19 秒 |
| 同一输入，16 秒 Bail Out | 有效结果可保留／进入保存；不验证挑战 | ResultSavingPolicy 拒绝本机保存 |

诊断夹具保留在 Scripts/diagnostics/TerminalTimingGapEvidence.swift.fixture。在 9075114 用 apply_patch 临时放到 Tests/TypebarTests/TerminalTimingGapEvidenceTests.swift，并运行 env TYPEBAR_QA_IN_MEMORY_STORE=1 swift test --filter TerminalTimingGapEvidenceTests，得到三项测试、五处有效断言失败（0.443 秒，/tmp/typebar-terminal-timing-native-gap.log），之后移回工具目录。当前前两项已提升为持续计时回归，不能再声称这五处仍全部失败；第三项保存资格反例仍未解决，未把错误保存规则改成等价期望。

源探针使用已安装 Node 24.19.0，执行 node --experimental-vm-modules Scripts/check-source-terminal-timing.mjs <只读参考绝对路径>，最终 34 组通过，日志 /tmp/typebar-terminal-timing-source.log。真实 keydown→日志→finish 已执行，登录保存前缀也实际执行；UI、timer clear 产生的 end 事件、配置／身份、哈希和请求端均为明确适配。请求端在内存返回自有 503，无网络请求，不证明成功保存、实际服务器、浏览器定时器、输入法、原生窗口或全组合等价。三处首次运行问题均为探针适配缺项（funbox/active、custom limit、resetIncompleteTests），不是产品红绿证据。

正常原生相关 100 项零失败、零跳过（0.361 秒，/tmp/typebar-terminal-timing-native-regression.log），只保护已有 Zen 准入／回放／计分、重复入口、物理时序和字段历史；不覆盖上述缺口。本轮没有生产 Swift、实体或协议改动，因此不重跑十分钟的完整门禁；上一回放阶段 2700／145 项完整通过仍只属于上一阶段。本轮 811 个唯一人工场景的清单结构、原创性边界、既有行为证据索引及干净固定参考检查通过；新增人工场景仍待验收，不冒充设备验收。会话内风险复核未发现探针新增的可操作问题，不是独立评审，也不消除已复现的产品缺口。

## 取证阶段的实现边界

下一步必须保留真实 startedAt／finishedAt 和原始输入，而为新结果保存独立的测量时长／尾部计时证据，不能通过篡改 finishedAt 或从最后一条接受输入推断末键来绕过差异。剪裁后的结果速度、图表网格、AFK、资格、展示、历史、CSV、分享、练习总时间及匿名服务消费者需要共同审计。仅放开 .bailedOut 的保存也不够：还需携带该语义，并排除挑战、PB 和排行榜，保留后端时长限制及拒绝原因。

迁移安全与决策复核要求新证据可选、旧记录不回算、不补造末键，不在真实用户库中回填；归档和服务能力需明确协商，旧客户端不能静默丢失计时／Bail Out 语义。当前归档仍 22，任何后续扩展版本尚未决定或实现。回滚、真实旧库与混合版本未验证；此次为会话内复核，非独立评审。源码驱动和行为优先技能将先前“Bail Out 必然不保存”的假设改为可执行反例，文档技能区分已实现与仅取证。

以上正常相关 100 项及“归档仍 22、没有生产改动”仅属于 9075114 取证阶段。后续计时实现与归档 23、服务协商以新合同为准。本阶段和后续实现均未启动 Typebar 图形进程、未写真实成绩库、未部署或访问账户服务。设备、完整内容／主题和整体功能等价仍未完成，goal active。
