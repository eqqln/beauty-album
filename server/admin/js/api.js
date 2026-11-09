/* ===========================================================
   后端接口封装
   =========================================================== */
(function () {
  'use strict';

  var BASE = (window.API_BASE || '') + '/meiyan-api/index.php';
  var TOKEN_KEY = 'meiyan_admin_token';

  function token() { return localStorage.getItem(TOKEN_KEY) || ''; }
  function setToken(t) { if (t) localStorage.setItem(TOKEN_KEY, t); else localStorage.removeItem(TOKEN_KEY); }

  async function request(r, opts) {
    opts = opts || {};
    var url = BASE + '?r=' + encodeURIComponent(r);
    if (opts.query) {
      Object.keys(opts.query).forEach(function (k) {
        var v = opts.query[k];
        if (v !== undefined && v !== null && v !== '') url += '&' + encodeURIComponent(k) + '=' + encodeURIComponent(v);
      });
    }
    var headers = {};
    if (token()) headers['Authorization'] = 'Bearer ' + token();
    var init = { method: opts.method || 'GET', headers: headers };
    if (opts.body) {
      headers['Content-Type'] = 'application/json';
      init.body = JSON.stringify(opts.body);
    }
    var res, json;
    try {
      res = await fetch(url, init);
    } catch (e) {
      throw new Error('网络连接失败，请检查网络后重试');
    }
    var text = await res.text();
    try {
      json = JSON.parse(text);
    } catch (e) {
      throw new Error('服务器返回异常（HTTP ' + res.status + '）');
    }
    if (!json.ok) {
      if (res.status === 401) {
        var had = token();
        setToken('');
        /* 只有“已登录状态下失效”才刷新页面；登录/注册时的 401 要留在原地显示错误 */
        if (had && window.onAuthLost) window.onAuthLost();
      }
      throw new Error(json.msg || '请求失败');
    }
    return json.data;
  }

  window.API = {
    token: token,
    setToken: setToken,
    get: function (r, query) { return request(r, { query: query }); },
    post: function (r, body) { return request(r, { method: 'POST', body: body || {} }); },
    list: function (m, query) {
      var q = Object.assign({ m: m }, query || {});
      return request('list', { query: q });
    },
    save: function (m, row) { return request('save', { method: 'POST', body: Object.assign({ m: m }, row) }); },
    del: function (m, id) { return request('delete', { method: 'POST', body: { m: m, id: id } }); },
    options: function (type) { return request('options', { query: { type: type } }); },
    upload: async function (file) {
      var fd = new FormData();
      fd.append('file', file);
      var res = await fetch(BASE + '?r=upload', {
        method: 'POST',
        headers: token() ? { 'Authorization': 'Bearer ' + token() } : {},
        body: fd
      });
      var json = await res.json().catch(function () { return { ok: false, msg: '上传失败' }; });
      if (!json.ok) throw new Error(json.msg || '上传失败');
      return json.data.url;
    },

    /** 下载文件（带 token，走 blob） */
    download: async function (r, query, filename) {
      var url = BASE + '?r=' + encodeURIComponent(r);
      if (query) {
        Object.keys(query).forEach(function (k) {
          var v = query[k];
          if (v !== undefined && v !== null && v !== '') {
            url += '&' + encodeURIComponent(k) + '=' + encodeURIComponent(v);
          }
        });
      }
      var res = await fetch(url, { headers: token() ? { 'Authorization': 'Bearer ' + token() } : {} });
      var ct = res.headers.get('Content-Type') || '';
      if (ct.indexOf('application/json') >= 0) {
        var j = await res.json().catch(function () { return { ok: false, msg: '下载失败' }; });
        if (!j.ok && res.status === 401) { setToken(''); if (window.onAuthLost) window.onAuthLost(); }
        throw new Error(j.msg || '下载失败');
      }
      if (!res.ok) throw new Error('下载失败（HTTP ' + res.status + '）');
      var blob = await res.blob();
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = filename || 'download.zip';
      document.body.appendChild(a);
      a.click();
      setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1500);
    }
  };
})();
