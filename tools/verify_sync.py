# -*- coding: utf-8 -*-
"""端到端验证：登录 -> 拉取 -> 检查 settings/各模块 -> 推送 -> 回读"""
import json
import sys

import requests

BASE = "https://meiyan.shengka.net/meiyan-api/"
ACC = "admin@meiyan.local"
PWD = "Meiyan@2026"


def call(route, data=None, token=None, method="POST", timeout=40):
    url = BASE + "?r=" + route
    h = {}
    if token:
        h["Authorization"] = "Bearer " + token
    if method == "GET":
        r = requests.get(url, headers=h, timeout=timeout)
    else:
        r = requests.post(url, data=data, headers=h, timeout=timeout)
    try:
        return r.json()
    except Exception:
        return {"ok": False, "raw": r.text[:400], "code": r.status_code}


print("=== 1. 登录 ===")
r = call("sync/login", {"account": ACC, "password": PWD})
print(json.dumps(r, ensure_ascii=False)[:400])
if not r.get("ok"):
    sys.exit(1)
tk = r["data"]["token"]

print("\n=== 2. 拉取全量 ===")
p = call("sync/pull", token=tk, method="GET")
if not p.get("ok"):
    print(json.dumps(p, ensure_ascii=False)[:600])
    sys.exit(1)
d = p["data"]
print("顶层字段:")
for k, v in d.items():
    if isinstance(v, list):
        print("  %-14s list  %d 条" % (k, len(v)))
    elif isinstance(v, dict):
        print("  %-14s dict  %d 键" % (k, len(v)))
    else:
        print("  %-14s %s" % (k, repr(v)[:60]))

print("\n=== 3. settings 内容 ===")
st = d.get("settings")
if isinstance(st, dict):
    for k in sorted(st.keys()):
        print("  %-16s = %s" % (k, repr(st[k])[:70]))
else:
    print("  !! 没有 settings 段")

print("\n=== 4. 各模块首条样本 ===")
for k in ["customers", "photos", "steps", "notes", "claims", "payments", "appointments", "compares", "teachers", "products", "agents"]:
    v = d.get(k)
    if isinstance(v, list) and v:
        print("  [%s] %s" % (k, json.dumps(v[0], ensure_ascii=False)[:220]))
    elif isinstance(v, list):
        print("  [%s] (空)" % k)
