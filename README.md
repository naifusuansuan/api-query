# API Query 接口查询 Skill

多平台开放接口查询技能 —— 让 AI 助手一行命令调用各大平台开放 API。

## 功能

- **14 个预设 API**：天气（高德）、汇率、GitHub、IP 归属地、天气（OpenWeather）、新闻、笑话等
- **密钥安全管理**：环境变量引用（`{env:VAR}`）、600 权限密钥文件、日志自动脱敏
- **参数优先级**：命令行 > 环境变量 > config.json 预设
- **统一错误处理**：401/403 鉴权、429 限流、DNS/超时、JSON 解析失败
- **移动端适配**：安卓 15 / WorkBuddy 完美兼容（无 ANSI 色彩、路径自适应）

## 安装

### 通用（skills CLI / skills.sh 生态）

```bash
npx skills add naifusuansuan/api-query
```

### ClawHub

```bash
npx clawhub install api-query --workdir ~ --dir .workbuddy/skills
```

### 手动安装

```bash
git clone https://github.com/naifusuansuan/api-query.git ~/.workbuddy/skills/api-query
# 或 CodeBuddy:
git clone https://github.com/naifusuansuan/api-query.git ~/.codebuddy/skills/api-query
```

## 快速使用

```bash
# 免费天气（高德，需要 key）
./scripts/set_key.sh set AMAP_API_KEY 你的高德key
./scripts/query_api.sh --preset amap_weather

# 汇率（免key）
./scripts/query_api.sh --preset exchangerate --param base=USD

# GitHub 仓库信息（免key）
./scripts/query_api.sh --preset github_repo --param owner=vercel-labs --param repo=skills
```

## 密钥安全规则

1. `config.json` 只存接口元信息，密钥一律走 `{env:VAR_NAME}` 环境变量引用
2. 密钥文件 `~/.api_keys/.env` 权限 600
3. 日志和 debug 输出自动脱敏（只显示前 4 位）
4. `.gitignore` 防止密钥被误提交

## License

MIT
