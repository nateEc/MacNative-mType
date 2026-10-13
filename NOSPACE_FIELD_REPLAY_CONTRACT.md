# 已捕获无空格词字段回放合同

## 格式 17 清空后继续插入的回放修复（2026-10-13）

真实 no-space 会话在有限末词批量提交后，可在同一字段保存 `discardedInputUnits` 并继续接受或停止下一键。此前接受文本回放先收缩尾单位，字段视觉回放却继续保留旧字母标记和旧光标：`abx` 停止模式仍显示 `ab` 正确、光标位置 2；普通 `abx` 再输入 `y` 把 `x/y` 画在目标之后。两项真实会话红测六处失败（work/no-space-field-replay-contraction-red.log）。

字段动作装配现在只对有效的插入清空标记，使用保存的插入后字段快照扣除当前接受单位数，先生成无声的同字段收缩，再处理原键。停止键扣除零接受单位；代理对的两个 UTF-16 单位可对应一个目标字形，收缩仍清除其标记。回放时间线不为收缩补一次点击音；正式输入与固定结果数据不改，便携实体往返后相同结果仍按新消费规则呈现。三项新增测试覆盖停止、接受／便携往返和代理对。

第一次试图把收缩扩展到退回已裁掉目标的删除事件，与已有完整源码回放合同冲突：181 项范围内六处旧断言失败。限定为带标记的退回仍有三处冲突；这条推断已撤回，旧的净最终词前缀、退回忽略及源声音规则全部保持。两轮失败日志 `work/no-space-field-replay-contraction-regression.log`、`work/no-space-field-replay-contraction-regression-final.log` 保留，不把曾经的新删除预期算作修复证据。最终字段回放、声音、seek、原始单位、格式 17／20 和旧版共 181 项零失败（work/no-space-field-replay-contraction-regression-complete.log）；固定源码九场景通过（work/no-space-field-replay-source-check-verified.log），原创性边界通过（work/no-space-field-replay-contraction-originality.log）。首次源码探针因缺 `--experimental-vm-modules` 未执行，日志单列，不算行为失败。行为优先、根因定位和同会话有界决策复核影响了边界选择，非独立评审。

这只修复已保存清空标记的插入视觉消费，未证明删除收缩的视觉等价、真实窗口点击／声音、全部旧库或实体 IME；无新存储格式、实体列、设置与服务协议。本增量尚未重跑完整门禁／Release，人工设备场景及完整 goal 仍待验收，零可见主程序。

固定参考：91bd24bb8513785c7364cbea29296ff7adafac41。只读完整 frontend/src/ts/test/replay-ui.ts 与 TestWords，并核对提交符生成处理。原生实现与夹具独立编写，没有复制参考源码或资产。

## 动作、目标与定位

有效 ResultTargetWordDirectory 必须逐 UTF-16 单位匹配提示且 noSpace 与配置一致，现接入 FieldReplayPlan／ReplayTimelineView。目录中的空词、literal LF 与跨词融合保持；不切割扁平提示或重采样。缺目录、不匹配、缺字段、混合旧日志、非法索引／时间仍走既有回退；共享 recordedFieldActions 的默认 no-space 守卫保留，避免改变缺目录的旧声音时间线。

字段索引改变只生成一次前进／回退，不按索引差跳多词。提交判定使用前词最终原始快照与真实目标，而非 clearedNextWord 的保存历史。停止键仍可导致字段转换但不加字母。整词删除用已有合并原语，回退不再按快照额外 resize。

显示初始化为净最终前进减回退的目标前缀，并非最大访问字段。源显示游标总从词零开始，即使首槽为空而首个事件字段非零；走出初始化字段后后续动作与声音被忽略。这是实际源行为，不混淆历史／接受文本／计分读者。

目标 letter 按 Unicode scalar；输入动作和 resize 数值仍用记录的 UTF-16 单位。两次代理输入可只标记一个 scalar，并递增游标两次；组合符和 LF 是独立目标 scalar。点击坐标重建消费动作序号，同时间戳恢复跳过已消费序号，增量 advance 不重复声音。

## 数据边界

本回放阶段未增载荷／回填，当时默认格式 19；后续独立删除位置增量默认 20，详见 DELETION_POSITION_CONTRACT.md。实体列／设置／服务协议不变。独立自有版本 15 目录-only 夹具经正式导入与便携实体转换后可渲染，固定 WPM 17／raw 29／accuracy 75 保持，不添加 16–20 元数据。没有打开真实库；真实旧库、旧二进制／降级／混合运行仍需备份与设备验证。

## 行为证据

先行四项有四处有效失败（0.464 秒），接入后四项零失败（0.004 秒）。补充边界用例后首次扩展编译失败：含 nil 的测试数组缺 Optional 元素声明，尚未运行断言；只补显式类型，未削弱断言。最终扩展 207 项零失败（0.874 秒），旧 12,000 次双投影 0.026075 秒。

NoSpaceFieldReplayTests 新增十三项：隐藏词定位／等时恢复、真实会话终端回退、代理／组合符／LF、停止键、空中间槽／非零首字段、错误目标／声音、整词删除、无效目录／索引／混合日志、展示入口、真正旧 15 和千词增量。千词样本不代表 no-space 十万词或混合性能。

Scripts/check-source-nospace-replay.mjs 只读执行实际完整 replay-ui 模块，附测试访问桥而不改行为函数。九个自有场景使用显式 TestWords、event/data、stats、DOM 与声音适配；getInputForWord 绑定夹具末快照，stats 不调用真实分类器，声音仅收集 cue。初始化／动作／展示／loadOldReplay 是实际源码函数；applyThrough 是单次测试驱动，不执行浏览器 timer loop。无真实 DOM 布局、HTML 解析、RAF、音频、Korean、Firefox、IME 或线上生命周期，不等于原生窗口对照。

最终完整串行门禁客户端 2,319 项零失败（442.380 秒），服务端 131 项零失败（1.382 秒），780 条唯一人工清单结构检查通过；固定参考、原创性／元数据、布局、页面／服务、主题／挑战身份与行为证据审计，以及未打开原生应用包构建／签名和资源边界检查通过。当前 gvdbDU 客户端日志的实际十万词 passed 行在清理前读取，用时 87.849 秒；旧 12,000 次双投影 0.025057 秒。普通耐久不证明 no-space／混合性能，身份审计不升级未映射项。门禁成功退出，参考检出仍固定且干净，Typebar 图形进程为零，真实背景成绩路径不存在，没有真实库／音频／部署操作。INPUT-NOSPACE-FIELD-REPLAY-01 保持设备待验收，不升级既有人工状态。

## 尚未关闭

旧缺目录／混合回放、浏览器计时及真实点击／VoiceOver、完整 commitsWord／lastWord 与删除 charIndex、其他模式单位统计、挑战／复制等消费者、Korean／Firefox、真实旧库／降级、官方主题／词库、部署及混合性能仍开放。源码驱动、行为优先、根因调试与会话内有界决策／风险／迁移复核影响本次实现，非独立评审；94 配置与部分 Funbox 不升级，完整 goal active。
