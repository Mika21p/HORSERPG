# HorseRPG Backup and Recovery

## 基本原则

- Production 数据库需要定期备份；Git 不能替代数据库备份。
- Migration 记录的是结构演进，不能替代实际 Owner、Horse、赛果、资金与跑团历史数据的备份。
- 正式跑团开始前建议保留一份 baseline backup。
- WP 年度结束后建议额外备份；大规模拍卖、退役或繁育批次前后可按需要增加备份。
- 重大 migration 部署前必须先确认可恢复的备份。

## 建议流程

1. 确认备份目标是 Production，而不是本地开发数据库。
2. 使用项目管理员已批准的 Supabase / PostgreSQL 备份方式创建备份。
3. 为备份记录日期、WP 年度、重要业务节点与 Production commit。
4. 将备份保存到受访问控制的位置，并确认可读取。
5. 不要把数据库密码、access token、service-role key 或带凭据的连接字符串写进 Git、Markdown 或截图。

如需命令行工具，请只在本机安全环境中使用占位值，例如：

```text
<PROJECT_REF>
<DB_URL>
<BACKUP_DESTINATION>
```

不要把真实凭据替换进仓库文件。

## 恢复前检查

恢复是高风险操作。开始前必须：

1. 停止对目标环境的写入，并通知参与者。
2. 再次确认恢复目标环境、目标数据库与备份时间点。
3. 先创建恢复前的额外备份。
4. 明确恢复会覆盖或回退哪些业务事实。
5. 在可行时优先在非 Production 环境演练。

未确认目标环境时，不要执行 restore、reset、truncate 或 delete。

## 推荐备份节点

- Initial Playtest 开始前。
- 每个 WP 年度结束后。
- 大规模拍卖、退役或繁育批次前后（可选）。
- 重大 migration 部署前。
