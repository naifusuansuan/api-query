#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
express_query.py — 快递100 快递轨迹查询（自动识别快递公司，Python 版）

依赖密钥（通过 set_key.py 管理，注册 https://api.kuaidi100.com/register 免费获取）：
  KUAIDI100_CUSTOMER   企业授权 Customer
  KUAIDI100_KEY        授权 Key

用法：
  python express_query.py <单号>                        # 自动识别快递公司
  python express_query.py <单号> <公司编码>              # 指定公司
  python express_query.py <单号> <公司编码> <手机后4位>   # 顺丰/中通等需手机号
  python express_query.py --com                         # 查看公司编码表

零第三方依赖：仅用 urllib / hashlib / json 标准库。
"""
import sys
import json
import hashlib
import urllib.request
import urllib.parse
import os

# ─── 跨平台密钥文件定位 ────────────────────────────────────────────────────
if os.name == "nt":
    HOME = os.environ.get("USERPROFILE", os.path.expanduser("~"))
else:
    HOME = os.environ.get("HOME") or "/data/data/com.termux/files/home"
KEYS_FILE = os.path.join(HOME, ".api_keys", ".env")

QUERY_URL = "https://poll.kuaidi100.com/poll/query.do"
AUTO_URL = "https://extapi.kuaidi100.com/autonumber/auto"

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

COM_TABLE = """常用快递公司编码表（完整表见 https://api.kuaidi100.com/manager/openapi/download/kdbm.do）
──────────────────────────────────────────────────
  编码        快递公司
──────────────────────────────────────────────────
  sf          顺丰速运        yto         圆通速运
  zto         中通快递        sto         申通快递
  yunda       韵达快递        ems         EMS
  jd          京东快递        deppon      德邦快递
  htky        百世快递        jtexpress   极兔速递
──────────────────────────────────────────────────
* 顺丰/中通查询通常需收/寄件人手机号后4位"""


def read_key(name):
    """从 ~/.api_keys/.env 读取密钥（与 set_key.py / set_key.sh 格式兼容）"""
    try:
        with open(KEYS_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith(name + "="):
                    val = line[len(name) + 1:].strip()
                    if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
                        val = val[1:-1]
                    return val
    except OSError:
        pass
    return None


def http_post(url, data, timeout=30):
    """发送 x-www-form-urlencoded POST，返回响应文本"""
    body = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def http_get(url, params, timeout=15):
    """发送 GET，返回响应文本"""
    full = url + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(full, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def detect_com(num, key):
    """调 autonumber 接口自动识别快递公司编码"""
    try:
        raw = http_get(AUTO_URL, {"num": num, "key": key})
        data = json.loads(raw)
        if isinstance(data, list) and data:
            return data[0].get("com", "")
    except Exception:
        pass
    return ""


def format_result(raw):
    """解析查询结果，人类可读输出"""
    try:
        data = json.loads(raw)
    except Exception:
        print(raw)
        return 1

    if data.get("status") == "200" or "data" in data:
        state = STATE_MAP.get(str(data.get("state", "?")), str(data.get("state", "?")))
        print("快递公司: {}    单号: {}".format(data.get("com", "?"), data.get("nu", "?")))
        print("当前状态: {}".format(state))
        print("─" * 52)
        for i, t in enumerate(data.get("data") or []):
            mark = "●最新" if i == 0 else "      "
            print("{}  {}".format(mark, t.get("ftime") or t.get("time", "")))
            status = t.get("status", "")
            if status:
                print("        [{}]".format(status))
            print("        {}".format(t.get("context", "")))
            print()
        return 0
    else:
        code = str(data.get("returnCode", ""))
        print("查询失败 [{}]".format(code))
        print(ERR_MAP.get(code, data.get("message", "未知错误")))
        return 1


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if args[0] in ("--com", "-c"):
        print(COM_TABLE)
        return 0
    if len(args) > 3:
        print("用法: python express_query.py <单号> [公司编码] [手机后4位]")
        return 1

    num = args[0]
    com = args[1] if len(args) >= 2 else ""
    phone = args[2] if len(args) >= 3 else ""

    # 单号基本校验
    if not (6 <= len(num) <= 32) or not num.isalnum():
        print("[ERROR] 快递单号格式应为 6-32 位字母数字: {}".format(num))
        return 1

    customer = read_key("KUAIDI100_CUSTOMER")
    key = read_key("KUAIDI100_KEY")
    if not customer or not key:
        print("[ERROR] 缺少快递100 密钥（KUAIDI100_CUSTOMER / KUAIDI100_KEY）")
        print()
        print("获取步骤：")
        print("  1. 注册 https://api.kuaidi100.com/register（免费）")
        print("  2. 登录后进入 企业管理后台 → 我的信息 → 企业信息，查看 Customer 和 Key")
        print("  3. 执行以下命令配置：")
        print("     python set_key.py set KUAIDI100_CUSTOMER <你的Customer>")
        print("     python set_key.py set KUAIDI100_KEY      <你的授权Key>")
        return 1

    if not com:
        print("[INFO]  未指定快递公司，自动识别单号 {} ...".format(num))
        com = detect_com(num, key)
        if not com:
            print("[WARN]  无法自动识别快递公司，请手动指定公司编码（--com 查看编码表）")
            return 1
        print("[INFO]  识别结果: {}".format(com))

    # 构造 param 与签名
    param = {"com": com, "num": num, "resultv2": "4"}
    if phone:
        param["phone"] = phone
    param_json = json.dumps(param, separators=(",", ":"), ensure_ascii=False)
    sign = hashlib.md5((param_json + key + customer).encode("utf-8")).hexdigest().upper()

    print("[INFO]  查询 {} 单号 {} ...".format(com, num))
    try:
        resp = http_post(QUERY_URL, {
            "customer": customer,
            "sign": sign,
            "param": param_json,
        })
    except Exception as e:
        print("[ERROR] 请求失败: {}".format(e))
        return 1

    if not resp:
        print("[ERROR] 接口返回为空，请稍后重试")
        return 1

    return format_result(resp)


if __name__ == "__main__":
    sys.exit(main())
