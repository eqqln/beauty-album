# -*- coding: utf-8 -*-
"""员工权限回归：角色预设、越权拦截、删除保护"""
import json
import os
import urllib.request

BASE = "https://meiyan.shengka.net/meiyan-api/"
OWNER = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_tok.txt")).read().strip()

PASS = 0
FAIL = 0


def call(route, body=None, token=OWNER, method="POST"):
    data = None
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(BASE + "?r=" + route, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode("utf-8", "replace"))
        except Exception:
            return e.code, {}


def check(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  PASS  %s" % name)
    else:
        FAIL += 1
        print("  FAIL  %s   %s" % (name, extra))


print("== 1. 角色预设")
st, r = call("staff/roles")
roles = (r.get("data") or {}).get("roles") or []
check("staff/roles 返回 5 个角色", len(roles) == 5, "got %d" % len(roles))
print("     角色:", ", ".join("%s(%s)" % (x.get("label"), x.get("key")) for x in roles))

print("== 2. 新建美容师账号")
email = "qa_therapist@meiyan.local"
st, r = call("staff/save", {"email": email, "name": "QA美容师", "role": "therapist",
                            "password": "Qa@2026pass", "status": "正常"})
check("staff/save 成功", r.get("ok") is True, json.dumps(r, ensure_ascii=False)[:200])

st, r = call("staff/list")
staff = (r.get("data") or []) if isinstance(r.get("data"), list) else (r.get("data") or {}).get("list") or []
newbie = [x for x in staff if x.get("email") == email]
check("staff/list 能查到新账号", len(newbie) == 1)
if newbie:
    p = newbie[0].get("perm") or {}
    mods = p.get("modules") or []
    caps = p.get("caps") or {}
    check("美容师有客户模块", "customers" in mods, str(mods))
    check("美容师没有员工模块", "staff" not in mods, str(mods))
    check("美容师没有 settings 能力", caps.get("settings") is not True, str(caps))
    check("美容师有 write 能力", caps.get("write") is True, str(caps))

print("== 3. 用美容师账号登录")
st, r = call("sync/login", {"account": email, "password": "Qa@2026pass"})
t2 = ((r.get("data") or {}).get("token")) or ""
check("登录成功拿到 token", bool(t2), json.dumps(r, ensure_ascii=False)[:200])

print("== 4. 越权拦截")
if t2:
    cases = [
        ("staff/list", {}, 403, "看员工列表"),
        ("staff/save", {"email": "x@y.z", "role": "owner"}, 403, "改员工权限"),
        ("settings/save", {"shop_name": "被改了"}, 403, "改店铺设置"),
        ("sms/providers", {}, 403, "看短信配置"),
        ("admin/backup-create", {}, 403, "导出全库备份"),
        ("admin/recharge-generate", {"count": 1, "amount": 100}, 403, "生成充值卡"),
        ("list", {"m": "payments"}, 403, "看收款记录"),
    ]
    for route, body, want, label in cases:
        st, r = call(route, body, token=t2)
        check("%s 被拦（%d）" % (label, want), st == want or r.get("ok") is False,
              "http=%d %s" % (st, json.dumps(r, ensure_ascii=False)[:120]))

    for route, body, label in [
        ("list", {"m": "customers"}, "看客户"),
        ("list", {"m": "appointments"}, "看预约"),
        ("list", {"m": "products"}, "看产品"),
        ("settings/get", {}, "读店铺设置"),
    ]:
        st, r = call(route, body, token=t2)
        check("%s 正常放行" % label, r.get("ok") is True,
              "http=%d %s" % (st, json.dumps(r, ensure_ascii=False)[:120]))

print("== 5. 删除保护")
st, r = call("staff/delete", {"id": 1})
check("不能删自己", r.get("ok") is False, json.dumps(r, ensure_ascii=False)[:160])

tid = (newbie[0].get("id") if newbie else 0)
st, r = call("staff/delete", {"id": tid})
check("删除测试账号", r.get("ok") is True, json.dumps(r, ensure_ascii=False)[:160])

st, r = call("staff/list")
staff = (r.get("data") or []) if isinstance(r.get("data"), list) else (r.get("data") or {}).get("list") or []
check("测试账号已消失", not [x for x in staff if x.get("email") == email])

print("\n结果：%d 通过 / %d 失败" % (PASS, FAIL))
