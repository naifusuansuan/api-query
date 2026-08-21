#!/usr/bin/env bash
#==============================================================================
# query_api.sh — 通用接口查询脚本
#
# 功能：通过预设配置或命令行参数发送 HTTP 请求，返回响应数据
# 优先级：命令行参数 > 环境变量 > config.json 预设配置
#
# 用法：
#   # 1. 按预设名调用
#   ./query_api.sh --preset weather
#
#   # 2. 按预设调用 + 命令行覆盖参数
#   ./query_api.sh --preset github --header "X-API-Key: ghp_newkey"
#
#   # 3. 完全命令行模式（临时查询任意接口）
#   ./query_api.sh --url "https://api.example.com/data" --method GET \
#       --header "Authorization: Bearer xxx" --query "q=test&page=1"
#
#   # 4. POST 请求带 body
#   ./query_api.sh --url "https://api.example.com/create" --method POST \
#       --header "Content-Type: application/json" --body '{"name":"test"}'
#
# 安全说明：
#   - config.json 中的 {env:VAR_NAME} 会被替换为对应环境变量值
#   - 密钥从 ~/.api_keys/.env 自动加载（权限 600）
#   - 日志输出自动脱敏，绝不打印完整 API-Key
#==============================================================================

set -euo pipefail

# ─── 常量 ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
KEYS_FILE="${HOME}/.api_keys/.env"
MAX_RETRIES=2
RETRY_DELAY=2
TIMEOUT=30

# ─── 安卓/Termux/WorkBuddy 环境适配 ─────────────────────────────────────
# Android 15 + Termux/WorkBuddy 环境自适应
# 1. 终端检测：非交互环境（管道/子进程）自动禁用 ANSI 颜色，避免乱码
# 2. 依赖检测：python3 / curl 不存在时给出明确安装指引
# 3. HOME 兜底：部分安卓执行环境 HOME 未设置时用 /data/data/com.termux/files/home
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

# HOME 未设置时的兜底（安卓某些执行上下文 HOME 为空）
if [[ -z "${HOME:-}" ]]; then
    export HOME="/data/data/com.termux/files/home"
fi

# 依赖检测（给出安卓/Termux 安装指引，不自动安装任何东西）
check_dependencies() {
    local missing=()
    if ! command -v curl >/dev/null 2>&1; then
        missing+=("curl")
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        missing+=("python3")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}[ERROR]${NC} 缺少依赖: ${missing[*]}" >&2
        echo "  Termux 环境:  pkg install ${missing[*]}" >&2
        echo "  WorkBuddy 环境: curl/python3 为预装依赖，若缺失请反馈" >&2
        exit 1
    fi
}
check_dependencies

# ─── 辅助函数 ────────────────────────────────────────────────────────────

# 日志输出（带颜色）
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[DEBUG]${NC} $*" >&2 || true; }

# 脱敏：将字符串中的敏感值替换为 前缀+****
# 用法：mask_secret "Bearer ghp_abc123xyz"  →  "Bearer ghp_****"
mask_secret() {
    local val="$1"
    local len=${#val}
    if [[ "$len" -le 8 ]]; then
        echo "****"
    else
        echo "${val:0:4}****"
    fi
}

# 脱敏 header 字符串中的鉴权值
# 用法：mask_headers "Authorization: Bearer xxx\nX-API-Key: yyy"
mask_headers() {
    local raw="$1"
    local masked=""
    local IFS=$'\n'
    for line in $raw; do
        # 匹配 Authorization / X-API-Key / *token* / *key* / *secret*
        if echo "$line" | grep -qiE '(authorization|x-api-key|.*token|.*key|.*secret)'; then
            # 分割 "Key: Value"，对 Value 脱敏
            local key_part val_part
            key_part="${line%%:*}"
            val_part="${line#*:}"
            val_part="$(echo "$val_part" | sed 's/^[[:space:]]*//')"
            masked+="${key_part}: $(mask_secret "$val_part")"
        else
            masked+="$line"
        fi
        masked+=$'\n'
    done
    echo "$masked"
}

# 脱敏 URL 中走 query 参数的敏感值（key/apikey/token/secret/sign 等）
# 高德等平台的 key 拼在 URL 上，debug 日志同样不能明文打印
# 用法：mask_url "https://api.com/path?key=abcdef123"
mask_url() {
    echo "$1" | python3 -c "
import sys, re
url = sys.stdin.read().rstrip('\n')
def repl(m):
    prefix, val = m.group(1), m.group(2)
    if len(val) > 8:
        return prefix + val[:4] + '****'
    return prefix + '****'
url = re.sub(r'([?&](?:key|apikey|api_key|appkey|access_key|token|access_token|secret|sign|signature|signature)=)([^&]*)',
             repl, url, flags=re.IGNORECASE)
sys.stdout.write(url)
"
}

# 从 config.json 中用 Python 提取字段（依赖 python3）
# 用法：config_get "weather" "url"
config_get() {
    local preset="$1"
    local field="$2"
    [[ ! -f "$CONFIG_FILE" ]] && return 1
    python3 -c "
import json, sys
try:
    with open('${CONFIG_FILE}') as f:
        data = json.load(f)
    preset = data.get('${preset}')
    if preset is None or not isinstance(preset, dict):
        sys.exit(1)
    val = preset.get('${field}', '')
    if val == '':
        sys.exit(1)
    print(val)
except (json.JSONDecodeError, FileNotFoundError):
    sys.exit(1)
" 2>/dev/null || return 1
}

# 从 config.json 中提取整个 preset 为 JSON
config_get_preset() {
    local preset="$1"
    [[ ! -f "$CONFIG_FILE" ]] && return 1
    python3 -c "
import json
with open('${CONFIG_FILE}') as f:
    data = json.load(f)
preset = data.get('${preset}')
if preset is None or not isinstance(preset, dict):
    exit(1)
print(json.dumps(preset))
" 2>/dev/null || return 1
}

# 替换字符串中的 {env:VAR_NAME} 为环境变量值
substitute_env_vars() {
    local input="$1"
    echo "$input" | python3 -c "
import re, os, sys
text = sys.stdin.read()
def replacer(m):
    var = m.group(1)
    val = os.environ.get(var, '')
    return val
result = re.sub(r'\{env:([A-Za-z_][A-Za-z0-9_]*)\}', replacer, text)
sys.stdout.write(result)
"
}

# 加载密钥文件
load_keys() {
    if [[ -f "$KEYS_FILE" ]]; then
        log_debug "加载密钥文件: $KEYS_FILE"
        set -a
        # shellcheck disable=SC1090
        source "$KEYS_FILE"
        set +a
    else
        log_debug "未找到密钥文件 $KEYS_FILE（非必须，仅预设配置引用环境变量时需要）"
    fi
}

# 列出所有预设名
list_presets() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "配置文件不存在: $CONFIG_FILE"
        return 1
    fi
    echo -e "${CYAN}可用预设接口：${NC}"
    python3 -c "
import json
with open('${CONFIG_FILE}') as f:
    data = json.load(f)
for name, cfg in data.items():
    if name.startswith('_') or not isinstance(cfg, dict):
        continue
    url = cfg.get('url', 'N/A')
    method = cfg.get('method', 'GET')
    desc = cfg.get('desc', '')
    print('  ' + name.ljust(20) + '  [' + method.ljust(6) + ']  ' + url)
    if desc:
        print('  ' + ''.ljust(20) + '           ' + desc)
" 2>/dev/null || {
        log_error "解析 config.json 失败"
        return 1
    }
}

# ─── 参数解析 ────────────────────────────────────────────────────────────

# 默认值
PRESET=""
URL=""
METHOD="GET"
EXPLICIT_METHOD=0
HEADERS=()
BODY=""
QUERY_PARAMS=()
RAW_OUTPUT=0

usage() {
    cat << 'EOF'
query_api.sh — 通用接口查询脚本

用法：
  ./query_api.sh [选项]

选项：
  -p, --preset NAME        使用 config.json 中的预设配置
  -u, --url URL            请求 URL（命令行优先）
  -m, --method METHOD      HTTP 方法（GET/POST/PUT/DELETE/PATCH），默认 GET
  -H, --header "K: V"      附加请求头（可多次指定）
  -d, --body DATA          请求体（POST/PUT 用）
  -q, --query "k=v"        查询参数（可多次指定，或用 "k=v&k2=v2"）
  -r, --raw                原始输出（不格式化 JSON）
      --debug              启用调试日志
  -l, --list               列出所有可用预设
  -h, --help               显示此帮助

示例：
  # 预设调用
  ./query_api.sh --preset weather
  ./query_api.sh --preset github --header "X-API-Key: ghp_newkey"

  # 临时查询
  ./query_api.sh --url "https://api.example.com/data" --method GET
  ./query_api.sh --url "https://api.example.com/create" --method POST \
      --header "Content-Type: application/json" --body '{"name":"test"}'

优先级：命令行参数 > 环境变量 > config.json 预设配置
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--preset)   PRESET="$2"; shift 2 ;;
        -u|--url)      URL="$2"; shift 2 ;;
        -m|--method)   METHOD="$2"; EXPLICIT_METHOD=1; shift 2 ;;
        -H|--header)   HEADERS+=("$2"); shift 2 ;;
        -d|--body)     BODY="$2"; shift 2 ;;
        -q|--query)    QUERY_PARAMS+=("$2"); shift 2 ;;
        -r|--raw)      RAW_OUTPUT=1; shift ;;
        --debug)       DEBUG=1; shift ;;
        -l|--list)     list_presets; exit 0 ;;
        -h|--help)     usage; exit 0 ;;
        *)             log_error "未知参数: $1"; usage; exit 1 ;;
    esac
done

# ─── 主逻辑 ──────────────────────────────────────────────────────────────

# 加载密钥文件中的环境变量
load_keys

# 1. 加载预设配置（作为基础值）
if [[ -n "$PRESET" ]]; then
    log_info "使用预设: $PRESET"
    PRESET_JSON="$(config_get_preset "$PRESET")" || {
        log_error "预设 '$PRESET' 不存在于 config.json 中"
        log_info "可用预设："
        list_presets >&2 || true
        exit 1
    }

    # 从预设提取各字段（命令行未指定时才用预设值）
    if [[ -z "$URL" ]]; then
        URL="$(echo "$PRESET_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url',''))" 2>/dev/null)"
    fi
    if [[ "$METHOD" == "GET" && -z "$EXPLICIT_METHOD" ]]; then
        METHOD="$(echo "$PRESET_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('method','GET'))" 2>/dev/null)"
        METHOD="${METHOD:-GET}"
    fi
    # 预设 headers
    PRESET_HEADERS_RAW="$(echo "$PRESET_JSON" | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
hdrs = cfg.get('headers', {})
for k,v in hdrs.items():
    print(f'{k}: {v}')
" 2>/dev/null)"
    if [[ -n "$PRESET_HEADERS_RAW" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && HEADERS+=("$line")
        done <<< "$PRESET_HEADERS_RAW"
    fi
    # 预设 body
    if [[ -z "$BODY" ]]; then
        BODY="$(echo "$PRESET_JSON" | python3 -c "import json,sys; b=json.load(sys.stdin).get('body',''); print(b if isinstance(b,str) else json.dumps(b))" 2>/dev/null)"
    fi
    # 预设 query params
    PRESET_QUERY="$(echo "$PRESET_JSON" | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
params = cfg.get('params', {})
for k,v in params.items():
    print(f'{k}={v}')
" 2>/dev/null)"
    if [[ -n "$PRESET_QUERY" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && QUERY_PARAMS+=("$line")
        done <<< "$PRESET_QUERY"
    fi
fi

# ─── 同名参数覆盖（实现"命令行 > 预设"优先级）──────────────────────────
# 数组顺序：命令行参数在前（参数解析阶段加入），预设参数在后（上面追加）。
# 因此"先出现的保留"即命令行覆盖预设同名项。
# 同时支持拆分 "k=v&k2=v2" 形式的多参数。

# Query 参数去重：同名 key 命令行优先
declare -A SEEN_QUERY_KEYS=()
DEDUPED_QUERY=()
for q in "${QUERY_PARAMS[@]}"; do
    IFS='&' read -ra _pairs <<< "$q"
    for pair in "${_pairs[@]}"; do
        [[ -n "$pair" ]] || continue
        _k="${pair%%=*}"
        if [[ -z "${SEEN_QUERY_KEYS[$_k]:-}" ]]; then
            SEEN_QUERY_KEYS["$_k"]=1
            DEDUPED_QUERY+=("$pair")
        fi
    done
done
if [[ ${#DEDUPED_QUERY[@]} -gt 0 ]]; then
    QUERY_PARAMS=("${DEDUPED_QUERY[@]}")
else
    QUERY_PARAMS=()
fi

# Header 去重：同名 header（名称大小写不敏感）命令行优先
declare -A SEEN_HDR_KEYS=()
DEDUPED_HEADERS=()
for h in "${HEADERS[@]}"; do
    _hk="$(echo "${h%%:*}" | tr '[:upper:]' '[:lower:]')"
    _hk="${_hk//[[:space:]]/}"
    if [[ -z "${SEEN_HDR_KEYS[$_hk]:-}" ]]; then
        SEEN_HDR_KEYS["$_hk"]=1
        DEDUPED_HEADERS+=("$h")
    fi
done
if [[ ${#DEDUPED_HEADERS[@]} -gt 0 ]]; then
    HEADERS=("${DEDUPED_HEADERS[@]}")
else
    HEADERS=()
fi

# 2. 校验 URL
if [[ -z "$URL" ]]; then
    log_error "未指定 URL。请使用 --url 或 --preset 参数"
    usage
    exit 1
fi

# 3. 环境变量替换（处理 config.json 中的 {env:XXX}）
URL="$(substitute_env_vars "$URL")"
BODY="$(substitute_env_vars "$BODY")"

# 替换 headers 中的 {env:XXX}
RESOLVED_HEADERS=()
for h in "${HEADERS[@]}"; do
    RESOLVED_HEADERS+=("$(substitute_env_vars "$h")")
done
HEADERS=("${RESOLVED_HEADERS[@]}")

# 替换 query params 中的 {env:XXX}
RESOLVED_QUERY=()
for q in "${QUERY_PARAMS[@]}"; do
    RESOLVED_QUERY+=("$(substitute_env_vars "$q")")
done
QUERY_PARAMS=("${RESOLVED_QUERY[@]}")

# 4. 构建 curl 命令
# 使用临时文件存储完整响应（body + 末尾状态码），避免管道丢数据
RESP_FILE="$(mktemp)"
trap 'rm -f "$RESP_FILE"' EXIT

CURL_ARGS=()
CURL_ARGS+=("-s" "-S")                            # 静默 + 显示错误
CURL_ARGS+=("-w" "\n%{http_code}")                # 在输出末尾附加 HTTP 状态码
CURL_ARGS+=("--connect-timeout" "$TIMEOUT")
CURL_ARGS+=("--max-time" "$((TIMEOUT * 2))")
CURL_ARGS+=("-o" "$RESP_FILE")                    # 响应体写入文件

# Method
CURL_ARGS+=("-X" "$METHOD")

# Headers
for h in "${HEADERS[@]}"; do
    CURL_ARGS+=("-H" "$h")
done

# Body
if [[ -n "$BODY" ]]; then
    CURL_ARGS+=("-d" "$BODY")
fi

# Query params：拼接到 URL
if [[ ${#QUERY_PARAMS[@]} -gt 0 ]]; then
    QUERY_STRING=""
    for q in "${QUERY_PARAMS[@]}"; do
        if [[ -n "$QUERY_STRING" ]]; then
            QUERY_STRING+="&"
        fi
        QUERY_STRING+="$q"
    done
    # URL 已有 ? 则用 & 拼接
    if echo "$URL" | grep -q '?'; then
        URL="${URL}&${QUERY_STRING}"
    else
        URL="${URL}?${QUERY_STRING}"
    fi
fi

CURL_ARGS+=("$URL")

# 5. 调试输出
log_debug "Method: $METHOD"
log_debug "URL: $(mask_url "$URL")"
if [[ ${#HEADERS[@]} -gt 0 ]]; then
    HEADERS_STR=$(printf '%s\n' "${HEADERS[@]}")
    log_debug "Headers:\n$(mask_headers "$HEADERS_STR")"
fi
[[ -n "$BODY" ]] && log_debug "Body: $BODY"

# 6. 发送请求（带重试）
send_request() {
    local attempt=0
    while [[ $attempt -le $MAX_RETRIES ]]; do
        attempt=$((attempt + 1))
        log_debug "发送请求 (尝试 $attempt/$((MAX_RETRIES + 1)))"

        # 清空临时文件
        : > "$RESP_FILE"

        # 执行 curl，HTTP 状态码通过 -w 输出到 stdout
        # -w 输出格式为 "\n200"，用 tr 去除换行
        local http_code
        http_code=$(curl "${CURL_ARGS[@]}" 2>/dev/null | tr -d '\n') || {
            local exit_code=$?
            case "$exit_code" in
                6)   log_error "DNS 解析失败：无法解析主机名"; return 1 ;;
                7)   log_error "连接失败：无法连接到服务器（检查网络或端口）"; return 1 ;;
                28)  log_error "请求超时：连接或响应超过 ${TIMEOUT}s 超时限制"; return 1 ;;
                35)  log_error "SSL 握手失败：检查证书或 TLS 配置"; return 1 ;;
                60)  log_error "SSL 证书验证失败：证书不受信任"; return 1 ;;
                *)   log_error "curl 请求失败，退出码: $exit_code"; return 1 ;;
            esac
        }

        # http_code 是 -w 的输出（最后一行），response body 在 RESP_FILE 中
        # 如果 http_code 为空，说明 curl 可能有异常
        if [[ -z "$http_code" ]]; then
            log_error "未获取到 HTTP 状态码（curl 可能异常退出）"
            return 1
        fi

        # 读取响应体
        local body_text
        body_text="$(cat "$RESP_FILE")"

        log_debug "HTTP 状态码: $http_code"
        log_debug "响应体长度: ${#body_text}"

        # 错误码处理
        case "$http_code" in
            200|201|202|204)
                # 成功 — 输出响应体
                echo "$body_text"
                return 0
                ;;
            301|302|307|308)
                log_warn "HTTP $http_code：重定向（curl 默认不跟随，如需跟随请加 -L 参数）"
                echo "$body_text"
                return 0
                ;;
            400)
                log_error "HTTP 400：请求参数错误（Bad Request）"
                [[ -n "$body_text" ]] && echo "$body_text" >&2
                return 1
                ;;
            401)
                log_error "HTTP 401：鉴权失败 — 请检查 API-Key 是否正确"
                log_info "提示：使用 set_key.sh set <KEY_NAME> <value> 设置密钥"
                [[ -n "$body_text" ]] && echo "$body_text" >&2
                return 1
                ;;
            403)
                log_error "HTTP 403：权限不足 — API-Key 无权访问此接口，或密钥已过期"
                [[ -n "$body_text" ]] && echo "$body_text" >&2
                return 1
                ;;
            404)
                log_error "HTTP 404：接口路径不存在 — 请检查 URL 是否正确"
                [[ -n "$body_text" ]] && echo "$body_text" >&2
                return 1
                ;;
            429)
                log_error "HTTP 429：触发限流 — 请求频率过高，请稍后重试"
                log_info "提示：降低调用频率，或检查 API 的 rate limit 策略"
                if [[ $attempt -le $MAX_RETRIES ]]; then
                    log_warn "${RETRY_DELAY}s 后重试..."
                    sleep "$RETRY_DELAY"
                    continue
                fi
                [[ -n "$body_text" ]] && echo "$body_text" >&2
                return 1
                ;;
            500|502|503)
                log_warn "HTTP $http_code：服务器端错误"
                if [[ $attempt -le $MAX_RETRIES ]]; then
                    log_warn "${RETRY_DELAY}s 后重试..."
                    sleep "$RETRY_DELAY"
                    continue
                fi
                log_error "重试已用尽"
                [[ -n "$body_text" ]] && echo "$body_text" >&2
                return 1
                ;;
            *)
                log_warn "HTTP $http_code：未预期的状态码"
                echo "$body_text"
                return 0
                ;;
        esac
    done
    log_error "重试 $MAX_RETRIES 次后仍失败"
    return 1
}

# 7. 执行请求并格式化输出
RAW_RESPONSE=""
if ! RAW_RESPONSE="$(send_request)"; then
    exit 1
fi

if [[ -z "$RAW_RESPONSE" ]]; then
    log_info "请求成功，响应为空"
    exit 0
fi

if [[ $RAW_OUTPUT -eq 1 ]]; then
    echo "$RAW_RESPONSE"
else
    # 尝试格式化 JSON
    FORMATTED=""
    if FORMATTED=$(echo "$RAW_RESPONSE" | python3 -m json.tool 2>/dev/null); then
        echo "$FORMATTED"
    else
        # JSON 解析失败，原样返回原始文本
        log_warn "响应非 JSON 格式，原样输出原始文本"
        echo "$RAW_RESPONSE"
    fi
fi
