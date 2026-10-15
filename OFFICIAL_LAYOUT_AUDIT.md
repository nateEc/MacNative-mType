# 官方键盘布局兼容矩阵

2026-10-14 逐键纠错：固定 `bulgarian_phonetic_traditional` 的底排第 3 键是普通 `ь`、Shift `Ь`，不含 `ѝ/Ѝ`。原生视觉图和物理输入模拟此前都把 Shift 层做成 `ѝ`，旧反向查找的不区分大小写回退掩盖了测试对 `Ѝ` 的错误期待。先将视觉、Shift 输出与精确反查测试更正为固定源码合同，得到三处产品断言失败；再修正两处原生映射，保留键位身份及独立 Swift 实现。布局相关 145 项及扩大输入／布局 809 项零失败，固定布局清单和原创性审计通过。历史盘点中称此布局支持 `ѝ` 的段落是旧误判，不再代表当前实现；这项更正不证明其余 238 个布局逐键无误。

## 基线与判定

- 参考仓库固定为 `monkeytypegame/monkeytype` 提交 `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 固定源码的 `LayoutNameSchema` 含 239 个唯一名称；名称快照与映射保存在 `Compatibility/official-layouts.json`。
- `nativeExact` 仅表示 Typebar 有可独立选择、提示、模拟、反查、归档并进入 Layout Fluid 的语义对应布局。
- `nativeRelated` 表示已有相关原生布局，但因来源或变体不完全等价，不计入精确覆盖。
- 其余名称统一标记为 `systemInputOrCustom`：可使用 macOS 当前输入源或用户自写键盘图，但不能宣称已有同名内置实现。
- 清单只保留公开配置名称和 Typebar 自有枚举值；固定参考键位 JSON 仅用于审计可观察输入行为，不复制、打包或执行其中的数据文件、图例、代码或其他资产，产品映射由 Typebar 以独立 Swift 数据结构重新实现。

### 逐键验证现状（2026-10-15）

2026-10-15 本地待推送的五布局纠偏：Pashto、Hindi InScript、Thai Pattachote、Arabic (macOS)、Whix2 与固定原版分别差 90、48、46、36、28 个四层输出；本次以独立原生映射、可见键盘提示及 Whix2 实际空格输入事件修正，5 × 192 个参考比较点全部通过。全局四层差分由上一批的 361/46,060 降为 113/46,060，分布于 16 布局：85 处显式值不同、28 处仍交给 macOS。五个已保存布局 ID 和数据格式不变，但升级后的键位字符会改变；旧二进制可恢复旧语义。真人键盘、IME、Option 图例与完整 UI 尚未验收，不能把逐键文本差分等同于全功能验收。

2026-10-15 上一批已推送（提交 56143f7）的四层输入修正：固定源码 `layout-emulator.ts` 的显式布局在 Option/AltGr 层不存在或为空时，回退到同一物理键的 Base/Shift；普通 Space 也由布局模拟输出。原生现仅对 239 个固定官方布局应用该回退，系统输入、自定义布局、Typebar 专属五项和旧 CRULP 维持原路径；已明确保留 Optimot 的非文本删除键。固定 239 布局中仅 13 项定义第三层，源码只读检查守卫这项分类；其余布局不再沿用旧 macOS Option 符号。ABNT2 按原版 ISO 键码表将 `|` 与 `/` 放回对应实体键，并移除原版未映射的额外键码 `94`；这会改变旧 Typebar 的 ABNT2 键位行为，但不改变持久化 ID。官方 QWERTY 在修正前为 98/192 处差异，修正后 192 项全过；ABNT2 196 项全过。完整四层差分由 15,404/46,060 降为 361/46,060，仍有 21 个布局未通过，其中 333 处显式值不同、28 处仍交给 macOS。此变化会改变已保存官方内置布局的 Option 输入行为，但不改变保存 ID 或数据格式；旧二进制回退会恢复旧行为，真人输入法、设备和 UI 图例尚未验收。

剩余四层文本差异按布局分布（同一固定参考与测试命令，可复测；非真人键盘验收）：

| 布局 | 差异数 | 布局 | 差异数 |
| --- | ---: | --- | ---: |
| `azerty` | 23 | `persian_standard` | 14 |
| `tamil99` | 12 | `arabic_102` | 10 |
| `ukrainian` | 10 | `arabic_101` | 8 |
| `colemak_dh_iso_wide` | 6 | `colemak_dh_wide` | 4 |
| `estonian` | 4 | `hebrew` | 4 |
| `latam_qwerty` | 4 | `optimot` | 4 |
| `turkish_f` | 4 | `mongolian` | 2 |
| `persian_farsi` | 2 | `polish_programmers` | 2 |

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

本批再加入精确覆盖名称：`whix2`、`haruka`、`kuntum`、`Kuntem`、`kuntem-jq`；它们与此前清单共同构成当前 148 项 `nativeExact`。Whix2 的 7 个空位保持不输出且不可反查。

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

本批继续加入精确覆盖名称：`optimot`；它与此前清单共同构成当前 199 项 `nativeExact`。Typebar 独立实现其 48 个 ISO 物理位置、四层字符和字母区向后删除动作；删除位不伪装为可输入文本。

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
