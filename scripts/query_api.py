#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
query_api.py — 通用接口查询脚本（Python 跨平台版）

平台支持：Windows 原生（python query_api.py）/ iPhone（a-Shell 等 python3 环境）
         以及任何有 Python 3.6+ 的系统（macOS / Linux 亦可直接用本脚本）
（Linux/macOS/WSL/Git Bash/Android 用户也可用功能等价的 query_api.sh）

功能：通过预设配置或命令行参数发送 HTTP 请求，返回响应数据
优先级：命令行参数 > 环境变量 > config.json 预设配置

用法：
  # 1. 按预设名调用
  python query_api.py --preset weather

  # 2. 预设 + 命令行覆盖
  python query_api.py --preset github_repo --url "https://api.github.com/repos/microsoft/vscode"

  # 3. 完全命令行模式
  python query_api.py --url "https://api.example.com/data" --query "q=test&page=1"

  # 4. POST 请求
  python query_api.py --url "https://api.example.com/create" --method POST \
      --header "Content-Type: application/json" --body '{"name":"test"}'

安全说明：
  - config.json 中的 {env:VAR_NAME} 会被替换为对应环境变量值
  - 密钥从 ~/.api_keys/.env 自动加载（POSIX 权限 600，Windows 上尽力而为）
  - 日志输出自动脱敏，绝不打印完整 API-Key
"""

import argparse
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# ─── 常量 ─────────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(SCRIPT_DIR, "config.json")
HOME = os.path.expanduser("~")
KEYS_FILE = os.path.join(HOME, ".api_keys", ".env")
MAX_RETRIES = 2
RETRY_DELAY = 2
TIMEOUT = 30

IS_TTY = sys.stdout.isatty()

# ─── 输出与脱敏 ───────────────────────────────────────────────────────────

def _c(code, text):
    return f"\033[{code}m{text}\033[0m" if IS_TTY else str(text)

def log_info(msg):
    print(_c("32", "[INFO]") + "  " + msg, file=sys.stderr)

def log_warn(msg):
    print(_c("33", "[WARN]") + "  " + msg, file=sys.stderr)

def log_error(msg):
    print(_c("31", "[ERROR]") + " " + msg, file=sys.stderr)

def log_debug(msg):
    if ARGS_DEBUG:
        print(_c("36", "[DEBUG]") + " " + msg, file=sys.stderr)

ARGS_DEBUG = False

def mask_secret(val):
    """脱敏：只显示前4位 + ****"""
    val = str(val)
    if len(val) <= 8:
        return "****"
    return val[:4] + "****"

def mask_headers(headers):
    """脱敏 header 列表中的鉴权值"""
    masked = []
    for h in headers:
        name, _, value = h.partition(":")
        if re.search(r"(authorization|token|key|secret)", name, re.IGNORECASE):
            masked.append(f"{name}: {mask_secret(value.strip())}")
        else:
            masked.append(h)
    return "\n".join(masked)

def mask_url(url):
    """脱敏 URL query 中的敏感参数（key/apikey/token/secret/sign 等）"""
    def repl(m):
        prefix, val = m.group(1), m.group(2)
        if len(val) > 8:
            return prefix + val[:4] + "****"
        return prefix + "****"
    return re.sub(
        r"([?&](?:key|apikey|api_key|appkey|access_key|token|access_token|secret|sign|signature)=)([^&]*)",
        repl, url, flags=re.IGNORECASE)

# ─── 配置加载 ─────────────────────────────────────────────────────────────

def load_keys():
    """加载 ~/.api_keys/.env 中的 KEY=VALUE 到环境变量"""
    if not os.path.isfile(KEYS_FILE):
        log_debug(f"未找到密钥文件 {KEYS_FILE}（非必须，仅预设配置引用环境变量时需要）")
        return
    log_debug(f"加载密钥文件: {KEYS_FILE}")
    try:
        with open(KEYS_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
                if not m:
                    continue
                name, value = m.group(1), m.group(2)
                # 去除包裹引号
                if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                    value = value[1:-1]
                os.environ[name] = value
    except OSError as e:
        log_warn(f"读取密钥文件失败: {e}")

def load_config():
    """加载 config.json，返回 dict（失败返回空 dict）"""
    if not os.path.isfile(CONFIG_FILE):
        return {}
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        log_error(f"解析 config.json 失败: {e}")
        return {}

def substitute_env_vars(text):
    """替换字符串中的 {env:VAR_NAME} 为环境变量值"""
    def replacer(m):
        return os.environ.get(m.group(1), "")
    return re.sub(r"\{env:([A-Za-z_][A-Za-z0-9_]*)\}", replacer, str(text))

def list_presets():
    config = load_config()
    if not config:
        log_warn(f"配置文件不存在或为空: {CONFIG_FILE}")
        return
    print(_c("36", "可用预设接口："))
    for name, cfg in config.items():
        if name.startswith("_") or not isinstance(cfg, dict):
            continue
        url = cfg.get("url", "N/A")
        method = cfg.get("method", "GET")
        desc = cfg.get("desc", "")
        print(f"  {name:<20}  [{method:<6}]  {url}")
        if desc:
            print(f"  {'':<20}           {desc}")

# ─── 参数去重（命令行优先，first-wins）────────────────────────────────────

def dedupe_pairs(items, sep_key="="):
    """同名 key 保留首次出现（命令行参数在列表前部，即命令行优先）"""
    seen = set()
    result = []
    for item in items:
        key = item.split(sep_key, 1)[0]
        if key not in seen:
            seen.add(key)
            result.append(item)
    return result

def dedupe_headers(headers):
    """同名 header（大小写不敏感）保留首次出现"""
    seen = set()
    result = []
    for h in headers:
        name = h.split(":", 1)[0].strip().lower()
        if name not in seen:
            seen.add(name)
            result.append(h)
    return result

# ─── HTTP 请求 ────────────────────────────────────────────────────────────

def build_request(url, method, headers, body):
    req = urllib.request.Request(url, method=method.upper())
    for h in headers:
        name, _, value = h.partition(":")
        if name and value:
            req.add_header(name.strip(), value.strip())
    data = None
    if body:
        data = body.encode("utf-8")
        if not req.has_header("Content-type"):
            req.add_header("Content-Type", "application/json")
    return req, data

def send_request(url, method, headers, body):
    """发送请求，带重试与统一错误处理。成功返回响应文本，失败返回 None。"""
    ssl_ctx = ssl.create_default_context()
    # 个别旧系统（iOS a-Shell 等）可能需要放宽 TLS；默认仍走系统信任链
    attempt = 0
    while attempt <= MAX_RETRIES:
        attempt += 1
        log_debug(f"发送请求 (尝试 {attempt}/{MAX_RETRIES + 1})")
        try:
            req, data = build_request(url, method, headers, body)
            with urllib.request.urlopen(req, data=data, timeout=TIMEOUT, context=ssl_ctx) as resp:
                raw = resp.read()
                charset = resp.headers.get_content_charset() or "utf-8"
                try:
                    return raw.decode(charset, errors="replace")
                except LookupError:
                    return raw.decode("utf-8", errors="replace")

        except urllib.error.HTTPError as e:
            body_text = ""
            try:
                body_text = e.read().decode("utf-8", errors="replace")
            except Exception:
                pass
            code = e.code
            log_debug(f"HTTP 状态码: {code}")
            if code in (200, 201, 202, 204):
                return body_text
            if code in (301, 302, 307, 308):
                log_warn(f"HTTP {code}：重定向（未自动跟随）")
                return body_text
            if code == 400:
                log_error("HTTP 400：请求参数错误（Bad Request）")
            elif code == 401:
                log_error("HTTP 401：鉴权失败 — 请检查 API-Key 是否正确")
                log_info("提示：使用 set_key.py set <KEY_NAME> <value> 设置密钥")
            elif code == 403:
                log_error("HTTP 403：权限不足 — API-Key 无权访问此接口，或密钥已过期")
            elif code == 404:
                log_error("HTTP 404：接口路径不存在 — 请检查 URL 是否正确")
            elif code == 429:
                log_error("HTTP 429：触发限流 — 请求频率过高，请稍后重试")
                if attempt <= MAX_RETRIES:
                    log_warn(f"{RETRY_DELAY}s 后重试...")
                    time.sleep(RETRY_DELAY)
                    continue
            elif code >= 500:
                log_warn(f"HTTP {code}：服务器端错误")
                if attempt <= MAX_RETRIES:
                    log_warn(f"{RETRY_DELAY}s 后重试...")
                    time.sleep(RETRY_DELAY)
                    continue
                log_error("重试已用尽")
            else:
                log_warn(f"HTTP {code}：未预期的状态码")
                return body_text
            if body_text:
                print(body_text, file=sys.stderr)
            return None

        except urllib.error.URLError as e:
            reason = e.reason
            if isinstance(reason, ssl.SSLError) or "SSL" in str(reason):
                log_error(f"SSL 错误：{reason}")
            elif "timed out" in str(reason).lower() or "timeout" in str(reason).lower():
                log_error(f"请求超时：超过 {TIMEOUT}s 超时限制")
            elif hasattr(reason, "errno") and reason.errno == -2:
                log_error(f"DNS 解析失败：无法解析主机名")
            elif "refused" in str(reason).lower():
                log_error("连接失败：无法连接到服务器（检查网络或端口）")
            else:
                log_error(f"网络错误：{reason}")
            return None
        except Exception as e:
            log_error(f"请求异常：{e}")
            return None
    log_error(f"重试 {MAX_RETRIES} 次后仍失败")
    return None

# ─── 主流程 ───────────────────────────────────────────────────────────────

def main():
    global ARGS_DEBUG

    parser = argparse.ArgumentParser(
        prog="query_api.py",
        description="通用接口查询脚本（Python 跨平台版：Windows/iPhone/macOS/Linux）",
        epilog="优先级：命令行参数 > 环境变量 > config.json 预设配置",
        add_help=True)
    parser.add_argument("-p", "--preset", help="使用 config.json 中的预设配置")
    parser.add_argument("-u", "--url", help="请求 URL（命令行优先）")
    parser.add_argument("-m", "--method", default="GET", help="HTTP 方法，默认 GET")
    parser.add_argument("-H", "--header", action="append", default=[], metavar='"K: V"',
                        help="附加请求头（可多次指定）")
    parser.add_argument("-d", "--body", default="", help="请求体（POST/PUT 用）")
    parser.add_argument("-q", "--query", action="append", default=[], metavar="K=V",
                        help="查询参数（可多次指定，或用 K=V&K2=V2）")
    parser.add_argument("-r", "--raw", action="store_true", help="原始输出（不格式化 JSON）")
    parser.add_argument("--debug", action="store_true", help="启用调试日志")
    parser.add_argument("-l", "--list", action="store_true", help="列出所有可用预设")

    args = parser.parse_args()
    ARGS_DEBUG = args.debug

    if args.list:
        list_presets()
        return 0

    # 加载密钥与预设
    load_keys()

    url = args.url or ""
    method = args.method or "GET"
    explicit_method = args.method is not None
    headers = list(args.header)
    body = args.body or ""
    query_params = list(args.query)

    if args.preset:
        log_info(f"使用预设: {args.preset}")
        config = load_config()
        preset = config.get(args.preset)
        if not isinstance(preset, dict):
            log_error(f"预设 '{args.preset}' 不存在于 config.json 中")
            log_info("可用预设：")
            list_presets()
            return 1
        if not url:
            url = preset.get("url", "")
        if not explicit_method:
            method = preset.get("method", "GET") or "GET"
        for k, v in (preset.get("headers") or {}).items():
            headers.append(f"{k}: {v}")
        if not body:
            b = preset.get("body", "")
            body = b if isinstance(b, str) else json.dumps(b)
        for k, v in (preset.get("params") or {}).items():
            query_params.append(f"{k}={v}")

    # 去重：命令行优先（first-wins，命令行参数在列表前部）
    deduped_q = []
    for q in query_params:
        for pair in q.split("&"):
            if pair:
                deduped_q.append(pair)
    query_params = dedupe_pairs(deduped_q)
    headers = dedupe_headers(headers)

    if not url:
        log_error("未指定 URL。请使用 --url 或 --preset 参数")
        return 1

    # {env:VAR} 替换
    url = substitute_env_vars(url)
    body = substitute_env_vars(body)
    headers = [substitute_env_vars(h) for h in headers]
    query_params = [substitute_env_vars(q) for q in query_params]

    # 拼接 query string
    if query_params:
        qs = "&".join(query_params)
        url = url + ("&" if "?" in url else "?") + qs

    # 调试输出（脱敏）
    log_debug(f"Method: {method}")
    log_debug(f"URL: {mask_url(url)}")
    if headers:
        log_debug("Headers:\n" + mask_headers(headers))
    if body:
        log_debug(f"Body: {body}")

    # 发送请求
    response = send_request(url, method, headers, body)
    if response is None:
        return 1

    if not response:
        log_info("请求成功，响应为空")
        return 0

    if args.raw:
        print(response)
        return 0

    # 尝试格式化 JSON
    try:
        parsed = json.loads(response)
        print(json.dumps(parsed, indent=2, ensure_ascii=False))
    except (json.JSONDecodeError, ValueError):
        log_warn("响应非 JSON 格式，原样输出原始文本")
        print(response)
    return 0

if __name__ == "__main__":
    sys.exit(main())
