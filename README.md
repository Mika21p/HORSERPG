# HorseRPG

在线赛马跑团管理网站的基础工程。本阶段只提供开发框架与 Supabase 连接准备，尚未创建远程数据库表，也未实现认证、比赛或拍卖功能。

## 技术栈

- Next.js 16（App Router）
- TypeScript
- Tailwind CSS 4
- ESLint
- Supabase PostgreSQL 与 Supabase Auth（依赖已就绪，暂未接入功能）
- GitHub 版本管理
- Netlify（计划中的部署平台）

## 本地启动

1. 安装依赖：`npm install`
2. 复制环境变量模板：`Copy-Item .env.example .env.local`
3. 在 `.env.local` 填写 Supabase 项目的 URL 与 publishable key。不要填写 `service_role` 密钥。
4. 启动开发服务器：`npm run dev`
5. 浏览器访问终端显示的本地地址，通常为 `http://localhost:3000`。

## 可用检查

- `npm run lint`：运行代码风格与静态检查
- `npm run build`：创建生产构建

## Supabase 连接测试

填写 `.env.local` 后，启动本地服务并访问 `/supabase-test`。该页面通过 Server Component 使用 Supabase server client 发送一次只读探测请求；它不会创建表或修改数据。

## 目录约定

```text
src/
├── app/                 # App Router 路由与全局样式
├── components/ui/       # 可复用展示组件
├── features/            # 按业务领域组织的功能模块
├── lib/supabase/        # Supabase browser client 与 server client
└── types/               # 共享 TypeScript 类型
```

`.env.local` 已被 Git 忽略；请只将变量名称提交到 `.env.example`，不要提交任何真实密钥。

## 后续建议

在确认业务规则后，先设计 Supabase 数据模型与 Row Level Security 策略，再实现认证和角色权限。数据库迁移应先在本地或预览环境验证，避免直接修改生产环境。
