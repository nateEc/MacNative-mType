# 校验前位置与末词快照合同

本增量是完整原生重写的日志前置步骤，不是末词重入修复或全功能等价声明。

## 格式 16

`TypingReplayEvent.inputPosition` 可选，包含非负 `charIndex` 与明确的 `lastWord` 布尔值。当前只由具备真实 no-space UTF‑16 目录且活动字段有效的新插入产生：位置在归一化／停止／追加／导航前捕获；末词身份取当时目录，追加生成不能回填旧事件。词索引仍使用同事件的 `inputField.index`。

`inputPosition` 不表示导航已经前进，也不表示字段快照可取代累计单位回放。正确性仍由独立 `inputCorrectness` 记录；严格末 LF 可以 `lastWord == true` 但不提交导航。停止后快照可能短于校验位置，不能以快照长度验证相等或补推旧位置。删除事件、未知词界、目前其他输入路径缺省，后续需各自取证接入；不推广为所有插入／删除的源码合同。

解码拒绝负数、类型错误、缺失必填成员、空插入、无字段或删除上的位置。含位置的归档构造最低版本为 16，正式导入拒绝含此字段却标为 1–15 的档案。真正旧 1–15 保留原日志、版本和固定成绩，不补造或重算。新的位置已包含在既有 `TestResultRecord.replayEventsData`，实体列、设置格式和服务协议未改。

内存 SwiftData 保存／读取与便携、正式归档往返已有自动化证据；真实旧库迁移、旧二进制直接读取新实体 JSON／降级、混合版本同步仍未验。不要将新档案交给旧程序读取并覆盖；保留迁移前备份。本轮没有操作真实数据库或部署。

## 固定源码反例

源码固定在 `91bd24bb8513785c7364cbea29296ff7adafac41`。实际 [getCurrentInput](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/test/events/data.ts) 优先读取当前词的最后事件快照；只有活动词真的增加到上一事件词索引加一时，才返回新空字段。实际 [word-navigation](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/helpers/word-navigation.ts) 在有限末词无新目标时不会增加索引，但仍清空输入元素；两者不能合并成一个“提交后全清”的状态。

在自有目标 `["hi\n_", "next"]` 上，单批 `hi\n_next` 的 x 先以位置 3 提交末词 `_nex`，之后 t 在位置 4 校验，但输入元素仅为 `t`。最后事件仍属于词 1，正确性为 false，测试 active。再输入 n，其位置才回到 1、快照为 `tn`。逐键输入则在 x 后结束，不再输入 t。这些是 [实际 insert-text](https://github.com/monkeytypegame/monkeytype/blob/91bd24bb8513785c7364cbea29296ff7adafac41/frontend/src/ts/input/handlers/insert-text.ts) 与当前快照读取／导航模块共同产生的不同合同，不应以改成逐键的测试抹掉批量反例。

另一个自有单词 `ab`，单批 `abx` 配 letter-stop：ab 在批量中间提交并清空；x 仍从前一快照读到位置 2，被停止后的输入元素与新字段快照为空，测试保持 active。所谓“停止不改变字段”不能用于这一末词清空场景。

`Scripts/check-source-input-position.mjs` 七个场景覆盖上述三种情况、代理单位停止、严格末 LF、普通有限词与提交时追加目标。它从只读、干净且固定提交的检出动态加载 11 个完整官方模块，没有把源代码／资产写入实现。Config、词生成、UI 与生命周期为明确的自有测试绑定；输入元素是内存 sentinel 适配，未执行浏览器布局／RAF／真实 IME／线上 TestLogic。生成仅在设定的边界追加一个自有目标，不宣称官方完整预取策略。

运行方式（使用支持 `stripTypeScriptTypes` 的 Node）：

```sh
node --experimental-vm-modules Scripts/check-source-input-position.mjs /absolute/path/to/monkeytype-reference
```

本机实际使用 bundled Node 24.19.0；Node 实验功能警告与断言失败分开。第一次临时绑定缺失类型导出与持久探针第一次错误地在非末词也追加目标均已纠正；源码未被改动。

## 尚未关闭的缺口

原生有限末词当前仍可能虚增字段／累积清空前输入／提前完成。格式 16 只保留当前有效字段的校验位置，不使这个状态正确；有限末词越界后的缺失位置不得反推或充当 source-authoritative 标记。`INPUT-NOSPACE-LASTWORD-BATCH-01` 继续待实现／实机验收。

下一步需要分别维护实际输入元素、验证事件快照及活动词；导航增减、字段覆盖、停键、硬恢复、预取、计分与各回放消费者要共同验证。累计原始单位回放的 1–16 合同本轮未变，不能仅凭位置存在就重解释旧成绩。完整 source `commitsWord`／`lastWord` 导出、删除 `charIndex`、Firefox/Korean、FieldReplayPlan／seek／挑战／复制文本等仍需独立接入与证明。

## 当前自动化范围

`InputPositionCaptureTests` 十项：隐式提交前位置、停止代理、跨字形字段、额外单位上限、严格末 LF、删除不泄漏插入位置、未知目录不补造、旧事件不回填、非法数据拒绝、末词旗标先于生成目录追加。`InputPositionArchiveTests` 七项：便携／正式与内存实体往返、拒绝旧标新数据、真实版本合同旧夹具不回算、格式 15 原始字段目录仍可读、直接非法元数据拒绝、停止快照短于校验位置仍可保存。

先行九项 19 处有效失败（0.456 秒），实现后九项零失败（0.013 秒），扩大 161 项零失败（0.659 秒）。第一轮测试私有访问编译失败单列，不视为行为 RED。源码七场景只证明有界观察；最终全量门禁结果见 README 最新阶段。人工设备场景未通过，不以无窗口自动化代替。
