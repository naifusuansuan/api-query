#!/usr/bin/env bash
#==============================================================================
# caiyun_weather.sh — 彩云天气查询（v2.6 API，免费版套餐）
#
# 依赖密钥（通过 set_key.sh 管理，注册 https://platform.caiyunapp.com 获取）：
#   CAIYUN_TOKEN    彩云开发者 Token（应用管理-访问控制-查看）
#
# 用法：
#   ./caiyun_weather.sh                    # 龙湖郦城（上海嘉定）实况+预报摘要
#   ./caiyun_weather.sh realtime           # 实况天气（默认位置）
#   ./caiyun_weather.sh hourly             # 未来 48 小时逐小时预报（重点降水）
#   ./caiyun_weather.sh daily              # 未来 3 天逐天预报 + 生活指数
#   ./caiyun_weather.sh alert              # 气象预警
#   ./caiyun_weather.sh all                # 实况+小时+天+预警 一次全出
#   ./caiyun_weather.sh realtime 121.255,31.375   # 指定坐标（经度,纬度）
#
# 套餐权益（免费版，QPS=1，总量 10000 次）：实况 / 未来2天逐小时 /
#   未来3天逐天 / 预警 / 4项生活指数。分钟级降水未开放。
# 坐标格式：经度,纬度（注意经度在前），如上海龙湖郦城 121.255,31.375
#==============================================================================

set -euo pipefail

# ─── 环境适配 ────────────────────────────────────────────────────────────
if [[ -z "${HOME:-}" ]]; then
    export HOME="/data/data/com.termux/files/home"
fi
KEYS_FILE="${HOME}/.api_keys/.env"

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; NC=''
fi

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── 密钥读取（与 set_key.sh 格式兼容：KEY_NAME='value'）──────────────────
read_key() {
    local key_name="$1"
    [[ ! -f "$KEYS_FILE" ]] && return 1
    grep -E "^${key_name}=" "$KEYS_FILE" 2>/dev/null | \
        sed -E "s/^${key_name}=//; s/^['\"]//; s/['\"]$//" || true
    return 0
}

TOKEN="$(read_key CAIYUN_TOKEN || true)"
if [[ -z "${TOKEN}" ]]; then
    log_error "缺少 CAIYUN_TOKEN，先配置："
    echo "  ~/.agents/skills/api-query/scripts/set_key.sh set CAIYUN_TOKEN <你的token>"
    exit 1
fi

# ─── 参数解析 ────────────────────────────────────────────────────────────
CMD="${1:-summary}"
COORD="${2:-121.255,31.375}"    # 默认：上海嘉定·龙湖郦城（经度,纬度）
BASE="https://api.caiyunapp.com/v2.6/${TOKEN}/${COORD}"

# ─── JSON 解析（优先 python3，降级 sed/grep）──────────────────────────────
jget() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    for k in sys.argv[1].split('.'):
        if isinstance(d,list): d=d[int(k)]
        else: d=d.get(k) if isinstance(d,dict) else None
        if d is None: break
    if isinstance(d,float): print(round(d,1))
    else: print(d if d is not None else '')
except Exception: pass
" "$1" 2>/dev/null
    fi
}

SKYCN_MAP='{"CLEAR_DAY":"晴（白天）","CLEAR_NIGHT":"晴（夜间）","PARTLY_CLOUDY_DAY":"多云（白天）","PARTLY_CLOUDY_NIGHT":"多云（夜间）","CLOUDY":"阴","LIGHT_HAZE":"轻度雾霾","MODERATE_HAZE":"中度雾霾","HEAVY_HAZE":"重度雾霾","LIGHT_RAIN":"小雨","MODERATE_RAIN":"中雨","HEAVY_RAIN":"大雨","STORM_RAIN":"暴雨","FOG":"雾","LIGHT_SNOW":"小雪","MODERATE_SNOW":"中雪","HEAVY_SNOW":"大雪","STORM_SNOW":"暴雪","DUST":"浮尘","SAND":"沙尘","WIND":"大风"}'
sky_cn() {
    local code="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json,sys
m=${SKYCN_MAP}
print(m.get(sys.argv[1], sys.argv[1]))
" "$code" 2>/dev/null
    else
        echo "$code"
    fi
}

aqi_desc() {
    local v="$1"
    if   (( v <= 50 ));  then echo "优";
    elif (( v <= 100 )); then echo "良";
    elif (( v <= 150 )); then echo "轻度污染";
    elif (( v <= 200 )); then echo "中度污染";
    elif (( v <= 300 )); then echo "重度污染";
    else echo "严重污染"; fi
}

# ─── 拉取接口 ─────────────────────────────────────────────────────────────
fetch() {
    local url="$1"
    curl -s --max-time 20 "$url"
}

check_err() {
    local resp="$1"
    if printf '%s' "$resp" | grep -q '"status":"failed"'; then
        log_error "接口返回错误：$(printf '%s' "$resp" | head -c 300)"
        exit 1
    fi
}

# ─── 实况 ─────────────────────────────────────────────────────────────────
show_realtime() {
    local resp; resp="$(fetch "${BASE}/realtime")"
    check_err "$resp"
    local temp hum sky windspd winddir app_temp pres vis pm25 aqistr
    temp="$(printf '%s' "$resp" | jget result.realtime.temperature)"
    app_temp="$(printf '%s' "$resp" | jget result.realtime.apparent_temperature)"
    hum="$(printf '%s' "$resp" | jget result.realtime.humidity)"
    sky="$(printf '%s' "$resp" | jget result.realtime.skycon)"
    windspd="$(printf '%s' "$resp" | jget result.realtime.wind.speed)"
    winddir="$(printf '%s' "$resp" | jget result.realtime.wind.direction)"
    pres="$(printf '%s' "$resp" | jget result.realtime.pressure)"
    vis="$(printf '%s' "$resp" | jget result.realtime.visibility)"
    pm25="$(printf '%s' "$resp" | jget result.realtime.air_quality.pm25)"
    local aqi_chn; aqi_chn="$(printf '%s' "$resp" | jget result.realtime.air_quality.aqi.chn)"
    local aqi_usa; aqi_usa="$(printf '%s' "$resp" | jget result.realtime.air_quality.aqi.usa)"
    local aqi_d;   aqi_d="$(printf '%s' "$resp" | jget result.realtime.air_quality.description.chn)"
    local precip; precip="$(printf '%s' "$resp" | jget result.realtime.precipitation.local.intensity)"

    echo -e "${CYAN}═══ 实况天气 ═══${NC}  坐标 ${COORD}"
    echo -e "  天气：${YELLOW}$(sky_cn "$sky")${NC}    气温：${temp}℃（体感 ${app_temp}℃）"
    echo -e "  湿度：$(python3 -c "print(round($hum*100))" 2>/dev/null || echo "$hum")%    气压：${pres%.*}Pa    能见度：${vis}km"
    echo -e "  风：${winddir}° @ ${windspd}km/h"
    echo -e "  PM2.5：${pm25}    AQI：${aqi_chn}（${aqi_d:-$({ aqi_desc "${aqi_chn:-0}"; })}，US ${aqi_usa}）"
    echo -e "  当前降水强度：${precip}（0=无雨）"
}

# ─── 逐小时（降水重点）───────────────────────────────────────────────────
show_hourly() {
    local resp; resp="$(fetch "${BASE}/hourly?hourlysteps=48")"
    check_err "$resp"
    echo -e "${CYAN}═══ 未来 48 小时预报 ═══${NC}  坐标 ${COORD}"
    echo -e "  ${BLUE}说明${NC}：降水强度 0=无雨 <0.08小雨 <0.35中雨 <0.65大雨 ≥0.65暴雨"
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$resp" | python3 -c "
import json,sys
d=json.load(sys.stdin)['result']['hourly']
SKY={'CLEAR_DAY':'晴','CLEAR_NIGHT':'晴','PARTLY_CLOUDY_DAY':'多云','PARTLY_CLOUDY_NIGHT':'多云','CLOUDY':'阴','LIGHT_HAZE':'轻雾霾','MODERATE_HAZE':'中雾霾','HEAVY_HAZE':'重雾霾','LIGHT_RAIN':'小雨','MODERATE_RAIN':'中雨','HEAVY_RAIN':'大雨','STORM_RAIN':'暴雨','FOG':'雾','LIGHT_SNOW':'小雪','MODERATE_SNOW':'中雪','HEAVY_SNOW':'大雪','STORM_SNOW':'暴雪','DUST':'浮尘','SAND':'沙尘','WIND':'大风'}
if d.get('description'): print('  走势：'+d['description'])
precip=d.get('precipitation',[])
temps=d.get('temperature',[])
skies=d.get('skycon',[])
def lvl(p): return '小雨' if p<0.08 else '中雨' if p<0.35 else '大雨' if p<0.65 else '暴雨'
rainy=[]
for i,p in enumerate(precip):
    v=p.get('value',0) or 0
    if v>0.03: rainy.append((p['datetime'][5:16].replace('T',' '), v, lvl(v), p.get('probability')))
print()
print(f'  降水时段（共 {len(rainy)} 个）：')
for t,v,l,prob in rainy[:16]:
    pp=f' 概率{prob}%' if isinstance(prob,(int,float)) and prob>0 else ''
    print(f'    {t}  {l}（强度 {v}）{pp}')
if not rainy: print('    未来48小时无有效降水')
print()
ts=[t['value'] for t in temps if isinstance(t.get('value'),(int,float))]
if ts: print(f'  温度区间：{min(ts)}℃ ~ {max(ts)}℃')
print('  每6小时概览：')
for i in range(0,len(skies),6):
    s=skies[i]
    tv=temps[i]['value'] if i<len(temps) else '?'
    print(f\"    {s['datetime'][5:16].replace('T',' ')}  {SKY.get(s['value'],s['value'])}  {tv}℃\")
" 2>/dev/null || echo "  [解析失败，原始数据前500字] $(printf '%s' "$resp" | head -c 500)"
    else
        echo "  （无 python3，无法格式化，原始摘要：）"
        printf '%s' "$resp" | head -c 500; echo
    fi
}

# ─── 逐天 + 生活指数 ─────────────────────────────────────────────────────
show_daily() {
    local resp; resp="$(fetch "${BASE}/daily?dailysteps=3")"
    check_err "$resp"
    echo -e "${CYAN}═══ 未来 3 天预报 ═══${NC}  坐标 ${COORD}"
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$resp" | python3 -c "
import json,sys
d=json.load(sys.stdin)['result']['daily']
SKY={'CLEAR_DAY':'晴','CLEAR_NIGHT':'晴','PARTLY_CLOUDY_DAY':'多云','PARTLY_CLOUDY_NIGHT':'多云','CLOUDY':'阴','LIGHT_RAIN':'小雨','MODERATE_RAIN':'中雨','HEAVY_RAIN':'大雨','STORM_RAIN':'暴雨','FOG':'雾','LIGHT_SNOW':'小雪','MODERATE_SNOW':'中雪','HEAVY_SNOW':'大雪','STORM_SNOW':'暴雪','DUST':'浮尘','SAND':'沙尘','WIND':'大风'}
for i in range(len(d['skycon'])):
    s=d['skycon'][i]
    date=s['date'][5:10]
    sky=SKY.get(s['value'],s['value'])
    tmin=d['temperature'][i]['min'] if i<len(d.get('temperature',[])) else '?'
    tmax=d['temperature'][i]['max'] if i<len(d.get('temperature',[])) else '?'
    prob=''
    if i<len(d.get('precipitation',[])):
        p=d['precipitation'][i].get('probability')
        if isinstance(p,dict): p=p.get('avg')
        if isinstance(p,(int,float)): prob=f'  降水概率 {round(p)}%'
    print(f'  {date}  {sky}  {tmin}~{tmax}℃{prob}')
li=d.get('life_index',{})
def show_li(name, key):
    v=li.get(key)
    items=v if isinstance(v,list) else (list(v.values())[0] if isinstance(v,dict) and v else [])
    if items and isinstance(items[0],dict):
        desc=items[0].get('desc') or items[0].get('name','')
        if desc: print(f'  {name}：{desc}')
show_li('紫外线','ultraviolet')
show_li('舒适度','comfort')
show_li('穿衣','dressing')
show_li('洗车','car_washing')
" 2>/dev/null || echo "  [解析失败] $(printf '%s' "$resp" | head -c 300)"
    else
        printf '%s' "$resp" | head -c 400; echo
    fi
}

# ─── 预警 + 天气走势要点 ──────────────────────────────────────────────────
show_alert() {
    # 免费版无独立 /alert 端点，预警在 weather 综合接口（alert=true）
    local resp; resp="$(fetch "${BASE}/weather?dailysteps=1&alert=true")"
    check_err "$resp"
    echo -e "${CYAN}═══ 气象预警 & 走势 ═══${NC}  坐标 ${COORD}"
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$resp" | python3 -c "
import json,sys
r=json.load(sys.stdin)['result']
kp=r.get('forecast_keypoint')
if kp: print('  要点：'+kp)
al=r.get('alert')
cts=(al or {}).get('content') if isinstance(al,dict) else None
if not cts:
    print('  当前无生效气象预警')
else:
    for a in cts:
        print(f\"  [{a.get('title','')}] {a.get('description','')[:200]}\")
" 2>/dev/null
    else
        printf '%s' "$resp" | head -c 400; echo
    fi
    return 0
}

# ─── 汇总模式 ─────────────────────────────────────────────────────────────
show_summary() {
    show_realtime
    echo
    if command -v python3 >/dev/null 2>&1; then
        # QPS=1：免费版连续请求会被限流，务必间隔 1.2s
        sleep 1.2
        # 摘要描述（hourly 的 description 字段）
        resp="$(fetch "${BASE}/hourly?hourlysteps=48")"
        desc="$(printf '%s' "$resp" | jget result.hourly.description)"
        if [[ -n "$desc" ]]; then
            echo -e "  ${BLUE}未来48h${NC}：$desc"
        else
            echo -e "  ${BLUE}未来48h${NC}：（限流未取到，可稍后重试 hourly）"
        fi
        sleep 1.2
        resp2="$(fetch "${BASE}/daily?dailysteps=3")"
        if printf '%s' "$resp2" | grep -q '"status":"ok"'; then
            printf '%s' "$resp2" | python3 -c "
import json,sys
d=json.load(sys.stdin)['result']['daily']
SKY={'CLEAR_DAY':'晴','CLEAR_NIGHT':'晴','PARTLY_CLOUDY_DAY':'多云','PARTLY_CLOUDY_NIGHT':'多云','CLOUDY':'阴','LIGHT_RAIN':'小雨','MODERATE_RAIN':'中雨','HEAVY_RAIN':'大雨','STORM_RAIN':'暴雨','FOG':'雾','LIGHT_SNOW':'小雪','MODERATE_SNOW':'中雪','HEAVY_SNOW':'大雪','STORM_SNOW':'暴雪','DUST':'浮尘','SAND':'沙尘','WIND':'大风'}
parts=[]
for i in range(len(d['skycon'])):
    s=d['skycon'][i]; t=d['temperature'][i]
    parts.append(f\"{s['date'][5:10]} {SKY.get(s['value'],s['value'])} {t['min']}~{t['max']}℃\")
print('  \033[0;34m未来3天\033[0m：' + '；'.join(parts))
" 2>/dev/null || true
        fi
    fi
    return 0
}

# ─── 主流程（QPS=1，多个请求间 sleep 1.2s）────────────────────────────────
case "$CMD" in
    realtime)  show_realtime ;;
    hourly)    show_hourly ;;
    daily)     show_daily ;;
    alert|warn) show_alert ;;
    summary)   show_summary ;;
    all)
        show_realtime; echo; sleep 1.2
        show_hourly;   echo; sleep 1.2
        show_daily;    echo; sleep 1.2
        show_alert
        ;;
    -h|--help|*)
        grep '^#' "$0" | head -18 | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
