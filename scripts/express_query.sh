#!/usr/bin/env bash
#==============================================================================
# express_query.sh — 快递100 快递轨迹查询（自动识别快递公司）
#
# 依赖密钥（通过 set_key.sh 管理，注册 https://api.kuaidi100.com/register 免费获取）：
#   KUAIDI100_CUSTOMER   企业授权 Customer（企业管理后台-我的信息-企业信息）
#   KUAIDI100_KEY        授权 Key（同上位置）
#
# 用法：
#   ./express_query.sh <单号>                        # 自动识别快递公司
#   ./express_query.sh <单号> <公司编码>              # 指定公司，如 yuantong
#   ./express_query.sh <单号> <公司编码> <手机后4位>   # 顺丰/中通等需手机号校验
#   ./express_query.sh --com                         # 查看常用快递公司编码表
#
# 常用公司编码：sf 顺丰 | yto 圆通 | zto 中通 | sto 申通
#               yunda 韵达 | ems EMS | jd 京东 | deutobell 德邦 | htky 百世
#==============================================================================

set -euo pipefail

# ─── 环境适配 ────────────────────────────────────────────────────────────
if [[ -z "${HOME:-}" ]]; then
    export HOME="/data/data/com.termux/files/home"
fi
KEYS_FILE="${HOME}/.api_keys/.env"

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── 快递公司编码表 ──────────────────────────────────────────────────────
show_com_table() {
    cat << 'EOF'
常用快递公司编码表（快递100，完整表见 https://api.kuaidi100.com/manager/openapi/download/kdbm.do）
──────────────────────────────────────────────────
  编码        快递公司
──────────────────────────────────────────────────
  sf          顺丰速运        yto         圆通速运
  zto         中通快递        sto         申通快递
  yunda       韵达快递        ems         EMS
  jd          京东快递        deppon      德邦快递
  htky        百世快递        youzhengguoji 邮政国际
  jtexpress   极兔速递        yuan Cheng 圆通快运*
──────────────────────────────────────────────────
* 顺丰/中通查询通常需收/寄件人手机号后4位
EOF
}

# ─── 密钥读取（与 set_key.sh 格式兼容：KEY_NAME='value'）──────────────────
read_key() {
    local key_name="$1"
    [[ ! -f "$KEYS_FILE" ]] && return 1
    grep -E "^${key_name}=" "$KEYS_FILE" 2>/dev/null | \
        sed -E "s/^${key_name}=//; s/^['\"]//; s/['\"]$//" || true
    return 0
}

# ─── MD5 计算（跨平台：md5sum > macOS md5 > python3）─────────────────────
md5_hex() {
    local input="$1"
    if command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$input" | md5sum | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        printf '%s' "$input" | md5 -q
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import hashlib,sys; print(hashlib.md5(sys.argv[1].encode()).hexdigest())" "$input"
    else
        return 1
    fi
}

# ─── 自动识别快递公司（autonumber 接口，仅需 Key，无签名）────────────────
detect_com() {
    local num="$1" key="$2"
    local resp
    resp="$(curl -s --max-time 15 -G \
        "https://extapi.kuaidi100.com/autonumber/auto" \
        --data-urlencode "num=${num}" \
        --data-urlencode "key=${key}")" || return 1
    # 返回形如 [{"length":13,"com":"yto"},...]，取第一个 com
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$resp" | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
    if isinstance(data, list) and data:
        print(data[0].get('com',''))
except Exception:
    pass
" 2>/dev/null
    else
        printf '%s' "$resp" | grep -o '"com":"[^"]*"' | head -1 | sed 's/"com":"//; s/"//'
    fi
}

# ─── 结果美化输出 ─────────────────────────────────────────────────────────
format_result() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c '
import json, sys

STATE_MAP = {
    "0": "在途", "1": "揽收", "2": "疑难", "3": "签收", "4": "退签",
    "5": "派件", "6": "退回", "7": "转投", "8": "清关", "14": "拒签",
    "10": "待清关", "11": "清关中", "12": "已清关", "13": "清关异常",
}

ERR_MAP = {
    "400": "找不到对应快递公司（检查公司编码，或账号未充值）",
    "408": "快递公司参数异常：电话号码校验未通过（顺丰/中通需手机后4位）",
    "500": "查询无结果（确认单号已发货，隔段时间再查）",
    "501": "快递100服务器临时异常，请稍后重试",
    "502": "服务器繁忙，请稍后重试",
    "503": "验证签名失败（检查 KUAIDI100_KEY / KUAIDI100_CUSTOMER）",
    "601": "Key 已过期或无可用单量",
}

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    print(raw)
    sys.exit(0)

if data.get("status") == "200" or "data" in data:
    state = STATE_MAP.get(str(data.get("state", "?")), data.get("state", "?"))
    print("快递公司: {}    单号: {}".format(data.get("com", "?"), data.get("nu", "?")))
    print("当前状态: {}".format(state))
    print("─" * 52)
    tracks = data.get("data") or []
    for i, t in enumerate(tracks):
        mark = "●最新" if i == 0 else "      "
        status = t.get("status", "")
        print("{}  {}".format(mark, t.get("ftime", t.get("time", ""))))
        if status:
            print("        [{}]".format(status))
        print("        {}".format(t.get("context", "")))
        print()
else:
    code = str(data.get("returnCode", ""))
    print("查询失败 [{}]".format(code))
    print(ERR_MAP.get(code, data.get("message", "未知错误")))
    sys.exit(1)
'
    else
        cat
    fi
}

# ─── 参数解析 ─────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--com" || "${1:-}" == "-c" ]]; then
    show_com_table
    exit 0
fi

if [[ $# -lt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat << 'EOF'
express_query.sh — 快递轨迹查询（快递100）

用法：
  ./express_query.sh <单号>                       自动识别快递公司
  ./express_query.sh <单号> <公司编码>             指定快递公司
  ./express_query.sh <单号> <公司编码> <手机后4位>  顺丰/中通等需手机号校验
  ./express_query.sh --com                        查看公司编码表

首次使用前（密钥注册 https://api.kuaidi100.com/register 免费获取）：
  set_key.sh set KUAIDI100_CUSTOMER <你的Customer>
  set_key.sh set KUAIDI100_KEY      <你的授权Key>

示例：
  ./express_query.sh YT25569986666541
  ./express_query.sh SF1356245698123 sf 1234
EOF
    exit 0
fi

NUM="$1"
COM="${2:-}"
PHONE="${3:-}"

# 单号基本校验（6-32 位字母数字）
if ! echo "$NUM" | grep -qE '^[A-Za-z0-9]{6,32}$'; then
    log_error "快递单号格式应为 6-32 位字母数字: $NUM"
    exit 1
fi

# ─── 读取密钥 ─────────────────────────────────────────────────────────────
CUSTOMER="$(read_key KUAIDI100_CUSTOMER || true)"
KEY="$(read_key KUAIDI100_KEY || true)"

if [[ -z "$CUSTOMER" || -z "$KEY" ]]; then
    log_error "缺少快递100 密钥（KUAIDI100_CUSTOMER / KUAIDI100_KEY）"
    echo ""
    echo "获取步骤："
    echo "  1. 注册 https://api.kuaidi100.com/register（免费）"
    echo "  2. 登录后进入 企业管理后台 → 我的信息 → 企业信息，查看 Customer 和 Key"
    echo "  3. 执行以下命令配置（bash 版）："
    echo "     set_key.sh set KUAIDI100_CUSTOMER <你的Customer>"
    echo "     set_key.sh set KUAIDI100_KEY      <你的授权Key>"
    echo "     （Python 版：python set_key.py set KUAIDI100_CUSTOMER <Customer>）"
    exit 1
fi

# ─── 自动识别快递公司 ─────────────────────────────────────────────────────
if [[ -z "$COM" ]]; then
    log_info "未指定快递公司，自动识别单号 $NUM ..."
    COM="$(detect_com "$NUM" "$KEY")"
    if [[ -z "$COM" ]]; then
        log_warn "无法自动识别快递公司，请手动指定公司编码（--com 查看编码表）"
        exit 1
    fi
    log_info "识别结果: $COM"
fi

# ─── 构造 param 与签名 ────────────────────────────────────────────────────
if [[ -n "$PHONE" ]]; then
    PARAM_JSON="{\"com\":\"${COM}\",\"num\":\"${NUM}\",\"phone\":\"${PHONE}\",\"resultv2\":\"4\"}"
else
    PARAM_JSON="{\"com\":\"${COM}\",\"num\":\"${NUM}\",\"resultv2\":\"4\"}"
fi

SIGN="$(md5_hex "${PARAM_JSON}${KEY}${CUSTOMER}")"
if [[ -z "$SIGN" ]]; then
    log_error "无法计算 MD5 签名（缺少 md5sum/md5/python3），请安装其中任一工具"
    exit 1
fi
SIGN="$(echo "$SIGN" | tr '[:lower:]' '[:upper:]')"

# ─── 发起查询 ─────────────────────────────────────────────────────────────
log_info "查询 ${COM} 单号 ${NUM} ..."

RESP="$(curl -s --max-time 30 -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "customer=${CUSTOMER}" \
    --data-urlencode "sign=${SIGN}" \
    --data-urlencode "param=${PARAM_JSON}" \
    "https://poll.kuaidi100.com/poll/query.do")" || {
    log_error "请求失败，请检查网络连接"
    exit 1
}

if [[ -z "$RESP" ]]; then
    log_error "接口返回为空，请稍后重试"
    exit 1
fi

printf '%s' "$RESP" | format_result
