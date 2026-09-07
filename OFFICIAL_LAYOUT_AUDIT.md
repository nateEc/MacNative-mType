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
| `nativeExact` | 153 | 同名语义已有原生提示、显式输入模拟、反查和持久化测试 |
| `nativeRelated` | 3 | 仅提供相关 Typebar 原生布局，不宣称精确兼容 |
| `systemInputOrCustom` | 83 | 当前通过系统输入源或用户自定义入口处理 |
| 总计 | 239 | 与固定参考源码名称集合一一对应 |

精确覆盖名称：`qwerty`、`dvorak`、`dvorak_L`、`dvorak_R`、`prog_dvorak`、`prog_dvorak_prime`、`german_dvorak`、`german_dvorak_imp`、`spanish_dvorak`、`swedish_colemak`、`swedish_dvorak`、`dvorak_fr`、`colemak`、`colemak_angle`、`colemak_wide`、`colemak_dh`、`colemak_dhv`、`colemak_dh_iso`、`colemak_dh_wide`、`colemak_dh_iso_wide`、`colemak_dh_matrix`、`colemak_dhk`、`colemak_dhk_iso`、`MTGAP_ASRT`、`MTGAP`、`MTGAP_full`、`halmak`、`QGMLWB`、`QGMLWY`、`qwpr`、`ina`、`soul`、`niro`、`typehack`、`ISRT`、`ISRT_Angle`、`engram`、`engrammer`、`semimak`、`semimak_jq`、`semimak_jqc`、`canary`、`canary_matrix`、`boo`、`boo_mangle`、`APT`、`APT_angle`、`middlemak`、`middlemak-nh`、`Foalmak`、`quartz`、`arensito`、`ARTS`、`capewell_dvorak`、`colman`、`heart`、`klauser`、`oneproduct`、`pine`、`pine_v4`、`three`、`asset`、`dwarf`、`flaw`、`stndc`、`uciea`、`whorf`、`whorf6`、`whorfmax`、`octa8`、`nerps`、`gallium`、`gallium_angle`、`gallium_v2`、`nila`、`noctum`、`cascade`、`vylet`、`romak`、`real`、`sertain`、`ctgap`、`graphite`、`focal`、`zenith`、`dhorf`、`gust`、`recurva`、`qwertz`、`swiss_german`、`swiss_french`、`workman`、`prog_workman`、`norman`、`turkish_q`、`turkish_f`、`turkish_e`、`uk_qwerty`、`spanish_qwerty`、`italian_qwerty`、`latam_qwerty`、`azerty`、`azerty_AFNOR`、`bepo`、`bepo_AFNOR`、`alpha`、`handsdown`、`handsdown_alt`、`handsdown_neu`、`handsdown_neu_inverted`、`persian_standard`、`persian_farsi`、`arabic_101`、`arabic_102`、`arabic_mac`、`hebrew`、`urdu_phonetic`、`thai_kedmanee`、`thai_pattachote`、`japanese_hiragana`、`hindi_inscript`、`tamil99`、`armenian_hm_qwerty`、`mongolian`、`polish_programmers`、`bulgarian_phonetic_traditional`、`belarusian`、`ukrainian`、`russian`、`norwegian_qwerty`、`portuguese_pt_qwerty_iso`、`portuguese_pt_qwerty_ansi`、`ABNT2`、`swedish_qwerty`、`danish_qwerty`、`macedonian`、`pashto`、`estonian`。

`handsdown_promethium` 仍归入 `systemInputOrCustom`：固定参考在标准 ANSI 四行之外定义独立 `R` 拇指键及空格键，而 Typebar 当前物理模型只有一个空格拇指位。把 `R` 塞入其他实体键会改变可观察布局语义，因此在原生模型支持双拇指键前不宣称精确覆盖。

本批另加入精确覆盖名称：`scythe`、`inqwerted`、`rain`、`night`、`night_stic`；它们与上方清单共同构成当前 143 项 `nativeExact`。

本批再加入精确覆盖名称：`whix2`、`haruka`、`kuntum`、`Kuntem`、`kuntem-jq`；它们与此前清单共同构成当前 148 项 `nativeExact`。Whix2 的 7 个空位保持不输出且不可反查。

本批继续加入精确覆盖名称：`BEAKL_Zi`、`snorkle`、`MALTRON`、`PRSTEN`、`RSTHD`；它们与此前清单共同构成当前 153 项 `nativeExact`。其中四项显示双拇指行；普通 Mac 的唯一物理 Space 按固定参考可观察语义映射至第五行首项，第二项仅作提示。

相关但不等价的名称：

- `hungarian` → `Hungarian QWERTZ · Typebar`：Typebar 自写映射，不导入官方布局资产。
- `JCUKEN` → `Russian JCUKEN`：只确认同属 JCUKEN 系列，未读取参考键位 JSON，故不与独立的 `russian` 条目重复计为精确覆盖。
- `bulgarian` → `Bulgarian Cyrillic · Typebar`：Typebar 自写 Cyrillic 图，不冒充 BDS 或参考资产。

## 自动化门槛

`OfficialLayoutCoverageTests` 会验证：固定提交标识、239 个名称完整且唯一、153/3/83 三类数量守恒、每个映射名称都存在于官方集合，以及每个目标 raw value 都能解析为当前 `KeyboardLayout`。新增或重命名布局必须同步更新机器清单、该测试和本文件。
