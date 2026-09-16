# Owner brief — `planning/briefs/brief_<n>.md`  (template; cap `DOC_CAP_TEMPLATE`)
<!-- One file per touchpoint; one section per item; one decision-log row per
     section (A§10). Chinese body (A§12). Refine before sending. Brief
     background sentences are claims (`claims.md` rule 1). -->

# Brief <n> — <date>
条目：<k> 项（§1…§<k>），**k ≤ `BRIEF_MAX_ITEMS`**——超出的余数按已定前提拆入
下一份 brief（§6）；涉及 row：[…]，**一节一行**：k 项 ⇒ 恰 k 条 decision-log 行，
不得合并（A§10）。两条约束互相咬：把合并的行拆开会把节数顶上去，所以拆行与拆
brief 要一起算，不能先合并凑进帽内。

## §<j> — <一行标题>  〔类型：grill 批次 / design 分节批准 / finding 升级 / R-Q / scope /
ruling-contradiction（仅可答：supersede|reaffirm）/ closure-proof 声明 /
verifier 争议 / 仪器失败封顶 / 上调 re-tag 提案 / bounded-limit 提案 /
amend 处置 / 废弃提案 / 收敛〕

<!-- 节标准（零上下文可裁,A§10）:owner 只凭本节文本即可裁决——不需回看其他文件或
     讨论史;裁决所依赖的每个事实在节内具名（带证据指针）。深度随分量伸缩:二元
     确认也至少要有来路、双向改动面、一个分叉示例。 -->

- **来龙去脉**：…（背景句也是断言——带证据指针）
- **为什么会有**：…
- **推荐怎么做**：先枚举**全部可行选项**（含「维持现状」,若可行）,每项一行:
  改动面（动哪个文件/机制/行为）· 代价 · 之后什么变得必须或不可能;再给推荐 +
  一句理由。（"ok" 即按推荐原文签署——不变。**若各选项殊途同归,本节不该存在**
  ——那不是裁决点,按既有纪律直接落地留档,不花 owner 决策位）
- **收益**：…
- **完整形象示例**：同一个具体场景,在**推荐项与最强对立项**（至少）下各走一遍,
  写明可见结果在哪里分叉——例子是共同理解的可执行测试,**结果不分叉的例子说明
  选项集是假的**;例子的选取标准是暴露机制的分界面,不是展示推荐项的优势
  （实测:owner 的追问打在机制本身,例子里要给那个入口）
- **代价与最强反方**：…（被否方案的最强理由,防说服文档化）
- **附加字段**（按类型必填）：废弃提案=归档摘要；closure-proof 声明=类别/复发证据/根假设/算子图/定向检查；scope brief=新轮次与批次预算（若提案含 split 选项：两个新 topic root、各自 topic statement、父题归档摘要；若为 staleness 更正：被更正的 doc 段落原文 + 卡片 staleness 行 id，预算字段填「不移动」——A§2）；amend=分类与 hash + **机械 diff**（已签版本 vs 改后 plan.md——editorial 之所以免评审轮，靠的就是这份 diff 证明它没碰 A§4 的触发清单；促成 escape count 的正是这个分类）；仪器失败封顶=失败史；收敛=填好的收敛检查单（作为本节附录随简报提交——A§9）；其余类型=无

> **裁决**：<owner 填/口头答复原文> → row `<id>`（原文逐字入行 + English gloss）
> 未答复 = row 留 `proposed`，依赖此项的工作 park（A§10）。

## Refine log（发送前）
| pass | findings（A/B/C/wording）| fixes |
|---|---|---|
