# 预设接口速查表

> 此文件列出 `config.json` 中已预设的接口，方便快速查阅。
> v1.3.0 新增快递100 预设与 `express_query.sh`；v1.4.0 新增彩云天气 3 个预设与 `caiyun_weather.sh`。

## 免费接口（无需 API Key）

| 预设名 | 平台 | 说明 | URL |
|--------|------|------|-----|
| `weather` | Open-Meteo | 天气预报 | `api.open-meteo.com/v1/forecast` |
| `exchangerate` | open.er-api.com | 汇率查询 | `open.er-api.com/v6/latest/USD` |
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
| `amap_weather` | 高德天气 | `AMAP_API_KEY` | 同上 |
| `tianapi_joke` | 天行 API 笑话 | `TIANAPI_KEY` | `set_key.sh set TIANAPI_KEY xxx` |

## 🚚 快递100（v1.3.0 新增，v1.4.0 增补 autonumber 预设）

注册获取密钥：<https://api.kuaidi100.com/register>（免费），在「企业管理后台-我的信息-企业信息」拿到 Customer 和 Key。

| 预设名 / 脚本 | 能力 | 需要的环境变量 |
|--------------|------|---------------|
| `kuaidi100_autonumber`（预设） | 智能单号识别，返回快递公司编码 | `KUAIDI100_KEY` |
| **`express_query.sh`**（专用脚本） | 完整快递轨迹查询、自动识别快递公司、免费网页通道降级 | `KUAIDI100_KEY` + `KUAIDI100_CUSTOMER` |

```bash
# 配置密钥（一次）
./set_key.sh set KUAIDI100_KEY xxxxxx
./set_key.sh set KUAIDI100_CUSTOMER ABCDEF1234567890

# 单号识别（通用预设即可）
./query_api.sh --preset kuaidi100_autonumber --query "num=SF0210676942900"

# 完整轨迹查询（专用脚本，功能最全）
./express_query.sh SF0210676942900              # 自动识别公司
./express_query.sh SF0210676942900 sf 5546      # 指定公司 + 手机后4位（顺丰/中通需要）
./express_query.sh --com                        # 查看快递公司编码表
```

> 为什么轨迹查询不做预设？快递100 轨迹接口是 **POST + MD5 动态签名**（sign=md5(param+key+customer)），每次请求签名都变，静态预设无法表达，所以提供专用脚本 `express_query.sh`（Windows 用 `python express_query.py`，参数一致）。

## 🌤️ 彩云天气（v1.4.0 新增）

注册获取 Token：<https://platform.caiyunapp.com>（免费版 10000 次，QPS=1），在「应用管理-访问控制」查看 Token。

| 预设名 / 脚本 | 能力 | 需要的环境变量 |
|--------------|------|---------------|
| `caiyun_realtime`（预设） | 实况天气（温度/湿度/空气质量/降水） | `CAIYUN_TOKEN` |
| `caiyun_hourly`（预设） | 未来 48 小时逐小时预报 | `CAIYUN_TOKEN` |
| `caiyun_daily`（预设） | 未来 3 天逐天预报 + 生活指数 | `CAIYUN_TOKEN` |
| **`caiyun_weather.sh`**（专用脚本） | 中文格式化天气报告（实况/降水时段/预警/穿衣指数） | `CAIYUN_TOKEN` |

```bash
# 配置 Token（一次）
./set_key.sh set CAIYUN_TOKEN xxxxxxxxxxxxxxxxxx

# 通用预设调用（返回 JSON）
./query_api.sh --preset caiyun_realtime
./query_api.sh --preset caiyun_hourly --url "https://api.caiyunapp.com/v2.6/你的token/116.4,39.9/hourly?hourlysteps=48"

# 格式化报告（专用脚本，输出中文摘要）
./caiyun_weather.sh                       # 实况 + 走势摘要
./caiyun_weather.sh hourly                # 未来48小时降水时段
./caiyun_weather.sh daily                 # 3天预报 + 紫外线/穿衣
./caiyun_weather.sh alert                 # 气象预警
./caiyun_weather.sh all                   # 全部
./caiyun_weather.sh realtime 116.4,39.9   # 指定坐标（经度在前！）
```

> 彩云 API 注意事项：坐标是**经度在前**（lng,lat）；免费版 QPS=1，连续请求间隔需 >1s；分钟级降水未开放；预警走 `weather?alert=true` 综合接口（独立 /alert 端点免费版 404）。

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
