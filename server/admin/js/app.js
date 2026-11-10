/* ===========================================================
   后台主程序：登录 / 路由 / 概览 / 套餐 / 短信 / 设置
   =========================================================== */
(function () {
  'use strict';

  var state = { admin: null, settings: {} };

  var NAV = [
    { group: '总览' },
    { key: 'overview', title: '概览', icon: '📊', sub: '今日经营情况' },
    { group: '经营' },
    { key: 'packages', title: '套餐', icon: '🎁', sub: '套餐内容与价格，App 端同步展示' },
    { key: 'm:members', title: '会员', icon: '👤', sub: 'App 注册用户与等级' },
    { key: 'm:subs', title: '开通记录', icon: '📋', sub: '套餐开通与到期' },
    { key: 'm:payments', title: '收款', icon: '💰', sub: '收款流水与欠款' },
    { group: '服务' },
    { key: 'm:customers', title: '客户', icon: '💁', sub: '客户档案与进度' },
    { key: 'm:appointments', title: '预约', icon: '📅', sub: 'App 排期同步，改一边两边都变' },
    { key: 'm:steps', title: '护理步骤', icon: '✅', sub: '疗程步骤与完成情况' },
    { key: 'm:notes', title: '客户笔记', icon: '📔', sub: 'App 里记的文字笔记' },
    { key: 'm:claims', title: '产品领用', icon: '🏷️', sub: '客户用了哪些产品' },
    { key: 'm:photos', title: '相册图片', icon: '📷', sub: '使用前 / 使用后照片' },
    { key: 'm:compares', title: '对比图', icon: '🔀', sub: '前后对比' },
    { key: 'm:mentors', title: '导师', icon: '🎓', sub: '导师档案' },
    { key: 'm:products', title: '产品', icon: '📦', sub: '产品与规格' },
    { group: '分销' },
    { key: 'm:agents', title: '代理', icon: '🤝', sub: '代理档案与上下级' },
    { key: 'm:orders', title: '拿货', icon: '🧾', sub: '拿货与结算' },
    { group: '营销' },
    { key: 'recharge', title: '充值卡', icon: '💳', sub: '批量生成卡号卡密，App 内直接充值' },
    { key: 'm:wallet', title: '钱包流水', icon: '📒', sub: '充值、消费、调整的完整流水' },
    { group: '系统' },
    { key: 'sms', title: '短信', icon: '✉️', sub: '多家短信通道与发送记录' },
    { key: 'backup', title: '数据备份', icon: '💾', sub: '一键导出全部数据与图片' },
    { key: 'settings', title: '系统设置', icon: '⚙️', sub: '店铺、安装包、开关' }
  ];

  var $ = function (id) { return document.getElementById(id); };

  /* ---------------- 登录 / 注册 ---------------- */

  function bindAuth() {
    /* 先绑登录，确保任何后续异常都不会让登录按钮失效 */
    try {
      var toSignup = $('toSignup');
      if (toSignup) toSignup.onclick = function (e) { e.preventDefault(); showSignup(); };
      var toLogin = $('toLogin');
      if (toLogin) toLogin.onclick = function (e) { e.preventDefault(); showLogin(); };
    } catch (e) { /* 页面切换失败不影响登录 */ }

    $('loginForm').onsubmit = async function (e) {
      e.preventDefault();
      var msg = $('loginMsg');
      var btn = $('loginBtn');
      var acc = $('loginEmail').value.trim();
      var pwd = $('loginPassword').value;

      msg.className = 'auth-msg';
      msg.textContent = '';
      if (!acc) { msg.textContent = '请输入账号（邮箱 / 姓名 / 手机号）'; $('loginEmail').focus(); return false; }
      if (!pwd) { msg.textContent = '请输入密码'; $('loginPassword').focus(); return false; }

      var oldText = btn.textContent;
      btn.disabled = true;
      btn.textContent = '登录中…';
      try {
        var data = await API.post('admin/login', { email: acc, password: pwd });
        if (!data || !data.token) throw new Error('登录返回数据异常，请重试');
        API.setToken(data.token);
        btn.textContent = '正在进入…';
        await enter(data.admin);
      } catch (err) {
        msg.className = 'auth-msg bad';
        msg.textContent = (err && err.message) ? err.message : '登录失败，请重试';
      }
      btn.disabled = false;
      btn.textContent = oldText;
      return false;
    };

    $('signupForm').onsubmit = async function (e) {
      e.preventDefault();
      var msg = $('suMsg');
      var btn = $('suBtn');
      var email = $('suEmail').value.trim();
      var pwd = $('suPassword').value;

      msg.className = 'auth-msg';
      msg.textContent = '';
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        msg.textContent = '请填写正确的邮箱，例如 name@shop.com';
        $('suEmail').focus();
        return false;
      }
      if (pwd.length < 6) {
        msg.textContent = '密码至少 6 位';
        $('suPassword').focus();
        return false;
      }

      var oldText = btn.textContent;
      btn.disabled = true;
      btn.textContent = '注册中…';
      try {
        var data = await API.post('admin/register', {
          email: email,
          name: $('suName').value.trim(),
          password: pwd,
          invite: $('suInvite').value.trim()
        });
        if (!data || !data.token) throw new Error('注册返回数据异常，请重试');
        API.setToken(data.token);
        btn.textContent = '正在进入…';
        await enter(data.admin);
      } catch (err) {
        msg.className = 'auth-msg bad';
        msg.textContent = (err && err.message) ? err.message : '注册失败，请重试';
        if (/邀请码/.test(msg.textContent)) { state.hasAdmin = true; $('inviteField').hidden = false; }
      }
      btn.disabled = false;
      btn.textContent = oldText;
      return false;
    };

    $('logoutBtn').onclick = async function () {
      try { await API.post('admin/logout'); } catch (e) { /* ignore */ }
      API.setToken('');
      location.reload();
    };

    var pwdBtn = $('pwdBtn');
    if (pwdBtn) {
      pwdBtn.onclick = function () {
        UI.modal({
          title: '修改登录密码',
          body: '<label class="field"><span>当前密码</span><input type="password" id="pwOld" autocomplete="current-password" placeholder="输入现在的密码"></label>' +
                '<label class="field"><span>新密码</span><input type="password" id="pwNew" autocomplete="new-password" placeholder="至少 6 位"></label>' +
                '<label class="field"><span>确认新密码</span><input type="password" id="pwNew2" autocomplete="new-password" placeholder="再输一次"></label>' +
                '<p class="td-sub">改完需要重新登录。密码请自行记好，忘了只能由服务器管理员重置。</p>',
          buttons: [
            { label: '取消', kind: 'ghost' },
            {
              label: '保存', kind: 'primary',
              onClick: async function (m) {
                var oldp = $('pwOld').value;
                var np = $('pwNew').value;
                var np2 = $('pwNew2').value;
                if (!oldp) { UI.toast('请输入当前密码', 'bad'); return; }
                if (np.length < 6) { UI.toast('新密码至少 6 位', 'bad'); return; }
                if (np !== np2) { UI.toast('两次输入的新密码不一致', 'bad'); return; }
                m.setBusy(true);
                try {
                  await API.post('admin/password', { old: oldp, new: np });
                  m.close();
                  UI.toast('密码已修改，请重新登录', 'ok');
                  API.setToken('');
                  setTimeout(function () { location.reload(); }, 900);
                } catch (e) { UI.toast(e.message, 'bad'); m.setBusy(false); }
              }
            }
          ]
        });
      };
    }

    window.onAuthLost = function () {
      API.setToken('');
      location.reload();
    };
  }

  async function boot() {
    bindAuth();
    try {
      var info = await API.get('site/info');
      state.settings = info || {};
      if (info) {
        state.hasAdmin = !!info.has_admin;
        if (info.shop_name) {
          if ($('authShopName')) $('authShopName').textContent = info.shop_name;
          if ($('authShopName2')) $('authShopName2').textContent = info.shop_name;
        }
      }
    } catch (e) { /* 首次安装时忽略 */ }

    if (!API.token()) { showAuth(); return; }
    try {
      var me = await API.get('admin/me');
      await enter(me, true);
    } catch (e) {
      showAuth();
    }
  }

  /* 登录页 / 注册页 两个独立页面 */
  function showLogin() {
    if ($('signupView')) $('signupView').hidden = true;
    if ($('authView')) $('authView').hidden = false;
    var e = $('loginEmail');
    if (e) { try { e.focus(); } catch (err) {} }
    if (location.hash === '#register') history.replaceState(null, '', location.pathname + location.search);
  }

  function showSignup() {
    if ($('authView')) $('authView').hidden = true;
    if ($('signupView')) $('signupView').hidden = false;
    if ($('inviteField')) $('inviteField').hidden = !state.hasAdmin;
    var e = $('suEmail');
    if (e) { try { e.focus(); } catch (err) {} }
  }

  function showAuth() {
    if (location.hash === '#register') { showSignup(); }
    else { showLogin(); }
    $('appView').hidden = true;
  }

  async function enter(admin, skipReload) {
    state.admin = admin;
    $('authView').hidden = true;
    if ($('signupView')) $('signupView').hidden = true;
    $('appView').hidden = false;
    $('userEmail').textContent = admin.email || admin.name;
    $('userAvatar').textContent = (admin.name || admin.email || 'A').slice(0, 1).toUpperCase();
    $('userRole').textContent = admin.role === 'owner' ? '店主管理员' : '员工';
    try {
      var s = await API.get('settings/get');
      state.settings = s || {};
      if (s && s.shop_name) {
        $('sideShopName').textContent = s.shop_name;
        document.title = s.shop_name + ' · 管理后台';
      }
    } catch (e) { /* ignore */ }
    buildNav();
    if (!location.hash) location.hash = '#/overview';
    route();
  }

  function buildNav() {
    var nav = $('nav');
    nav.innerHTML = NAV.map(function (n) {
      if (n.group) return '<div class="nav-group">' + UI.esc(n.group) + '</div>';
      return '<button class="nav-item" data-key="' + n.key + '">' +
        '<span class="ico">' + n.icon + '</span>' + UI.esc(n.title) + '</button>';
    }).join('');
    nav.querySelectorAll('.nav-item').forEach(function (btn) {
      btn.onclick = function () {
        location.hash = '#/' + btn.getAttribute('data-key');
        $('sidebar').classList.remove('open');
      };
    });
  }

  function currentNav() {
    var key = (location.hash || '#/overview').replace(/^#\//, '') || 'overview';
    return NAV.find(function (n) { return n.key === key; }) || NAV[1];
  }

  async function route() {
    var nav = currentNav();
    $('pageTitle').textContent = nav.title;
    $('pageSub').textContent = nav.sub || '';
    document.querySelectorAll('.nav-item').forEach(function (b) {
      b.classList.toggle('active', b.getAttribute('data-key') === nav.key);
    });
    var view = $('view');
    view.innerHTML = UI.loading();

    if (nav.key === 'overview') return renderOverview(view);
    if (nav.key === 'packages') return renderPackages(view);
    if (nav.key === 'recharge') return renderRecharge(view);
    if (nav.key === 'backup') return renderBackup(view);
    if (nav.key === 'sms') return renderSms(view);
    if (nav.key === 'settings') return renderSettings(view);
    if (nav.key.indexOf('m:') === 0) return CRUD.render(view, nav.key.slice(2));
  }

  /* ---------------- 概览 ---------------- */

  async function renderOverview(view) {
    try {
      var s = await API.get('stats/overview');
      var cards = [
        { k: '会员', v: UI.num(s.members), d: '今日新增 ' + s.members_today + ' 位', cls: 'rose' },
        { k: '客户', v: UI.num(s.customers), d: '照片 ' + s.photos + ' 张 · 对比 ' + s.compares + ' 组' },
        { k: '本月收款', v: UI.money(s.income_month), d: '累计 ' + UI.money(s.income_total), cls: 'ok' },
        { k: '未收款', v: UI.money(s.unpaid), d: '待跟进核对', cls: s.unpaid > 0 ? 'bad' : '' },
        { k: '累计充值', v: UI.money(s.recharge_total || 0), d: '本月 ' + UI.money(s.recharge_month || 0), cls: 'ok' },
        { k: '未使用充值卡', v: UI.num(s.cards_unused || 0), d: '共 ' + UI.num(s.cards_total || 0) + ' 张', cls: 'rose' },
        { k: '上架套餐', v: UI.num(s.packages), d: '生效中 ' + s.subs + ' 份' },
        { k: '导师', v: UI.num(s.mentors), d: '在岗导师' },
        { k: '产品', v: UI.num(s.products), d: '在售产品' },
        { k: '代理', v: UI.num(s.agents), d: '合作中' }
      ];
      var html = '<div class="grid g4">' + cards.map(function (c) {
        return '<div class="card stat"><div class="k">' + c.k + '</div>' +
          '<div class="v ' + (c.cls || '') + '">' + c.v + '</div>' +
          '<div class="d">' + UI.esc(c.d) + '</div></div>';
      }).join('') + '</div>';

      /* App 同步状态：让店主一眼看出手机和后台是否已经对上 */
      html += '<div class="section-head"><h3>App 数据同步</h3><div class="sp"></div>' +
        '<span class="td-sub" id="syncHint">正在读取…</span></div>';
      html += '<div class="card sync-panel" id="syncPanel">' +
        '<div class="sync-grid" id="syncGrid"><span class="td-sub">读取中…</span></div></div>';

      html += '<div class="section-head"><h3>最近新增会员</h3><div class="sp"></div>' +
        '<button class="btn sm ghost" onclick="location.hash=\'#/m:members\'">全部会员</button></div>';
      html += '<div class="card" style="padding:0;overflow:hidden">';
      if (!s.recent_members || !s.recent_members.length) {
        html += UI.empty('还没有会员注册', '👤');
      } else {
        html += '<table><thead><tr><th>会员</th><th>手机号</th><th>等级</th><th>状态</th><th>注册时间</th></tr></thead><tbody>' +
          s.recent_members.map(function (m) {
            return '<tr><td class="td-main">' + UI.esc(m.name) + '</td>' +
              '<td class="td-sub">' + UI.esc(m.phone || '—') + '</td>' +
              '<td>' + UI.badge(m.level) + '</td>' +
              '<td>' + UI.badge(m.status) + '</td>' +
              '<td class="td-sub">' + UI.fmtDate(m.created_at) + '</td></tr>';
          }).join('') + '</tbody></table>';
      }
      html += '</div>';

      html += '<div class="section-head"><h3>最近收款</h3><div class="sp"></div>' +
        '<button class="btn sm ghost" onclick="location.hash=\'#/m:payments\'">全部收款</button></div>';
      html += '<div class="card" style="padding:0;overflow:hidden">';
      if (!s.recent_payments || !s.recent_payments.length) {
        html += UI.empty('还没有收款记录', '💰');
      } else {
        html += '<table><thead><tr><th>客户</th><th>金额</th><th>方式</th><th>状态</th><th>时间</th></tr></thead><tbody>' +
          s.recent_payments.map(function (p) {
            return '<tr><td class="td-main">' + UI.esc(p.customer || '—') + '</td>' +
              '<td class="td-main">' + UI.money(p.amount) + '</td>' +
              '<td>' + UI.esc(p.method || '—') + '</td>' +
              '<td>' + UI.badge(p.status) + '</td>' +
              '<td class="td-sub">' + UI.fmtDate(p.paid_at) + '</td></tr>';
          }).join('') + '</tbody></table>';
      }
      html += '</div>';

      html += '<div class="section-head"><h3>最近充值</h3><div class="sp"></div>' +
        '<button class="btn sm ghost" onclick="location.hash=\'#/recharge\'">充值卡管理</button></div>';
      html += '<div class="card" style="padding:0;overflow:hidden">';
      if (!s.recent_recharges || !s.recent_recharges.length) {
        html += UI.empty('还没有充值记录，去「充值卡」生成一批卡吧', '💳');
      } else {
        html += '<table><thead><tr><th>会员</th><th>到账金额</th><th>积分</th><th>卡号</th><th>时间</th></tr></thead><tbody>' +
          s.recent_recharges.map(function (r) {
            return '<tr><td class="td-main">' + UI.esc(r.member || '—') + '</td>' +
              '<td class="td-main up">+' + UI.money(r.amount) + '</td>' +
              '<td>' + (Number(r.points) > 0 ? '<span class="up">+' + Number(r.points) + '</span>' : '<span class="td-sub">—</span>') + '</td>' +
              '<td class="td-sub mono">' + UI.esc(r.ref || '—') + '</td>' +
              '<td class="td-sub">' + UI.fmtDate(r.created_at) + '</td></tr>';
          }).join('') + '</tbody></table>';
      }
      html += '</div>';

      view.innerHTML = html;
      loadSyncPanel();
    } catch (e) {
      view.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  /* 概览里的同步状态：拉各模块条数，标出还没上云的项目 */
  async function loadSyncPanel() {
    var grid = $('syncGrid');
    var hint = $('syncHint');
    if (!grid) return;
    var LABELS = {
      customers: '客户', photos: '照片', compares: '对比', payments: '收款',
      steps: '护理步骤', notes: '笔记', claims: '产品领用',
      teachers: '导师', products: '产品', agents: '代理',
      agent_orders: '拿货', appointments: '预约'
    };
    try {
      var r = await API.get('sync/stats');
      var c = (r && r.counts) || {};
      var total = 0;
      Object.keys(c).forEach(function (k) { total += Number(c[k] || 0); });
      grid.innerHTML = Object.keys(LABELS).map(function (k) {
        var n = Number(c[k] || 0);
        return '<div class="sync-cell' + (n === 0 ? ' zero' : '') + '">' +
          '<div class="sc-k">' + LABELS[k] + '</div>' +
          '<div class="sc-v">' + UI.num(n) + '</div></div>';
      }).join('');
      if (hint) hint.textContent = '共 ' + UI.num(total) + ' 条记录与 App 双向同步';
    } catch (e) {
      grid.innerHTML = '<span class="td-sub">同步状态读取失败：' + UI.esc(e.message) + '</span>';
      if (hint) hint.textContent = '';
    }
  }

  /* ---------------- 套餐 ---------------- */

  async function renderPackages(view) {
    try {
      var res = await API.list('packages', { size: 100 });
      var rows = res.rows || [];
      var html = '<div class="toolbar"><div class="td-sub">共 ' + rows.length +
        ' 个套餐，上架的会在 App 内展示</div><div style="flex:1"></div>' +
        '<button class="btn primary" id="addPkg">+ 新建套餐</button></div>';

      if (!rows.length) {
        html += '<div class="card">' + UI.empty('还没有套餐，点右上角新建', '🎁') + '</div>';
      } else {
        html += '<div class="pkg-grid">' + rows.map(function (p) {
          var items = String(p.items || '').split(/\r?\n/).filter(Boolean);
          return '<div class="pkg' + (p.badge ? ' hot' : '') + '">' +
            (p.badge ? '<div class="pkg-flag">' + UI.esc(p.badge) + '</div>' : '') +
            '<div class="pkg-name">' + UI.esc(p.name) + '</div>' +
            '<div class="pkg-price">' + UI.money(p.price) + '<small>/' + (p.days || 0) + ' 天</small></div>' +
            '<div class="pkg-desc">' + UI.esc(p.desc || '暂无说明') + '</div>' +
            '<div class="pkg-items">' + items.slice(0, 4).map(function (t) {
              return '<span class="chip">' + UI.esc(t.trim()) + '</span>';
            }).join('') + (items.length > 4 ? '<span class="chip">+' + (items.length - 4) + '</span>' : '') + '</div>' +
            '<div style="display:flex;gap:6px;margin-top:6px">' +
              UI.badge(p.status) +
              '<div style="flex:1"></div>' +
              '<button class="btn sm ghost" data-pe="' + p.id + '">编辑</button>' +
              '<button class="btn sm danger" data-pd="' + p.id + '">删除</button>' +
            '</div></div>';
          }).join('') + '</div>';
      }
      view.innerHTML = html;

      view.querySelector('#addPkg').onclick = function () {
        CRUD.openForm('packages', null, function () { renderPackages(view); });
      };
      view.querySelectorAll('[data-pe]').forEach(function (b) {
        b.onclick = function () {
          var id = Number(b.getAttribute('data-pe'));
          var row = rows.find(function (r) { return Number(r.id) === id; });
          CRUD.openForm('packages', row, function () { renderPackages(view); });
        };
      });
      view.querySelectorAll('[data-pd]').forEach(function (b) {
        b.onclick = function () {
          var id = Number(b.getAttribute('data-pd'));
          UI.confirm('删除套餐', '删除后 App 端不再展示，已开通的记录不受影响。确定删除？', async function () {
            try { await API.del('packages', id); UI.toast('已删除', 'ok'); renderPackages(view); }
            catch (e) { UI.toast(e.message, 'bad'); }
          }, true);
        };
      });
    } catch (e) {
      view.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  /* ---------------- 充值卡 ---------------- */

  var RC = { page: 1, size: 30, kw: '', status: '', batch: '' };

  function rcPad(n) { return n < 10 ? '0' + n : '' + n; }

  function rcDate(d) {
    return d.getFullYear() + '-' + rcPad(d.getMonth() + 1) + '-' + rcPad(d.getDate());
  }

  function rcAddDays(days) {
    var d = new Date();
    d.setDate(d.getDate() + days);
    return rcDate(d);
  }

  function copyText(t) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(t);
    }
    return new Promise(function (resolve, reject) {
      var ta = document.createElement('textarea');
      ta.value = t;
      ta.style.position = 'fixed';
      ta.style.top = '-999px';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); resolve(); } catch (e) { reject(e); }
      ta.remove();
    });
  }

  function downloadCSV(name, rows) {
    var head = ['卡号', '卡密', '类型', '充值金额', '赠送金额', '积分', '会员天数',
                '批次', '生效日期', '有效期至', '状态', '使用人', '使用时间', '备注', '生成时间'];
    var keys = ['card_no', 'card_secret', 'card_type', 'amount', 'bonus', 'points', 'days',
                'batch', 'start_at', 'expire_at', 'status', 'used_name', 'used_at', 'note', 'created_at'];
    var lines = [head.join(',')];
    rows.forEach(function (r) {
      lines.push(keys.map(function (k) {
        var v = r[k] === null || r[k] === undefined ? '' : String(r[k]);
        return '"' + v.replace(/"/g, '""') + '"';
      }).join(','));
    });
    var blob = new Blob(['\ufeff' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1200);
  }

  function rcStatCards(s) {
    var cards = [
      { k: '未使用卡', v: UI.num(s.unused), d: '面额合计 ' + UI.money(s.unused_amount), cls: 'rose' },
      { k: '已使用', v: UI.num(s.used), d: '已充值 ' + UI.money(s.used_amount), cls: 'ok' },
      { k: '累计充值', v: UI.money(s.recharge_total), d: '本月 ' + UI.money(s.recharge_month) + ' · 今日 ' + UI.money(s.recharge_today), cls: 'ok' },
      { k: '会员余额总额', v: UI.money(s.balance_total), d: '共 ' + UI.num(s.recharge_count) + ' 笔充值' },
      { k: '已作废 / 已过期', v: UI.num(s.voided) + ' / ' + UI.num(s.expired), d: '作废的卡不能再充值', cls: s.voided > 0 ? 'bad' : '' },
      { k: '卡总数', v: UI.num(s.total), d: '待领积分 ' + UI.num(s.unused_points) }
    ];
    return '<div class="grid g4">' + cards.map(function (c) {
      return '<div class="card stat"><div class="k">' + c.k + '</div>' +
        '<div class="v ' + (c.cls || '') + '">' + c.v + '</div>' +
        '<div class="d">' + UI.esc(c.d) + '</div></div>';
    }).join('') + '</div>';
  }

  async function renderRecharge(view) {
    view.innerHTML = UI.loading();
    try {
      var s = await API.get('admin/recharge-stats');
      var def = s.settings || {};

      var html = rcStatCards(s);

      html += '<div class="card" style="margin:16px 0">' +
        '<div class="rc-head">' +
          '<strong>生成充值卡</strong>' +
          '<span class="td-sub">卡号卡密自动生成，一次最多 500 张；金额、积分、会员天数可以任意组合</span>' +
          (def.enabled === '1' ? '' : '<span class="badge bad">App 端充值已关闭</span>') +
        '</div>' +
        '<div class="rc-grid">' +
          '<label class="field"><span>卡类型</span><select id="rcType">' +
            ['余额卡', '积分卡', '组合卡', '体验卡'].map(function (t) {
              return '<option value="' + t + '">' + t + '</option>';
            }).join('') + '</select></label>' +
          '<label class="field"><span>充值金额（元）</span><input type="number" id="rcAmount" value="100" min="0" step="1" inputmode="decimal"></label>' +
          '<label class="field"><span>赠送金额（元）</span><input type="number" id="rcBonus" value="0" min="0" step="1" inputmode="decimal"></label>' +
          '<label class="field"><span>赠送积分</span><input type="number" id="rcPoints" value="0" min="0" step="1" inputmode="numeric"></label>' +
          '<label class="field"><span>赠送会员天数</span><input type="number" id="rcDays" value="0" min="0" step="1" inputmode="numeric"></label>' +
          '<label class="field"><span>生成数量</span><input type="number" id="rcCount" value="10" min="1" max="500" step="1" inputmode="numeric"></label>' +
          '<label class="field"><span>卡号前缀</span><input type="text" id="rcPrefix" value="' + UI.esc(def.prefix || 'MY') + '" maxlength="6" placeholder="MY"></label>' +
          '<label class="field"><span>生效日期（年月日）</span><input type="date" id="rcStart"></label>' +
          '<label class="field"><span>有效期至（年月日）</span><input type="date" id="rcExpire" value="' + rcAddDays(Number(def.default_days || 365)) + '"></label>' +
          '<label class="field"><span>批次名称</span><input type="text" id="rcBatch" placeholder="留空自动用时间戳"></label>' +
          '<label class="field" style="grid-column:1/-1"><span>内部备注</span><input type="text" id="rcNote" placeholder="如：2026 春节活动 / 老客户回馈（会员看不到）"></label>' +
        '</div>' +
        '<div class="rc-presets">' +
          '<span class="td-sub">面额：</span>' +
          [50, 100, 200, 300, 500, 1000, 2000].map(function (v) {
            return '<button type="button" class="chip-btn" data-amt="' + v + '">' + v + '</button>';
          }).join('') +
          '<span class="td-sub" style="margin-left:16px">有效期：</span>' +
          [30, 90, 180, 365].map(function (v) {
            return '<button type="button" class="chip-btn" data-days="' + v + '">' + v + ' 天</button>';
          }).join('') +
          '<button type="button" class="chip-btn" data-days="0">长期有效</button>' +
          '<span class="td-sub" style="margin-left:16px">积分：</span>' +
          [0, 100, 200, 500, 1000].map(function (v) {
            return '<button type="button" class="chip-btn" data-pts="' + v + '">' + v + '</button>';
          }).join('') +
        '</div>' +
        '<div class="rc-foot">' +
          '<span class="td-sub" id="rcPreview">—</span>' +
          '<div style="flex:1"></div>' +
          '<button class="btn ghost" id="rcExport">导出 CSV</button>' +
          '<button class="btn primary" id="rcGen">立即生成</button>' +
        '</div>' +
      '</div>';

      html += '<div class="toolbar">' +
        '<input class="search" id="rcKw" placeholder="搜卡号 / 卡密 / 使用人 / 批次">' +
        '<select id="rcStatus" class="rc-select">' +
          ['', '未使用', '已使用', '已作废', '已过期'].map(function (v) {
            return '<option value="' + v + '">' + (v === '' ? '全部状态' : v) + '</option>';
          }).join('') + '</select>' +
        '<select id="rcBatchSel" class="rc-select"><option value="">全部批次</option></select>' +
        '<div style="flex:1"></div>' +
        '<span class="td-sub" id="rcTotal"></span>' +
      '</div>' +
      '<div class="card" style="padding:0;overflow:hidden"><div id="rcTable">' + UI.loading() + '</div></div>' +
      '<div id="rcPager" class="rc-pager"></div>';

      view.innerHTML = html;
      bindRecharge(view);
      await loadCards();
    } catch (e) {
      view.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  function bindRecharge(view) {
    var $v = function (id) { return view.querySelector('#' + id); };

    function preview() {
      var amt = Number($v('rcAmount').value) || 0;
      var bonus = Number($v('rcBonus').value) || 0;
      var pts = Number($v('rcPoints').value) || 0;
      var days = Number($v('rcDays').value) || 0;
      var cnt = Number($v('rcCount').value) || 0;
      var one = amt + bonus;
      var parts = [];
      if (one > 0) parts.push('每张到账 ' + UI.money(one) + (bonus > 0 ? '（含赠送 ' + UI.money(bonus) + '）' : ''));
      if (pts > 0) parts.push('送 ' + pts + ' 积分');
      if (days > 0) parts.push('送 ' + days + ' 天会员');
      if (!parts.length) parts.push('还没填面额');
      var total = one * cnt;
      $v('rcPreview').textContent = parts.join(' · ') + (total > 0 ? ' · 共 ' + UI.money(total) : '');
    }

    ['rcAmount', 'rcBonus', 'rcPoints', 'rcDays', 'rcCount'].forEach(function (id) {
      $v(id).addEventListener('input', preview);
    });
    preview();

    view.querySelectorAll('[data-amt]').forEach(function (b) {
      b.onclick = function () { $v('rcAmount').value = b.getAttribute('data-amt'); preview(); };
    });
    view.querySelectorAll('[data-days]').forEach(function (b) {
      b.onclick = function () {
        var d = Number(b.getAttribute('data-days'));
        $v('rcExpire').value = d > 0 ? rcAddDays(d) : '';
      };
    });
    view.querySelectorAll('[data-pts]').forEach(function (b) {
      b.onclick = function () { $v('rcPoints').value = b.getAttribute('data-pts'); preview(); };
    });

    $v('rcGen').onclick = async function () {
      var body = {
        card_type: $v('rcType').value,
        amount: Number($v('rcAmount').value) || 0,
        bonus: Number($v('rcBonus').value) || 0,
        points: Number($v('rcPoints').value) || 0,
        days: Number($v('rcDays').value) || 0,
        count: Number($v('rcCount').value) || 1,
        prefix: $v('rcPrefix').value.trim() || 'MY',
        start_at: $v('rcStart').value,
        expire_at: $v('rcExpire').value,
        batch: $v('rcBatch').value.trim(),
        note: $v('rcNote').value.trim()
      };
      if (!body.amount && !body.bonus && !body.points && !body.days) {
        UI.toast('充值金额、赠送金额、积分、会员天数至少要填一项', 'bad');
        return;
      }
      if (body.count > 500) { UI.toast('一次最多生成 500 张', 'bad'); return; }
      if (body.start_at && body.expire_at && body.start_at > body.expire_at) {
        UI.toast('生效日期不能晚于有效期', 'bad');
        return;
      }
      $v('rcGen').disabled = true;
      try {
        var res = await API.post('admin/recharge-generate', body);
        UI.toast('已生成 ' + res.count + ' 张，批次 ' + res.batch, 'ok');
        showGenerated(res, body);
        RC.page = 1;
        await renderRecharge(view);
      } catch (e) {
        UI.toast(e.message, 'bad');
        $v('rcGen').disabled = false;
      }
    };

    $v('rcExport').onclick = async function () {
      try {
        var res = await API.get('admin/recharge-export', { status: RC.status, batch: RC.batch });
        if (!res.rows || !res.rows.length) { UI.toast('没有可导出的卡', 'bad'); return; }
        downloadCSV('充值卡-' + rcDate(new Date()) + '.csv', res.rows);
        UI.toast('已导出 ' + res.count + ' 张卡', 'ok');
      } catch (e) { UI.toast(e.message, 'bad'); }
    };

    var kw = $v('rcKw');
    var timer = null;
    kw.oninput = function () {
      clearTimeout(timer);
      timer = setTimeout(function () { RC.kw = kw.value.trim(); RC.page = 1; loadCards(); }, 320);
    };
    $v('rcStatus').onchange = function () { RC.status = $v('rcStatus').value; RC.page = 1; loadCards(); };
    $v('rcBatchSel').onchange = function () { RC.batch = $v('rcBatchSel').value; RC.page = 1; loadCards(); };
  }

  function showGenerated(res, body) {
    var html = '<p class="td-sub" style="margin-bottom:10px">批次 <strong>' + UI.esc(res.batch) +
      '</strong> · 共 ' + res.count + ' 张 · ' +
      (res.amount > 0 ? '¥' + res.amount + ' ' : '') +
      (res.bonus > 0 ? '赠 ¥' + res.bonus + ' ' : '') +
      (res.points > 0 ? res.points + ' 积分 ' : '') +
      (res.days > 0 ? res.days + ' 天 ' : '') +
      (res.expire_at ? '· 有效期至 ' + res.expire_at : '· 长期有效') + '</p>';

    html += '<div class="rc-result"><table><thead><tr><th>#</th><th>卡号</th><th>卡密</th></tr></thead><tbody>' +
      res.cards.map(function (c, i) {
        return '<tr><td class="td-sub">' + (i + 1) + '</td>' +
          '<td class="mono">' + UI.esc(c.card_no) + '</td>' +
          '<td class="mono">' + UI.esc(c.card_secret) + '</td></tr>';
      }).join('') + '</tbody></table></div>';

    UI.modal({
      title: '生成完成',
      body: html,
      wide: true,
      buttons: [
        {
          label: '复制全部（卡号,卡密）', kind: 'ghost',
          onClick: function () {
            var txt = res.cards.map(function (c) { return c.card_no + ',' + c.card_secret; }).join('\n');
            copyText(txt).then(function () { UI.toast('已复制 ' + res.cards.length + ' 张', 'ok'); })
              .catch(function () { UI.toast('复制失败，请手动选择', 'bad'); });
          }
        },
        {
          label: '下载 CSV', kind: 'ghost',
          onClick: function () {
            downloadCSV('充值卡-' + res.batch + '.csv', res.cards.map(function (c) {
              return {
                card_no: c.card_no, card_secret: c.card_secret, card_type: body.card_type,
                amount: body.amount, bonus: body.bonus, points: body.points, days: body.days,
                batch: res.batch, start_at: body.start_at, expire_at: body.expire_at,
                status: '未使用', used_name: '', used_at: '', note: body.note,
                created_at: rcDate(new Date())
              };
            }));
            UI.toast('已下载', 'ok');
          }
        },
        { label: '完成', kind: 'primary' }
      ]
    });
  }

  async function loadCards() {
    var view = document.getElementById('view');
    var wrap = view.querySelector('#rcTable');
    var pager = view.querySelector('#rcPager');
    if (!wrap) return;
    wrap.innerHTML = UI.loading();
    pager.innerHTML = '';
    try {
      var res = await API.get('admin/recharge-list', {
        page: RC.page, size: RC.size, kw: RC.kw, status: RC.status, batch: RC.batch
      });
      var rows = res.rows || [];

      var sel = view.querySelector('#rcBatchSel');
      if (sel && res.batches) {
        var cur = RC.batch;
        sel.innerHTML = '<option value="">全部批次</option>' + res.batches.map(function (b) {
          return '<option value="' + UI.esc(b.batch) + '"' + (b.batch === cur ? ' selected' : '') + '>' +
            UI.esc(b.batch) + '（' + b.n + '）</option>';
        }).join('');
      }
      var totalEl = view.querySelector('#rcTotal');
      if (totalEl) totalEl.textContent = '共 ' + UI.num(res.total) + ' 张';

      if (!rows.length) {
        wrap.innerHTML = UI.empty(RC.kw || RC.status || RC.batch ? '没有匹配的卡' : '还没有充值卡，在上面生成一批吧', '💳');
        return;
      }

      var body = rows.map(function (r) {
        var valid = (r.start_at || r.expire_at)
          ? (r.start_at ? r.start_at : '不限') + ' ~ ' + (r.expire_at ? r.expire_at : '长期')
          : '长期有效';
        var used = r.used_name
          ? UI.esc(r.used_name) + '<div class="td-sub">' + UI.fmtDate(r.used_at) + '</div>'
          : '<span class="td-sub">—</span>';
        var acts = '';
        if (r.status !== '已使用') {
          acts += '<button class="btn sm ghost" data-rcedit="' + r.id + '">编辑</button> ';
          acts += '<button class="btn sm ghost" data-rcvoid="' + r.id + '">' +
                  (r.status === '已作废' ? '恢复' : '作废') + '</button> ';
          acts += '<button class="btn sm danger" data-rcdel="' + r.id + '">删除</button>';
        }
        return '<tr>' +
          '<td><div class="mono td-main">' + UI.esc(r.card_no) + '</div>' +
            '<div class="td-sub mono">密 ' + UI.esc(r.card_secret) + '</div></td>' +
          '<td>' + UI.badge(r.card_type) + '</td>' +
          '<td class="td-main">' + UI.esc(r.label) + '</td>' +
          '<td>' + (r.days > 0 ? r.days + ' 天' : '<span class="td-sub">—</span>') + '</td>' +
          '<td class="td-sub">' + UI.esc(valid) + '</td>' +
          '<td>' + UI.badge(r.status) + '</td>' +
          '<td>' + used + '</td>' +
          '<td class="td-sub">' + UI.esc(r.batch || '—') + '</td>' +
          '<td class="td-actions">' + acts +
            '<button class="btn sm ghost" data-rccopy="' + UI.esc(r.card_no + ',' + r.card_secret) + '">复制</button>' +
          '</td></tr>';
      }).join('');

      wrap.innerHTML = '<div style="overflow-x:auto"><table><thead><tr>' +
        '<th>卡号 / 卡密</th><th>类型</th><th>面额</th><th>会员天数</th><th>有效期</th>' +
        '<th>状态</th><th>使用情况</th><th>批次</th><th></th></tr></thead><tbody>' + body + '</tbody></table></div>';

      wrap.querySelectorAll('[data-rccopy]').forEach(function (b) {
        b.onclick = function () {
          copyText(b.getAttribute('data-rccopy')).then(function () { UI.toast('已复制卡号卡密', 'ok'); })
            .catch(function () { UI.toast('复制失败', 'bad'); });
        };
      });
      wrap.querySelectorAll('[data-rcvoid]').forEach(function (b) {
        b.onclick = async function () {
          try {
            var r = await API.post('admin/recharge-void', { id: Number(b.getAttribute('data-rcvoid')) });
            UI.toast(r.status === '已作废' ? '已作废' : '已恢复', 'ok');
            loadCards();
          } catch (e) { UI.toast(e.message, 'bad'); }
        };
      });
      wrap.querySelectorAll('[data-rcdel]').forEach(function (b) {
        b.onclick = function () {
          UI.confirm('删除充值卡', '删除后这张卡将永久失效，确定删除？', async function () {
            try {
              await API.post('admin/recharge-delete', { id: Number(b.getAttribute('data-rcdel')) });
              UI.toast('已删除', 'ok');
              loadCards();
            } catch (e) { UI.toast(e.message, 'bad'); }
          }, true);
        };
      });
      wrap.querySelectorAll('[data-rcedit]').forEach(function (b) {
        b.onclick = function () {
          var id = Number(b.getAttribute('data-rcedit'));
          var row = rows.find(function (x) { return Number(x.id) === id; });
          editCard(row);
        };
      });

      var pages = Math.max(1, Math.ceil((res.total || 0) / RC.size));
      pager.innerHTML =
        '<span class="td-sub">第 ' + RC.page + ' / ' + pages + ' 页</span>' +
        (RC.page > 1 ? '<button class="btn sm ghost" id="rcPrev">上一页</button>' : '') +
        (RC.page < pages ? '<button class="btn sm ghost" id="rcNext">下一页</button>' : '');
      var prev = pager.querySelector('#rcPrev');
      var next = pager.querySelector('#rcNext');
      if (prev) prev.onclick = function () { RC.page--; loadCards(); };
      if (next) next.onclick = function () { RC.page++; loadCards(); };
    } catch (e) {
      wrap.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  function editCard(row) {
    if (!row) return;
    var html = '<div class="rc-grid">' +
      '<label class="field"><span>卡号（不可改）</span><input type="text" value="' + UI.esc(row.card_no) + '" disabled></label>' +
      '<label class="field"><span>卡密（不可改）</span><input type="text" value="' + UI.esc(row.card_secret) + '" disabled></label>' +
      '<label class="field"><span>卡类型</span><select id="ecType">' +
        ['余额卡', '积分卡', '组合卡', '体验卡'].map(function (t) {
          return '<option value="' + t + '"' + (row.card_type === t ? ' selected' : '') + '>' + t + '</option>';
        }).join('') + '</select></label>' +
      '<label class="field"><span>充值金额（元）</span><input type="number" id="ecAmount" value="' + Number(row.amount || 0) + '" min="0" step="1"></label>' +
      '<label class="field"><span>赠送金额（元）</span><input type="number" id="ecBonus" value="' + Number(row.bonus || 0) + '" min="0" step="1"></label>' +
      '<label class="field"><span>赠送积分</span><input type="number" id="ecPoints" value="' + Number(row.points || 0) + '" min="0" step="1"></label>' +
      '<label class="field"><span>赠送会员天数</span><input type="number" id="ecDays" value="' + Number(row.days || 0) + '" min="0" step="1"></label>' +
      '<label class="field"><span>生效日期</span><input type="date" id="ecStart" value="' + UI.esc(row.start_at || '') + '"></label>' +
      '<label class="field"><span>有效期至</span><input type="date" id="ecExpire" value="' + UI.esc(row.expire_at || '') + '"></label>' +
      '<label class="field"><span>状态</span><select id="ecStatus">' +
        ['未使用', '已作废', '已过期'].map(function (t) {
          return '<option value="' + t + '"' + (row.status === t ? ' selected' : '') + '>' + t + '</option>';
        }).join('') + '</select></label>' +
      '<label class="field" style="grid-column:1/-1"><span>内部备注</span><input type="text" id="ecNote" value="' + UI.esc(row.note || '') + '"></label>' +
      '</div>';

    UI.modal({
      title: '编辑充值卡',
      body: html,
      wide: true,
      buttons: [
        { label: '取消', kind: 'ghost' },
        {
          label: '保存', kind: 'primary',
          onClick: async function (m) {
            var body = {
              id: row.id,
              card_type: document.getElementById('ecType').value,
              amount: Number(document.getElementById('ecAmount').value) || 0,
              bonus: Number(document.getElementById('ecBonus').value) || 0,
              points: Number(document.getElementById('ecPoints').value) || 0,
              days: Number(document.getElementById('ecDays').value) || 0,
              start_at: document.getElementById('ecStart').value,
              expire_at: document.getElementById('ecExpire').value,
              status: document.getElementById('ecStatus').value,
              note: document.getElementById('ecNote').value
            };
            m.setBusy(true);
            try {
              await API.post('admin/recharge-save', body);
              m.close();
              UI.toast('已保存', 'ok');
              loadCards();
            } catch (e) { UI.toast(e.message, 'bad'); m.setBusy(false); }
          }
        }
      ]
    });
  }

  /* ---------------- 会员钱包（会员列表行内按钮） ---------------- */

  window.ROW_ACTION_RUNNERS = {
    wallet: function (row, refresh) { openWallet(row.id, refresh); }
  };

  async function openWallet(memberId, refresh) {
    var m = UI.modal({ title: '会员钱包', body: UI.loading(), wide: true, buttons: [{ label: '关闭', kind: 'ghost' }] });
    try {
      var res = await API.get('admin/member-wallet', { member_id: memberId, size: 30 });
      var mem = res.member || {};
      var logs = res.logs || [];

      var html = '<div class="wallet-head">' +
        '<div class="wallet-cell"><span>会员</span><strong>' + UI.esc(mem.name || '—') + '</strong>' +
          '<small>' + UI.esc(mem.phone || '') + '</small></div>' +
        '<div class="wallet-cell"><span>账户余额</span><strong class="rose">' + UI.money(mem.balance) + '</strong>' +
          '<small>累计充值 ' + UI.money(mem.total_recharge) + '</small></div>' +
        '<div class="wallet-cell"><span>积分</span><strong>' + UI.num(mem.points) + '</strong>' +
          '<small>累计获得 ' + UI.num(mem.total_points) + '</small></div>' +
        '<div class="wallet-cell"><span>套餐到期</span><strong>' + UI.esc(mem.expire_at ? String(mem.expire_at).slice(0, 10) : '未开通') + '</strong>' +
          '<small>' + UI.esc((mem.package && mem.package.name) || '无套餐') + '</small></div>' +
      '</div>';

      html += '<div class="card" style="padding:14px;margin:14px 0;box-shadow:none;border:1px solid #f0e4e8">' +
        '<div style="font-weight:700;margin-bottom:10px">手动调账</div>' +
        '<div class="rc-grid" style="grid-template-columns:repeat(3,1fr)">' +
          '<label class="field"><span>类型</span><select id="waKind">' +
            ['赠送', '调整', '消费', '充值'].map(function (t) { return '<option value="' + t + '">' + t + '</option>'; }).join('') +
          '</select></label>' +
          '<label class="field"><span>金额变动（负数为扣减）</span><input type="number" id="waAmount" value="0" step="1" inputmode="decimal"></label>' +
          '<label class="field"><span>积分变动</span><input type="number" id="waPoints" value="0" step="1" inputmode="numeric"></label>' +
          '<label class="field" style="grid-column:1/-1"><span>说明</span><input type="text" id="waNote" placeholder="如：到店赠送 / 消费扣款"></label>' +
        '</div>' +
        '<div style="display:flex;justify-content:flex-end"><button class="btn primary sm" id="waSubmit">确认调整</button></div>' +
      '</div>';

      html += '<div class="section-head"><h3>流水记录</h3><div class="sp"></div><span class="td-sub">最近 30 条</span></div>';
      if (!logs.length) {
        html += UI.empty('还没有流水', '📒');
      } else {
        html += '<div style="max-height:320px;overflow:auto"><table><thead><tr>' +
          '<th>时间</th><th>类型</th><th>金额</th><th>积分</th><th>余额</th><th>说明</th></tr></thead><tbody>' +
          logs.map(function (l) {
            var amt = Number(l.amount || 0);
            var pts = Number(l.points || 0);
            return '<tr><td class="td-sub">' + UI.fmtDate(l.created_at) + '</td>' +
              '<td>' + UI.badge(l.kind) + '</td>' +
              '<td>' + (amt > 0 ? '<span class="up">+' + UI.money(amt) + '</span>' : amt < 0 ? '<span class="down">-' + UI.money(Math.abs(amt)) + '</span>' : '<span class="td-sub">—</span>') + '</td>' +
              '<td>' + (pts > 0 ? '<span class="up">+' + pts + '</span>' : pts < 0 ? '<span class="down">' + pts + '</span>' : '<span class="td-sub">—</span>') + '</td>' +
              '<td class="td-sub">' + UI.money(l.balance_after) + '</td>' +
              '<td class="td-sub">' + UI.esc(l.note || l.ref || '—') + '</td></tr>';
          }).join('') + '</tbody></table></div>';
      }

      m.body.innerHTML = html;
      m.body.querySelector('#waSubmit').onclick = async function () {
        var body = {
          member_id: memberId,
          kind: m.body.querySelector('#waKind').value,
          amount: Number(m.body.querySelector('#waAmount').value) || 0,
          points: Number(m.body.querySelector('#waPoints').value) || 0,
          note: m.body.querySelector('#waNote').value.trim()
        };
        if (!body.amount && !body.points) { UI.toast('金额与积分不能同时为 0', 'bad'); return; }
        try {
          await API.post('admin/wallet-adjust', body);
          UI.toast('余额已更新', 'ok');
          m.close();
          if (refresh) refresh();
          openWallet(memberId, refresh);
        } catch (e) { UI.toast(e.message, 'bad'); }
      };
    } catch (e) {
      m.body.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  /* ---------------- 数据备份 ---------------- */

  async function renderBackup(view) {
    view.innerHTML = UI.loading();
    try {
      var s = await API.get('admin/backup-stats');

      var cards = [
        { k: '会员', v: UI.num(s.members), d: '手机号 / 等级 / 余额 / 积分', cls: 'rose' },
        { k: '客户', v: UI.num(s.customers), d: '手机号 / 环节 / 应收金额' },
        { k: '代理', v: UI.num(s.agents), d: '手机号 / 微信号 / 上下级' },
        { k: '相册图片', v: UI.num(s.photos), d: '对比图 ' + UI.num(s.compares) + ' 组' },
        { k: '图片文件', v: UI.num(s.image_files), d: '占用 ' + s.image_size_text },
        { k: '数据库体积', v: s.db_size_text, d: '收款 ' + UI.num(s.payments) + ' 笔 · 流水 ' + UI.num(s.wallet) + ' 条' }
      ];

      var html = '<div class="grid g4">' + cards.map(function (c) {
        return '<div class="card stat"><div class="k">' + c.k + '</div>' +
          '<div class="v ' + (c.cls || '') + '">' + c.v + '</div>' +
          '<div class="d">' + UI.esc(c.d) + '</div></div>';
      }).join('') + '</div>';

      var include = [
        '会员：姓名、手机号、邮箱、等级、余额、积分、到期时间',
        '客户：姓名、手机号、关联会员、环节进度、应收金额',
        '代理：姓名、手机号、微信号、地区、等级折扣、上下级',
        '导师 / 产品 / 套餐 / 拿货记录',
        '相册图片与前后对比图的文件与路径',
        '收款流水、套餐开通记录、钱包流水、充值卡',
        '通讯录汇总表：所有手机号与微信号，可直接导入手机',
        '系统设置（店铺名称、联系方式等）'
      ];

      html += '<div class="card" style="margin:16px 0">' +
        '<div class="rc-head">' +
          '<strong>一键备份全部数据</strong>' +
          '<span class="td-sub">导出成一个 zip 包，解压后 Excel / WPS 可直接打开</span>' +
        '</div>' +
        '<div class="bk-list">' + include.map(function (t) {
          return '<div class="bk-item"><span class="bk-dot"></span>' + UI.esc(t) + '</div>';
        }).join('') + '</div>' +
        '<div class="bk-actions">' +
          '<label class="field" style="flex:1;min-width:220px"><span>备份备注（可选）</span>' +
            '<input type="text" id="bkNote" placeholder="如：月底存档 / 换机前备份"></label>' +
          '<label class="bk-check"><input type="checkbox" id="bkImg" checked>' +
            '<span>同时打包图片原图</span></label>' +
          '<button class="btn primary" id="bkGo">立即备份</button>' +
        '</div>' +
        '<p class="td-sub" style="margin-top:12px">备份文件保存在服务器 <code>backups/</code> 目录，可随时下载到本地。' +
          '建议每周备份一次，换服务器或重装前务必先备份。</p>' +
      '</div>';

      html += '<div class="section-head"><h3>备份记录</h3><div class="sp"></div>' +
        '<span class="td-sub" id="bkCount"></span></div>' +
        '<div class="card" style="padding:0;overflow:hidden"><div id="bkTable">' + UI.loading() + '</div></div>' +
        '<div id="bkPager" class="rc-pager"></div>';

      view.innerHTML = html;

      view.querySelector('#bkGo').onclick = async function () {
        var btn = view.querySelector('#bkGo');
        var note = view.querySelector('#bkNote').value.trim();
        var withImg = view.querySelector('#bkImg').checked ? 1 : 0;
        btn.disabled = true;
        btn.textContent = '备份中…';
        UI.toast(withImg ? '正在打包数据与图片，请稍候…' : '正在打包数据，请稍候…');
        try {
          var r = await API.post('admin/backup-create', { note: note, with_images: withImg });
          UI.toast('备份完成：' + r.size_text + ' · ' + r.rows_total + ' 行' +
                   (r.photos > 0 ? ' · ' + r.photos + ' 张图片' : ''), 'ok');
          view.querySelector('#bkNote').value = '';
          renderBackup(view);
        } catch (e) {
          UI.toast(e.message, 'bad');
          btn.disabled = false;
          btn.textContent = '立即备份';
        }
      };

      await loadBackups(view);
    } catch (e) {
      view.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  var BK = { page: 1, size: 20 };

  async function loadBackups(view) {
    var wrap = view.querySelector('#bkTable');
    var pager = view.querySelector('#bkPager');
    if (!wrap) return;
    wrap.innerHTML = UI.loading();
    pager.innerHTML = '';
    try {
      var res = await API.get('admin/backup-list', { page: BK.page, size: BK.size });
      var rows = res.rows || [];
      var cnt = view.querySelector('#bkCount');
      if (cnt) cnt.textContent = '共 ' + UI.num(res.total) + ' 份';

      if (!rows.length) {
        wrap.innerHTML = UI.empty('还没有备份，点上面的「立即备份」生成第一份', '💾');
        return;
      }

      wrap.innerHTML = '<div style="overflow-x:auto"><table><thead><tr>' +
        '<th>备份文件</th><th>大小</th><th>内容</th><th>数据量</th><th>时间</th><th>操作人</th><th></th>' +
        '</tr></thead><tbody>' + rows.map(function (r) {
          return '<tr>' +
            '<td><div class="td-main">' + UI.esc(r.name) + '</div>' +
              (r.note ? '<div class="td-sub">' + UI.esc(r.note) + '</div>' : '') +
              (r.exists ? '' : '<div class="td-sub" style="color:#cf4b4b">文件已丢失</div>') + '</td>' +
            '<td class="td-main">' + UI.esc(r.size_text) + '</td>' +
            '<td class="td-sub">' + UI.esc(r.scope || '—') + '</td>' +
            '<td class="td-sub">' + UI.num(r.rows_total) + ' 行' +
              (r.photos > 0 ? ' · ' + UI.num(r.photos) + ' 张图' : '') + '</td>' +
            '<td class="td-sub">' + UI.fmtDate(r.created_at) + '</td>' +
            '<td class="td-sub">' + UI.esc(r.created_by || '—') + '</td>' +
            '<td class="td-actions">' +
              (r.exists ? '<button class="btn sm ghost" data-bkdl="' + r.id + '">下载</button> ' : '') +
              '<button class="btn sm danger" data-bkdel="' + r.id + '">删除</button>' +
            '</td></tr>';
        }).join('') + '</tbody></table></div>';

      wrap.querySelectorAll('[data-bkdl]').forEach(function (b) {
        b.onclick = async function () {
          var id = Number(b.getAttribute('data-bkdl'));
          var row = rows.find(function (x) { return Number(x.id) === id; });
          b.disabled = true;
          b.textContent = '准备中';
          try {
            await API.download('admin/backup-download', { id: id }, row ? row.name : 'backup.zip');
            UI.toast('已开始下载', 'ok');
          } catch (e) {
            UI.toast(e.message, 'bad');
          }
          b.disabled = false;
          b.textContent = '下载';
        };
      });

      wrap.querySelectorAll('[data-bkdel]').forEach(function (b) {
        b.onclick = function () {
          var id = Number(b.getAttribute('data-bkdel'));
          UI.confirm('删除备份', '删除后这份备份文件将从服务器移除，且无法恢复。确定删除？', async function () {
            try {
              await API.post('admin/backup-delete', { id: id });
              UI.toast('已删除', 'ok');
              loadBackups(view);
            } catch (e) { UI.toast(e.message, 'bad'); }
          }, true);
        };
      });

      var pages = Math.max(1, Math.ceil((res.total || 0) / BK.size));
      pager.innerHTML =
        '<span class="td-sub">第 ' + BK.page + ' / ' + pages + ' 页</span>' +
        (BK.page > 1 ? '<button class="btn sm ghost" id="bkPrev">上一页</button>' : '') +
        (BK.page < pages ? '<button class="btn sm ghost" id="bkNext">下一页</button>' : '');
      var prev = pager.querySelector('#bkPrev');
      var next = pager.querySelector('#bkNext');
      if (prev) prev.onclick = function () { BK.page--; loadBackups(view); };
      if (next) next.onclick = function () { BK.page++; loadBackups(view); };
    } catch (e) {
      wrap.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  /* ---------------- 短信 ---------------- */

  async function renderSms(view) {
    try {
      var providers = await API.get('sms/providers');
      var logs = await API.get('sms/logs', { size: 20 });
      var def = state.settings.sms_default || '';

      var html = '<div class="card" style="margin-bottom:16px">' +
        '<div style="display:flex;align-items:center;gap:10px;margin-bottom:6px">' +
        '<strong style="font-size:14.5px">短信通道</strong>' +
        (def ? '<span class="badge ok">当前使用：' + UI.esc(def) + '</span>' : '<span class="badge warn">未启用任何通道</span>') +
        '</div>' +
        '<p class="td-sub" style="margin-bottom:12px">启用后用于会员注册、登录验证码与通知。可同时配置多家，启用最后保存的那家为默认通道。</p>' +
        '<div style="overflow-x:auto"><table><thead><tr><th>通道</th><th>状态</th><th>签名</th><th>验证码模板</th><th></th></tr></thead><tbody>' +
        providers.map(function (p) {
          return '<tr><td class="td-main">' + UI.esc(p.name) + '</td>' +
            '<td>' + (Number(p.enabled) ? '<span class="badge ok">已启用</span>' : '<span class="badge gray">未启用</span>') + '</td>' +
            '<td class="td-sub">' + UI.esc(p.sign || '—') + '</td>' +
            '<td class="td-sub">' + UI.esc(p.tpl_code || '—') + '</td>' +
            '<td class="td-actions">' +
              '<button class="btn sm ghost" data-cfg="' + UI.esc(p.code) + '">配置</button> ' +
              '<button class="btn sm ghost" data-test="' + UI.esc(p.code) + '">测试</button>' +
            '</td></tr>';
        }).join('') + '</tbody></table></div></div>';

      html += '<div class="section-head"><h3>发送记录</h3><div class="sp"></div>' +
        '<span class="td-sub">最近 20 条</span></div>';
      html += '<div class="card" style="padding:0;overflow:hidden">';
      if (!logs.rows || !logs.rows.length) {
        html += UI.empty('还没有发送记录', '✉️');
      } else {
        html += '<div style="overflow-x:auto"><table><thead><tr><th>时间</th><th>通道</th><th>手机号</th><th>内容</th><th>结果</th></tr></thead><tbody>' +
          logs.rows.map(function (l) {
            return '<tr><td class="td-sub">' + UI.fmtDate(l.created_at) + '</td>' +
              '<td>' + UI.esc(l.provider || '—') + '</td>' +
              '<td class="td-sub">' + UI.esc(l.phone || '—') + '</td>' +
              '<td class="td-sub">' + UI.esc(l.content || '—') + '</td>' +
              '<td>' + UI.badge(l.status) + '</td></tr>';
          }).join('') + '</tbody></table></div>';
      }
      html += '</div>';

      view.innerHTML = html;

      view.querySelectorAll('[data-cfg]').forEach(function (b) {
        b.onclick = function () { openProvider(providers.find(function (p) { return p.code === b.getAttribute('data-cfg'); })); };
      });
      view.querySelectorAll('[data-test]').forEach(function (b) {
        b.onclick = function () { testProvider(b.getAttribute('data-test')); };
      });

      function openProvider(p) {
        if (!p) return;
        var cfg = p.config_masked || {};
        var fields = Object.keys(cfg);
        var html2 = '<label class="field"><span>短信签名</span><input id="pvSign" value="' + UI.esc(p.sign || '') + '" placeholder="如：美颜相册"></label>' +
          '<label class="field"><span>验证码模板 ID</span><input id="pvTpl" value="' + UI.esc(p.tpl_code || '') + '" placeholder="模板编号"></label>' +
          '<label class="field"><span>通知模板 ID</span><input id="pvTpl2" value="' + UI.esc(p.tpl_notice || '') + '" placeholder="可留空"></label>' +
          fields.map(function (k) {
            var isLong = k === 'body' || k === 'headers';
            return '<label class="field"><span>' + UI.esc(k) + '</span>' +
              (isLong
                ? '<textarea id="pv_' + UI.esc(k) + '">' + UI.esc(cfg[k]) + '</textarea>'
                : '<input id="pv_' + UI.esc(k) + '" value="' + UI.esc(cfg[k]) + '">') + '</label>';
          }).join('') +
          '<label class="field" style="flex-direction:row;align-items:center;gap:10px">' +
          '<input type="checkbox" id="pvEnable" style="width:auto" ' + (Number(p.enabled) ? 'checked' : '') + '>' +
          '<span style="margin:0">启用该通道（保存后设为默认）</span></label>' +
          '<p class="td-sub">带 ****** 的是已保存的值，不改动就保持原样。</p>';

        UI.modal({
          title: p.name + ' 配置',
          body: html2,
          wide: true,
          buttons: [
            { label: '取消', kind: 'ghost' },
            {
              label: '保存', kind: 'primary',
              onClick: async function (m) {
                var body = {
                  code: p.code,
                  sign: $('pvSign').value,
                  tpl_code: $('pvTpl').value,
                  tpl_notice: $('pvTpl2').value,
                  enabled: $('pvEnable').checked ? 1 : 0,
                  config: {}
                };
                fields.forEach(function (k) {
                  body.config[k] = $('pv_' + k).value;
                });
                m.setBusy(true);
                try {
                  await API.post('sms/provider-save', body);
                  m.close();
                  UI.toast('已保存', 'ok');
                  state.settings = await API.get('settings/get');
                  renderSms(view);
                } catch (e) { UI.toast(e.message, 'bad'); m.setBusy(false); }
              }
            }
          ]
        });
      }

      function testProvider(code) {
        UI.modal({
          title: '测试发送',
          body: '<label class="field"><span>接收手机号</span><input id="testPhone" placeholder="11 位手机号" inputmode="numeric"></label>' +
                '<p class="td-sub">会用该通道的验证码模板发送一条测试短信（验证码 123456）。</p>',
          buttons: [
            { label: '取消', kind: 'ghost' },
            {
              label: '发送', kind: 'primary',
              onClick: async function (m) {
                var phone = $('testPhone').value.trim();
                if (!/^1[3-9]\d{9}$/.test(phone)) { UI.toast('手机号不正确', 'bad'); return; }
                m.setBusy(true);
                try {
                  await API.post('sms/test', { code: code, phone: phone });
                  m.close();
                  UI.toast('测试短信已发送', 'ok');
                  renderSms(view);
                } catch (e) { UI.toast(e.message, 'bad'); m.setBusy(false); }
              }
            }
          ]
        });
      }
    } catch (e) {
      view.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  /* ---------------- 系统设置 ---------------- */

  async function renderSettings(view) {
    try {
      var s = await API.get('settings/get');
      state.settings = s;
      var groups = [
        {
          title: '店铺信息', fields: [
            { k: 'shop_name', label: '系统名称', ph: '显示在 App 与后台顶部' },
            { k: 'shop_slogan', label: '副标题', ph: '如：专业皮肤管理' },
            { k: 'contact_phone', label: '联系电话' },
            { k: 'contact_wechat', label: '微信 / 客服号' },
            { k: 'notice', label: '公告', type: 'textarea', ph: '显示在 App 首页，可留空' }
          ]
        },
        {
          title: '文案设置', fields: [
            { k: 'before_label', label: '「使用前」叫法', ph: '默认 使用前' },
            { k: 'after_label', label: '「使用后」叫法', ph: '默认 使用后' }
          ]
        },
        {
          title: '安装包', fields: [
            { k: 'api_base', label: '服务器地址', ph: 'https://meiyan.shengka.net' },
            { k: 'app_version', label: '当前版本号', ph: '1.1.0' },
            { k: 'install_note', label: '安装说明', type: 'textarea' }
          ]
        },
        {
          title: '充值设置', fields: [
            { k: 'recharge_enabled', label: 'App 内充值开关（1 开 / 0 关）', ph: '1' },
            { k: 'recharge_prefix', label: '卡号默认前缀', ph: 'MY（最多 6 位字母数字）' },
            { k: 'recharge_default_days', label: '默认有效期天数', ph: '365' },
            { k: 'recharge_min', label: '单次最低充值金额', ph: '1' },
            { k: 'recharge_notice', label: '充值说明', type: 'textarea', ph: '显示在 App 充值页，可留空' }
          ]
        },
        {
          title: 'App 收款码', fields: [
            { k: 'wechat_qr', label: '微信收款码图片地址', ph: '上传后自动填，也可粘贴外链' },
            { k: 'alipay_qr', label: '支付宝收款码图片地址', ph: '上传后自动填，也可粘贴外链' },
            { k: 'pay_link', label: '商户收款链接', ph: '填了会生成带金额的二维码，留空则用收款码图' },
            { k: 'pay_note', label: '扫码提示语', ph: '扫码后请输入本次金额' }
          ]
        },
        {
          title: 'App 流程模板', fields: [
            { k: 'step_template', label: '护理环节（JSON 数组）', type: 'textarea',
              ph: '["初次咨询","拍照建档","第 1 次护理","第 2 次护理","第 3 次护理","疗程结束"]' }
          ]
        },
        {
          title: 'App 首页布局', fields: [
            { k: 'home_layout', label: '客户列表排列', ph: '竖排列表 / 横排卡片' },
            { k: 'home_columns', label: '横排每行几个（2 或 3）', ph: '2' },
            { k: 'home_limit', label: '首页最多显示几位（0 = 全部）', ph: '0' },
            { k: 'show_cover', label: '显示封面图（1 开 / 0 关）', ph: '1' }
          ]
        },
        {
          title: 'App 功能开关', fields: [
            { k: 'app_features', label: '模块开关（JSON）', type: 'textarea',
              ph: '{"teachers":true,"appointments":true,"products":true,"payments":true,"compare":true,"steps":true,"notes":true,"backup":true,"agents":true,"agentParent":true,"agentQuantity":true,"agentRelation":true,"agentTime":true,"account":true}' }
          ]
        },
        {
          title: '会员与短信', fields: [
            { k: 'sms_debug_code', label: '调试模式（1 开 / 0 关）', ph: '开启后未配置短信也能看到验证码' },
            { k: 'admin_invite', label: '员工注册邀请码', ph: '把这个码给员工即可注册' }
          ]
        }
      ];

      var html = groups.map(function (g) {
        return '<div class="card" style="margin-bottom:16px">' +
          '<div style="font-weight:700;margin-bottom:14px">' + UI.esc(g.title) + '</div>' +
          '<div style="display:grid;grid-template-columns:1fr 1fr;gap:14px">' +
          g.fields.map(function (f) {
            var v = s[f.k] || '';
            var ctl = f.type === 'textarea'
              ? '<textarea data-s="' + f.k + '">' + UI.esc(v) + '</textarea>'
              : '<input type="text" data-s="' + f.k + '" value="' + UI.esc(v) + '" placeholder="' + UI.esc(f.ph || '') + '">';
            return '<label class="field"><span>' + UI.esc(f.label) + '</span>' + ctl + '</label>';
          }).join('') + '</div></div>';
      }).join('');

      /* ---- 安装包上传 ---- */
      var ipa = null;
      try { ipa = await API.get('admin/ipa-info'); } catch (e) { /* ignore */ }

      html += '<div class="card" style="margin-bottom:16px">' +
        '<div class="rc-head">' +
          '<strong>安装包（IPA）</strong>' +
          '<span class="td-sub">上传后自动更新下载地址、版本号与 OTA 清单，用户重新打开安装页即可装新版</span>' +
        '</div>' +
        '<div class="wallet-head" style="margin-bottom:14px">' +
          '<div class="wallet-cell"><span>当前版本</span><strong>' +
            UI.esc(ipa ? ipa.app_version : (s.app_version || '—')) + '</strong>' +
            '<small>' + UI.esc(ipa ? ipa.file : '—') + '</small></div>' +
          '<div class="wallet-cell"><span>文件大小</span><strong>' +
            UI.esc(ipa && ipa.exists ? ipa.size_text : '未上传') + '</strong>' +
            '<small>' + UI.esc(ipa && ipa.mtime ? ipa.mtime : 'dl 目录为空') + '</small></div>' +
          '<div class="wallet-cell"><span>Bundle ID</span><strong style="font-size:12.5px">' +
            UI.esc(ipa ? ipa.bundle_id : '—') + '</strong><small>OTA 清单固定指向此包</small></div>' +
          '<div class="wallet-cell"><span>状态</span><strong style="font-size:13px">' +
            (ipa && ipa.exists ? '<span class="badge ok">可安装</span>' : '<span class="badge bad">缺少安装包</span>') +
            '</strong><small>装不上时先看这里</small></div>' +
        '</div>' +
        '<div class="bk-actions">' +
          '<label class="field" style="width:150px"><span>版本号</span>' +
            '<input type="text" id="ipaVer" value="' + UI.esc(ipa ? ipa.app_version : (s.app_version || '')) + '" placeholder="1.1.0"></label>' +
          '<label class="field" style="flex:1;min-width:240px"><span>选择 .ipa 文件（最大 300MB）</span>' +
            '<input type="file" id="ipaFile" accept=".ipa"></label>' +
          '<button class="btn primary" id="ipaUp">上传并发布</button>' +
        '</div>' +
        (ipa && ipa.exists
          ? '<p class="td-sub" style="margin-top:12px">下载地址：<a href="' + UI.esc(ipa.download_url) + '" target="_blank">' +
            UI.esc(ipa.download_url) + '</a> · OTA 清单：<a href="' + UI.esc(ipa.manifest_url) + '" target="_blank">manifest.plist</a></p>'
          : '<p class="td-sub" style="margin-top:12px">还没有上传安装包，安装页目前无法安装 App。</p>') +
      '</div>';

      html += '<div style="display:flex;justify-content:flex-end;gap:8px">' +
        '<button class="btn primary" id="saveSettings">保存设置</button></div>';

      view.innerHTML = html;

      var ipaUp = view.querySelector('#ipaUp');
      if (ipaUp) {
        ipaUp.onclick = async function () {
          var input = view.querySelector('#ipaFile');
          var file = input.files && input.files[0];
          if (!file) { UI.toast('请先选择一个 .ipa 文件', 'bad'); return; }
          if (!/\.ipa$/i.test(file.name)) { UI.toast('只支持 .ipa 文件', 'bad'); return; }
          var ver = view.querySelector('#ipaVer').value.trim();
          var fd = new FormData();
          fd.append('file', file);
          if (ver) fd.append('version', ver);
          ipaUp.disabled = true;
          ipaUp.textContent = '上传中…';
          UI.toast('正在上传 ' + (file.size / 1048576).toFixed(1) + ' MB，请勿关闭页面');
          try {
            var res = await fetch((window.API_BASE || '') + '/meiyan-api/index.php?r=admin/ipa-upload', {
              method: 'POST',
              headers: { 'Authorization': 'Bearer ' + API.token() },
              body: fd
            });
            var json = await res.json().catch(function () { return { ok: false, msg: '上传失败（HTTP ' + res.status + '）' }; });
            if (!json.ok) throw new Error(json.msg || '上传失败');
            UI.toast(json.msg || '安装包已更新', 'ok');
            renderSettings(view);
          } catch (e) {
            UI.toast(e.message, 'bad');
            ipaUp.disabled = false;
            ipaUp.textContent = '上传并发布';
          }
        };
      }

      view.querySelector('#saveSettings').onclick = async function () {
        var body = {};
        view.querySelectorAll('[data-s]').forEach(function (el) {
          body[el.getAttribute('data-s')] = el.value;
        });
        try {
          await API.post('settings/save', body);
          UI.toast('设置已保存', 'ok');
          state.settings = await API.get('settings/get');
          if (body.shop_name) {
            $('sideShopName').textContent = body.shop_name;
            document.title = body.shop_name + ' · 管理后台';
          }
        } catch (e) { UI.toast(e.message, 'bad'); }
      };
    } catch (e) {
      view.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  /* ---------------- 启动 ---------------- */

  window.addEventListener('hashchange', route);
  document.addEventListener('DOMContentLoaded', function () {
    try {
      if ($('menuBtn')) $('menuBtn').onclick = function () { $('sidebar').classList.toggle('open'); };
      if ($('refreshBtn')) $('refreshBtn').onclick = function () { route(); };
      boot();
    } catch (e) {
      var m = document.getElementById('loginMsg');
      if (m) m.textContent = '初始化失败：' + (e && e.message ? e.message : e);
    }
  });
})();
