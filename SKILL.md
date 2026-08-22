---
name: api-query
description: "通用接口查询工具 - 调用各类平台开放接口发送 HTTP 请求并返回数据。支持 GET/POST/PUT/DELETE/PATCH 方法，支持 API Key 鉴权，支持预设配置和命令行动态传参。内置快递查询（快递100，轨迹+单号识别）和彩云天气（实况/小时/天预报+预警）专用脚本。全平台适配：Android 15/Termux/WorkBuddy、Linux、macOS、Windows（原生+WSL+Git Bash）、iPhone（a-Shell）。关键词：接口查询、API查询、调用接口、发送请求、HTTP请求、接口测试、快递查询、查快递、物流轨迹、天气查询、彩云天气"
version: "1.4.0"
author: "CodeBuddy AI"
created: "2026-08-21"
updated: "2026-08-22"
---

# 接口查询 Skill

## Overview

通用 HTTP 接口查询工具。通过预设配置或命令行参数发送 HTTP 请求，返回接口响应数据。支持 API Key 鉴权管理。

**核心能力：**
- 调用任意 HTTP/HTTPS 接口（GET/POST/PUT/DELETE/PATCH）
- 预设常用接口配置，一键调用
- 命令行临时传参查询任意接口
- API Key 安全管理（存储/查看/删除）
- 统一的错误码处理和响应格式化
- **快递查询**（v1.3.0）：快递100 轨迹查询、智能单号识别、免费网页通道降级
- **天气报告**（v1.4.0）：彩云天气中文格式化报告（实况/逐小时降水/逐天/预警）
- **全平台适配**（Android / Linux / macOS / Windows / iPhone）

## 跨平台支持矩阵（v1.3.0+，v1.4.0 增补）

提供**两套功能等价的脚本**，按平台选择：

| 平台 | 查询脚本 | 密钥管理 | 说明 |
|------|---------|---------|------|
| **Android**（Termux/WorkBuddy，安卓 15） | `query_api.sh` | `set_key.sh` | bash 版，toybox 兼容 |
| **Linux**（服务器/桌面） | `query_api.sh` | `set_key.sh` | bash 版，开箱即用 |
| **macOS**（Intel/Apple Silicon） | `query_api.sh` | `set_key.sh` | bash 3.2 兼容（无需装新版 bash） |
| **Windows - WSL / Git Bash** | `query_api.sh` | `set_key.sh` | bash 版，WSL/Git for Windows 自带环境 |
| **Windows 原生**（PowerShell/CMD） | `python query_api.py` | `python set_key.py` | Python 3.6+，无需 bash |
| **iPhone**（a-Shell 等） | `python3 query_api.py` | `python3 set_key.py` | App Store 装 a-Shell 即可用 |

**依赖要求：**
- bash 版：`bash 3.2+` + `curl` + `python3`（Android Termux: `pkg install curl python`）
- Python 版：仅 `Python 3.6+`（标准库，零第三方依赖）——Windows/iPhone 推荐此版

**快速调用示例：**
```bash
# Linux / macOS / Android / WSL / Git Bash
<skill-directory>/scripts/query_api.sh --preset weather

# Windows 原生（PowerShell 或 CMD）
python <skill-directory>\scripts\query_api.py --preset weather

# iPhone（a-Shell）
python3 ~/skills/api-query/scripts/query_api.py --preset weather
```

## 跨平台适配细节

| 适配项 | 说明 |
|--------|------|
| bash 3.2 兼容（macOS） | 不使用关联数组等 bash 4+ 特性，macOS 自带 bash 直接跑 |
| ANSI 颜色自动禁用 | 非交互环境（管道/App 子进程）自动禁色，避免乱码 |
| HOME 兜底 | 安卓执行上下文 HOME 为空时自动回退 Termux 标准路径 |
| stat 跨平台 | GNU stat → BSD/toybox stat → ls+awk 三级降级 |
| sed -i 跨平台 | `sed -i''` 优先，GNU/BusyBox/BSD sed 全兼容 |
| Python 版零依赖 | 纯标准库（urllib/ssl/argparse），Windows/iPhone 免安装 |
| Windows 权限处理 | POSIX 600 权限在 Windows 上自动跳过（NTFS ACL 自行管理） |
| 依赖检测 | 缺 curl/python3 时给出各平台安装指引，不自动安装 |
| 非交互保护 | purge 等交互操作在非交互环境自动拒绝，防止误删 |

## When to Use

- 用户需要调用某个平台的开放 API 获取数据
- 用户需要发送 HTTP 请求测试接口
- 用户需要查询天气、汇率、IP 信息等公开 API
- 用户提到"调用接口""查 API""发请求""接口测试"等关键词
- 用户需要配置 API Key 并用其访问需要鉴权的接口
- 用户查快递：提到"快递单号""物流轨迹""到哪了""顺丰/圆通/中通"等 → `express_query.sh`
- 用户查天气：提到"彩云""天气预报""几点下雨""降水"等 → `caiyun_weather.sh` 或 `caiyun_*` 预设

## When NOT to Use

- 用户只需要用 `curl` 发一个简单请求（可直接用 Bash 工具的 curl）
- 涉及已有专用 connector 的平台（GitHub 用 github-connector，Figma 用 figma-connector）
- 用户需要的是数据库查询而非 HTTP API 查询

## 路径说明

本 SKILL.md 中 `<skill-directory>` 指 skill 自身安装目录，取决于运行环境：

| 环境 | 路径 |
|------|------|
| CodeBuddy（云端沙箱） | `~/.codebuddy/skills/api-query` |
| WorkBuddy（移动端） | `~/.workbuddy/skills/api-query` |
| 通用 skills CLI 安装 | `~/.agents/skills/api-query` |
| 手动安装（任意平台） | 自行 clone/复制的目录 |

脚本内部自动定位自身目录（bash 用 `BASH_SOURCE`，Python 用 `__file__`），无需手动指定。

所有脚本路径基于此目录：
- 核心查询脚本（bash）：`<skill-directory>/scripts/query_api.sh`
- 核心查询脚本（Python）：`<skill-directory>/scripts/query_api.py`
- 快递查询（bash）：`<skill-directory>/scripts/express_query.sh`
- 快递查询（Python）：`<skill-directory>/scripts/express_query.py`
- 彩云天气报告（bash）：`<skill-directory>/scripts/caiyun_weather.sh`
- 密钥管理（bash）：`<skill-directory>/scripts/set_key.sh`
- 密钥管理（Python）：`<skill-directory>/scripts/set_key.py`
- 预设配置文件：`<skill-directory>/scripts/config.json`
- 预设速查表：`<skill-directory>/references/preset_apis.md`
- 密钥存储位置：`~/.api_keys/.env`（POSIX 权限 600，禁止提交）

## 安全警告

> **⚠️ 密钥安全是第一优先级**

1. **`config.json` 只存接口元信息**，严禁填写真实密钥。需要鉴权的接口，在 headers 或 params 的值中用 `{env:VAR_NAME}` 引用环境变量。
2. **密钥文件 `~/.api_keys/.env`** 由 `set_key.sh` / `set_key.py` 创建，权限强制为 `600`（仅当前用户可读写，Windows 上交由 NTFS ACL），禁止其他用户读取。
3. **`.gitignore`** 已配置忽略 `.api_keys/.env` 和所有 `.env` 文件，防止密钥被提交到版本库。
4. **日志脱敏**：脚本输出日志时自动脱敏，绝不打印完整 API-Key，只显示前4位 + `****`。

## 脚本使用

> 💡 **Windows 原生 / iPhone 用户**：把下文所有命令中的 `query_api.sh` 换成 `python query_api.py`、`set_key.sh` 换成 `python set_key.py`，参数完全一致。

### 1. 密钥管理（set_key.sh / set_key.py）

```bash
# 设置/更新 API Key
<skill-directory>/scripts/set_key.sh set <KEY_NAME> <KEY_VALUE>
# 示例
<skill-directory>/scripts/set_key.sh set GITHUB_API_KEY ghp_xxxxxxxxxxxx
<skill-directory>/scripts/set_key.sh set OPENWEATHER_KEY abc123def456

# 列出所有密钥（脱敏显示值）
<skill-directory>/scripts/set_key.sh list

# 查看单个密钥（脱敏显示）
<skill-directory>/scripts/set_key.sh get GITHUB_API_KEY

# 删除密钥
<skill-directory>/scripts/set_key.sh remove GITHUB_API_KEY

# 输出 export 语句（供 source 使用）
<skill-directory>/scripts/set_key.sh export GITHUB_API_KEY

# 显示密钥文件路径
<skill-directory>/scripts/set_key.sh path

# 清空所有密钥（需确认）
<skill-directory>/scripts/set_key.sh purge
```

**KEY_NAME 格式规则：** 大写字母开头，仅含大写字母/数字/下划线（如 `GITHUB_API_KEY`、`OPENWEATHER_KEY`）。

### 2. 接口查询（query_api.sh / query_api.py）

#### 命令行参数

| 参数 | 简写 | 说明 |
|------|------|------|
| `--preset NAME` | `-p` | 使用 config.json 中的预设配置 |
| `--url URL` | `-u` | 请求 URL（命令行优先） |
| `--method METHOD` | `-m` | HTTP 方法，默认 GET |
| `--header "K: V"` | `-H` | 附加请求头（可多次指定） |
| `--body DATA` | `-d` | 请求体（POST/PUT 用） |
| `--query "k=v"` | `-q` | 查询参数（可多次指定） |
| `--raw` | `-r` | 原始输出（不格式化 JSON） |
| `--debug` | | 启用调试日志 |
| `--list` | `-l` | 列出所有可用预设 |
| `--help` | `-h` | 显示帮助 |

#### 优先级规则

> **命令行参数 > 环境变量 > config.json 预设配置**

- 命令行 `--header "X-API-Key: xxx"` 优先级最高，可临时覆盖预设和环境变量中的同名 header
- `--preset xxx` 加载预设作为基础值，同时允许命令行追加/覆盖 url、method、header、body、query 参数
- 环境变量（包括 `~/.api_keys/.env` 中设置的）用于替换 config.json 中的 `{env:VAR_NAME}` 引用

#### 调用方式

```bash
# 方式一：按预设名调用（最简单）
<skill-directory>/scripts/query_api.sh --preset weather

# 方式二：预设 + 命令行覆盖
<skill-directory>/scripts/query_api.sh --preset github \
  --header "Authorization: Bearer ghp_newkey"

<skill-directory>/scripts/query_api.sh --preset github_repo \
  --url "https://api.github.com/repos/microsoft/vscode"

# 方式三：完全命令行模式（临时查询任意接口）
<skill-directory>/scripts/query_api.sh \
  --url "https://api.example.com/data" \
  --method GET \
  --query "q=test&page=1"

# 方式四：POST 请求带 body
<skill-directory>/scripts/query_api.sh \
  --url "https://api.example.com/create" \
  --method POST \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer xxx" \
  --body '{"name":"test","type":"demo"}'

# 列出所有预设
<skill-directory>/scripts/query_api.sh --list

# 原始输出（不格式化 JSON）
<skill-directory>/scripts/query_api.sh --preset weather --raw
```

### 3. 快递查询（express_query.sh / express_query.py，v1.3.0 新增）

依赖密钥（注册 https://api.kuaidi100.com/register 免费获取）：
- `KUAIDI100_KEY`（授权 Key）
- `KUAIDI100_CUSTOMER`（企业授权 Customer）

```bash
# 一次性配置密钥
<skill-directory>/scripts/set_key.sh set KUAIDI100_KEY xxxxxx
<skill-directory>/scripts/set_key.sh set KUAIDI100_CUSTOMER ABCDEF123

# 查询轨迹
<skill-directory>/scripts/express_query.sh <单号>                       # 自动识别快递公司
<skill-directory>/scripts/express_query.sh <单号> <公司编码>             # 指定公司，如 sf/yto/zto
<skill-directory>/scripts/express_query.sh <单号> <公司编码> <手机后4位>  # 顺丰/中通需手机号校验
<skill-directory>/scripts/express_query.sh --com                        # 查看快递公司编码表
```

**特性：** 官方 API 查询（POST+MD5 动态签名）→ 401 时自动降级快递100 网页免费通道（无需密钥，含顺丰）；顺丰/中通首次查询需收/寄件人手机后4位；Windows 用 `python express_query.py`，参数一致。

**轻量替代：** 只需识别单号属于哪家快递时，可用通用预设 `query_api.sh --preset kuaidi100_autonumber --query "num=单号"`（仅需 KUAIDI100_KEY）。

### 4. 彩云天气报告（caiyun_weather.sh，v1.4.0 新增）

依赖密钥（注册 https://platform.caiyunapp.com 免费获取，免费版 10000 次，QPS=1）：
- `CAIYUN_TOKEN`

```bash
# 一次性配置密钥
<skill-directory>/scripts/set_key.sh set CAIYUN_TOKEN xxxxxxxxxxxxxxxxxx

# 中文格式化报告
<skill-directory>/scripts/caiyun_weather.sh                    # 实况 + 未来48h/3天摘要（默认上海嘉定龙湖郦城）
<skill-directory>/scripts/caiyun_weather.sh hourly             # 未来48小时逐小时（降水时段重点）
<skill-directory>/scripts/caiyun_weather.sh daily              # 未来3天 + 紫外线/舒适度/穿衣指数
<skill-directory>/scripts/caiyun_weather.sh alert              # 气象预警 + 走势要点
<skill-directory>/scripts/caiyun_weather.sh all                # 一次全出（约6秒，受QPS=1限制）
<skill-directory>/scripts/caiyun_weather.sh realtime 116.4,39.9  # 指定坐标（经度,纬度）
```

**JSON 原始数据：** 用通用预设 `caiyun_realtime` / `caiyun_hourly` / `caiyun_daily`，URL 中坐标可覆盖。

**彩云 API 要点：** 坐标**经度在前**（lng,lat）；免费版 QPS=1（连续请求需间隔 >1s）；分钟级降水未开放；预警走 `weather?alert=true` 综合接口（独立 /alert 端点免费版 404）；降水概率是 0-100 整数。

## 示例

### 示例 1：查询天气（免费接口，无需 Key）

```bash
<skill-directory>/scripts/query_api.sh --preset weather
```
返回北京当前温度和风速数据。

### 示例 2：查询汇率（免费接口）

```bash
<skill-directory>/scripts/query_api.sh --preset exchangerate
```
返回美元兑人民币/欧元/日元/英镑的汇率。

### 示例 3：使用 GitHub API（需先设置 Key）

```bash
# 第一步：设置 GitHub API Key
<skill-directory>/scripts/set_key.sh set GITHUB_API_KEY ghp_xxxxxxxxxxxx

# 第二步：查询当前用户信息
<skill-directory>/scripts/query_api.sh --preset github --url "https://api.github.com/user"

# 第三步：查询指定仓库
<skill-directory>/scripts/query_api.sh --preset github_repo \
  --url "https://api.github.com/repos/microsoft/vscode"
```

### 示例 4：使用 DeepSeek API（需先设置 Key）

```bash
# 设置 Key
<skill-directory>/scripts/set_key.sh set DEEPSEEK_API_KEY sk-xxxxxxxxxxxx

# 查询余额
<skill-directory>/scripts/query_api.sh --preset deepseek_balance

# 对话（覆盖 body 中的默认消息）
<skill-directory>/scripts/query_api.sh --preset deepseek_chat \
  --body '{"model":"deepseek-chat","messages":[{"role":"user","content":"你好，请介绍一下自己"}]}'
```

### 示例 5：临时查询任意接口

```bash
# GET 请求带查询参数
<skill-directory>/scripts/query_api.sh \
  --url "https://httpbin.org/get" \
  --query "foo=bar" --query "baz=qux"

# POST 请求带 JSON body
<skill-directory>/scripts/query_api.sh \
  --url "https://httpbin.org/post" \
  --method POST \
  --header "Content-Type: application/json" \
  --body '{"message":"hello"}'
```

### 示例 6：新增预设接口

编辑 `<skill-directory>/scripts/config.json`，添加新条目：

```json
"my_api": {
  "desc": "我的自定义接口",
  "url": "https://api.myservice.com/v1/data",
  "method": "GET",
  "headers": {
    "X-API-Key": "{env:MY_API_KEY}"
  },
  "params": {
    "limit": "20"
  }
}
```

然后设置对应的 Key：
```bash
<skill-directory>/scripts/set_key.sh set MY_API_KEY your_secret_key
```

调用：
```bash
<skill-directory>/scripts/query_api.sh --preset my_api
```

## 错误处理

脚本统一处理常见错误，给出明确提示：

| 错误类型 | 状态码/情况 | 处理逻辑 |
|---------|-----------|---------|
| 鉴权失败 | HTTP 401 | 提示检查 API-Key，给出 set_key.sh 设置指引 |
| 权限不足 | HTTP 403 | 提示 Key 无权访问或已过期 |
| 接口不存在 | HTTP 404 | 提示检查 URL 是否正确 |
| 触发限流 | HTTP 429 | 提示频率限制，自动延迟重试（最多 2 次） |
| 服务器错误 | HTTP 500/502/503 | 自动延迟重试（最多 2 次），重试用尽后报错 |
| 请求参数错误 | HTTP 400 | 显示错误信息 |
| DNS 解析失败 | curl exit 6 | 提示无法解析主机名 |
| 连接失败 | curl exit 7 | 提示检查网络或端口 |
| 请求超时 | curl exit 28 | 提示超过超时限制（默认 30s） |
| SSL 错误 | curl exit 35/60 | 提示证书问题 |
| JSON 解析失败 | — | 原样返回原始响应文本（不丢弃数据） |

**重试策略：** 对 429 和 5xx 错误，自动延迟 2 秒后重试，最多重试 2 次。

## 新增预设接口指南

如需新增接口配置到 `config.json`：

1. **确定接口信息**：URL、HTTP 方法、需要的 headers/params
2. **判断是否需要鉴权**：
   - 不需要：直接填 headers/params 的值
   - 需要：用 `{env:VAR_NAME}` 引用环境变量，绝不填明文密钥
3. **编辑 `config.json`**：添加新条目，包含 `desc`、`url`、`method`，按需添加 `headers`、`params`、`body`
4. **设置密钥**（如需）：`./set_key.sh set VAR_NAME <value>`
5. **测试调用**：`./query_api.sh --preset <name>`

## 注意事项

- **密钥安全**：`config.json` 永远不存放明文密钥，全部走 `{env:VAR_NAME}` 环境变量引用
- **密钥文件权限**：`~/.api_keys/.env` 自动设为 `600`，禁止其他用户读取
- **日志脱敏**：所有含 `authorization`/`key`/`token`/`secret` 的 header 在日志中只显示前4位 + `****`
- **优先级顺序**：命令行参数 > 环境变量 > config.json 预设（命令行可覆盖预设中同名字段）
- **JSON 格式化**：响应默认尝试用 `python3 -m json.tool` 格式化，解析失败时原样返回原始文本
- **超时设置**：默认连接超时 30s，总超时 60s
- **依赖**：需要 `curl` 和 `python3`（均预装）
