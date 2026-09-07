# 官方键盘布局兼容矩阵

## 基线与判定

- 参考仓库固定为 `monkeytypegame/monkeytype` 提交 `91bd24bb8513785c7364cbea29296ff7adafac41`。
- 固定源码的 `LayoutNameSchema` 含 239 个唯一名称；名称快照与映射保存在 `Compatibility/official-layouts.json`。
- `nativeExact` 仅表示 Typebar 有可独立选择、提示、模拟、反查、归档并进入 Layout Fluid 的语义对应布局。
- `nativeRelated` 表示已有相关原生布局，但因来源或变体不完全等价，不计入精确覆盖。
- 其余名称统一标记为 `systemInputOrCustom`：可使用 macOS 当前输入源或用户自写键盘图，但不能宣称已有同名内置实现。
- 清单只保留公开配置名称和 Typebar 自有枚举值；固定参考键位 JSON 仅用于审计可观察输入行为，不复制、打包或执行其中的数据文件、图例、代码或其他资产，产品映射由 Typebar 以独立 Swift 数据结构重新实现。

## 当前覆盖

| 状态 | 数量 | 验收含义 |
| --- | ---: | --- |
| `nativeExact` | 193 | 同名语义已有原生提示、显式输入模拟、反查和持久化测试 |
| `nativeRelated` | 3 | 仅提供相关 Typebar 原生布局，不宣称精确兼容 |
| `systemInputOrCustom` | 43 | 当前通过系统输入源或用户自定义入口处理 |
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

相关但不等价的名称：

- `hungarian` → `Hungarian QWERTZ · Typebar`：Typebar 自写映射，不导入官方布局资产。
- `JCUKEN` → `Russian JCUKEN`：只确认同属 JCUKEN 系列，未读取参考键位 JSON，故不与独立的 `russian` 条目重复计为精确覆盖。
- `bulgarian` → `Bulgarian Cyrillic · Typebar`：Typebar 自写 Cyrillic 图，不冒充 BDS 或参考资产。

## 自动化门槛

`OfficialLayoutCoverageTests` 会验证：固定提交标识、239 个名称完整且唯一、193/3/43 三类数量守恒、每个映射名称都存在于官方集合，以及每个目标 raw value 都能解析为当前 `KeyboardLayout`。新增或重命名布局必须同步更新机器清单、该测试和本文件。
