#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
多板块（多租户）+ 网址加密 端到端验证

跑法：python tools/test_tenant.py
"""
import json
import sys
import time
import uuid

import requests

BASE = "https://meiyan.shengka.net/meiyan-api/index.php"
ADMIN = ("admin@meiyan.local", "Meiyan@2026")

ok_count = 0
fail_count = 0
cleanup = []


def call(route, payload=None, token=None, tenant=None, method="POST"):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if tenant is not None:
        headers["X-Tenant-Id"] = str(tenant)
    url = BASE + "?r=" + route
    if method == "GET":
        r = requests.get(url, headers=headers, timeout=30)
    else:
        r = requests.post(url, headers=headers, data=json.dumps(payload or {}), timeout=30)
    try:
        j = r.json()
    except Exception:
        j = {"ok": False, "msg": "非 JSON: " + r.text[:200]}
    return j


def check(name, cond, detail=""):
    global ok_count, fail_count
    if cond:
        ok_count += 1
        print("  [PASS] " + name + ((" · " + str(detail)) if detail else ""))
    else:
        fail_count += 1
        print("  [FAIL] " + name + ((" · " + str(detail)) if detail else ""))


def main():
    stamp = time.strftime("%H%M%S")
    phone = "1380013" + stamp[-4:]
    name = "测试客户" + stamp[-4:]

    print("\n=== 0. 网址加密 ===")
    r = call("site/info", method="GET")
    d = r.get("data") or {}
    check("site/info 正常", r.get("ok") is True, r.get("msg"))
    check("url_display = encrypted", d.get("url_display") == "encrypted", d.get("url_display"))
    check("api_base 是密文不是 https://", not str(d.get("api_base", "")).startswith("http"), d.get("api_base"))

    print("\n=== 1. 管理员登录 ===")
    r = call("admin/login", {"email": ADMIN[0], "password": ADMIN[1]})
    if not r.get("ok"):
        print("  登录失败，终止：" + str(r.get("msg")))
        return 1
    tok = r["data"]["token"]
    me = r["data"]["admin"]
    print("  账号：%s  tenant_id=%s" % (me.get("email"), me.get("tenant_id")))
    check("admin_out 带 tenant_id", "tenant_id" in me, me.get("tenant_id"))

    print("\n=== 2. 板块列表（改造前） ===")
    r = call("admin/tenant-list", {}, tok)
    before = r.get("data", {}).get("rows", [])
    check("tenant-list 可用", r.get("ok") is True, r.get("msg"))
    check("默认板块 id=0 存在", any(int(x["id"]) == 0 for x in before), [x["id"] for x in before])
    print("  现有板块数：%d" % len(before))

    print("\n=== 3. 生成激活码 ===")
    r = call("admin/license-generate", {"count": 1, "duration_value": 1, "duration_unit": "年",
                                        "kind": "正式码", "note": "多板块自动化测试"}, tok)
    if not r.get("ok"):
        print("  生成失败：" + str(r.get("msg")))
        return 1
    code = r["data"]["rows"][0]["code"]
    code_raw = r["data"]["rows"][0]["code_raw"]
    print("  激活码：%s" % code)

    print("\n=== 4. 缺姓名/手机号时应被拒绝（1.6.0 客户端） ===")
    dev = "TESTDEV-" + uuid.uuid4().hex[:10].upper()
    r = call("license/redeem", {"code": code_raw, "device_id": dev, "device_name": "测试机",
                                "app_version": "1.6.0"})
    check("无姓名被拒", r.get("ok") is False and "姓名" in str(r.get("msg")), r.get("msg"))

    r = call("license/redeem", {"code": code_raw, "device_id": dev, "device_name": "测试机",
                                "app_version": "1.6.0", "name": name})
    check("无手机号被拒", r.get("ok") is False and "手机" in str(r.get("msg")), r.get("msg"))

    r = call("license/redeem", {"code": code_raw, "device_id": dev, "device_name": "测试机",
                                "app_version": "1.6.0", "name": name, "phone": "12345"})
    check("手机号格式错被拒", r.get("ok") is False, r.get("msg"))

    print("\n=== 5. 带姓名+手机号激活 → 自动开板块 ===")
    r = call("license/redeem", {"code": code_raw, "device_id": dev, "device_name": "测试机",
                                "name": name, "phone": phone, "platform": "iOS",
                                "app_version": "1.6.0"})
    if not r.get("ok"):
        print("  激活失败：" + str(r.get("msg")))
        return 1
    rd = r["data"]
    new_tid = int(rd.get("tenant_id") or 0)
    sync_token = rd.get("sync_token")
    license_key = rd.get("license_key")
    print("  新板块 id=%s  店主=%s  手机=%s" % (new_tid, rd.get("owner_name"), rd.get("owner_phone")))
    check("返回 tenant_id > 0", new_tid > 0, new_tid)
    check("owner_name 正确", rd.get("owner_name") == name, rd.get("owner_name"))
    check("owner_phone 正确", rd.get("owner_phone") == phone, rd.get("owner_phone"))
    check("shop_name 默认用姓名", rd.get("shop_name") == name, rd.get("shop_name"))
    check("首次激活 restore=false", rd.get("restore") is False, rd.get("restore"))
    check("拿到 sync_token", bool(sync_token))
    cleanup.append(("device", dev, license_key, new_tid))

    print("\n=== 6. 板块列表（改造后） ===")
    r = call("admin/tenant-list", {}, tok)
    rows = r.get("data", {}).get("rows", [])
    hit = [x for x in rows if int(x["id"]) == new_tid]
    check("新板块已出现在列表", len(hit) == 1, "共 %d 个板块" % len(rows))
    if hit:
        check("板块状态正常", hit[0].get("status") == "正常", hit[0].get("status"))
        check("板块带授权剩余", hit[0].get("license_left") not in (None, ""), hit[0].get("license_left"))

    print("\n=== 7. 数据隔离：默认板块 vs 新板块 ===")
    # 默认板块（平台账号自身 tenant_id=0）
    r = call("save", {"m": "customers", "name": "默认板块客户" + stamp, "phone": "13900000001"}, tok)
    check("默认板块建客户", r.get("ok") is True, r.get("msg"))
    default_cid = (r.get("data") or {}).get("id")

    # 新板块（带 X-Tenant-Id）
    r = call("save", {"m": "customers", "name": "新板块客户" + stamp, "phone": "13900000002"}, tok, tenant=new_tid)
    check("新板块建客户", r.get("ok") is True, r.get("msg"))
    new_cid = (r.get("data") or {}).get("id")
    if new_cid:
        check("新客户落到 tenant_id=" + str(new_tid), int(r["data"].get("tenant_id") or 0) == new_tid,
              r["data"].get("tenant_id"))

    r = call("list", {"m": "customers", "size": 200}, tok)
    ids0 = [x["id"] for x in (r.get("data") or {}).get("rows", [])]
    check("默认板块看得到自己的客户", default_cid in ids0)
    check("默认板块看不到新板块客户", new_cid not in ids0)

    r = call("list", {"m": "customers", "size": 200}, tok, tenant=new_tid)
    ids1 = [x["id"] for x in (r.get("data") or {}).get("rows", [])]
    check("新板块看得到自己的客户", new_cid in ids1)
    check("新板块看不到默认板块客户", default_cid not in ids1)

    print("\n=== 8. 跨板块越权修改应失败 ===")
    if new_cid:
        r = call("save", {"m": "customers", "id": new_cid, "name": "越权改名"}, tok)  # 默认板块去改新板块的
        still = call("list", {"m": "customers", "size": 200}, tok, tenant=new_tid)
        row = [x for x in (still.get("data") or {}).get("rows", []) if x["id"] == new_cid]
        check("跨板块改名未生效", bool(row) and row[0]["name"] != "越权改名",
              row[0]["name"] if row else "行不存在")

    print("\n=== 9. 板块设置独立 ===")
    r = call("settings/get", {}, tok, tenant=new_tid)
    sd = r.get("data") or {}
    check("settings/get 可用", r.get("ok") is True, r.get("msg"))
    check("板块回传 tenant_id", int(sd.get("tenant_id") or -1) == new_tid, sd.get("tenant_id"))
    check("板块 shop_name 跟着变", sd.get("shop_name") == name, sd.get("shop_name"))
    check("url_display 继承默认板块", sd.get("url_display") == "encrypted", sd.get("url_display"))

    print("\n=== 10. 恢复标志全链路 ===")
    r = call("admin/tenant-restore", {"id": new_tid}, tok)
    check("后台标记恢复", r.get("ok") is True, r.get("msg"))

    r = call("license/verify", {"device_id": dev, "license_key": license_key, "app_version": "1.6.0"})
    check("verify 返回 restore=true", r.get("ok") is True and r["data"].get("restore") is True,
          r.get("msg") or (r.get("data") or {}).get("restore"))
    check("verify 回传 tenant_id", int((r.get("data") or {}).get("tenant_id") or 0) == new_tid)

    r = call("license/restore-ack", {}, token=sync_token)
    check("restore-ack 成功", r.get("ok") is True, r.get("msg"))

    r = call("license/verify", {"device_id": dev, "license_key": license_key, "app_version": "1.6.0"})
    check("恢复后标志已清", (r.get("data") or {}).get("restore") is False, (r.get("data") or {}).get("restore"))

    print("\n=== 11. 同一手机号再激活 → 复用板块不新建 ===")
    r = call("admin/license-generate", {"count": 1, "duration_value": 1, "duration_unit": "年",
                                        "kind": "正式码", "note": "多板块复用测试"}, tok)
    code2 = r["data"]["rows"][0]["code_raw"] if r.get("ok") else None
    if code2:
        dev2 = "TESTDEV-" + uuid.uuid4().hex[:10].upper()
        r = call("license/redeem", {"code": code2, "device_id": dev2, "device_name": "测试机2",
                                    "name": name, "phone": phone})
        check("同手机号激活成功", r.get("ok") is True, r.get("msg"))
        check("复用原板块而不是新建", int((r.get("data") or {}).get("tenant_id") or 0) == new_tid,
              (r.get("data") or {}).get("tenant_id"))
        cleanup.append(("device2", dev2, (r.get("data") or {}).get("license_key"), new_tid))

    print("\n=== 12. 停用板块后设备复核被拒 ===")
    r = call("admin/tenant-save", {"id": new_tid, "status": "停用"}, tok)
    check("停用板块", r.get("ok") is True, r.get("msg"))
    r = call("license/verify", {"device_id": dev, "license_key": license_key, "app_version": "1.6.0"})
    check("停用后 verify 被拒", r.get("ok") is False and "停用" in str(r.get("msg")), r.get("msg"))
    r = call("admin/tenant-save", {"id": new_tid, "status": "正常"}, tok)
    check("恢复板块", r.get("ok") is True, r.get("msg"))

    print("\n=== 13. 网址显示方式可切换 ===")
    r = call("settings/save", {"url_display": "plain"}, tok)
    check("切到明文", r.get("ok") is True, r.get("msg"))
    r = call("site/info", method="GET")
    d = r.get("data") or {}
    check("明文时 api_base 是 http(s)", str(d.get("api_base", "")).startswith("http"), d.get("api_base"))
    check("明文时 api_base_enc 仍是密文", not str(d.get("api_base_enc", "")).startswith("http"))

    r = call("settings/save", {"url_display": "encrypted"}, tok)
    check("切回加密", r.get("ok") is True, r.get("msg"))
    r = call("site/info", method="GET")
    d = r.get("data") or {}
    check("加密时 api_base 是密文", not str(d.get("api_base", "")).startswith("http"), d.get("api_base"))

    print("\n=== 13.5 旧版客户端（1.5.1）兼容 ===")
    r = call("admin/license-generate", {"count": 2, "duration_value": 1, "duration_unit": "年",
                                        "kind": "正式码", "note": "旧客户端兼容测试"}, tok)
    codes = [x["code_raw"] for x in r["data"]["rows"]] if r.get("ok") else []
    old_tid = 0
    olddev = "OLD151-" + uuid.uuid4().hex[:8].upper()
    if len(codes) == 2:
        r = call("license/redeem", {"code": codes[0], "device_id": olddev,
                                    "device_name": "旧版机", "app_version": "1.5.1"})
        check("1.5.1 仍能激活", r.get("ok") is True, r.get("msg"))
        old_tid = int((r.get("data") or {}).get("tenant_id") or 0)
        old_name = str(((r.get("data") or {}).get("tenant") or {}).get("name") or "")
        check("老客户端单独开板（不进默认板块）", old_tid > 0, old_tid)
        check("板名标了待补信息", "待补" in old_name, old_name)

        r = call("license/redeem", {"code": codes[1], "device_id": olddev,
                                    "device_name": "旧版机", "app_version": "1.6.0",
                                    "name": "升级用户", "phone": "13700137000"})
        d = r.get("data") or {}
        check("升级后复用原来那块板", int(d.get("tenant_id") or 0) == old_tid, d.get("tenant_id"))
        check("升级后补上姓名电话", d.get("owner_name") == "升级用户" and d.get("owner_phone") == "13700137000",
              "%s / %s" % (d.get("owner_name"), d.get("owner_phone")))

    print("\n=== 14. 清理测试数据 ===")
    # 解绑测试设备
    for item in cleanup:
        _, d_, _k, tid_ = item
        r = call("admin/license-devices", {"kw": d_}, tok)
        for row in (r.get("data") or {}).get("rows", []):
            if row.get("device_id") == d_:
                call("admin/license-device-void", {"id": row["id"]}, tok)
                print("  已解绑设备 %s" % d_)
    # 删客户
    if default_cid:
        call("delete", {"m": "customers", "id": default_cid}, tok)
    if new_cid:
        call("delete", {"m": "customers", "id": new_cid}, tok, tenant=new_tid)
        print("  已删除测试客户")
    # 删板块
    r = call("admin/tenant-delete", {"id": new_tid}, tok)
    check("测试板块已删除", r.get("ok") is True, r.get("msg"))

    # 旧客户端那块板
    if old_tid > 0:
        r = call("admin/license-devices", {"kw": olddev}, tok)
        for row in (r.get("data") or {}).get("rows", []):
            if row.get("device_id") == olddev:
                call("admin/license-device-void", {"id": row["id"]}, tok)
        r = call("admin/tenant-delete", {"id": old_tid}, tok)
        check("旧客户端测试板块已删除", r.get("ok") is True, r.get("msg"))

    print("\n" + "=" * 46)
    print("  通过 %d 项，失败 %d 项" % (ok_count, fail_count))
    print("=" * 46)
    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
