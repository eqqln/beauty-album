/* ===========================================================
   云服务封装：认证 / 数据库 / 文件存储
   =========================================================== */
(function () {
  'use strict';

  var cfg = window.PUBLIC_CONFIG || {};
  var ready = false;
  var cloud = null;

  function boot() {
    if (ready) return cloud;
    if (!cfg.endpoint || !cfg.publishableKey) {
      throw new Error('云服务尚未配置，请联系管理员完成开通');
    }
    if (!window.WorkBuddyCloud || !window.WorkBuddyCloud.createWorkBuddyCloud) {
      throw new Error('云 SDK 加载失败，请检查网络后刷新页面');
    }
    cloud = window.WorkBuddyCloud.createWorkBuddyCloud({
      endpoint: cfg.endpoint,
      oauthRelayBaseUrl: cfg.oauthRelayBaseUrl,
      publishableKey: cfg.publishableKey
    });
    ready = true;
    return cloud;
  }

  function C() { return ready ? cloud : boot(); }

  function unwrap(res) {
    if (res && res.error) throw res.error;
    return res ? res.data : null;
  }

  function msgOf(err) {
    if (!err) return '未知错误';
    if (typeof err === 'string') return err;
    var m = err.message || err.error_description || err.msg;
    if (m) return String(m);
    if (err.code) return String(err.code);
    return '操作失败，请重试';
  }

  /* ---------------- 认证 ---------------- */

  var auth = {
    session: async function () {
      var res = await C().auth.getSession();
      return res && res.data ? res.data : null;
    },
    user: async function () {
      var res = await C().auth.getUser();
      return res && res.data ? res.data : null;
    },
    signIn: async function (email, password) {
      var res = await C().auth.signInWithPassword({ email: email, password: password });
      if (res.error) throw res.error;
      return res.data;
    },
    sendCode: async function (email) {
      var res = await C().auth.sendOtp({ email: email });
      if (res.error) throw res.error;
      return res.data; // { verificationId, isExistingUser }
    },
    verify: async function (pending, token, password) {
      var payload = {
        email: pending.email,
        verificationId: pending.verificationId,
        isExistingUser: pending.isExistingUser,
        token: token
      };
      if (!pending.isExistingUser && password) payload.password = password;
      var res = await C().auth.verifyOtp(payload);
      if (res.error) throw res.error;
      return res.data;
    },
    signOut: async function () {
      try { await C().auth.signOut(); } catch (e) { /* ignore */ }
    },
    onChange: function (fn) {
      try { return C().auth.onAuthStateChange(fn); } catch (e) { return null; }
    }
  };

  /* ---------------- 数据库 ---------------- */

  function table(name) {
    return C().database.from(name);
  }

  var db = {
    table: table,
    /** 查询列表 */
    list: async function (name, build) {
      var q = table(name).select('*');
      if (typeof build === 'function') q = build(q) || q;
      var res = await q;
      if (res.error) throw res.error;
      return res.data || [];
    },
    one: async function (name, id) {
      var res = await table(name).select('*').eq('id', id).maybeSingle();
      if (res.error) throw res.error;
      return res.data;
    },
    insert: async function (name, row) {
      var res = await table(name).insert(row).select();
      if (res.error) throw res.error;
      return (res.data || [])[0];
    },
    update: async function (name, id, patch) {
      var res = await table(name).update(patch).eq('id', id).select();
      if (res.error) throw res.error;
      var rows = res.data || [];
      if (!rows.length) throw new Error('没有改动任何数据（可能无权限或记录已删除）');
      return rows[0];
    },
    remove: async function (name, id) {
      var res = await table(name).delete().eq('id', id).select();
      if (res.error) throw res.error;
      var rows = res.data || [];
      if (!rows.length) throw new Error('没有删除任何数据（可能无权限或记录已删除）');
      return true;
    },
    count: async function (name, build) {
      var q = table(name).select('*', { count: 'exact', head: true });
      if (typeof build === 'function') q = build(q) || q;
      var res = await q;
      if (res.error) throw res.error;
      return res.count || 0;
    },
    rpc: async function (fn, args) {
      var res = await C().database.rpc(fn, args || {});
      if (res.error) throw res.error;
      return res.data;
    },
    raw: async function (build) {
      var res = await build(C().database);
      if (res.error) throw res.error;
      return res.data;
    }
  };

  /* ---------------- 存储 ---------------- */

  var storage = {
    /** 上传图片，返回对象路径 */
    upload: async function (file, folder) {
      var s = await auth.session();
      if (!s) throw new Error('请先登录');
      var ext = (file.name || 'img.jpg').split('.').pop().toLowerCase();
      if (['jpg', 'jpeg', 'png', 'webp', 'gif'].indexOf(ext) < 0) ext = 'jpg';
      var key = (folder || 'images') + '/' + Date.now() + '-' + Math.random().toString(36).slice(2, 8) + '.' + ext;
      var path = C().storage.sharedPath(s.user.id, key);
      var res = await C().storage.upload(path, file, { contentType: file.type || 'image/jpeg' });
      if (res.error) throw res.error;
      return (res.data && res.data.path) || path;
    },
    /** 取签名地址（带缓存） */
    url: async function (path) {
      if (!path) return '';
      if (/^https?:\/\//.test(path)) return path;
      if (storage._cache[path] && storage._cache[path].t > Date.now()) return storage._cache[path].u;
      try {
        var res = await C().storage.createSignedUrl(path, 3600);
        if (res.error) return '';
        var u = (res.data && (res.data.signedUrl || res.data.url)) || '';
        if (u) storage._cache[path] = { u: u, t: Date.now() + 3000 * 1000 };
        return u;
      } catch (e) { return ''; }
    },
    remove: async function (path) {
      try { await C().storage.remove([path]); } catch (e) { /* ignore */ }
    },
    _cache: {}
  };

  /* ---------------- 管理员判定 ---------------- */

  var admin = {
    isAdmin: async function () {
      try { return (await db.rpc('is_admin')) === true; } catch (e) { return false; }
    },
    claim: async function () {
      try { return (await db.rpc('claim_admin')) === true; } catch (e) { return false; }
    }
  };

  window.Cloud = {
    boot: boot,
    raw: C,
    auth: auth,
    db: db,
    storage: storage,
    admin: admin,
    unwrap: unwrap,
    msg: msgOf,
    configured: function () { return !!(cfg.endpoint && cfg.publishableKey); }
  };
})();
