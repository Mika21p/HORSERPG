# HorseRPG Initial Playtest Checklist

这份清单用于实际跑团时，由 GM 按需要逐项确认。无需在一次 Session 内完成全部项目；遇到问题请记录到 [PLAYTEST_NOTES.md](PLAYTEST_NOTES.md)，不要当场扩展功能。

## 开始前

- [ ] 本次试玩的日期、GM、PLAYER、WP 年度已记录。
- [ ] 重要操作前已按 [BACKUP_RECOVERY.md](BACKUP_RECOVERY.md) 的原则完成备份确认。
- [ ] GM 与 PLAYER 分别可以正常登录。
- [ ] 每位 PLAYER 的 Owner 绑定正确。
- [ ] PLAYER 无法进入 GM 管理页面；GM 可以进入管理页面。

## Horse

- [ ] Horse 列表与详情页正常打开。
- [ ] Owner 归属正确。
- [ ] 马名、片假名、译名显示正确。
- [ ] 骑手、调教师与血统信息显示正确。
- [ ] 当前 life stage 符合实际状态。

## Foal 与 Pedigree

- [ ] GM 可以创建 Foal。
- [ ] INTERNAL parent 选择正确。
- [ ] REFERENCE parent 选择正确。
- [ ] MANUAL parent 填写正确。
- [ ] 新 Foal 不会自动获得 Owner。
- [ ] 新 Foal 不会自动进入拍卖。
- [ ] Pedigree 快照显示正确。

## 庭先取引

- [ ] PLAYER 可以提交询问。
- [ ] PLAYER 只能看到自己的私密报价与询问内容。
- [ ] 修改报价与撤回报价正常。
- [ ] GM 结算正常。
- [ ] 资金冻结与可用资金变化正确。
- [ ] 成交后 Horse Owner 正确。
- [ ] 未成交 Lot 保持正确状态。

## 公开拍卖

- [ ] Event 与 Lot 准备正常。
- [ ] Reveal 与 Open 操作正常。
- [ ] PLAYER 报价正常。
- [ ] 倒计时显示合理。
- [ ] 多个客户端的状态同步正常。
- [ ] Settlement 后 Owner 与资金变化正确。
- [ ] Emergency Rollback 仅在必要时按受控流程使用。

## Race Entry

- [ ] PLAYER 可以提交报名。
- [ ] GM 可以确认、拒绝与调整最终赛程。
- [ ] GM Direct Entry 正常。
- [ ] 同一 Horse 同一 WP 周的冲突被正确处理。
- [ ] Injury 覆盖周会阻止确认；非伤病周可以正常报名。
- [ ] Stamina 为“未启用”不会阻止报名。
- [ ] Stamina 为 `0 / 100` 不会被数据库自动阻止报名。

## Race Result

- [ ] Actual Race 创建正常。
- [ ] 批量录入赛果正常。
- [ ] 名次与 Prize 金额正确。
- [ ] Result Correction 正常。
- [ ] Result Void 正常。
- [ ] Horse 战绩显示正确。

## Prize 与 Funds

- [ ] Prize Receivable 正常生成。
- [ ] Pending Prize 显示正确。
- [ ] Owner 的账户资金、可用资金与冻结资金区分正确。
- [ ] Retirement 时 Prize Release 正常。
- [ ] 已释放 Prize 的 Correction 与 Void reversal 正常。

## Stamina 与 Health

- [ ] 未启用体力管理显示为“未启用”，而不是 `0 / 100`。
- [ ] Stamina `0` 显示为 `0 / 100`。
- [ ] Enable、Adjust、Disable 与 Re-enable 正常。
- [ ] POST_RACE Managed 正常。
- [ ] POST_RACE `NULL → NULL` 正常。
- [ ] POST_RACE Injury 正常。
- [ ] Health 历史、Latest Correction 与 Latest Void 正常。

## Injury

- [ ] Manual Injury 正常。
- [ ] ACTIVE Injury 与 Injury History 显示正确。
- [ ] Recover 与 Void 正常。
- [ ] PLAYER 看不到内部 reason 或 actor。
- [ ] Race Entry 的伤病约束正常。

## Retirement

- [ ] Owner request、Forced retirement 与 Reject 正常。
- [ ] Confirm 正常。
- [ ] Pending Prize Release 正常。
- [ ] Horse 进入 `RETIRED`，且 Retirement History 正确。

## Breeding Candidate

- [ ] RETIRED MALE 可以成为 STALLION。
- [ ] RETIRED FEMALE 可以成为 BROODMARE。
- [ ] GELDING 不能加入。
- [ ] Activate / Deactivate 正常。
- [ ] Internal parent 选择正常。

## 移动端抽查

实际跑团期间，至少偶尔以约 390px 宽度查看以下页面：

- [ ] Horse Detail
- [ ] Race 页面
- [ ] Auction
- [ ] GM Result 页面
- [ ] Health 操作
- [ ] Retirement
- [ ] Breeding

记录是否出现横向溢出、按钮难点、必须反复缩放或信息过密。

## Feature Freeze Rules

试玩阶段默认只处理：

- **P0**：数据损坏、主流程无法继续、严重安全或财务错误。
- **P1**：核心流程明显受阻，GM 必须绕路或手工补数据。

P2 根据出现频率与实际影响决定；P3 不进入当前开发。任何新功能建议先记录，不立即开发。

## 问题记录方式

遇到问题时，先在 [PLAYTEST_NOTES.md](PLAYTEST_NOTES.md) 记录：

1. 当时页面与操作步骤。
2. Horse、Race、Owner 等业务上下文。
3. 预期结果与实际结果。
4. 是否可以继续流程、是否需要人工绕过、是否可重复。
5. Priority，以及可用的截图。
