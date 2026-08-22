#!/usr/bin/env bash
#==============================================================================
# set_key.sh — API Key 管理脚本
#
# 功能：安全地存储、查看、删除 API Key
#   - 密钥文件位置：~/.api_keys/.env，权限 600（仅当前用户可读写）
#   - 日志输出自动脱敏，绝不打印完整 API-Key，只显示前4位 + ****
#
# 用法：
#   ./set_key.sh set    <KEY_NAME> <KEY_VALUE>   # 设置/更新密钥
#   ./set_key.sh list                            # 列出所有密钥名（脱敏显示值）
#   ./set_key.sh get    <KEY_NAME>               # 查看单个密钥（脱敏显示）
#   ./set_key.sh remove <KEY_NAME>               # 删除密钥
#   ./set_key.sh export <KEY_NAME>               # 输出 export 语句（供 source）
#   ./set_key.sh path                            # 显示密钥文件路径
#==============================================================================

set -euo pipefail

# ─── 常量 ────────────────────────────────────────────────────────────────
# HOME 未设置时的兜底（安卓某些执行上下文 HOME 为空）
if [[ -z "${HOME:-}" ]]; then
    export HOME="/data/data/com.termux/files/home"
fi
KEYS_DIR="${HOME}/.api_keys"
KEYS_FILE="${KEYS_DIR}/.env"

# ─── 安卓/Termux/WorkBuddy 环境适配 ─────────────────────────────────────
# 非交互环境（管道/子进程）自动禁用 ANSI 颜色，避免乱码
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# ─── 辅助函数 ────────────────────────────────────────────────────────────

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# 脱敏：只显示前4位 + ****
mask_secret() {
    local val="$1"
    local len=${#val}
    if [[ "$len" -le 8 ]]; then
        echo "****"
    else
        echo "${val:0:4}****"
    fi
}

# 确保密钥目录和文件存在，且权限正确
ensure_keys_file() {
    if [[ ! -d "$KEYS_DIR" ]]; then
        mkdir -p "$KEYS_DIR"
        chmod 700 "$KEYS_DIR"
        log_info "创建密钥目录: $KEYS_DIR (权限 700)"
    fi
    if [[ ! -f "$KEYS_FILE" ]]; then
        touch "$KEYS_FILE"
        chmod 600 "$KEYS_FILE"
        log_info "创建密钥文件: $KEYS_FILE (权限 600)"
    fi
}

# 读取密钥值（从 .env 文件）
read_key() {
    local key_name="$1"
    [[ ! -f "$KEYS_FILE" ]] && return 1
    # 格式为 KEY_NAME='value' 或 KEY_NAME="value" 或 KEY_NAME=value
    # grep 未匹配时返回 1，在 set -e 下会中断，用 || true 保护
    grep -E "^${key_name}=" "$KEYS_FILE" 2>/dev/null | \
        sed -E "s/^${key_name}=//; s/^['\"]//; s/['\"]$//" || true
    return 0
}

# ─── 命令实现 ────────────────────────────────────────────────────────────

cmd_set() {
    local key_name="$1"
    local key_value="$2"

    if [[ -z "$key_name" || -z "$key_value" ]]; then
        log_error "用法: set_key.sh set <KEY_NAME> <KEY_VALUE>"
        echo "示例: set_key.sh set GITHUB_API_KEY ghp_xxxxxxxxxxxx" >&2
        exit 1
    fi

    # 校验 KEY_NAME 格式（只允许大写字母、数字、下划线）
    if ! echo "$key_name" | grep -qE '^[A-Z][A-Z0-9_]*$'; then
        log_error "KEY_NAME 必须为大写字母开头，仅含大写字母/数字/下划线"
        echo "正确示例: GITHUB_API_KEY, OPENWEATHER_KEY" >&2
        exit 1
    fi

    ensure_keys_file

    # 如果已存在同名 key，先删除旧行
    if grep -q "^${key_name}=" "$KEYS_FILE" 2>/dev/null; then
        sed -i'' "/^${key_name}=/d" "$KEYS_FILE" 2>/dev/null || sed -i "/^${key_name}=/d" "$KEYS_FILE"
        log_warn "覆盖已存在的密钥: $key_name"
    fi

    # 写入新行（用单引号包裹，防止特殊字符）
    echo "${key_name}='${key_value}'" >> "$KEYS_FILE"

    # 确保权限正确
    chmod 600 "$KEYS_FILE"

    log_info "密钥已保存: $key_name = $(mask_secret "$key_value")"
    log_info "存储位置: $KEYS_FILE (权限 600)"
}

cmd_list() {
    if [[ ! -f "$KEYS_FILE" ]] || [[ ! -s "$KEYS_FILE" ]]; then
        log_info "暂无已存储的密钥"
        log_info "使用 'set_key.sh set <KEY_NAME> <KEY_VALUE>' 添加密钥"
        return 0
    fi

    echo -e "${CYAN}已存储的 API Key：${NC}"
    echo "──────────────────────────────────────────────────"
    printf "%-25s  %s\n" "KEY_NAME" "VALUE (脱敏)"
    echo "──────────────────────────────────────────────────"

    while IFS='=' read -r key_name key_value; do
        # 跳过空行和注释
        [[ -z "$key_name" || "$key_name" =~ ^# ]] && continue
        # 去除值的引号
        key_value="${key_value#\'}"
        key_value="${key_value%\'}"
        key_value="${key_value#\"}"
        key_value="${key_value%\"}"
        printf "%-25s  %s\n" "$key_name" "$(mask_secret "$key_value")"
    done < "$KEYS_FILE"

    echo "──────────────────────────────────────────────────"
    # 跨平台权限获取：GNU stat > BSD/toybox stat > ls 兜底
    local perms
    perms="$(stat -c '%a' "$KEYS_FILE" 2>/dev/null \
        || stat -f '%Lp' "$KEYS_FILE" 2>/dev/null \
        || ls -l "$KEYS_FILE" 2>/dev/null | awk '{k=0;for(i=0;i<=8;i++)k+=((substr($1,i+2,1)~/[rwx]/)*2^(8-i));if(k)printf("%0o",k)}' \
        || echo '???')"
    log_info "文件路径: $KEYS_FILE (权限 $perms)"
}

cmd_get() {
    local key_name="$1"
    if [[ -z "$key_name" ]]; then
        log_error "用法: set_key.sh get <KEY_NAME>"
        exit 1
    fi

    local value
    if ! value="$(read_key "$key_name")" || [[ -z "$value" ]]; then
        log_error "密钥 '$key_name' 不存在"
        exit 1
    fi

    echo "$key_name = $(mask_secret "$value")"
}

cmd_remove() {
    local key_name="$1"
    if [[ -z "$key_name" ]]; then
        log_error "用法: set_key.sh remove <KEY_NAME>"
        exit 1
    fi

    if [[ ! -f "$KEYS_FILE" ]] || ! grep -q "^${key_name}=" "$KEYS_FILE" 2>/dev/null; then
        log_error "密钥 '$key_name' 不存在"
        exit 1
    fi

    sed -i'' "/^${key_name}=/d" "$KEYS_FILE" 2>/dev/null || sed -i "/^${key_name}=/d" "$KEYS_FILE"
    log_info "已删除密钥: $key_name"
}

cmd_export() {
    local key_name="$1"
    if [[ -z "$key_name" ]]; then
        log_error "用法: set_key.sh export <KEY_NAME>"
        exit 1
    fi

    local value
    if ! value="$(read_key "$key_name")" || [[ -z "$value" ]]; then
        log_error "密钥 '$key_name' 不存在"
        exit 1
    fi

    # 输出 export 语句，供 source 使用
    echo "export ${key_name}='${value}'"
}

cmd_path() {
    echo "$KEYS_FILE"
}

cmd_purge() {
    if [[ ! -f "$KEYS_FILE" ]]; then
        log_info "密钥文件不存在，无需清理"
        return 0
    fi
    log_warn "即将永久删除所有密钥: $KEYS_FILE"
    # 非交互环境（安卓 App 子进程/管道）无法交互确认，直接拒绝，防止误删
    if [[ ! -t 0 ]]; then
        log_error "非交互环境无法确认删除，请改用: set_key.sh remove <KEY_NAME> 逐个删除"
        exit 1
    fi
    read -rp "确认删除？(yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
        rm -f "$KEYS_FILE"
        log_info "已删除密钥文件: $KEYS_FILE"
    else
        log_info "已取消"
    fi
}

# ─── 帮助 ────────────────────────────────────────────────────────────────

usage() {
    cat << 'EOF'
set_key.sh — API Key 安全管理脚本

用法：
  ./set_key.sh set    <KEY_NAME> <KEY_VALUE>   设置/更新密钥
  ./set_key.sh list                            列出所有密钥（脱敏显示）
  ./set_key.sh get    <KEY_NAME>               查看单个密钥（脱敏显示）
  ./set_key.sh remove <KEY_NAME>               删除指定密钥
  ./set_key.sh export <KEY_NAME>               输出 export 语句（供 source）
  ./set_key.sh path                            显示密钥文件路径
  ./set_key.sh purge                           清空所有密钥（需确认）

安全说明：
  - 密钥文件 ~/.api_keys/.env 权限为 600（仅当前用户可读写）
  - 日志输出自动脱敏，只显示前4位 + ****
  - KEY_NAME 格式：大写字母开头，仅含大写字母/数字/下划线

示例：
  ./set_key.sh set GITHUB_API_KEY ghp_xxxxxxxxxxxx
  ./set_key.sh set OPENWEATHER_KEY abc123def456
  ./set_key.sh list
  ./set_key.sh remove GITHUB_API_KEY
EOF
}

# ─── 入口 ────────────────────────────────────────────────────────────────

[[ $# -eq 0 ]] && { usage; exit 0; }

case "$1" in
    set)     shift; cmd_set "$@" ;;
    list)    cmd_list ;;
    get)     shift; cmd_get "$@" ;;
    remove)  shift; cmd_remove "$@" ;;
    export)  shift; cmd_export "$@" ;;
    path)    cmd_path ;;
    purge)   cmd_purge ;;
    -h|--help) usage ;;
    *)       log_error "未知命令: $1"; usage; exit 1 ;;
esac
