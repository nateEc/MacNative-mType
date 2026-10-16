# 官方键盘布局兼容矩阵

2026-10-16 实际屏幕键盘按钮文字全布局审计（本地待合批）：固定参考 239 布局、Base／Shift／Option／Shift+Option 共 45,104 个主键比较点，新增由点击输出到可见 `Text` 的逐点核对；先红 80 处，分布于 3l 32 处及 AdNW、bone、koy、mine、neo、noted 各 8 处。根因是这七布局用字面空格 `" "` 作基础图例，旧按钮留白规则只处理空字符串；20 个键的输入输出本来正确。现在两种留白图例均不在按钮里写“空格”，底排单独命名的空格键仍有文字。该固定参考测试与屏幕键盘 10 项聚焦回归通过；可见窗口和真人辅助功能未验，新增人工项 `KBD-VIRTUAL-04` 保持待验收，未单独推送。

2026-10-16 屏幕键盘实际按钮文字补证（已推送 `7d484b9`）：此前四层图例比较只到键模型，未覆盖 SwiftUI 按钮的可见 `Text`。Latin American QWERTY 一处和 Whix2 七处源布局留白但输出空格的键，旧按钮会统一显示“空格”；两布局四层共 32 处定点红测证实。现保留留白按钮的空文字、底排空格键的“空格”文字，输入及辅助功能排位名称不变。屏幕键盘 8 项、固定参考四层审计 39 项通过；当前源码的完整客户端／固定参考总运行，以及 Release 包构建／签名／资源／原创性检查均退出码 0。单一隔离 QA 实例的可见窗口中，两布局四层各已截图核对留白按钮边框与空文字，底排仍有“空格”；Whix2 Base／Option、Latin American Option 留白点击各推进一个正确词，错误 0。未穷尽 32 次点击、VoiceOver 或实体 IME；一轮长间隔观察触发不保存的调度延迟结果，未计有效成绩。实例正常退出且进程为零。远端 #812 已通过上一提交，[#813](https://github.com/nateEc/MacNative-mType/actions/runs/38843820650) 因两项客户端滚动时序测试失败；本段状态更正将与下一批实质改动合并。

2026-10-15 键盘可访问名称批次补证（已推送 `372a17f`）：固定参考四层审计和完整本机客户端 `swift test --quiet` 均以退出码 0 结束，Release 应用包、签名、资源及原创性检查通过；这不等于 VoiceOver 真人设备验收。远端 #811 已通过上一提交，#812 已通过本批。

2026-10-15 屏幕键盘空格辅助功能名称增量（已推送 `372a17f`）：Whix2 七个留白键与底排空格键原本共用“输入空格”名称，Latin American QWERTY 的留白键也与底排重名；按名称定位无法区分。只为输出空格的键增加排位名称，当批未改可见图例、输入字符或布局存储。覆盖 239 个内置布局四修饰层的红测出现 38 处断言失败，修复后屏幕键盘 7 项、固定参考审计 39 项通过。单一内存数据 QA 实例的辅助功能树显示 Whix2 八个不同空格键名；点击第 1 排第 11、12 键分别正确提交首两词，进度 `0/50 → 1/50 → 2/50`、错误 0，退出后进程清零。此证据不替代真实 VoiceOver 朗读、其他布局／修饰层窗口验收；#811 已通过上一提交，#812 也已通过本批。

2026-10-15 屏幕键盘点击空格增量（已推送 `a553864`，远端 #811 已通过）：固定参考的 239 布局四层图例审计扩展为同层鼠标键盘输出审计；先行失败为 **32／45,104** 次点击输出，集中在 Latin American QWERTY 一个及 Whix2 七个视觉留白、实际表示空格的键。原生仅在空标签且唯一输入字符为空格时输出空格，其他空白控制键仍禁用。定点红测八处失败后，鼠标键盘 6 项及固定参考审计 39 项零失败；图例 **0／45,104**、点击 **0／45,104**、实体键输出 **0／46,060** 差异。布局存储、实体键映射和参考数据未改；完整客户端、服务端与 Release 包已在本地通过。唯一的内存数据 QA 实例中，Latin American QWERTY 留白键的鼠标点击让正确输入的 `quiet` 提交，进度 `0/50 → 1/50`、错误 0，结束后无 Typebar 进程；Whix2 的真实点击、IME 和 VoiceOver 仍未验收。远端 [#811](https://github.com/nateEc/MacNative-mType/actions/runs/38728095944) 已通过，此文档与下一批实质改动合并推送。

2026-10-15 已推送 `b213011`，远端 #810 已通过：逐行复核固定参考的 239 个布局后，移除 Arabic 101/102、Hebrew、Macedonian、Russian 可见底排的非参考前缀键，补齐 Pashto 底排 `ذ`、四项数字行首键、七项 ANSI 风格行两端符号键，并把 ABNT2、Belarusian、Estonian、Turkish Q 的边缘键移回各自参考行。最后按土耳其语点号规则分别显示 Turkish Q 的 `ı/I` 和 `i/İ`，没有修改实体键模拟器或保存布局身份。每组变动均先由定点测试复现红灯，再转绿；固定参考的四实体行、四修饰层视觉审计现为 **0／45,104 差异**，另有 32 个经空格输入能力核对的留白 Space 图例。四层实体键文本审计仍为 **0／46,060 差异**。首次全量客户端中 18 处失败全是旧测试的视觉行位预期，修正后相关 798 项和官方审计 39 项通过；最终全量客户端 4,645 项、95 项条件跳过、零失败，Release 应用包检查通过。这些检查证明键盘图例与模拟输出在该固定参考口径下对齐，不证明真实设备、IME、完整窗口或全部 Monkeytype 功能等价。CI 客户端测试将显式运行两项固定参考审计；上一批远端 [#809](https://github.com/nateEc/MacNative-mType/actions/runs/38704379469) 已通过，本批已由远端 #810 验证。

2026-10-15 本地下一批待验：已推送的 [Native Rewrite Gate #808](https://github.com/nateEc/MacNative-mType/actions/runs/38692909281) 在 4,638 项客户端测试中有一项失败、97 项条件跳过，停在 `PromptLineScrollTests.testSmoothLineScrollMovesOverTimeAndSettlesAtTheSameOrigin` 的固定 40 ms 中途位置断言；包与服务步骤未执行。本地同一提交的完整客户端、服务与 Release 应用包检查曾通过，但不能替代远端失败结论。新一批把集成测试改为确认实际计时器调度和有界最终位置，并以确定性曲线中段测试保留“随时间移动”的行为证据；相关组 48 项通过，失败项连续 20 次通过，尚未重新推送。

同一批的独立图例审计以固定参考版本复测：Redaktor 与 JUIYAF 各一枚官方底层大写键原被动态显示转为小写，先红后绿定点修正。大小写保留只施加在这两枚键，其他官方布局继续原有显示规则；四层视觉审计由 38／43,464（23 布局）降至 34／43,464（21 布局）。剩余项主要是实体行键数或位置，行数不同时整行逐键比较被跳过，不能由差异数推断整行完全一致。实体键输出审计此前 46,060 点零差异，此批没有修改模拟输出；真实设备、IME 和完整 UI 仍待验收。

2026-10-15 门禁边界：[Native Rewrite Gate #807](https://github.com/nateEc/MacNative-mType/actions/runs/38683801181) 仅覆盖前一批 `2887fcc`，客户端 4,628 项中三项失败／96 项按既有条件跳过，包与服务未执行。失败是低帧率滚动测试计时器读取 `nil`、两项异步换行退休通知在 2ms 后仍为空；与本批布局输出及图例审计互不构成通过证据。修正及本地验证详见功能盘点顶部；本批尚未推送，远端不能宣称已通过。

2026-10-15 屏幕键盘图例的独立只读审计（#808 已推送批次）：在固定源码的 239 官方布局上比较四个实体行、四个修饰层，先行发现 578／43,464 处图例或行位差异，跨 42 布局；这不改变下方 46,060 个物理输入模拟输出零差异的独立结论。左右手 Dvorak 先红后绿纠正错误的 macOS Option 图例及鼠标输入；对没有固定 AltGr 层的官方布局统一移除额外 Option 图例，缺层时虚拟键盘退回 Base／Shift。另修复三层键的 Shift+Option 回退、Turkish E/F 点号差异与西班牙／瑞典 Dvorak、Swedish Colemak 的 Shift 符号；32 个值为空格且视觉留白的图例通过 `characters` 空格能力确认后不计差异。该批仍有 38 处差异、跨 23 布局；行数与位置不匹配会跳过该行逐键比较，故不是所有键位图例的完成证明。首轮扩大回归 839 项中一项 Arabic (macOS) 测试因旧错误 Option 图例期待出现四处断言；按固定源码更正后 842 项零失败、2 项条件跳过。原生保存 ID／格式不变，旧 Option 视觉和鼠标行为变化；真实设备、IME 及其余图例仍待验收。#808 包含此批，但客户端一项测试失败，尚未通过完整门禁。

2026-10-15 本地待推送的最终四层输出纠偏：Colemak-DH Wide ANSI／ISO 补首键，ISO 的底排 `#` Shift 改为 `#`；Latin American home 行末空白键明确插入普通空格；Optimot 的 `⌫` 依固定原版 `getCharFromEvent` 到 `emulateInsertText` 实际路径作为文字，而非旧 Typebar 的删除动作。先行差分分别 4、6、4、4 项，独立先红后绿测试通过；连同本批 AZERTY 后，239 个官方布局的 46,060 个四层物理键输出点在只读固定参考审计中零差异，扩大输入／布局 833 项零失败，目录和原创性检查通过。此口径仅覆盖模拟器文本，不证明视觉提示全部键位、实体键盘、IME、功能矩阵或完整客户端门禁；保存 ID／格式不变，旧 Optimot 输入语义会改变，旧二进制回退恢复旧行为。下文早期关于 Optimot 删除动作的描述为历史旧态。#807 仍验证上一批，新的远端验收未执行。

2026-10-15 远端 #806 完整客户端 4,620 项中有一项 100,001 词完整预览主机测试在固定 200 次刷新后提前断言，已生成 99,700 词但未返回；服务与 Release 因门禁停止未执行。本地将该测试改为有界等待实际完成，定点一次及主机组 12 项均通过，远端待验收，不把当前布局审计成果冒称完整门禁通过。[运行记录](https://github.com/nateEc/MacNative-mType/actions/runs/38679545501)。

2026-10-14 逐键纠错：固定 `bulgarian_phonetic_traditional` 的底排第 3 键是普通 `ь`、Shift `Ь`，不含 `ѝ/Ѝ`。原生视觉图和物理输入模拟此前都把 Shift 层做成 `ѝ`，旧反向查找的不区分大小写回退掩盖了测试对 `Ѝ` 的错误期待。先将视觉、Shift 输出与精确反查测试更正为固定源码合同，得到三处产品断言失败；再修正两处原生映射，保留键位身份及独立 Swift 实现。布局相关 145 项及扩大输入／布局 809 项零失败，固定布局清单和原创性审计通过。历史盘点中称此布局支持 `ѝ` 的段落是旧误判，不再代表当前实现；这项更正不证明其余 238 个布局逐键无误。

## 基线与判定

- 参考仓库固定为 `monkeytypegame/monkeytype` 提交 `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 固定源码的 `LayoutNameSchema` 含 239 个唯一名称；名称快照与映射保存在 `Compatibility/official-layouts.json`。
- `nativeExact` 仅表示 Typebar 有可独立选择、提示、模拟、反查、归档并进入 Layout Fluid 的语义对应布局。
- `nativeRelated` 表示已有相关原生布局，但因来源或变体不完全等价，不计入精确覆盖。
- 其余名称统一标记为 `systemInputOrCustom`：可使用 macOS 当前输入源或用户自写键盘图，但不能宣称已有同名内置实现。
- 清单只保留公开配置名称和 Typebar 自有枚举值；固定参考键位 JSON 仅用于审计可观察输入行为，不复制、打包或执行其中的数据文件、图例、代码或其他资产，产品映射由 Typebar 以独立 Swift 数据结构重新实现。

### 逐键验证现状（2026-10-15）

2026-10-15 本地待推送的 French AZERTY：固定源码是 ISO 物理布局，先行四层对照发现 23/196 差异；旧原生版本缺左上角、home 额外键及底排 ISO 键，且数字行十处、顶行一处 AltGr 与固定版不符。修正原生提示和模拟后，196/196 定点、实际按键与旧持久化身份测试通过，保存 ID 不变、输出语义可能变化。全局四层差分降至 18/46,060，跨 4 布局（2 显式、16 macOS 回退）；扩大回归、真实设备及 #807 之后的新远端门禁尚待验收。

2026-10-15 本地待推送的 Persian Farsi 与 Polish (Programmers)：固定版前者 Q 键无 `ریال` Shift 输出、ANSI 底排无多出的 ISO 键；后者 U 键无 `€` Option 层，数字行与顶行有原生提示漏显的实体键。新增先行测试复现两者各 2 项四层差异并更新原生映射与提示；旧布局身份不变，旧 Typebar 额外快捷输出不再由该官方布局提供。定点及扩大输入／布局 829 项通过（1 项既有条件跳过），合批四层审计降至 41/46,060（5 布局，13 显式、28 系统回退）；不复制原版数据入包。

2026-10-15 本地待推送的 Estonian、Hebrew、Turkish F、Mongolian 四布局：固定源码四层差分分别发现 4、4、4、2 项显式不一致。先行测试复现旧字符或实体行位置，现以独立 Swift 键位映射修正提示和输入；旧保存身份不变、升级后相关字符行为变化。定点测试已过，全局四层审计及扩大回归待本批最终复验；不宣称真实输入法或全功能一致。

2026-10-15 本地待推送的 Ukrainian 纠偏：先行四层审计差 10/192，修正原生 `'/₴`、独立 `ґ/Ґ` 实体键与第三／四层及多余 ANSI 键；键盘提示、实际按键事件、旧设置恢复和 192 项定点通过。全局差分从下段 69/46,060 降为 59/46,060，分布于 11 布局（31 显式、28 macOS 回退）。保存 ID／格式不变，输出语义改变；真人键盘、IME 与可见窗口待验收。

2026-10-15 本地待推送的 Arabic (101) 纠偏：固定源码四层比较原差 8/192，先行定点测试复现 `ﻹ/ﻷ/ﻻ/ﻵ` 被旧实现写成多字符组合；改正原生输入、提示、反查后，192 项、实际按键事件和旧设置恢复定点通过，扩大相关 823 项零失败（1 项条件跳过）。全局差分从下段 77/46,060 降为 69/46,060，跨 12 布局（41 显式、28 macOS 回退）。旧 ID／格式不变，但已保存布局的输出语义改变；真人键盘与 IME 未验收。

2026-10-15 本地待推送的 Arabic (102) 纠偏：四个实体键涉及 10 个四层比较点，先行测试复现兼容字形 `ﻹ/ﻷ/ﻻ/ﻵ` 与零宽空格被旧实现写成分解字符及 NUL；改正原生输入与提示后，该布局 192 项、原生按键交付和设置恢复定点通过，扩大相关 822 项零失败（1 项条件跳过）。全局差分从下段 87/46,060 降为 77/46,060，跨 13 布局（49 显式、28 macOS 回退）。旧 ID／格式保持，文本语义改变；真人键盘和 IME 未验收。

2026-10-15 Tamil99 纠偏：固定源码四层 192 个实体输出原差 12 处，先行定点测试复现六键，再校正原生输入与键盘提示；192 项、旧布局持久化测试现全过。全局四层差分从下段所述 99/46,060 降为 87/46,060，跨 14 布局（59 处显式不同、28 处仍回退 macOS）。保存 ID 和数据格式不变，字符语义变化；真人键盘、IME、Option 图例尚未验收。

2026-10-15 本地待推送的六布局纠偏：Pashto、Hindi InScript、Thai Pattachote、Arabic (macOS)、Whix2、Persian Standard 与固定原版分别差 90、48、46、36、28、14 个四层输出；本次以独立原生映射、可见键盘提示、Whix2 实际空格输入事件及 Persian Standard ANSI 额外键边界修正，6 × 192 个参考比较点全部通过。全局四层差分由上一批的 361/46,060 降为 99/46,060，分布于 15 布局：71 处显式值不同、28 处仍交给 macOS。六个已保存布局 ID 和数据格式不变，但升级后的键位字符会改变；旧二进制可恢复旧语义。真人键盘、IME、Option 图例与完整 UI 尚未验收，不能把逐键文本差分等同于全功能验收。

2026-10-15 上一批已推送（提交 56143f7）的四层输入修正：固定源码 `layout-emulator.ts` 的显式布局在 Option/AltGr 层不存在或为空时，回退到同一物理键的 Base/Shift；普通 Space 也由布局模拟输出。原生现仅对 239 个固定官方布局应用该回退，系统输入、自定义布局、Typebar 专属五项和旧 CRULP 维持原路径；已明确保留 Optimot 的非文本删除键。固定 239 布局中仅 13 项定义第三层，源码只读检查守卫这项分类；其余布局不再沿用旧 macOS Option 符号。ABNT2 按原版 ISO 键码表将 `|` 与 `/` 放回对应实体键，并移除原版未映射的额外键码 `94`；这会改变旧 Typebar 的 ABNT2 键位行为，但不改变持久化 ID。官方 QWERTY 在修正前为 98/192 处差异，修正后 192 项全过；ABNT2 196 项全过。完整四层差分由 15,404/46,060 降为 361/46,060，仍有 21 个布局未通过，其中 333 处显式值不同、28 处仍交给 macOS。此变化会改变已保存官方内置布局的 Option 输入行为，但不改变保存 ID 或数据格式；旧二进制回退会恢复旧行为，真人输入法、设备和 UI 图例尚未验收。

剩余四层文本差异按布局分布（同一固定参考与测试命令，可复测；非真人键盘验收）：

| 布局 | 差异数 | 布局 | 差异数 |
| --- | ---: | --- | ---: |
| `azerty` | 23 | `colemak_dh_iso_wide` | 6 |
| `colemak_dh_wide` | 4 | `estonian` | 4 |
| `hebrew` | 4 | `latam_qwerty` | 4 |
| `optimot` | 4 | `turkish_f` | 4 |
| `mongolian` | 2 | `persian_farsi` | 2 |
| `polish_programmers` | 2 | — | — |

`nativeExact` 的 239 项目前是布局身份及原生功能路径的覆盖声明，**不是逐键输出已全部验证通过**。只读差分测试 `OfficialLayoutOutputAuditTests.testPinnedBaseAndShiftLegendsAgreeWithNativeEmulation` 在设置 `TYPEBAR_LAYOUT_AUDIT_REFERENCE` 为上述固定 checkout 路径时，比较原版布局模拟器实际消费的键位 JSON 与原生物理键模拟；不设置时跳过，不会下载或打包上游数据。`TYPEBAR_LAYOUT_AUDIT_ONLY` 可限于一个官方 ID；`TYPEBAR_LAYOUT_AUDIT_ALL_LAYERS=1` 还验证 Base、Shift、Option、Shift+Option 和实体 Space，按原版缺层回退规则计算期望值。该测试要求差异为零，除已验证的定点布局外目前仍失败，不能作为全布局绿色验收引用。

上一轮基线（本次四层回退修正前）：修复前述 ANSI／ISO 键位与 Norwegian 首键，并将官方 `urdu_phonetic` 指向独立精确入口后，22,444 个 Base／显式 Shift 比较点尚有 142 处差异，分布于 20 个布局：129 处显式输出不同，13 处回退 macOS。四层口径涵盖 46,060 个比较点，当时有 15,404 处差异，分布于 232 个布局：603 处显式输出不同，14,801 处本地未接管而交给 macOS。该数字已由上段的新测量取代；也不能不经实际事件验证便把每个 nil 都断定为不同的最终输入字符。官方 Urdu 的 48 个可触达键 × 四层共 192 项已在固定源码定点对照中通过；旧 CRULP 以原始持久化 ID 保留。真实 IME／实体键盘及其余差异仍待逐项修复与验收。

## 当前覆盖

| 状态 | 数量 | 验收含义 |
| --- | ---: | --- |
| `nativeExact` | 239 | 同名语义已有原生提示、显式输入模拟、反查和持久化测试 |
| `nativeRelated` | 0 | 固定名称集合已无近似替代项 |
| `systemInputOrCustom` | 0 | 固定名称集合已无回退项 |
| 总计 | 239 | 与固定参考源码名称集合一一对应 |

精确覆盖名称：`qwerty`、`dvorak`、`dvorak_L`、`dvorak_R`、`prog_dvorak`、`prog_dvorak_prime`、`german_dvorak`、`german_dvorak_imp`、`spanish_dvorak`、`swedish_colemak`、`swedish_dvorak`、`dvorak_fr`、`colemak`、`colemak_angle`、`colemak_wide`、`colemak_dh`、`colemak_dhv`、`colemak_dh_iso`、`colemak_dh_wide`、`colemak_dh_iso_wide`、`colemak_dh_matrix`、`colemak_dhk`、`colemak_dhk_iso`、`MTGAP_ASRT`、`MTGAP`、`MTGAP_full`、`halmak`、`QGMLWB`、`QGMLWY`、`qwpr`、`ina`、`soul`、`niro`、`typehack`、`ISRT`、`ISRT_Angle`、`engram`、`engrammer`、`semimak`、`semimak_jq`、`semimak_jqc`、`canary`、`canary_matrix`、`boo`、`boo_mangle`、`APT`、`APT_angle`、`middlemak`、`middlemak-nh`、`Foalmak`、`quartz`、`arensito`、`ARTS`、`capewell_dvorak`、`colman`、`heart`、`klauser`、`oneproduct`、`pine`、`pine_v4`、`three`、`asset`、`dwarf`、`flaw`、`stndc`、`uciea`、`whorf`、`whorf6`、`whorfmax`、`octa8`、`nerps`、`gallium`、`gallium_angle`、`gallium_v2`、`nila`、`noctum`、`cascade`、`vylet`、`romak`、`real`、`sertain`、`ctgap`、`graphite`、`focal`、`zenith`、`dhorf`、`gust`、`recurva`、`qwertz`、`swiss_german`、`swiss_french`、`workman`、`prog_workman`、`norman`、`turkish_q`、`turkish_f`、`turkish_e`、`uk_qwerty`、`spanish_qwerty`、`italian_qwerty`、`latam_qwerty`、`azerty`、`azerty_AFNOR`、`bepo`、`bepo_AFNOR`、`alpha`、`handsdown`、`handsdown_alt`、`handsdown_neu`、`handsdown_neu_inverted`、`persian_standard`、`persian_farsi`、`arabic_101`、`arabic_102`、`arabic_mac`、`hebrew`、`urdu_phonetic`、`thai_kedmanee`、`thai_pattachote`、`japanese_hiragana`、`hindi_inscript`、`tamil99`、`armenian_hm_qwerty`、`mongolian`、`polish_programmers`、`bulgarian_phonetic_traditional`、`belarusian`、`ukrainian`、`russian`、`norwegian_qwerty`、`portuguese_pt_qwerty_iso`、`portuguese_pt_qwerty_ansi`、`ABNT2`、`swedish_qwerty`、`danish_qwerty`、`macedonian`、`pashto`、`estonian`。

`handsdown_promethium` 现已归入 `nativeExact`：Typebar 原生提示模型可显示独立 `R` 与空格拇指位；普通 Mac 的唯一物理 Space 按固定参考的扁平键位语义输入第五行首项 `r`，第二项保留为视觉提示。

本批另加入精确覆盖名称：`scythe`、`inqwerted`、`rain`、`night`、`night_stic`；它们与上方清单共同构成当前 143 项 `nativeExact`。

本批再加入精确覆盖名称：`whix2`、`haruka`、`kuntum`、`Kuntem`、`kuntem-jq`；它们与此前清单共同构成当时 148 项 `nativeExact`。Whix2 七处视觉留白在固定源码中实际是空格输出；旧版“不输出”记述已由 2026-10-15 四层实体键／鼠标输出审计纠正，不再作为验收口径。

本批继续加入精确覆盖名称：`BEAKL_Zi`、`snorkle`、`MALTRON`、`PRSTEN`、`RSTHD`；它们与此前清单共同构成当前 153 项 `nativeExact`。其中四项显示双拇指行；普通 Mac 的唯一物理 Space 按固定参考可观察语义映射至第五行首项，第二项仅作提示。

本批继续加入精确覆盖名称：`handsdown_promethium`、`statica_3x5`、`Vestnik`、`Diktor`、`Diktor_VoronovMod`；它们与此前清单共同构成当前 158 项 `nativeExact`。Promethium 使用双拇指提示；Statica/Vestnik 保留特殊 AltGr 字母层；Diktor 两项保留重排数字符号层。

本批继续加入精确覆盖名称：`Redaktor`、`JUIYAF`、`Zubachev`、`colemak_Qix`、`colemak_Qi`；它们与此前清单共同构成当前 163 项 `nativeExact`。五项保留完整 ANSI Base/Shift、数字行与 AltGr 基础层回退，非标准 Cyrillic Shift 配对按精确大小写优先反查。

本批继续加入精确覆盖名称：`colemaQ`、`colemaQ_F`、`thai_manoonchai`、`brasileiro_nativo`、`beakl_15`；它们与此前清单共同构成当前 168 项 `nativeExact`。Brasileiro Nativo 保留 ISO 行结构，泰文组合符保留独立实体键，其余项保留 ANSI 结构；五项均实现 Base/Shift、AltGr 基础层回退及各自数字行显示策略。

本批继续加入精确覆盖名称：`beakl_19`、`beakl_19_bis`、`rolll`、`whorfmax_ortho`、`neo`；它们与此前清单共同构成当前 173 项 `nativeExact`。Neo 保留 ISO 行结构与两个单层空格实体键，前四项保留 ANSI 行结构；五项均实现 Base/Shift、AltGr 基础层回退并隐藏精简数字行。

本批继续加入精确覆盖名称：`bone`、`AdNW`、`mine`、`noted`、`koy`；它们与此前清单共同构成当前 178 项 `nativeExact`。五项保留 Neo 系 ISO 行、各自字母与变音符排列、单层空格实体键及缺失层首层回退，不以一个近似布局替代其他变体。

本批继续加入精确覆盖名称：`3l`、`korean`、`ekverto_b`、`sturdy_angle_ansi`、`sturdy_angle_iso`；它们与此前清单共同构成当前 183 项 `nativeExact`。3l 保留单层空格与数字键，Korean 保留 Jamo 层，Ekverto B 与两项 Sturdy 保留 ISO/ANSI 行及各自符号差异。

本批继续加入精确覆盖名称：`sturdy_ortho`、`HiYou`、`xenia`、`xenia_alt`、`burmese`；它们与此前清单共同构成当前 188 项 `nativeExact`。HiYou 保留 ISO 单层符号键，Burmese 保留独立组合符和数字行，其余项保留各自 ANSI 排列。

本批继续加入精确覆盖名称：`gallium_v2_matrix`、`gallium_nl`、`maya`、`gallaya_angle_ansi`、`gallaya_angle_iso`；它们与此前清单共同构成当前 193 项 `nativeExact`。Gallium v2 Matrix 依固定参考实际声明保留 ANSI 物理类型；Gallaya Angle ISO 保留额外 ISO 键与地区 Shift 符号，其余项保留各自 ANSI 排列。

本批继续加入精确覆盖名称：`gallaya_matrix`、`minimak_4k`、`minimak_8k`、`minimak_12k`、`graphite_angle`；它们与此前清单共同构成当前 198 项 `nativeExact`。五项依固定参考实际声明保留 ANSI 物理类型，三个 Minimak 阶段保留各自渐进键位和英式 `£` Shift 符号。

本批继续加入精确覆盖名称：`optimot`；它与此前清单共同构成当时的 199 项 `nativeExact`。此段关于字母区 `⌫` 的原生删除动作是旧实现的历史记录，已由上方 2026-10-15 固定源码输入路径核验纠正为文字输入；当前精确覆盖数见基线。

本批继续加入精确覆盖名称：`graphite_angle_vc`、`graphite_angle_kp`、`graphite_matrix`、`UGJRMV`、`ORNATE`；它们与此前清单共同构成当前 204 项 `nativeExact`。五项保留各自 ANSI Base/Shift 排列、Graphite 底行差异、UGJRMV 特殊字母/符号及 ORNATE 非对称 Shift 配对。

本批继续加入精确覆盖名称：`tarmak_1`、`tarmak_2`、`tarmak_3`、`tarmak_4`；它们与此前清单共同构成当前 208 项 `nativeExact`。四项保留各自 ANSI Base/Shift 排列和逐阶段迁移差异，并实现 AltGr 基础层回退。

本批继续加入精确覆盖名称：`stronk`、`seht-drai`、`ints`、`rollla`、`wreathy`；它们与此前清单共同构成当前 213 项 `nativeExact`。五项保留各自 ANSI Base/Shift 字母与标点位置，并实现 AltGr 基础层回退。

本批继续加入精确覆盖名称：`saiga`、`saiga-e`、`krai`、`mir`、`ergol`；它们与此前清单共同构成当前 218 项 `nativeExact`。五项保留各自 ANSI Base/Shift 字母与标点位置；Ergol 的特殊数字符号和弯引号非对称配对保持独立。

本批继续加入精确覆盖名称：`hyperroll`、`anishtro`、`dusk`、`panini`、`panini_wide`；它们与此前清单共同构成当前 223 项 `nativeExact`。Anishtro 与 Dusk 保留双拇指提示和物理 Space 字母输出，Panini 两变体保持独立的 ANSI 标点位置。

本批继续加入精确覆盖名称：`sword`、`opy`、`ergo_split46`、`Gralmak`、`vitrimak`；它们与此前清单共同构成当前 228 项 `nativeExact`。五项保持独立 ANSI Base/Shift 键位，OPY 与 Ergo Split 46 的特殊字母和符号按固定可观察配对保留。

本批继续加入精确覆盖名称：`persian_farsi_colemak`、`persian_standard_colemak`、`miligram`、`nokwts`、`vylet_v4`；它们与此前清单共同构成当前 233 项 `nativeExact`。Persian 两项保留逐键组合音标和 RTL 字符，Miligram 保留 ISO 行与数字行策略，另两项保留各自 ANSI 标点位置。

本批继续加入精确覆盖名称：`ergopti`、`rulemak`、`GralmakS`；它们与此前清单共同构成当前 236 项 `nativeExact`，固定官方名称集合不再有 `systemInputOrCustom` 回退。ErgolPT 保留 ISO 行和 Space 的 `空格/-` 层，Rulemak 保留 Cyrillic 扩展层，Gralmak S 保留组合符与完整符号层；缺失的第三、第四层按固定可观察行为分别回退 Base、Shift。

本批继续加入精确覆盖名称：`hungarian`、`JCUKEN`、`bulgarian`；它们与此前清单共同构成当前 239 项 `nativeExact`。三项采用独立原生枚举，分别保留 Hungarian ISO 行与符号层、JCUKEN ANSI 行且不映射额外 ISO 键，以及 Bulgarian BDS ISO 排列和隐藏数字提示行策略，不再借用相关但不等价的既有布局。

## 自动化门槛

`OfficialLayoutCoverageTests` 会验证：固定提交标识、239 个名称完整且唯一、239/0/0 三类数量守恒、每个映射名称都存在于官方集合，以及每个目标 raw value 都能解析为当前 `KeyboardLayout`。新增或重命名布局必须同步更新机器清单、该测试和本文件。
