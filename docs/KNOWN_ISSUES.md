# HorseRPG Known Issues

本表只记录已确认的技术债或实际试玩中发现的问题。不要把新功能想法当作 Bug 记录。

| ID | Priority | Area | Description | Status | Found During | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| KI-001 | P2 | Database ACL | 历史 Supabase ACL 中，部分旧 `public` 业务表仍有非最小权限的 `DELETE`、`TRUNCATE`、`REFERENCES`、`TRIGGER` 或 `MAINTAIN` grant。`public.injuries` 的 `DELETE` / `TRUNCATE` 已单独修复。 | Deferred during feature freeze | v0.7-A local ACL audit | 个人/小圈子试玩暂不作为使用 blocker。若未来开放陌生用户、扩大规模或处理敏感数据，应重新执行 Global ACL Hardening。 |
| KI-002 | P2 | Injury read boundary | 应用的纯公开伤病读取已切换到 `injuries_public`，但 `public.injuries` 的 legacy `SELECT` 仍为现有兼容与 GM 管理边界保留。 | Deferred during feature freeze | v0.7-A local ACL audit | 后续若进行严格 least-privilege 收口，可单独评估；本试玩阶段不处理。 |

## Priority 定义

| Priority | 含义 |
| --- | --- |
| P0 | 数据损坏、主流程无法继续，或严重安全 / 财务错误。 |
| P1 | 核心流程明显受阻，GM 需要绕路或手工补数据。 |
| P2 | UX 明显不便，但仍可正常继续。 |
| P3 | 锦上添花、新功能想法或视觉优化。 |
