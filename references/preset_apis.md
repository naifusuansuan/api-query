# 预设接口速查表

> 此文件列出 `config.json` 中已预设的接口，方便快速查阅。

## 免费接口（无需 API Key）

| 预设名 | 平台 | 说明 | URL |
|--------|------|------|-----|
| `weather` | Open-Meteo | 天气预报 | `api.open-meteo.com/v1/forecast` |
| `exchangerate` | exchangerate.host | 汇率查询 | `api.exchangerate.host/latest` |
| `ipinfo` | ipinfo.io | IP 信息 | `ipinfo.io/json` |
| `httpbin_get` | httpbin.org | GET 测试 | `httpbin.org/get` |
| `httpbin_post` | httpbin.org | POST 测试 | `httpbin.org/post` |

## 需要 API Key 的接口

| 预设名 | 平台 | 需要的环境变量 | 设置密钥命令 |
|--------|------|---------------|-------------|
| `github` | GitHub REST API | `GITHUB_API_KEY` | `set_key.sh set GITHUB_API_KEY ghp_xxx` |
| `github_repo` | GitHub 仓库查询 | `GITHUB_API_KEY` | 同上 |
| `openweather` | OpenWeatherMap | `OPENWEATHER_KEY` | `set_key.sh set OPENWEATHER_KEY xxx` |
| `news` | NewsAPI | `NEWS_API_KEY` | `set_key.sh set NEWS_API_KEY xxx` |
| `deepseek_chat` | DeepSeek 对话 | `DEEPSEEK_API_KEY` | `set_key.sh set DEEPSEEK_API_KEY sk-xxx` |
| `deepseek_balance` | DeepSeek 余额 | `DEEPSEEK_API_KEY` | 同上 |
| `amap_geocode` | 高德地理编码 | `AMAP_API_KEY` | `set_key.sh set AMAP_API_KEY xxx` |
| `tianapi_joke` | 天行 API 笑话 | `TIANAPI_KEY` | `set_key.sh set TIANAPI_KEY xxx` |

## 新增预设接口

在 `scripts/config.json` 中添加新条目即可：

```json
"your_api": {
  "desc": "接口说明",
  "url": "https://api.example.com/endpoint",
  "method": "GET",
  "headers": {
    "Authorization": "Bearer {env:YOUR_API_KEY}"
  },
  "params": {
    "param1": "value1"
  }
}
```

**安全规则：**
- ❌ 严禁在 `config.json` 中直接填写真实密钥
- ✅ 必须用 `{env:VAR_NAME}` 引用环境变量
- ✅ 密钥通过 `set_key.sh set VAR_NAME <value>` 管理
