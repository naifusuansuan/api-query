#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
set_key.py — API Key 管理脚本（Python 跨平台版）

平台支持：Windows 原生 / iPhone（a-Shell 等） / macOS / Linux
（Linux/macOS/Android 用户也可用功能等价的 set_key.sh）

功能：安全地存储、查看、删除 API Key
  - 密钥文件位置：~/.api_keys/.env（POSIX 权限 600；Windows 上尽力而为）
  - 日志输出自动脱敏，绝不打印完整 API-Key，只显示前4位 + ****

用法：
  python set_key.py set    <KEY_NAME> <KEY_VALUE>   # 设置/更新密钥
  python set_key.py list                            # 列出所有密钥（脱敏显示值）
  python set_key.py get    <KEY_NAME>               # 查看单个密钥（脱敏显示）
  python set_key.py remove <KEY_NAME>               # 删除密钥
  python set_key.py export <KEY_NAME>               # 输出 export 语句（供 source）
  python set_key.py path                            # 显示密钥文件路径
"""

import os
import re
import stat
import sys

HOME = os.path.expanduser("~")
KEYS_DIR = os.path.join(HOME, ".api_keys")
KEYS_FILE = os.path.join(KEYS_DIR, ".env")

IS_WINDOWS = os.name == "nt"
IS_TTY = sys.stdout.isatty()


def _c(code, text):
    return f"\033[{code}m{text}\033[0m" if IS_TTY else str(text)

def log_info(msg):
    print(_c("32", "[INFO]") + "  " + msg, file=sys.stderr)

def log_warn(msg):
    print(_c("33", "[WARN]") + "  " + msg, file=sys.stderr)

def log_error(msg):
    print(_c("31", "[ERROR]") + " " + msg, file=sys.stderr)


def mask_secret(val):
    val = str(val)
    if len(val) <= 8:
        return "****"
    return val[:4] + "****"


def ensure_keys_file():
    created = False
    if not os.path.isdir(KEYS_DIR):
        os.makedirs(KEYS_DIR, exist_ok=True)
        if not IS_WINDOWS:
            os.chmod(KEYS_DIR, 0o700)
        log_info(f"创建密钥目录: {KEYS_DIR} (权限 700)")
        created = True
    if not os.path.isfile(KEYS_FILE):
        with open(KEYS_FILE, "a", encoding="utf-8"):
            pass
        if not IS_WINDOWS:
            os.chmod(KEYS_FILE, 0o600)
        log_info(f"创建密钥文件: {KEYS_FILE} (权限 600)")
        created = True
    return created


def read_all_keys():
    """读取全部密钥，返回 dict（保持文件顺序用 list of tuples）"""
    result = []
    if not os.path.isfile(KEYS_FILE):
        return result
    with open(KEYS_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
            if not m:
                continue
            name, value = m.group(1), m.group(2)
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                value = value[1:-1]
            result.append((name, value))
    return result


def write_all_keys(keys):
    with open(KEYS_FILE, "w", encoding="utf-8") as f:
        for name, value in keys:
            f.write(f"{name}='{value}'\n")
    if not IS_WINDOWS:
        os.chmod(KEYS_FILE, 0o600)


def file_perms():
    if IS_WINDOWS:
        return "N/A (Windows)"
    try:
        return oct(stat.S_IMODE(os.stat(KEYS_FILE).st_mode))[-3:]
    except OSError:
        return "???"


def cmd_set(args):
    if len(args) < 2:
        log_error("用法: set_key.py set <KEY_NAME> <KEY_VALUE>")
        print("示例: python set_key.py set GITHUB_API_KEY ghp_xxxxxxxxxxxx", file=sys.stderr)
        return 1
    key_name, key_value = args[0], args[1]
    if not re.match(r"^[A-Z][A-Z0-9_]*$", key_name):
        log_error("KEY_NAME 必须为大写字母开头，仅含大写字母/数字/下划线")
        print("正确示例: GITHUB_API_KEY, OPENWEATHER_KEY", file=sys.stderr)
        return 1
    ensure_keys_file()
    keys = read_all_keys()
    if any(k == key_name for k, _ in keys):
        log_warn(f"覆盖已存在的密钥: {key_name}")
        keys = [(k, v) for k, v in keys if k != key_name]
    keys.append((key_name, key_value))
    write_all_keys(keys)
    log_info(f"密钥已保存: {key_name} = {mask_secret(key_value)}")
    log_info(f"存储位置: {KEYS_FILE} (权限 {file_perms()})")
    return 0


def cmd_list(_args):
    keys = read_all_keys()
    if not keys:
        log_info("暂无已存储的密钥")
        log_info("使用 'python set_key.py set <KEY_NAME> <KEY_VALUE>' 添加密钥")
        return 0
    print(_c("36", "已存储的 API Key："))
    print("─" * 50)
    print(f"{'KEY_NAME':<25}  VALUE (脱敏)")
    print("─" * 50)
    for name, value in keys:
        print(f"{name:<25}  {mask_secret(value)}")
    print("─" * 50)
    log_info(f"文件路径: {KEYS_FILE} (权限 {file_perms()})")
    return 0


def cmd_get(args):
    if not args:
        log_error("用法: set_key.py get <KEY_NAME>")
        return 1
    key_name = args[0]
    for name, value in read_all_keys():
        if name == key_name:
            print(f"{key_name} = {mask_secret(value)}")
            return 0
    log_error(f"密钥 '{key_name}' 不存在")
    return 1


def cmd_remove(args):
    if not args:
        log_error("用法: set_key.py remove <KEY_NAME>")
        return 1
    key_name = args[0]
    keys = read_all_keys()
    if not any(k == key_name for k, _ in keys):
        log_error(f"密钥 '{key_name}' 不存在")
        return 1
    write_all_keys([(k, v) for k, v in keys if k != key_name])
    log_info(f"已删除密钥: {key_name}")
    return 0


def cmd_export(args):
    if not args:
        log_error("用法: set_key.py export <KEY_NAME>")
        return 1
    key_name = args[0]
    for name, value in read_all_keys():
        if name == key_name:
            print(f"export {key_name}='{value}'")
            return 0
    log_error(f"密钥 '{key_name}' 不存在")
    return 1


def cmd_path(_args):
    print(KEYS_FILE)
    return 0


USAGE = """set_key.py — API Key 安全管理脚本（Python 跨平台版）

用法：
  python set_key.py set    <KEY_NAME> <KEY_VALUE>   设置/更新密钥
  python set_key.py list                            列出所有密钥（脱敏显示）
  python set_key.py get    <KEY_NAME>               查看单个密钥（脱敏显示）
  python set_key.py remove <KEY_NAME>               删除指定密钥
  python set_key.py export <KEY_NAME>               输出 export 语句（供 source）
  python set_key.py path                            显示密钥文件路径

安全说明：
  - 密钥文件 ~/.api_keys/.env 权限为 600（Windows 上为普通文件 ACL）
  - 日志输出自动脱敏，只显示前4位 + ****
  - KEY_NAME 格式：大写字母开头，仅含大写字母/数字/下划线

示例：
  python set_key.py set GITHUB_API_KEY ghp_xxxxxxxxxxxx
  python set_key.py list
  python set_key.py remove GITHUB_API_KEY
"""


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(USAGE)
        return 0
    cmd, rest = args[0], args[1:]
    table = {
        "set": cmd_set, "list": cmd_list, "get": cmd_get,
        "remove": cmd_remove, "export": cmd_export, "path": cmd_path,
    }
    if cmd not in table:
        log_error(f"未知命令: {cmd}")
        print(USAGE, file=sys.stderr)
        return 1
    return table[cmd](rest)


if __name__ == "__main__":
    sys.exit(main())
