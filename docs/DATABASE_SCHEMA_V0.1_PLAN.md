# HorseRPG v0.1 数据库设计草案

> 状态：设计草案。本文定义建议的数据边界、关系和一致性要求；**不包含 migration SQL，不创建任何表，也不修改 Supabase 数据库。** 业务规则以 [PRODUCT_SPEC_V0.1.md](PRODUCT_SPEC_V0.1.md) 为准。

## 1. 设计原则

1. **GM 为最终裁判。** 将玩家请求、GM 决定、最终记录和自动结算分开保存，避免把玩家提交直接当作事实。
2. **资金以不可变流水为准。** 金额均为 `bigint`；账户资金和可用资金应从初始资金、正式流水和当前冻结计算，不储存可被随意改写的余额。
3. **结算必须原子且可重试。** 报价、成交、所有权分配、奖金释放等会影响资金与归属的操作，均必须经受并发和重复请求。
4. **WP 时间与现实时间分离。** 游戏事件保存 `wp_year`、`wp_month`、`wp_week`；操作和截止时间使用 PostgreSQL `timestamptz`。不能用客户端时钟裁定拍卖。
5. **私密数据按数据层隔离。** 庭先报价和私密评价不能因列表、聚合、Realtime payload、审计浏览或错误信息而泄漏。
6. **事实与派生值分离。** 比赛结果、正式资金流水和当前有效报价是事实；马匹战绩、账户资金、冻结、可用资金和总资产应查询计算或由可验证的读模型计算。
7. **历史不物理删除。** Horse 以 `DISCARDED` 表示退出；已结算事实以追加修正或状态变迁处理，保留审计轨迹。

## 2. 建议实体总览

```text
auth.users ── 1:1 ── user_profiles ── PLAYER:1:1 ── owners ──< horses
                                                              ├──< horse_factors
                                                              ├──< race_entry_requests ── 0..1 confirmed_race_entries ──< race_results >── actual_races
                                                              ├──< injuries
                                                              └──< condition_records

race_results ── 0..1 prize_receivables ──< prize_receivable_adjustments  (v0.4-D 以后)

foal_trade_sessions ──< foal_trade_lots ── 1:1 ── horses
       ├──< foal_trade_inquiries
       └──< secret_bid_offers

public_auction_events ──< public_auction_lots ── 1:1 ── horses
                                      ├──< public_auction_lot_reviews
                                      └──< public_auction_bids

owners ──< financial_transactions
owners ──< prize_receivables
all key changes ──< audit_logs
```

箭头表示“一对多”。`auth.users` 是 Supabase Auth 的既有身份来源；其余为将来应用 schema 中的建议表，而非本阶段要创建的表。

## 3. 建议表与职责

### 3.1 身份、权限与公开归属

| 表 | 职责与建议存储 | 关系 | PLAYER RLS |
| --- | --- | --- | --- |
| `user_profiles` | 以 `auth.users.id` 为主键；角色枚举 `PLAYER`/`GM`，可包含显示名、创建/更新时间和可空 `owner_id`。 | `PLAYER` 必须关联恰好一个 Owner；`GM` 不关联 Owner。 | 玩家仅可读自己的资料；角色授予和变更仅 GM/server。 |
| `owners` | Owner 的公开名称、`initial_funds bigint`、时间戳。 | 一个 Owner 可以暂时没有 PLAYER，v0.1 最多关联一个 PLAYER；拥有多匹 Horse、多笔财务事实。 | 所有人可读公开字段与公开资金汇总；资金初始化/调整仅 GM/server。 |

Owner 与 PLAYER 身份分开：Owner 是游戏内经济与马匹归属主体，玩家账号是操作主体。数据约束必须保证 `PLAYER` 有且只有一个 `owner_id`，一个 Owner 最多对应一个 PLAYER；Owner 没有 PLAYER 合法。骑手、调教师和外部血统名称均保持文本字段，v0.1 不建立相应主数据表。

### 3.2 马匹与血统

| 表 | 职责与建议存储 | 关系 | PLAYER RLS |
| --- | --- | --- | --- |
| `horses` | 内部 `id`、永久唯一 `horse_number`、`birth_year`、`foal_name`、可空正式名、性别、毛色、父/父系/母父名称、可空 `owner_id`、当前主战骑手名、当前调教师名、`life_stage`、时间戳。 | 多对一 Owner；一对多因子、报名、伤病等。 | 全员可读。写入仅 GM/server；Owner 通过获马流程取得所有权，不直接更新 `owner_id`。 |
| `horse_factors` | `horse_id`、因子类型 `SIRE`/`MARE`、因子值/名称、排序或时间戳。 | 多对一 Horse。 | 全员可读；仅 GM/server 写。每马每类型至多两条。 |

主战骑手和调教师以 Horse 当前字段保存，符合 v0.1 不保留历史的规则。`owner_id` 一经由结算流程填入不应转让或清空；数据库约束/受控函数应阻止普通更新。名称是否需要规范化为骑手、调教师、血统名独立表，当前规则尚不足以要求。

### 3.3 庭先取引

| 表 | 职责与建议存储 | 关系 | PLAYER RLS |
| --- | --- | --- | --- |
| `foal_trade_sessions` | 届次、相关 WP 年、服务器现实开始/截止时间、状态（草案/开放/锁定/核对中/已结算等）。 | 一对多交易 Lot、询问、报价。 | 可公开读取届次及公开阶段信息；状态推进仅 GM/server。 |
| `foal_trade_lots` | `session_id`、`horse_id`、最低报价（`bigint`，可为 0）、Lot/展示信息、交易处理状态。 | 每个 Horse 只可有一个庭先 Lot，且该 Session 的 WP 年必须等于 Horse `birth_year`；被询问和报价引用。 | 公开可读；仅 GM/server 写。 |
| `foal_trade_inquiries` | `session_id`、`owner_id`、`horse_id`、GM 私密评价、提交/回复时间和状态。 | 每届 Owner 最多一条。 | 仅所属 Owner 与 GM 可读；创建、回复、修改须受控。唯一约束应为 `(session_id, owner_id)`。 |
| `secret_bid_offers` | `session_id`、`lot_id`、`owner_id`、金额、当前状态、当前报价形成现实时间、撤回/取代关联、时间戳。当前报价可配合独立的不可变历史表保存每次变更。 | 一位 Owner 对一 Lot 最多一笔当前有效报价。 | 报价阶段仅所属 Owner 与 GM 可读；创建/修改/撤回仅 Owner 的受控 server 操作，结算仅 GM/server。失败报价及其历史永久私密。 |
| `foal_trade_settlements` | 系统推荐报价、最终选择报价、获胜 Owner、成交金额、是否 override、非空 override 原因、GM 确认者/时间、结果状态与备注。 | 每个 Lot 至多一个最终结算。 | 仅安全公开投影向所有 PLAYER 展示最终 Owner 与最终成交价格；内部报价引用、override 原因和 GM 备注仅 GM 可读；写入仅 GM/server。 |

庭先 Session 的现实 `starts_at` / `ends_at` 仍为数据库服务器裁定用的 `timestamptz`；GM 界面以中国标准时间的预设开始时刻和 1 小时至 7 天的预设持续时长生成它们。仅 `DRAFT`、尚未开始且没有任何询问、报价、报价历史或结算的 Session/Lot 可经 GM-only 受控 RPC 移除；被移除配置必须写 Audit，且 Horse 可重新配置。已开始或已有业务事实的数据不允许物理删除。

`secret_bid_offers` 的当前有效记录需要支持“修改后重新形成同价优先时间”，因此不应只覆盖金额而丢失形成时间。可采用当前单行报价配合不可变历史，或追加版本并标记当前有效版本；两者都必须保留每次变更。数据库需确保同 Owner、同 Lot 只有一个当前有效报价。报价阶段完全秘密；GM 确认后只可通过安全投影公开最终 Owner 与成交价格，不能以结算记录、计数、关联查询、Realtime 或错误信息泄漏任何失败报价。

一匹幼驹仅参加出生批次的一届庭先取引。庭先未成交的 Horse 只能进入同一 WP 年的年末公开拍卖；公开拍卖未成交后设为 `DISCARDED`，不可再次进入庭先或公开拍卖。`foal_trade_lots.horse_id` 与 `public_auction_lots.horse_id` 都应各自全局唯一；进入公开拍卖的资格和年份一致性应由受控 server-side 操作验证。

当前 `horses_prevent_foal_trade_lot_direct_assignment` 会阻止已经参加庭先的未成交 Horse 通过普通路径完成 `NULL → Owner`。未来公开拍卖模块必须以新的受控结算 guard/RPC 扩展此保护，使庭先 Settlement 与同年年末公开拍卖 Settlement 都能合法完成首次归属；不得为了提前支持拍卖而放宽当前普通 Horse 更新保护。

### 3.4 年末公开拍卖

| 表 | 职责与建议存储 | 关系 | PLAYER RLS |
| --- | --- | --- | --- |
| `public_auction_events` | 年度 WP 年、名称、`DRAFT`/`OPEN`/`CLOSED`/`SETTLED`、最低加价单位（当前固定为 `100000`）与时间戳。 | 一对多公开拍卖 Lot。 | 已认证用户可读；仅受控 GM/server RPC 推进。 |
| `public_auction_lots` | `event_id`、`horse_id`、Lot 编号、起拍价、评价价值、`revealed_at`、当前 Round、当前价/赢家、开始、`close_at`、无报价截止、关闭时间和派生状态。 | Horse 全局至多一个 Lot；每 Lot 多个 Round、五条评分，且每 Round 至多一个 Settlement。 | GM 可读全部；PLAYER 仅可读 `revealed_at IS NOT NULL` 的 Lot。创建、展示、开始、关闭、确认仅受控 GM/server RPC。 |
| `public_auction_rounds` | `round_number`、`QUEUED`/`OPEN_WAITING`/`BIDDING`/`CLOSED`/`SOLD`/`PASSED`/`VOIDED`、当前价/赢家和全部服务器时间字段。 | 多对一 Lot；Lot 只指向一个当前 Round。Emergency Rollback 创建新 Round 而不覆盖历史。 | PLAYER 仅可读已展示 Lot 的当前 Round；GM 可读全部 Round。 |
| `public_auction_lot_reviews` | `lot_id`、`slot`（1–5）、`stars`（1–5）、`comment`、时间戳。 | 每个 Lot 恰好五条评分，分别对应 slot 1–5。 | GM 可读全部；PLAYER 仅可读已展示 Lot 的评分；仅 GM/server 写。 |
| `public_auction_bids` | `lot_id`、`round_id`、`owner_id`、金额、客户端请求幂等键、数据库接收时间。 | 多对一 Round 和 Owner；仅追加历史。 | PLAYER 仅可读已展示 Lot 的当前 Round 已接受 Bid；写入只允许本人经受控 Bid RPC。旧 `VOIDED` Round 的 Bid 仅 GM/audit 历史。 |
| `public_auction_settlements` | 每个 Round 的 `SOLD`/`PASSED`、赢家/金额、GM 确认、原因、Rollback 标记和引用。 | `round_id` 唯一；同一 Lot 通过新 Round 可保留多个历史 Settlement。 | 直接读取仅 GM；最终未 rollback 结果仅经安全 View 向 authenticated 公开。 |
| `public_auction_rollback_requests` | 高风险申请、非空原因、严格确认文本、申请/确认/执行者与时间、补偿流水、新 Round。 | 每个 Settlement 至多一个 pending 与一个 executed 请求。 | 仅 GM 可读写/调用；原因和内部引用不公开。 |

评分和评语正式使用 `public_auction_lot_reviews`，不存入 Lot 的固定列。该表要求 `UNIQUE(lot_id, slot)`，并约束 `slot`、`stars` 都在 1–5 范围内。Lot 在展示或开始竞价前必须具备 slot 1–5 五条评分；这一“恰好五条”的跨行条件需由受控操作或等价数据库完整性机制保证。

拍卖运行中 Lot 的当前价/当前 Owner 是当前 Round 的受控投影；权威竞价历史是 `public_auction_bids`。所有金额必须为 `100000` 的整数倍：首口 `>= starting_price`，后续口 `>= current_price + minimum_increment`，当前赢家不得自抬，Bid 无撤回路径。报价 RPC 必须接收客户端预期的当前 `round_id` 与幂等 `request_id`：Lot 当前 Round 不匹配即拒绝；同 Owner/同 Round/同请求键仅同金额可幂等返回原 Bid，异金额必须拒绝。每次合法报价在同一数据库事务内锁定 Lot/当前 Round/Owner，使用服务器时间校验期限、检查庭先和其他公开拍卖冻结、写入 append-only Bid，并以最终插入 Bid 的服务器 `accepted_at + 10 秒` 精确更新 `close_at`。不得依赖客户端或 Realtime 写入状态。

`revealed_at` 是展示公开面的最小事实：GM 只能在 Event `OPEN`、Lot/当前 Round 都为 `QUEUED` 且已有五份评分时设置它；该动作只写服务器时间和 Audit，不启动期限、不改变 Round。只有已展示 Lot 才可被 GM 开始，进入 `OPEN_WAITING` 后才设置 10 分钟无报价期限。`OPEN_WAITING` 只有服务器设置的 10 分钟无报价期限，不启动 10 秒竞价时钟；第一口才进入 `BIDDING`。期限到达时系统仅逻辑或显式转为 `CLOSED`，不自动 `SOLD`、`PASSED` 或改变 Horse。GM 可在 `CLOSED` 后确认成交或流拍；有报价的未结算 `CLOSED` Round 可带原因普通重开并保留最高价/赢家，没报价的 Round 恢复 `OPEN_WAITING`。`SOLD`/`PASSED` 禁止普通重开。Emergency Rollback 不清空 `revealed_at`。

Emergency Rollback 使用双阶段 `public_auction_rollback_requests`：申请阶段不改业务事实；严格确认阶段锁定 Lot/Round/Settlement/Horse/Owner。`SOLD` 通过新增正向补偿 `financial_transactions` 保留原扣款，并受控使 Horse `Owner → NULL`、`OWNED_FOAL → FOAL`；`PASSED` 受控使 `DISCARDED → FOAL` 而无资金补偿。两种情况均保留原历史、将旧 Round 标为 `VOIDED`、创建从起拍价重新开始的 `QUEUED` Round，并完整审计。若关联 Event 为 `CLOSED` 或 `SETTLED`，确认 Rollback 必须在同一受控事务将 Event 改为 `OPEN` 并记录状态恢复 Audit，使新 Round 可以再次开拍；该恢复不是普通 `SETTLED → OPEN` 状态转换。公开最终结果使用 `public_auction_public_settlements` 安全 View，仅暴露未 rollback 的 Lot/Event/Horse、结果、赢家、金额和确认时间。

公开拍卖可物理移除的范围仅限 Event 为 `DRAFT` 的未开始配置：Lot 必须 `QUEUED`、`revealed_at IS NULL`，其所有 Round 均未开始且没有 Bid、Settlement 或 Rollback 历史。GM-only 受控 RPC 先锁 Event、再锁 Lot/初始 Round，删除草稿评价与初始 Round 后删除 Lot；移除整个草稿 Event 时逐 Lot 复核同一条件。不得授予业务表直接 DELETE 权限，所有移除必须有非空原因并写入 `audit_logs`。

### 3.5 比赛报名、赛果、状态记录

| 表 | 职责与建议存储 | 关系 | PLAYER RLS |
| --- | --- | --- | --- |
| `race_catalog` | OP/G3/G2/G1 固定比赛名、级别、默认 WP 月/周、启用状态与时间戳。默认月/周仅供填写参考。 | 可被意向与确认赛程引用，但不约束确认赛程的最终时间。 | authenticated 可读；仅 GM 维护。 |
| `race_entry_requests` | PLAYER 原始 Horse、Owner、请求 WP 时间、固定比赛或类别型比赛、可空骑手/跑法/备注，以及 `PENDING`/`CONFIRMED`/`REJECTED`/`WITHDRAWN` 审核状态。 | 多对一 Horse；一条请求最多一条确认赛程。请求字段在审核后不被覆盖。 | 请求 Owner 与 GM 可读；写入、撤回只通过受控 RPC。 |
| `confirmed_race_entries` | GM 权威赛前安排：可空来源 Request、Horse/Owner 快照、最终 WP 时间、固定比赛或类别型比赛、可空骑手/跑法/GM 备注、确认者与时间。 | 有来源时与 Request 一对一；也可由 GM 直接安排；未来可由 `race_results` 稳定引用。 | 基础表仅 GM 可读；所有 authenticated 用户仅通过安全 `confirmed_race_entries_public` 投影读取公开赛程。 |
| `actual_races` | 实际发生的 WP 比赛：WP 年/月/周、比赛类别、可空 Catalog 引用、`race_name`/`grade` 历史快照、创建 GM 与时间。Catalog 实际比赛创建时复制当前名称/Grade；非 Catalog 必须保存自由文本比赛名且 Grade 为 NULL。 | 一场实际比赛可关联多条 `race_results`。 | 基础表仅 GM；PLAYER 通过 `race_results_public` 间接读取已有效赛果的实际比赛事实。 |
| `race_results` | 必填 `confirmed_race_entry_id`、`actual_race_id`、由 Entry 派生的 Horse、`CONFIRMED`/`VOIDED`、名次、`prize_amount bigint`、可空实际骑手/跑法/GM Note、录入/作废者与时间。 | 多对一 `actual_races`；同一确认赛程和同一 Horse/实际比赛各至多一个当前 `CONFIRMED` 结果；VOID 后可重新录入。 | 基础表仅 GM；所有 authenticated 用户只经 `race_results_public` 查看当前有效的公开字段。 |
| `injuries` | Horse、是否伤病、WP 开始/结束年/月/周、备注、GM 确认信息。 | 多对一 Horse。 | 全员可读；仅 GM/server 写。伤病结束 WP 周按包含处理，从下一 WP 周起可报名。 |
| `condition_records` | Horse、相关 WP 时间、GM 最终体力/投骰/结算记录和备注。 | 多对一 Horse。 | 全员可读；仅 GM/server 写。它只记录 GM 裁定，不作为系统自动推导正确体力或伤病结论的依据。 |

Race Management v0.4-A 采用 Request + Confirmed 双表：PLAYER 可以为自己的 ACTIVE Horse 提交任意多个未来或当前周 PENDING 意向；GM Confirm RPC 必须显式写最终 WP 时间与比赛身份，允许最终时间/比赛覆盖请求，且骑手/跑法可空。GM 也可通过受控 Direct Confirm RPC 为已有 Owner 的 ACTIVE Horse 创建不附带 Player Request 的权威赛程；该路径不接受 Owner 参数，而是从锁定的 Horse 派生 Owner。仅 `confirmed_race_entries` 以 `(horse_id, wp_year, wp_month, wp_week)` 唯一约束占用赛程；多个 PENDING 同周意向合法。两条 GM 路径共用 Horse、`game_state`、比赛身份和 ACTIVE injury 的服务器端校验；Request 确认在同一事务原子写 Confirmed Entry、Request 状态和 Audit。双向触发器保证有来源的 Confirmed Entry 对应 PENDING Request，且 CONFIRMED Request 恰好有一条匹配赛程。公开赛程只能通过安全投影读取，不公开 Request、GM 备注或确认者。伤病冲突和特殊跑法规则应在 server-side 检查，GM 保留未来赛果层的最终裁定能力。

Race Results v0.4-C 已确定三层事实：`confirmed_race_entries` 是赛前计划，`actual_races` 是 Winning Post 实际发生的比赛，`race_results` 是某 Horse 的赛后事实；计划与实际时间、比赛、骑手、跑法允许不同且永久并存。创建/更正 Actual Race 只能使用当前或过去 WP 周；Catalog 仅要求引用行存在而不要求 `is_active`，并在 `race_name`/`grade` 存历史快照，之后目录变动不得回写历史。非 Catalog Actual Race 使用非空 label 作为 `race_name`、不引用 Catalog、`grade = NULL`。Result 只能由 GM RPC 从 Confirmed Entry 派生 Horse，不能让客户端传 Horse/Owner；更正不能迁移 Entry 或 Horse，选错 Entry 必须 VOID 旧结果后重新 Record。`prize_amount` 是无公式的 GM 最终赛果金额，v0.4-C 不创建 Prize Receivable、Financial Transaction、资金或待释放奖金副作用；v0.4-D 必须扩展更正/VOID 以受控调整已存在的应收。

### 3.6 财务、奖金与退役

| 表 | 职责与建议存储 | 关系 | PLAYER RLS |
| --- | --- | --- | --- |
| `financial_transactions` | Owner、`amount bigint`（正负）、交易类别、有效现实时间、来源对象/结算引用、GM/系统操作者、备注、时间戳。仅记录真正入账或扣款的事实。 | 多对一 Owner；可由拍卖、庭先、奖金释放或修正产生。 | 逐笔公开范围未定；仅 GM/server 追加，禁止普通 UPDATE/DELETE。 |
| `prize_receivables` | Horse、Owner、来源赛果、`amount bigint`（GM 最终确认值）、`PENDING`/`RELEASED`、生成/释放时间、释放流水引用。 | 多对一 Horse/Owner；一条基础应收对应一条赛果。 | 全员可读；创建、释放、受控调整仅 GM/server。 |
| `prize_receivable_adjustments` | 原始应收、GM 确认的调整金额、调整原因、关联赛果修正、处理状态、释放/修正流水引用和时间戳。 | 多对一基础应收；用于已生成或已释放奖金后的受控调整。 | 全员可读；仅 GM/server 追加。 |
| `retirement_cases` | Horse、申请 Owner、申请时 WP 时间、申请/强制退役原因、GM 确认者与时间、状态、最终奖金释放批次/幂等键、备注。 | 一 Horse 至多一个已确认退役结算。 | Owner 可查看/提交自身马匹的申请；GM 全读写；结算仅 GM/server。 |

`prize_receivables.amount` 是 GM 输入/确认的最终基础金额，而不是由数据库公式自动计算的结果。未来辅助计算只能提供建议。赛果在应收生成后被更正时，不得再次生成基础应收：未释放部分通过受控 `prize_receivable_adjustments` 调整有效待释放额；已释放部分通过关联调整记录的追加 `financial_transactions` 修正。两种路径都必须审计且可幂等重试。

冻结资金不是 `financial_transactions`。它应从当前有效秘密报价与当前公开拍卖最高有效报价计算，或保存在严格受控、可从报价重建的投影中。账户资金、可用资金、待释放奖金、总资产同样应动态计算，避免双写余额。正常 PLAYER 业务操作必须拒绝会使账户资金或可用资金为负的请求；金额使用 `bigint` 整数游戏资金单位。

### 3.7 审计

| 表 | 职责与建议存储 | 关系 | PLAYER RLS |
| --- | --- | --- | --- |
| `audit_logs` | 操作者账号/角色、现实时间、动作类型、实体类型/ID、可追溯前后内容或引用、原因/备注、关联请求/事务 ID。 | 可引用所有关键实体。 | GM 可读全部；玩家不得藉由审计读取私有报价/评价。写入由 server/数据库触发机制控制。 |

必须记录的范围：资金、赛果、WP 赏金、拍卖结果、庭先成交、伤病、退役、奖金释放和其他已结算的重要数据。由于日志本身可能包含秘密报价，RLS/视图必须按源数据敏感级别拆分，不能默认对玩家公开。

## 4. 实际存储与动态计算

| 实际存储的事实 | 应动态计算或由可验证读模型产生 |
| --- | --- |
| Horse 基础资料、当前阶段、当前 Owner、文本形式的骑手/调教师/血统名称、血统因子 | Horse 战绩：出赛次数、胜/亚/季、G1 胜、总 WP 赏金、主要胜鞍 |
| WP 时间字段、现实时间戳、GM 决定与备注 | 账户资金 = 初始资金 + 正式流水合计 |
| 庭先 Lot/询问/报价的当前状态及历史、最终成交 | 当前冻结 = 当前有效秘密报价 + 当前公开拍卖当前 Round 赢家报价 |
| 公开拍卖 Lot、Round、五条独立评分、追加式竞价、服务器期限、最终成交/流拍和 rollback 申请 | 可用资金 = 账户资金 − 当前冻结 |
| 报名意图、确认赛程、实际比赛、赛果、伤病、GM 最终体力记录 | 待释放奖金 = 基础 `PENDING` 应收款与未处理调整的有效金额合计；总资产 = 账户资金 + 待释放奖金 |
| Prize Receivable、奖金调整、正式 Financial Transaction、退役结算状态 | 是否达到 G1 九胜等可从确认赛果计算的提示条件 |
| 审计日志 | |

如需性能优化，可以添加只读物化视图或受控投影；它们必须可从上述事实重建，且不能成为 GM 任意直接修改的另一份真相。

已发布的 `get_current_owner_funds()` 保持庭先阶段的三字段兼容语义，不追溯修改。公开拍卖阶段新增独立的、无 `owner_id` 参数的 `get_current_owner_financial_summary()`：仅当前 authenticated PLAYER 可调用，返回 `account_funds`、`foal_trade_frozen_funds`、`public_auction_frozen_funds`、`total_frozen_funds` 与 `available_funds`。它由 `auth.uid() → user_profiles → owner_id` 推导 Owner，GM、anon 与 service_role 直接调用均被拒绝；其公开拍卖冻结口径与出价/结算事务相同，即仅当前 Round 的 `BIDDING`/`CLOSED` 赢家报价。

## 5. RLS 与执行边界

### PLAYER 数据访问

PLAYER 必须绑定 Owner，且可读全部 Horse、Owner、比赛、公开拍卖状态、奖金应收和 Owner 公开资金汇总；可读写自身 Owner 的尚未处理意图（如报名、庭先询问、秘密报价的受控操作）。公开拍卖为公开竞价：PLAYER 可读当前 Event/Lot/评分/当前 Round 已接受 Bid/当前价/赢家/期限及安全最终结果，但不能直接写任何拍卖基础表，也不能读取 rollback 申请、原因、旧 `VOIDED` Round 或内部 Settlement。除庭先秘密报价和庭先私密 GM 评价外，v0.1 不设置玩家之间的 Owner 数据隔离。

庭先 `secret_bid_offers`、其历史与 `foal_trade_inquiries` 必须按 `owner_id` 严格隔离，GM 例外。报价阶段完全秘密：列表计数、聚合、报错、审计、Realtime channel 和关联查询都必须遵循相同隔离，避免旁路泄漏。GM 确认结算后，所有 PLAYER 仅可通过安全公开投影读取最终成交 Owner 与最终成交价格；失败报价、报价历史、推荐与 override 内部资料继续隔离。公开资金汇总不得包含或可反推出当前秘密报价、秘密报价冻结或可用资金；逐笔 `financial_transactions` 的公开范围仍待产品确认。

### GM 与 server-side 操作

GM 可访问并修正全部业务数据，但涉及结算的写入不应由客户端直接修改基础表。以下至少必须在 server-side 或受控数据库函数/事务中执行，并验证操作者 GM 权限：

- 创建/锁定/核对/确认庭先交易，分配所有权和扣款；
- 展示、开始、关闭、确认或流拍公开 Lot；
- 赛果、WP 赏金、伤病、退役和奖金应收的 GM 确认/修正；
- 任何正式资金流水、资金修正和奖金释放；
- 角色授予、初始资金变更和 Horse 所有权变更；
- 写入或维护审计记录。

普通 PLAYER 客户端不应持有可绕过上述边界的权限或密钥。

## 6. 事务、并发和幂等要求

| 操作 | 为什么需要事务/锁 | 幂等要求 |
| --- | --- | --- |
| 创建、修改、撤回庭先报价 | 同时校验截止、同 Lot 当前报价唯一性、Owner 全部冻结和可用资金，拒绝导致可用资金为负的请求，防止并发超额冻结。 | 请求应有幂等键；重复提交不得产生重复有效报价或改变同价优先时间。 |
| 庭先 GM 确认成交 | 正常路径必须选出 `amount DESC, priority_at ASC, id ASC` 的系统推荐报价；异常路径必须显式选择另一有效报价并保存非空原因、推荐与选择。两条路径都须锁定 Lot、扣款、分配 Horse Owner、写流水与审计，并原子完成。 | 每 Lot 至多一次最终结算；重试返回同一结算结果。 |
| 公开拍卖报价 | 锁定当前 Lot/当前 Round/Owner，先校验客户端预期 `round_id` 仍是 Lot 当前 Round；再使用数据库服务器时间判断 10 秒或无报价 10 分钟期限，校验 10 万单位、首口/增量/非自抬、庭先与其他 Round 冻结以及可用资金非负，写 Bid 并以该 Bid 最终 `accepted_at + 10 秒` 更新当前赢家/期限。 | 同 Owner/同 Round/同请求键的同金额重试返回原 Bid，不重复延长倒计时或产生重复竞价；同键不同金额拒绝。 |
| 公开拍卖 GM 确认 | 锁定 Lot/Round/Horse/赢家 Owner，验证合法 `CLOSED`；成交时写追加扣款、Owner、Horse 阶段、Round 与审计；无赢家时 `PASSED` 并受控更新 Horse 为 `DISCARDED`。 | 每 Round 至多一个最终结果；重试返回同一 Settlement，不得重复扣款或重复转归属。 |
| 公开拍卖 Emergency Rollback | 两阶段锁定申请、Lot/Round/Settlement/Horse/Owner；保留旧历史，成交时追加补偿流水、受控回退 Horse，作废旧 Round 并创建新 Round。 | 每 Settlement 至多成功一次；重复确认无副作用，绝不重复退款或创建新 Round。 |
| 比赛报名及 GM 确认 | Request 确认锁定 Request/Horse/当前 `game_state`；GM Direct Confirm 只锁定 Horse/当前 `game_state` 并从 Horse 派生 Owner。两者共用 ACTIVE、最终 WP 周伤病、比赛身份和最终周唯一性校验；Request 路径仍保留原请求。 | 同 Request 的相同确认可安全重试；Direct Confirm 的相同最终事实可安全重试；Request 与 Direct 路径不能产生两笔占用同一 Horse/最终 WP 周的确认赛程。 |
| v0.4-C 赛果 | GM Record 锁定 Confirmed Entry、读取/锁定 Actual Race 与当前 `game_state`，从 Entry 派生 Horse，验证实际周不在未来，再写当前结果与 Audit；Correct/VOID 只改赛后事实并保留历史。 | 同一 Entry 的相同 Record 重试返回原结果；不同事实拒绝并要求 Correct；每 Entry 与每 Horse/Actual Race 至多一个当前结果；VOID 重试不重复 Audit，随后可重新 Record。 |
| v0.4-D 奖金应收（未来） | GM 确认金额、赛果与基础应收创建要原子化并防止重复；后续赛果更正通过受控调整，不重建基础应收。 | 每个来源赛果的基础应收应有唯一来源约束或幂等键；每项调整亦需唯一来源/幂等键。 |
| 退役与奖金释放 | 锁定 Horse/退役案，找到其全部有效 `PENDING` 应收和调整，生成对应正式流水，标记已释放，记录审计。 | 重试不得使任一基础应收或调整二次释放或写入重复流水。 |
| 财务修正 | 追加修正流水与审计，而非改历史余额。 | 修正来源或幂等键应防止重复记账。 |

账户可用资金检查必须与冻结变化在同一数据库事务内完成，并对同一 Owner 的竞争操作串行化或施加等价锁定。只在应用层先查询余额再写入，无法保证报价并发时不超额冻结。

## 7. 建议的完整性约束

- `horses.horse_number` 永久唯一；Horse 不物理删除。
- `horse_factors`：同一 `horse_id`、同一类型最多两条。
- `user_profiles` 角色只允许 `PLAYER` 或 `GM`；`PLAYER` 必须绑定一个 Owner，`GM` 不绑定 Owner；一个 Owner 最多一个 PLAYER 绑定。
- 一匹 Horse 的 `foal_trade_lots` 全局至多一条，且其 Session 年份等于 `birth_year`；一匹 Horse 的 `public_auction_lots` 全局至多一条，且只允许庭先未成交的同出生年 Horse 进入。
- `foal_trade_inquiries`：同一 `session_id`、`owner_id` 只能一条。
- 当前有效秘密报价：同一 `owner_id`、`lot_id` 只能一条；锁定后不得由玩家修改。
- 每个公开拍卖事件的同时 `OPEN_WAITING`/`BIDDING` Lot 至多一个；每个 Lot 同时 `OPEN_WAITING`/`BIDDING` Round 至多一个；每个 Round 至多一个 Settlement。`public_auction_events` 只允许 `DRAFT → OPEN → CLOSED`、`CLOSED → OPEN`、以及在全部 Lot 已最终处理且无待确认 Rollback 时 `CLOSED → SETTLED`；同状态为无副作用重试，且活跃 `OPEN_WAITING`/`BIDDING` Lot 存在时不得 `OPEN → CLOSED`。Lot 的历史 Round 可因 Emergency Rollback 追加，但旧 Round 必须 `VOIDED` 且不再参与公开读取、赢家或冻结。庭先成交结算必须保存系统推荐报价；仅异常路径可选择不同有效报价，且必须保存非空原因和审计。
- `public_auction_lot_reviews`：`UNIQUE(lot_id, slot)`；`slot` 和 `stars` 均为 1–5；Lot 展示或开拍前恰好具备五个 slot。
- `public_auction_lot_reviews` 必须在 GM 打开 Lot 前存在五个 slot；`public_auction_bids.amount`、起拍价与最低加价单位必须是 `100000` 的整数倍；首口不低于起拍价，后续至少加一个单位，当前赢家不可再次报价。
- 公开拍卖 `close_at`、无报价截止与合法报价接收时间必须由数据库服务器产生/校验；Bid、`financial_transactions` 与 Audit 不可通过普通 UPDATE/DELETE 篡改。
- `public_auction_settlements` 的成交 Owner/Horse/Round/金额必须与当前赢家一致；受控 Horse guard 仅允许对应 Settlement 的 `NULL → Owner/OWNED_FOAL`，以及对应已执行 rollback 的反向回退。
- `confirmed_race_entries`：同一 Horse、同一最终 WP 年/月/周至多一笔；`request_id` 可空以支持 GM Direct Confirm，有值时必须唯一并与 PENDING Request 的 Horse/Owner 匹配；CONFIRMED Request 必须恰有一条匹配 Entry。PENDING、REJECTED、WITHDRAWN Request 不占用最终周唯一性。固定 Catalog 默认月/周不约束 Confirmed Entry 的最终时间。固定比赛使用 Catalog 引用；`MAIDEN`、`CONDITION`、`OTHER` 必须保存非空 label。
- 每条 `race_results` 必须归属一场 `actual_races` 且必填 `confirmed_race_entry_id`；其 Horse 必须等于该 Entry Horse。赛前计划与实际比赛身份/时间不要求相同。Catalog Actual Race 的 `(wp_year, wp_month, wp_week, race_catalog_id)` 至多一条；非 Catalog 不设过强自然唯一。每 Entry 与每 Horse/Actual Race 均至多一条当前 `CONFIRMED` Result；名次不唯一以允许并列。VOIDED 历史永久保留且不经公开投影显示。
- 同一来源赛果不得重复生成基础 `prize_receivable`；奖金调整必须引用其基础应收；已释放基础应收或调整均须有且只有一次对应正式流水或修正流水。
- Horse 已拥有 Owner 后，不允许常规所有权转让；成交结算与退役奖金释放必须使用受控操作。

## Open Questions

以下问题仍会改变约束、RLS、显示或事务细节，需在相应 migration/功能实施前由产品方确认：

1. 公开资金汇总的确切字段（在不得反推秘密报价/冻结的前提下），以及逐笔 `financial_transactions` 是否公开、向谁公开。
2. `initial_funds` 的设定与变更流程，以及经 GM 审计的纠错是否允许使账户资金为负；常规 PLAYER 操作已确定不得导致负数。
3. “主要胜鞍”、特殊跑法、满 3 岁、寿命过低与 G1 九胜触发后的精确判定和系统动作。
4. 生命周期允许的完整跳转集合，特别是 `RETIRED → BREEDING` 是否必经，以及除公开拍卖流拍外哪些情况可以进入 `DISCARDED`。
