# -*- coding: utf-8 -*-
"""验证 photos 视频字段能完整走通 push -> DB -> pull"""
import json
import os
import urllib.request
from datetime import datetime, timezone, timedelta

BASE = "https://meiyan.shengka.net/meiyan-api/"
TOKEN = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_tok.txt")).read().strip()


def call(route, body):
    req = urllib.request.Request(BASE + "?r=" + route,
                                 data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                                 method="POST")
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode("utf-8", "replace"))


def now_iso():
    return datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds")


pull = call("sync/pull", {})
clients = (pull["data"].get("data") or {}).get("customers") or []
if not clients:
    print("没有客户，先造一个")
    cid = "00000000-0000-4000-8000-00000000c001"
    r = call("sync/push", {"data": {"customers": [{
        "uid": cid, "name": "视频测试客户", "phone": "13000000001",
        "stage": "体验", "progress": 0, "quoted": 0, "note": "",
        "created_at": now_iso(), "updated_at": now_iso(),
    }]}})
    print("  建客户:", json.dumps(r, ensure_ascii=False))
else:
    cid = clients[0]["uid"]
    print("用现有客户:", clients[0].get("name"), cid)

puid = "00000000-0000-4000-8000-00000000v001".replace("v", "a")
ts = now_iso()
row = {
    "uid": puid,
    "client_uid": cid,
    "phase": "before",
    "url": "/uploads/202611/10182719-7c83c290.mp4",
    "thumb_url": "/uploads/202611/10182719-cddd0b90.png",
    "kind": "video",
    "duration": 12.5,
    "thumb_name": "abc-thumb.jpg",
    "size_bytes": 1048576,
    "file_name": "abc.mp4",
    "tag": "",
    "caption": "视频同步测试",
    "created_at": ts,
    "updated_at": ts,
    "field_ts": {"caption": ts},
}

print("\n== push")
r = call("sync/push", {"data": {"photos": [row]}})
print(json.dumps(r, ensure_ascii=False))

print("\n== pull 回读")
p2 = call("sync/pull", {})
photos = (p2["data"].get("data") or {}).get("photos") or []
hit = [x for x in photos if x.get("uid") == puid]
if hit:
    x = hit[0]
    keys = ["kind", "duration", "thumb_name", "thumb_url", "size_bytes", "file_name", "caption"]
    for k in keys:
        print("  %-12s = %r" % (k, x.get(k)))
    print("  field_ts     =", x.get("field_ts"))
else:
    print("  !! 没回读到这条记录")
