# 结果页重开触发随机主题

完整导入的后续总线证据和成功路径衔接见 `WEBSITE_THEME_IMPORT_RESTART_CONTRACT.md`；下文保留本阶段的结果页交付证据与当时待办。

起点 `c8a80fc4`，固定参考 `91bd24bb8513785c7364cbea29296ff7adafac41`。本批继续整体原生重写，将结果页返回与已有显式随机命令接通。完整导入引发的隐式 restart 交叉、故障后的实体交互及全项目验收仍未完成，不能把本批通过视为所有 Monkeytype 功能已等价。

## 实际来源事件

固定 `test-logic.restart` 先检查 No Quit／忙状态并关闭旧尝试，捕获 getResultVisible 作为 testPage 或 resultPage，淡出并将结果设为隐藏，再等待初始化。初始化返回 false 时直接结束，不调用 onTestRestart。成功后初始化配速、调用 funbox restart、执行完整 `TestUI.onTestRestart(source)`，再淡入。只有 resultPage 且 Config.randomTheme 不为 off 时，UI 函数才调用随机控制器；重复词集不豁免这个分支，随机 Promise 不阻塞 UI 重开函数。

`check-source-random-theme-restart.mjs` 执行上述两个完整实际函数，不复制函数实现到原生应用。初始化、DOM、无关服务和随机调用计数是明确的自有适配边界，抽取与配置细节另由已有完整控制器对照验证。57 条轨迹、114 个检查点覆盖结果／测试页、七种范围、重复与否、首次初始化失败后重试及活动 No Quit 拦截；脚本验证 init、UI 回调、随机调用和淡入顺序。失败的首次初始化已隐藏结果，随后重试不再获得 resultPage 来源，即使旧原生 session 仍持有失败结果。

## 原生状态与发布

`WebsiteRestartSource` 将 completed、failed、invalidAFK、bailedOut 的未离开结果映射为 resultPage，active／abandoned 映射为 testPage；同一尝试已接受离开时不重复计算为结果页。该映射不以“曾经完成过”或宽泛 isFinished 代替结果可见性。实际重开控制器在 admission 前捕获来源，初始化失败、取消或所有者过期不发成功事件。

成功 advance 后，控制器先释放 isPreparing 和页面预留，再报告包含 owner、尝试 ID、publication ID 的 Delivery。工作流重新校验当前窗口、租约及发布，并按新尝试 ID 去重；范围为 off 的事件也不留作未来开启范围时补抽。直接重开立即使用已有随机事务；设置命令内部的重开在 applying 期间排队，待该工作流退出后处理，避免因重入保护丢掉来源事件。普通 setter 的新练习发布和分享回执的首次初始化走相同交付处理，分享回执保留首次来源信息，并在首次初始化准备时消耗；失败后的恢复不重抽。

这仍使用显式命令已有的临时 customTheme 标记、后续 autoSwitchTheme 保存、源故障前缀、页脚和预览语义，不再调用原生后备的完成时随机设置。随机抽取出错不会撤销已经交付的新练习，错误单独进入本机会话提示，不把成功重开改报成初始化失败，也不重复记账。

## 取消与所有权审查

会话内有界审查聚焦两个主张：未成功初始化不能推进候选；成功交付后不能把已接受的新练习和来源事件回滚。反例包括资源失败后重试、挂起读取中的取消、切换窗口、设置工作流仍持预留、成功发布观察者发起迟到取消，以及随机控制器自身故障。控制器取消与调用 Task 取消分开测试，没有声称独立审查或完整并发状态空间证明。

调用 Task 在成功发布观察者中被取消时，新练习已交付，但该 Task 的取消标记仍会被后续显式随机事务观察到。新增测试在 `/tmp/typebar-random-restart-task-cancel-red.log` 复现一项活动候选断言失败（驱动 22.360 秒）。修复限定为：已交付的结果页事件遇到取消标记时，用一个不继承该标记的 MainActor 任务再次校验并处理；不取消或放宽普通显式命令、初始化和保存事务的取消检查。不匹配当前窗口／尝试／publication 的事件不会覆盖有效待处理事件，工作流停止时取消该任务。该分支的换色是异步交付，测试以有限等待确认结果；不据此声称与浏览器所有事件循环交错完全等价。

## 验证记录与剩余边界

`/tmp/typebar-random-restart-red.log` 先在真实 workflow 上出现 20 项失败，包含未触发随机状态的行为断言及完成测试误用 master 难度的设置问题；首轮实现的 `/tmp/typebar-random-restart-green.log` 仅剩四项测试完成状态断言。完成场景改用 normal、失败场景继续 master 后，37 项定向通过（驱动 59.270 秒）。继续加入成功交付观察者取消与随机故障不撤销新练习后，`/tmp/typebar-random-restart-final-focused.log` 39 项定向通过（驱动 57.444 秒）；输入哈希不变。最终相关回归和打包结束后补充，不把进行中的日志当作通过。

补齐调用 Task 取消前，首轮 `/tmp/typebar-random-restart-final-regression.log` 805 项相关回归及 116 项必需来源方法通过（驱动 370.770 秒），不将它作为后来修改版本的最终证据。修复调用 Task 取消后，`/tmp/typebar-random-restart-task-focused.log` 39 项定向通过（驱动 100.065 秒，代码输入哈希未变），同时覆盖控制器取消和调用 Task 取消两个观察者分支。最终版本回归与签名包结束后另记。

最终 `/tmp/typebar-random-restart-task-regression.log` 805 项相关回归零失败、零跳过，独立证据检查确认 116 项必需来源方法全部执行（驱动 365.023 秒）。`/tmp/typebar-random-restart-package.log` debug 构建、签名、实际包资源边界及固定参考原创性比对通过（驱动 32.716 秒）。两项原生作业串行，非 Markdown 输入哈希未变化；来源证据检查自身 13 项、元数据和行为审计、1,404 项人工账本结构检查通过。参考克隆仍干净，未启动 Typebar。推送前开发分支无开放 PR、Actions 总数仍为 826，没有用 main 门禁试错。以上不代替实体结果页验收。

结果页普通重开、失败结果、重复、普通词数 setter、分享回执、系统跟随自动关闭、资源失败／取消／所有者变化后重试均有原生集成证据；源码初始化内部重试另有已有初始化来源对照。invalidAFK／bailedOut 的分类有枚举边界证据，但未据此宣称实体结果页操作全部验收。完整导入的配置事件可能与原版隐式 restart 交错，当前仍保留其独立配置应用路径，需另取真实总线顺序证据；不因完成了显式重开就自动认定这条路径已完成。
