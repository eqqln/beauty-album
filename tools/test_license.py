#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
激活码全链路回归：生成 → 兑换 → 复核 → 设备凭证同步 → 充能 → 停用 → 恢复 → 删除

用法：
    python tools/test_license.py                      # 跑完整流程，结束时清理测试数据
    python tools/test_license.py --keep               # 保留测试激活码，便于后台看界面
    python tools/test_license.py --base https://...   # 换站点

约定：测试码前缀 TST，备注带 RUN_ID，结束时按 id 删除，不留垃圾。
"""
import argparse
import json
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://meiyan.shengka.net"
API = "/meiyan-api/index.php"
ADMIN = ("admin@meiyan.local", "Meiyan@2026")

PASS, FAIL = [], []


def call(route, body=None, token=None, method=None, query=None):
    url = BASE + API + "?r=" + route
    for k, v in (query or {}).items():
        url += "&" + k + "=" + urllib.parse.quote(str(v))
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=data, headers=headers,
                                 method=method or ("POST" if data else "GET"))
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "ignore")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"ok": False, "msg": raw[:200]}


def check(name, cond, detail=""):
    if cond:
        PASS.append(name)
        print("  PASS  " + name + (("  " + detail) if detail else ""))
    else:
        FAIL.append(name)
        print("  FAIL  " + name + (("  " + detail) if detail else ""))


def main():
    global BASE
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=BASE)
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    BASE = a.base.rstrip("/")

    run_id = time.strftime("%m%d%H%M%S")
    device = "TESTDEV-" + run_id

    print("== 1. 后台登录 ==")
    st, r = call("admin/login", {"email": ADMIN[0], "password": ADMIN[1]})
    check("登录成功", st == 200 and r.get("ok"), r.get("msg", ""))
    token = (r.get("data") or {}).get("token", "")
    if not token:
        print("登录失败，后续无法继续")
        return 1
    caps = ((r["data"].get("admin") or {}).get("perm") or {}).get("caps") or {}
    check("owner 有 license 能力位", caps.get("license") is True, str(caps.get("license")))

    print("== 2. 授权概览 ==")
    st, r = call("admin/license-stats", token=token)
    d = r.get("data") or {}
    check("license-stats 可访问", st == 200 and r.get("ok"), r.get("msg", ""))
    check("返回统计字段", "codes_total" in d and "devices" in d,
          "codes_total=%s devices=%s" % (d.get("codes_total"), d.get("devices")))

    print("== 3. 生成激活码 ==")
    st, r = call("admin/license-generate", {
        "kind": "试用码", "duration_value": 1, "duration_unit": "天",
        "max_devices": 1, "count": 1, "amount": 100, "bonus": 0, "points": 10,
        "prefix": "TST", "batch": "TEST-" + run_id, "note": "回归脚本 " + run_id,
    }, token=token)
    gen = (r.get("data") or {}).get("rows") or []
    check("生成成功", st == 200 and r.get("ok") and len(gen) == 1, r.get("msg", ""))
    if not gen:
        return 1
    code = gen[0]["code_raw"]
    code_id = gen[0]["id"]
    check("码格式为 前缀+12 位", code.startswith("TST") and len(code) == 15, code)

    print("== 4. 兑换（App 首次激活）==")
    st, r = call("license/redeem", {
        "code": code, "device_id": device, "device_name": "回归测试机",
        "platform": "iOS 18.0", "app_version": "1.5.0(13)",
    })
    red = r.get("data") or {}
    check("兑换成功", st == 200 and r.get("ok"), r.get("msg", ""))
    check("签发 license_key", len(red.get("license_key") or "") >= 32, str(len(red.get("license_key") or "")))
    check("签发设备同步凭证", len(red.get("sync_token") or "") >= 20, str(len(red.get("sync_token") or "")))
    check("到期时间已计算", bool(red.get("expire_at")), str(red.get("expire_at")))
    check("剩余时长文案", bool(red.get("left_text")), str(red.get("left_text")))
    lic_key = red.get("license_key") or ""
    sync_token = red.get("sync_token") or ""
    expire_1 = red.get("expire_at") or ""

    print("== 5. 重复兑换同一张码（同一设备应复用）==")
    st, r = call("license/redeem", {"code": code, "device_id": device,
                                    "device_name": "回归测试机", "platform": "iOS 18.0",
                                    "app_version": "1.5.0(13)"})
    check("同设备重兑不占新名额", st == 200 and r.get("ok"), r.get("msg", ""))
    # 每次兑换都会换发新的 license_key，App 端要跟着覆盖本地凭证
    red2 = r.get("data") or {}
    if red2.get("license_key"):
        lic_key = red2["license_key"]
    if red2.get("sync_token"):
        sync_token = red2["sync_token"]

    print("== 6. 启动复核 ==")
    st, r = call("license/verify", {"device_id": device, "license_key": lic_key,
                                    "app_version": "1.5.0(13)"})
    v = r.get("data") or {}
    check("复核通过", st == 200 and r.get("ok") and v.get("active") is True, r.get("msg", ""))
    check("复核回传同步凭证", bool(v.get("sync_token")), str(len(v.get("sync_token") or "")))

    print("== 7. 设备凭证直接同步（不再需要登录店铺账号）==")
    st, r = call("sync/pull", token=sync_token)
    check("sync/pull 接受设备凭证", st == 200 and r.get("ok"), r.get("msg", ""))
    mods = list(((r.get("data") or {}).get("data") or {}).keys())
    check("拉取返回模块数据", len(mods) > 0, ",".join(mods[:6]))

    print("== 8. 充能续期 ==")
    st, r = call("admin/license-boost", {"id": code_id, "target": "code", "days": 7,
                                         "note": "回归充能"}, token=token)
    b = r.get("data") or {}
    check("充能成功", st == 200 and r.get("ok") and b.get("updated", 0) >= 1, r.get("msg", ""))
    st, r = call("license/verify", {"device_id": device, "license_key": lic_key})
    v2 = r.get("data") or {}
    check("到期时间被延长", (v2.get("expire_at") or "") > expire_1,
          "%s → %s" % (expire_1, v2.get("expire_at")))

    print("== 9. 停用 ==")
    st, r = call("admin/license-void", {"id": code_id, "void": 1}, token=token)
    check("停用成功", st == 200 and r.get("ok"), r.get("msg", ""))
    st, r = call("license/verify", {"device_id": device, "license_key": lic_key})
    check("停用后复核被拒", r.get("ok") is False, r.get("msg", ""))
    st, r = call("sync/pull", token=sync_token)
    check("停用后同步被拒", r.get("ok") is False, r.get("msg", ""))

    print("== 10. 恢复 ==")
    st, r = call("admin/license-void", {"id": code_id, "void": 0}, token=token)
    check("恢复成功", st == 200 and r.get("ok"), r.get("msg", ""))
    st, r = call("license/verify", {"device_id": device, "license_key": lic_key})
    check("恢复后复核通过", st == 200 and r.get("ok"), r.get("msg", ""))

    print("== 11. 设备明细 / 流水 / 导出 ==")
    st, r = call("admin/license-devices", token=token, query={"code_id": code_id})
    devs = (r.get("data") or {}).get("rows") or []
    check("设备明细可查", st == 200 and len(devs) >= 1, "设备数=%d" % len(devs))
    st, r = call("admin/license-logs", token=token)
    logs = (r.get("data") or {}).get("rows") or []
    acts = set(x.get("action") for x in logs[:40])
    check("流水记录可查", st == 200 and len(logs) > 0, "含动作：" + ",".join(sorted(a for a in acts if a)))
    st, r = call("admin/license-export", token=token)
    check("导出可查", st == 200 and len((r.get("data") or {}).get("rows") or []) > 0)

    print("== 12. 无效码拦截 ==")
    st, r = call("license/redeem", {"code": "TSTZZZZZZZZZZZZ", "device_id": device + "-x"})
    check("不存在的码被拒", r.get("ok") is False, r.get("msg", ""))

    if a.keep:
        print("\n保留测试数据：code=%s id=%s device=%s" % (code, code_id, device))
    else:
        print("== 13. 清理 ==")
        st, r = call("admin/license-delete", {"id": code_id}, token=token)
        check("删除测试码", st == 200 and r.get("ok"), r.get("msg", ""))
        st, r = call("license/verify", {"device_id": device, "license_key": lic_key})
        check("删除后授权失效", r.get("ok") is False, r.get("msg", ""))

    print("\n结果：%d 通过 / %d 失败" % (len(PASS), len(FAIL)))
    if FAIL:
        print("失败项：" + "，".join(FAIL))
        return 1
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
