#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
不依赖 github.com 网页与 git push 的上传通道。

适用场景：github.com 被网络干扰打不开，但 api.github.com 可访问。

流程：
  1. 验证 token
  2. 建仓库（不存在时）
  3. Git Data API 上传全部文件 → 合并成 1 个提交（不是 36 个）
  4. 等 Actions 自动开始构建（必要时手动 dispatch）
  5. 轮询状态，成功后把 IPA 下载到 dist/

用法：
    python tools/push_api.py --owner 用户名 --repo beauty-album --token ghp_xxx
    python tools/push_api.py --owner 用户名 --repo beauty-album --token ghp_xxx --public
    python tools/push_api.py ... --dry-run      # 只统计文件，不联网
    python tools/push_api.py ... --no-watch     # 推完就走
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")
WORKFLOW_FILE = ".github/workflows/build.yml"

SKIP_DIRS = {".git", "build", "DerivedData", "dist", "__pycache__", ".workbuddy-ai"}
SKIP_FILES = {".DS_Store"}
SKIP_EXT = {".ipa", ".xcworkspace", ".xcodeproj", ".dSYM"}


def log(msg=""):
    print(msg, flush=True)


def step(msg):
    print("\n==> " + msg, flush=True)


def die(msg):
    print("\n[失败] " + msg, file=sys.stderr, flush=True)
    sys.exit(1)


def request(method, url, token, body=None, accept="application/vnd.github+json",
            raw=False, timeout=60):
    data = None
    headers = {
        "Authorization": "Bearer " + token,
        "Accept": accept,
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "BeautyAlbum-Deployer",
    }
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = resp.read()
            if raw:
                return resp.status, payload
            return resp.status, (json.loads(payload) if payload else None)
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        if raw:
            return e.code, text.encode("utf-8")
        try:
            return e.code, json.loads(text)
        except Exception:
            return e.code, {"raw": text}
    except urllib.error.URLError as e:
        die("网络不可达：%s\n目标：%s" % (e.reason, url))


def collect_files():
    out = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.endswith(".xcodeproj")]
        for name in files:
            if name in SKIP_FILES:
                continue
            if any(name.endswith(ext) for ext in SKIP_EXT):
                continue
            full = os.path.join(base, name)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            out.append((rel, full))
    out.sort()
    return out


def ensure_repo(owner, repo, token, public):
    status, data = request("GET", "%s/repos/%s/%s" % (API, owner, repo), token)
    if status == 200:
        branch = data.get("default_branch", "main")
        log("仓库已存在，默认分支 %s" % branch)
        return branch
    if status != 404:
        die("查询仓库失败 HTTP %s" % status)

    log("仓库不存在，正在创建…")
    status, data = request("POST", API + "/user/repos", token, {
        "name": repo,
        "private": not public,
        "auto_init": False,
        "description": "美颜相册 - 美容院客户相册与档案管理",
    })
    if status != 201:
        msg = data.get("message", "") if isinstance(data, dict) else ""
        die("创建仓库失败 HTTP %s %s" % (status, msg))
    log("仓库创建成功（%s）" % ("公开" if public else "私有"))
    return data.get("default_branch", "main")


def get_head(owner, repo, token, branch):
    """返回 (commit_sha, tree_sha)，空仓库返回 (None, None)"""
    status, ref = request("GET", "%s/repos/%s/%s/git/ref/heads/%s"
                          % (API, owner, repo, branch), token)
    if status != 200:
        return None, None
    commit_sha = ref["object"]["sha"]
    status, commit = request("GET", "%s/repos/%s/%s/git/commits/%s"
                             % (API, owner, repo, commit_sha), token)
    if status != 200:
        die("读取最新提交失败 HTTP %s" % status)
    return commit_sha, commit["tree"]["sha"]


def bootstrap_empty_repo(owner, repo, token):
    """空仓库调 Git Data API 会返回 409 Git Repository is empty，
    先用 Contents API 建一个初始提交（只放 .gitignore，不含 workflow，不会触发构建）。"""
    rel = ".gitignore"
    full = os.path.join(ROOT, rel)
    if not os.path.exists(full):
        die("仓库是空的，且本地没有 .gitignore 用来建初始提交")
    with open(full, "rb") as f:
        content = base64.b64encode(f.read()).decode("ascii")
    status, data = request("PUT", "%s/repos/%s/%s/contents/%s" % (API, owner, repo, rel),
                           token, {"message": "初始化仓库", "content": content})
    if status not in (200, 201):
        msg = data.get("message", "") if isinstance(data, dict) else ""
        die("初始化空仓库失败 HTTP %s %s" % (status, msg))
    log("已创建初始提交（.gitignore），接着打包全部源码")


def upload_tree(owner, repo, token, branch, files):
    """把所有文件合成一个提交，只触发一次构建。"""
    parent_sha, base_tree = get_head(owner, repo, token, branch)
    if parent_sha:
        log("已有历史，新提交会叠加在 %s 之上" % parent_sha[:7])
    else:
        log("空仓库，先建初始提交")
        bootstrap_empty_repo(owner, repo, token)
        parent_sha, base_tree = get_head(owner, repo, token, branch)
        if not parent_sha:
            die("初始提交后仍读不到 main 分支，检查仓库默认分支名")

    tree_items = []
    for idx, (rel, full) in enumerate(files, 1):
        with open(full, "rb") as f:
            content = base64.b64encode(f.read()).decode("ascii")
        status, blob = request("POST", "%s/repos/%s/%s/git/blobs"
                               % (API, owner, repo), token,
                               {"content": content, "encoding": "base64"})
        if status != 201:
            msg = blob.get("message", "") if isinstance(blob, dict) else ""
            die("上传 %s 失败 HTTP %s %s" % (rel, status, msg))
        tree_items.append({"path": rel, "mode": "100644", "type": "blob",
                           "sha": blob["sha"]})
        sys.stdout.write("\r  打包 [%d/%d] %-46s" % (idx, len(files), rel[:46]))
        sys.stdout.flush()
    log("")

    tree_body = {"tree": tree_items}
    if base_tree:
        tree_body["base_tree"] = base_tree
    status, tree = request("POST", "%s/repos/%s/%s/git/trees" % (API, owner, repo),
                           token, tree_body)
    if status != 201:
        die("创建目录树失败 HTTP %s" % status)

    commit_body = {
        "message": "美颜相册 iOS 源码 %s" % time.strftime("%Y-%m-%d %H:%M"),
        "tree": tree["sha"],
    }
    if parent_sha:
        commit_body["parents"] = [parent_sha]
    status, commit = request("POST", "%s/repos/%s/%s/git/commits" % (API, owner, repo),
                             token, commit_body)
    if status != 201:
        msg = commit.get("message", "") if isinstance(commit, dict) else ""
        die("创建提交失败 HTTP %s %s" % (status, msg))

    if parent_sha:
        status, _ = request("PATCH", "%s/repos/%s/%s/git/refs/heads/%s"
                            % (API, owner, repo, branch), token,
                            {"sha": commit["sha"], "force": False})
        if status not in (200, 201):
            die("更新分支失败 HTTP %s" % status)
    else:
        status, _ = request("POST", "%s/repos/%s/%s/git/refs" % (API, owner, repo),
                            token, {"ref": "refs/heads/" + branch, "sha": commit["sha"]})
        if status not in (200, 201):
            die("创建分支失败 HTTP %s" % status)

    log("提交完成 %s（1 个提交，只触发 1 次构建）" % commit["sha"][:7])
    return commit["sha"]


def latest_run(owner, repo, token, branch):
    status, data = request("GET", "%s/repos/%s/%s/actions/runs?per_page=1&branch=%s"
                           % (API, owner, repo, branch), token)
    if status == 200 and data and data.get("workflow_runs"):
        return data["workflow_runs"][0]
    return None


def dispatch(owner, repo, token, branch):
    status, data = request("POST",
                           "%s/repos/%s/%s/actions/workflows/build.yml/dispatches"
                           % (API, owner, repo), token, {"ref": branch})
    if status == 204:
        return "已手动触发构建"
    if status == 403:
        return "token 缺 workflow 权限，无法用 API 触发（构建可能已由 push 自动触发）"
    if status == 404:
        return "workflow 还没被索引，稍等 10 秒再触发"
    return "触发返回 HTTP %s" % status


def download_ipa(owner, repo, token):
    os.makedirs(DIST, exist_ok=True)

    status, rel = request("GET", "%s/repos/%s/%s/releases/latest" % (API, owner, repo), token)
    if status == 200 and isinstance(rel, dict):
        for asset in rel.get("assets", []):
            if asset.get("name", "").endswith(".ipa"):
                target = os.path.join(DIST, asset["name"])
                log("下载 %s（%.1f MB）…" % (asset["name"], asset["size"] / 1048576.0))
                code, payload = request("GET", asset["url"], token,
                                        accept="application/octet-stream",
                                        raw=True, timeout=300)
                if code == 200:
                    with open(target, "wb") as f:
                        f.write(payload)
                    return target
                log("下载失败 HTTP %s" % code)

    status, arts = request("GET", "%s/repos/%s/%s/actions/artifacts?per_page=10"
                           % (API, owner, repo), token)
    if status == 200 and isinstance(arts, dict):
        for art in arts.get("artifacts", []):
            if art.get("expired"):
                continue
            target = os.path.join(DIST, art["name"] + ".zip")
            log("下载 artifact %s（%.1f MB，内含 IPA）…"
                % (art["name"], art["size_in_bytes"] / 1048576.0))
            code, payload = request("GET", art["archive_download_url"], token,
                                    raw=True, timeout=300)
            if code == 200:
                with open(target, "wb") as f:
                    f.write(payload)
                return target
            log("下载失败 HTTP %s" % code)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", required=True, help="GitHub 用户名")
    ap.add_argument("--repo", default="beauty-album", help="仓库名，默认 beauty-album")
    ap.add_argument("--token", default=os.environ.get("GH_TOKEN", ""), help="PAT，需 repo + workflow 权限")
    ap.add_argument("--public", action="store_true", help="建成公开仓库（macOS 构建完全免费）")
    ap.add_argument("--dry-run", action="store_true", help="只列文件，不联网")
    ap.add_argument("--no-watch", action="store_true", help="推完不等待构建")
    args = ap.parse_args()

    files = collect_files()
    total = sum(os.path.getsize(f) for _, f in files)
    step("待上传 %d 个文件，共 %.2f MB" % (len(files), total / 1048576.0))

    if args.dry_run:
        for rel, full in files:
            log("  %-58s %7.1f KB" % (rel, os.path.getsize(full) / 1024.0))
        return

    if not args.token:
        die("缺少 token，用 --token 或环境变量 GH_TOKEN 传入")

    owner, repo, token = args.owner, args.repo, args.token

    step("验证 Token")
    status, me = request("GET", API + "/user", token)
    if status != 200:
        die("Token 无效（HTTP %s）。检查是否勾选了 repo 与 workflow 权限" % status)
    login = me.get("login", "")
    log("Token 有效，账号 %s" % login)
    if owner.lower() != login.lower():
        log("提示：token 属于 %s，将以该账号名义建仓库" % login)
        owner = login

    step("准备仓库")
    branch = ensure_repo(owner, repo, token, args.public)

    step("上传源码（合并为 1 个提交）")
    commit = upload_tree(owner, repo, token, branch, files)

    if WORKFLOW_FILE not in [r for r, _ in files]:
        log("警告：仓库里没有 %s，不会自动构建" % WORKFLOW_FILE)

    if args.no_watch:
        log("\n仓库地址：https://github.com/%s/%s" % (owner, repo))
        log("提交：%s" % commit)
        return

    step("等待 Actions 启动")
    run = None
    for i in range(4):
        time.sleep(10)
        run = latest_run(owner, repo, token, branch)
        if run:
            log("已发现构建任务 #%s（%s）" % (run.get("run_number"), run.get("event")))
            break
        log("[%2ds] 还没出现构建记录…" % ((i + 1) * 10))

    if not run:
        log(dispatch(owner, repo, token, branch))
        for i in range(4):
            time.sleep(10)
            run = latest_run(owner, repo, token, branch)
            if run:
                break

    if not run:
        die("构建没有启动。去 https://github.com/%s/%s/actions 看原因（多半是 workflow 文件或权限）"
            % (owner, repo))

    step("等待构建完成（每 20 秒查一次，最长 25 分钟）")
    seen, conclusion = 0, None
    while seen < 75:
        time.sleep(20)
        seen += 1
        run = latest_run(owner, repo, token, branch) or run
        st, cc = run.get("status"), run.get("conclusion")
        log("[%3ds] %s%s" % (seen * 20, st, (" / " + cc) if cc else ""))
        if st == "completed":
            conclusion = cc
            break

    if conclusion != "success":
        log("\n构建未成功（%s）。日志：https://github.com/%s/%s/actions"
            % (conclusion or "超时", owner, repo))
        sys.exit(2)

    step("构建成功，下载 IPA")
    path = download_ipa(owner, repo, token)
    if path:
        log("已保存：%s（%.2f MB）" % (path, os.path.getsize(path) / 1048576.0))
        if path.endswith(".zip"):
            log("这是 artifact 压缩包，解开里面的 BeautyAlbum.ipa 即可")
    else:
        log("自动下载没成功，手动去：https://github.com/%s/%s/releases" % (owner, repo))


if __name__ == "__main__":
    main()
