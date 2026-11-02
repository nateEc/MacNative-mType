# 隐藏墨迹、独立光标与 readAhead 临时显示

后续字段内 LF 导航的 144 个有限普通模式输入／回放直接对照见 EMBEDDED_LF_NAVIGATION_SOURCE_CONTRACT.md；这补充输入证据，不将本合同的颜色／控制器快照扩大为全部输入、实体 IME 或视觉证明。

2026-11-02，起点 ffc593c4d9b7d9fb28c764453c97407d6af3db8d。前批以原生完整 getter 对照局部 getter，只证明内部一致；本批核对固定参考 91bd24bb8513785c7364cbea29296ff7adafac41 的实际控制器、CSS 选择器和输入前事件处理，发现该一致性不能证明隐藏规则的源行为。

## 来源与真实差异

读取行为来源：frontend/static/funbox/read_ahead{,_easy,_hard}.css、simon_says.css，frontend/src/styles/test.scss，test/caret.ts，test/test-ui.ts 的 buildWordHTML／beforeTestWordChange／highlightAllLettersAsCorrect／removeTestElements／showWords／updateWordWrapperClasses，以及 funbox-functions.ts 的完整 readAheadHandleKeydown。

readAhead 的首个 DIV 豁免来自 nth-of-type(n + 2)，当前与后一／两词的隐藏来自相邻 .word 选择器；改变的是未输入颜色。普通高亮下，正确或错误输入使用各自颜色；关闭高亮后，正确输入和盲模式错误也使用未输入颜色。Simon Says 的未输入颜色对整个 words 容器透明，但 caret 是其独立兄弟节点，控制器仍按当前输入位置移动。

包含 LF 的源字段会由实际 HTML 生成器追加三个布局 DIV。因此相邻词隐藏不能跨这些节点，移除词后留下的节点也会影响首个 DIV 豁免；不能简单按字面空格／LF 或未删词数量猜测。源 Backspace 处理在删除之前比较当前输入与目标的最后一个 UTF-16 单元，不匹配时添加临时显示类；物理空格移除该类。粘贴中包含空格或按 Enter 不等价于该物理空格事件。

源 showWords 只替换容器内容，updateWordWrapperClasses 保留临时类；因此显示状态属于同一页面，而非某次尝试或磁盘配置。

## 先行反例及夹具边界

hidden-target-source-red：初步 96 场景以逻辑 hidden 状态作对照，一项 141 处失败，driver 24.993 秒。随后改为比较真实 AttributedString 颜色透明度，加入高亮／盲模式，hidden-target-paint-red 的 384 场景一项 621 处失败，driver 25.543 秒；两轮非 Markdown 输入均保持。

首次实现的 hidden-target-focused：11 项中一项共 49 处失败，driver 184.833 秒。该轮驱动把完整字段内 LF 当成同一字段历史提交，当前引擎推进到了不同字段；CSS／光标控制器的受控输入边界并不验证该插入逻辑。现在历史使用明确的正确前缀提前提交来建立同一个源字段快照，源码与原生比较采用同一已声明历史；字段内部完整 LF 的输入导航仍须独立输入源 oracle 验证，不能用本批通过来关闭。

后续对照执行实际 buildWordHTML，显式保留布局节点，并执行源提交前盲模式处理以获得已提交缺字的 correct 类。前缀退休边界及单词节点删除是受控 DOM 边界，实际 removeTestElements 函数执行删除；尚未证明浏览器 CSS 引擎、实际滚动动画或像素完全等价。hidden-target-structural-focused 曾因可选 activeWordIndex 未展开而编译失败，已校正，不作为产品反例。

## 原生实现

1. 逻辑字格继续记录正确／错误／当前位置；readAhead 和 Simon 的透明墨迹放入 PromptGlyphAppearance，独立主光标保持有效。完整投影使用源字段、退休／移除标记和结构换行来选隐藏范围；局部目录预记录结构边界，按实际字段着色。关闭高亮及盲模式仍按源颜色角色处理。
2. TypingSession 记录临时显示状态，原生 keyDown 在实际编辑前发布逻辑键。Backspace 按原始 UTF-16 比较，空格恢复隐藏；受拒绝的空格也能改变显示。视口快照复用条件包含该显示状态，不因 typed 未变而复用旧墨迹。输入接收器退休时清除新回调。
3. PracticePageSessionStore 在同一页面替换尝试时携带显示状态，新页面从未显示状态开始；不写 UserDefaults、SwiftData 或结果结构。memory 整块隐藏政策未由这些透明颜色规则推断改写。

## 验证范围

新增 QA 脚本只在开发测试读取干净固定参考，输出全部自有词／输入的样例。816 个选择器／HTML／提交／控制器／移除快照含高亮与盲模式、结构换行、退休和空洞；70 个完整按键处理样例在三档 readAhead 中分别对照；两项实际词容器重建类状态检查。它不装入产品，不向产品复制源码、样式、字体或词库。

新增原生页面用例通过真实 TypingInputView.keyDown 桥接 Backspace 与空格，检查先显示再隐藏、被拒绝空格不改输入、同一尝试／输入控件及完整高度。直接输入接收器检查编辑前回调与退休隔离。

hidden-target-dom-focused：12 项零失败，原生 8.272 秒、driver 90.142498 秒，非 Markdown 输入保持。首轮扩大 hidden-target-regression：1060 项一项失败，原生 839.646 秒、driver 853.037 秒；失败是重启宿主在释放生成 continuation 后只等一次 run-loop 就检查异步渲染发布，观察到空目标。单独同项 hidden-target-restart-repro 通过（driver 7.032 秒），尚不能据此宣称产品故障已复现。准备流水线仍含异步渲染及发布；该测试改用与实际生成场景相同的有限发布等待（20 秒），保留旧结果不得出现及取消计数断言，超时报告阶段观测。它没有重试生成、跳过测试或更改产品流水线；同范围最终回归另记。

最终同范围 hidden-target-regression-final：1060 项零失败／跳过，原生 867.708 秒、driver 904.732765 秒，非 Markdown 输入保持；149 项必需源码合同全部通过。重启项通过（1.337 秒），原有发布及取消断言保留。人工验收清单审计通过（1478 个唯一场景），这不代表实体人工验收已经完成。

hidden-target-package：签名、资源字节与原创性检查通过，driver 44.851664 秒，非 Markdown 输入保持；仅生成并清理临时 QA 包，未启动应用，不代表发行包已交付。推送前 main 为 8c52fb13028f82fd8e8718d55cb7ed65463b034e，开发分支为 ffc593c4d9b7d9fb28c764453c97407d6af3db8d；无打开 PR，Actions 826 次，最近 39118939684 成功。不改工作流、通知或 main，只进行一次开发分支批次推送，推后另存远端核对证据。

实体键盘／IME、VoiceOver、实际浏览器与原生帧／像素、结构换行的完整输入导航、全部滚动瞬态及组合仍开放。普通入口默认值保持，完整重写目标继续 active；不更改 CI 或通知。
