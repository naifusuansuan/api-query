# API Query 接口查询 Skill

多平台开放接口查询技能 —— 让 AI 助手一行命令调用各大平台开放 API。

## 功能

- **14 个预设 API**：天气（高德/Open-Meteo）、汇率、GitHub、IP 归属地、新闻、笑话等
- **快递物流查询**（v1.3.0+）：基于快递100，支持 1200+ 快递公司，自动识别单号，MD5 签名自动计算
- **密钥安全管理**：环境变量引用（`{env:VAR}`）、600 权限密钥文件、日志自动脱敏
- **参数优先级**：命令行 > 环境变量 > config.json 预设
- **统一错误处理**：401/403 鉴权、429 限流、DNS/超时、JSON 解析失败
- **全平台适配**：

| 平台 | 调用方式 |
|------|---------|
| Android（Termux/WorkBuddy） | `./query_api.sh --preset weather` |
| Linux | `./query_api.sh --preset weather` |
| macOS（bash 3.2 兼容） | `./query_api.sh --preset weather` |
| Windows WSL / Git Bash | `./query_api.sh --preset weather` |
| **Windows 原生**（PowerShell/CMD） | `python query_api.py --preset weather` |
| **iPhone**（a-Shell） | `python3 query_api.py --preset weather` |

> bash 版依赖 `bash 3.2+` + `curl` + `python3`；Python 版仅依赖 Python 3.6+（纯标准库零依赖）。

## 安装

### 通用（skills CLI / skills.sh 生态，支持 70+ AI agent）

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
# CodeBuddy:
git clone https://github.com/naifusuansuan/api-query.git ~/.codebuddy/skills/api-query
# Windows（PowerShell）:
git clone https://github.com/naifusuansuan/api-query.git $HOME\.agents\skills\api-query
```

## 快速使用

```bash
# 免费天气（Open-Meteo，无需 key）
./query_api.sh --preset weather

# 高德天气（需要 key，先设置）
./set_key.sh set AMAP_API_KEY 你的高德key     # Windows: python set_key.py set AMAP_API_KEY ...
./query_api.sh --preset amap_weather

# 汇率（免key）
./query_api.sh --preset exchangerate

# GitHub 仓库信息（免key）
./query_api.sh --preset github_repo --param owner=vercel-labs --param repo=skills

# 临时查询任意接口
./query_api.sh --url "https://httpbin.org/get" --query "foo=bar"

# 快递查询（v1.3.0+，需先注册 https://api.kuaidi100.com/register 免费拿密钥）
./set_key.sh set KUAIDI100_CUSTOMER 你的Customer
./set_key.sh set KUAIDI100_KEY      你的授权Key
./express_query.sh YT25569986666541              # 自动识别公司
./express_query.sh SF1356245698123 sf 1234       # 顺丰需手机后4位
```

> Windows 原生用户：将 `query_api.sh` 替换为 `python query_api.py`、`set_key.sh` 替换为 `python set_key.py`，参数完全一致。

## 密钥安全规则

1. `config.json` 只存接口元信息，密钥一律走 `{env:VAR_NAME}` 环境变量引用
2. 密钥文件 `~/.api_keys/.env` 权限 600（Windows 上由 NTFS ACL 管理）
3. 日志和 debug 输出自动脱敏（只显示前 4 位）
4. `.gitignore` 防止密钥被误提交

## License

MIT
