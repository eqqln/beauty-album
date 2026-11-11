#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
板块一键备份 端到端验证

覆盖：
  1. 1.6.0(15) 这种版本号能正确识别，激活时姓名电话真的落到板块上
  2. 板块内各表数据 + 图片能完整打进 zip
  3. data.json 只含本板块，不串别人的数据
  4. 下载接口能拿到包，包内文件齐全
"""
import io
import json
import os
import sys
import time
import uuid
import zipfile

import requests

BASE = "https://meiyan.shengka.net/meiyan-api/index.php"
ADMIN = ("admin@meiyan.local", "Meiyan@2026")

ok_count = 0
fail_count = 0


def call(route, payload=None, token=None, tenant=None, method="POST"):
    h = {"Content-Type": "application/json"}
    if token:
        h["Authorization"] = "Bearer " + token
    if tenant is not None:
        h["X-Tenant-Id"] = str(tenant)
    url = BASE + "?r=" + route
    r = requests.get(url, headers=h, timeout=60) if method == "GET" else \
        requests.post(url, headers=h, data=json.dumps(payload or {}), timeout=120)
    try:
        return r.json()
    except Exception:
        return {"ok": False, "msg": "非 JSON: " + r.text[:200]}


def check(name, cond, detail=""):
    global ok_count, fail_count
    if cond:
        ok_count += 1
        print("  [PASS] " + name + ((" · " + str(detail)) if detail else ""))
    else:
        fail_count += 1
        print("  [FAIL] " + name + ((" · " + str(detail)) if detail else ""))


def tiny_png():
    # 8x8 纯色 PNG，够 getimagesize 认出来
    import struct
    import zlib
    w = h = 8
    raw = b""
    for y in range(h):
        raw += b"\x00" + bytes([200, 120, 130] * w)
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def main():
    stamp = time.strftime("%H%M%S")
    phone = "1360013" + stamp[-4:]
    name = "备份测试" + stamp[-4:]
    dev = "EXPTEST-" + uuid.uuid4().hex[:8].upper()
    tid = 0

    print("\n=== 1. 管理员登录 ===")
    r = call("admin/login", {"email": ADMIN[0], "password": ADMIN[1]})
    if not r.get("ok"):
        print("  登录失败：" + str(r.get("msg")))
        return 1
    tok = r["data"]["token"]
    print("  OK")

    print("\n=== 2. 版本号 1.6.0(15) 必须被识别为新客户端 ===")
    r = call("admin/license-generate", {"count": 1, "duration_value": 1, "duration_unit": "年",
                                        "kind": "正式码", "note": "备份测试"}, tok)
    code = r["data"]["rows"][0]["code_raw"]
    r = call("license/redeem", {"code": code, "device_id": dev, "device_name": "备份测试机",
                                "app_version": "1.6.0(15)", "name": name, "phone": phone})
    if not r.get("ok"):
        print("  激活失败：" + str(r.get("msg")))
        return 1
    d = r["data"]
    tid = int(d.get("tenant_id") or 0)
    check("激活成功并开板块", tid > 0, tid)
    check("板块名是使用人姓名（不是「待补信息」）", d.get("owner_name") == name, d.get("owner_name"))
    check("板块手机号正确", d.get("owner_phone") == phone, d.get("owner_phone"))
    check("店名用姓名", d.get("shop_name") == name, d.get("shop_name"))

    print("\n=== 3. 往这块板里造数据 ===")
    h = {"Authorization": "Bearer " + tok, "X-Tenant-Id": str(tid)}

    # 客户
    r = call("save", {"m": "customers", "name": "客户甲", "phone": "13900001111",
                      "stage": "护理中", "progress": 40, "quoted": 1980, "note": "敏感肌"}, tok, tenant=tid)
    check("建客户", r.get("ok") is True, r.get("msg"))
    cid = (r.get("data") or {}).get("id")
    cuid = (r.get("data") or {}).get("uid")

    # 上传一张图
    url = BASE + "?r=upload"
    files = {"file": ("t.png", io.BytesIO(tiny_png()), "image/png")}
    up = requests.post(url, headers=h, files=files, timeout=60).json()
    check("上传图片", up.get("ok") is True, up.get("msg"))
    img_url = (up.get("data") or {}).get("url") or ""
    check("图片落在本板块目录", ("/uploads/t%d/" % tid) in img_url, img_url)

    # 相册
    r = call("save", {"m": "photos", "customer_id": cid, "client_uid": cuid,
                      "phase": "护理前", "url": img_url, "note": "正面"}, tok, tenant=tid)
    check("建相册记录", r.get("ok") is True, r.get("msg"))

    # 护理步骤
    r = call("save", {"m": "steps", "client_uid": cuid, "title": "清洁", "done": 1, "sort": 1}, tok, tenant=tid)
    check("建护理步骤", r.get("ok") is True, r.get("msg"))

    # 笔记
    r = call("save", {"m": "notes", "client_uid": cuid, "content": "对酒精过敏"}, tok, tenant=tid)
    check("建客户笔记", r.get("ok") is True, r.get("msg"))

    # 预约
    r = call("save", {"m": "appointments", "client_uid": cuid, "client_name": "客户甲",
                      "phone": "13900001111", "service": "深层补水", "at": "2026-11-15 10:00:00",
                      "duration": 60, "status": "待到店"}, tok, tenant=tid)
    check("建预约", r.get("ok") is True, r.get("msg"))

    # 收款
    r = call("save", {"m": "payments", "customer_id": cid, "amount": 1980, "method": "微信",
                      "status": "已收款", "paid_at": "2026-11-12 10:00:00"}, tok, tenant=tid)
    check("建收款", r.get("ok") is True, r.get("msg"))

    # 产品
    r = call("save", {"m": "products", "name": "玻尿酸精华", "brand": "测试牌", "price": 299,
                      "stock": 12, "status": "在售"}, tok, tenant=tid)
    check("建产品", r.get("ok") is True, r.get("msg"))

    print("\n=== 4. 生成备份包 ===")
    r = call("admin/tenant-export", {"id": tid}, tok)
    if not r.get("ok"):
        print("  生成失败：" + str(r.get("msg")))
        return 1
    ex = r["data"]
    print("  文件 %s · %s 条数据 · %s 个文件 · %s" % (ex["file"], ex["rows"], ex["media"], ex["size_text"]))
    check("备份包已生成", bool(ex.get("file")))
    check("行数 > 0", int(ex.get("rows") or 0) > 0, ex.get("rows"))
    check("含媒体文件", int(ex.get("media") or 0) >= 1, ex.get("media"))
    check("体积 > 0", int(ex.get("size") or 0) > 0, ex.get("size_text"))

    print("\n=== 5. 下载并检查包内容 ===")
    url = BASE + "?r=admin/tenant-export-download&id=%d&file=%s" % (tid, requests.utils.quote(ex["file"]))
    resp = requests.get(url, headers={"Authorization": "Bearer " + tok}, timeout=180)
    check("下载成功", resp.status_code == 200 and len(resp.content) > 0,
          "HTTP %d · %d 字节" % (resp.status_code, len(resp.content)))

    z = zipfile.ZipFile(io.BytesIO(resp.content))
    names = z.namelist()
    print("  包内 %d 个条目" % len(names))
    check("有 data.json", "data.json" in names)
    check("有备份说明", any(n.endswith("备份说明.txt") for n in names))
    check("有 manifest.json", "manifest.json" in names)
    csvs = [n for n in names if n.startswith("data/") and n.endswith(".csv")]
    check("CSV 数量 >= 17", len(csvs) >= 17, len(csvs))
    media = [n for n in names if n.startswith("media/")]
    check("有 media/ 文件", len(media) >= 1, media[:2])

    payload = json.loads(z.read("data.json").decode("utf-8"))
    t = payload.get("tables", {})
    check("data.json 有 customers", len(t.get("customers") or []) == 1, len(t.get("customers") or []))
    check("data.json 有 photos", len(t.get("photos") or []) == 1, len(t.get("photos") or []))
    check("data.json 有 client_steps", len(t.get("client_steps") or []) == 1)
    check("data.json 有 client_notes", len(t.get("client_notes") or []) == 1)
    check("data.json 有 appointments", len(t.get("appointments") or []) == 1)
    check("data.json 有 payments", len(t.get("payments") or []) == 1)
    check("data.json 有 products", len(t.get("products") or []) == 1)

    print("\n=== 6. 隔离：不能混进默认板块的数据 ===")
    check("客户表只有本板块 1 条（默认板块那 2 条没混进来）",
          len(t.get("customers") or []) == 1, len(t.get("customers") or []))
    check("meta.tenant_id 正确", int(payload["meta"]["tenant_id"]) == tid, payload["meta"]["tenant_id"])
    check("meta 记了归属人", payload["meta"]["tenant_name"] == name, payload["meta"]["tenant_name"])
    check("授权记录带上了", len(payload["license"]["codes"]) >= 1, len(payload["license"]["codes"]))

    # 每个 CSV 都要有表头，不能是空文件
    empty = []
    for n in csvs:
        body = z.read(n)
        if len(body) <= 3:
            empty.append(n)
    check("没有空的 CSV", not empty, empty)

    print("\n=== 7. 清理 ===")
    for row in (call("admin/license-devices", {"kw": dev}, tok).get("data") or {}).get("rows", []):
        if row.get("device_id") == dev:
            call("admin/license-device-void", {"id": row["id"]}, tok)
    r = call("admin/tenant-delete", {"id": tid}, tok)
    check("测试板块已删除", r.get("ok") is True, r.get("msg"))

    print("\n" + "=" * 46)
    print("  通过 %d 项，失败 %d 项" % (ok_count, fail_count))
    print("=" * 46)
    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
