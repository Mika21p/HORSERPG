# HorseRPG

在线赛马跑团管理网站。Core Schema 已部署；当前阶段提供 Email/Password 登录、GM Core 管理和公开 Owner/Horse 浏览。

## 技术栈

- Next.js 16（App Router）
- TypeScript
- Tailwind CSS 4
- ESLint
- Supabase PostgreSQL 与 Supabase Auth（Email/Password）
- GitHub 版本管理
- Netlify（计划中的部署平台）

## 本地启动

1. 安装依赖：`npm install`
2. 复制环境变量模板：`Copy-Item .env.example .env.local`
3. 在 `.env.local` 填写 Supabase 项目的 URL 与 publishable key。GM 创建 PLAYER 和 Bootstrap 工具还需要 server-only 的 `SUPABASE_SERVICE_ROLE_KEY`。
4. 启动开发服务器：`npm run dev`
5. 浏览器访问终端显示的本地地址，通常为 `http://localhost:3000`。

## 可用检查

- `npm run lint`：运行代码风格与静态检查
- `npm run build`：创建生产构建

## 使用文档

- [PLAYER 与 GM 简要使用指南](docs/USER_GUIDE.md)

## 身份与权限

- 登录页：`/login`。第一版没有公开注册入口。
- 未登录用户会被重定向到登录页；普通业务页面使用 authenticated Supabase session 读取数据。
- `/admin` 及其子路由同时由 `src/proxy.ts`、GM Server Layout 和每个写入 Server Action 进行服务器端角色检查。
- PLAYER 无法访问 GM 页面，也不能通过浏览器获得 service-role 权限。
- 生产 Supabase Auth 还必须在 Dashboard 的 Email provider 中关闭 **Enable sign ups**；本地 `supabase/config.toml` 已关闭该开关。仅移除网站注册链接并不能阻止直接调用 Auth API 的注册请求。

## 首位 GM Bootstrap（仅人工执行）

正常网站没有“创建 GM”入口。首次初始化管理员时，由开发者在已配置服务器环境变量的终端中手动执行：

```powershell
$env:BOOTSTRAP_GM_EMAIL = "gm@example.com"
$env:BOOTSTRAP_GM_PASSWORD = "use-a-strong-password"
npm run bootstrap:gm
```

该工具只读取环境变量，不会输出密钥或密码；它会创建指定 Auth 用户，或将已有用户的 Profile 提升为 GM。若目标已经是 GM，工具会安全退出。**不要自动在 Production 执行；先确认目标账号与环境。**

## 目录约定

```text
src/
├── app/                 # App Router 路由与全局样式
├── components/ui/       # 可复用展示组件
├── features/            # 按业务领域组织的功能模块
├── lib/supabase/        # Supabase browser client 与 server client
└── types/               # 共享 TypeScript 类型
```

`.env.local`、Supabase CLI 凭据和 `supabase/.temp/` 都被 Git 忽略。`.env.example` 只包含变量名称，绝不能填写真实密钥。

## 后续建议

后续业务模块必须使用新 migration；不要修改已经部署的 Core Migration。数据库迁移应先在本地或预览环境验证，避免直接修改生产环境。

## Migration 版本号

HorseRPG 早期 Core Migration 使用本地时间版本号，而 Supabase CLI 的 `migration new` 使用 UTC。每次新增 Migration 前必须确认版本号严格大于当前最新版本；若 CLI 生成的版本号发生倒序，应在**尚未部署前**安全重命名为一个更大的唯一版本号，再进行本地验证和部署。
