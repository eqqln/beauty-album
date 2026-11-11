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
    { key: 'recharge', title: '充值卡', icon: '💳', cap: 'recharge', sub: '批量生成卡号卡密，App 内直接充值' },
    { key: 'm:wallet', title: '钱包流水', icon: '📒', sub: '充值、消费、调整的完整流水' },
    { group: '系统' },
    { key: 'tenants', title: '板块管理', icon: '🗂️', cap: 'license', sub: '一个激活码一个板块，资料互不掺和' },
    { key: 'license', title: '激活码', icon: '🔑', cap: 'license', sub: '软件授权、设备管理、充能续期' },
    { key: 'staff', title: '员工管理', icon: '🧑‍💼', cap: 'staff', sub: '加员工、设岗位、分权限' },
    { key: 'sms', title: '短信', icon: '✉️', cap: 'sms', sub: '多家短信通道与发送记录' },
    { key: 'backup', title: '数据备份', icon: '💾', cap: 'backup', sub: '一键导出全部数据与图片' },
    { key: 'settings', title: '系统设置', icon: '⚙️', cap: 'settings', sub: '店铺、安装包、开关' }
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
    state.perm = admin.perm || { role: 'viewer', label: '只读', modules: [], caps: {} };
    window.CAN_WRITE_FLAG = !!((state.perm.caps || {}).write);
    $('authView').hidden = true;
    if ($('signupView')) $('signupView').hidden = true;
    $('appView').hidden = false;
    $('userEmail').textContent = admin.email || admin.name;
    $('userAvatar').textContent = (admin.name || admin.email || 'A').slice(0, 1).toUpperCase();
    $('userRole').textContent = state.perm.label || '员工';
    try {
      var s = await API.get('settings/get');
      state.settings = s || {};
      if (s && s.shop_name) {
        $('sideShopName').textContent = s.shop_name;
        document.title = s.shop_name + ' · 管理后台';
      }
    } catch (e) { /* ignore */ }
    buildNav();
    await initTenantPicker();
    if (!location.hash) location.hash = '#/overview';
    route();
  }

  /* ---------------- 板块切换器 ---------------- */

  /**
   * 平台账号（tenant_id = 0）可以在顶栏切换板块，所有列表跟着变。
   * 绑定了板块的员工看不到切换器，永远只看自己那块。
   */
  async function initTenantPicker() {
    var wrap = $('tenantPickWrap');
    var sel = $('tenantPick');
    if (!wrap || !sel) return;
    if ((state.admin && state.admin.tenant_id) > 0) { wrap.hidden = true; return; }

    var rows = [];
    try {
      var r = await API.get('admin/tenant-list');
      rows = (r && r.rows) || [];
    } catch (e) {
      wrap.hidden = true;
      return;
    }
    if (!rows.length) { wrap.hidden = true; return; }

    /* 选中的板块可能已被删除，退回默认板块 */
    var cur = API.tenant();
    if (cur > 0 && !rows.some(function (t) { return t.id === cur; })) {
      API.setTenant(0);
      cur = 0;
    }

    sel.innerHTML = rows.map(function (t) {
      var label = (t.shop_name || t.name || ('板块 #' + t.id));
      if (t.id === 0) label = '默认板块';
      if (t.status !== '正常') label += '（已停用）';
      return '<option value="' + t.id + '"' + (t.id === cur ? ' selected' : '') + '>' +
        UI.esc(label) + '</option>';
    }).join('');
    wrap.hidden = false;

    sel.onchange = async function () {
      API.setTenant(sel.value);
      /* 店名、标语这些跟着板块走，切完要重新读一遍设置 */
      try {
        state.settings = await API.get('settings/get') || {};
        if (state.settings.shop_name) {
          $('sideShopName').textContent = state.settings.shop_name;
          document.title = state.settings.shop_name + ' · 管理后台';
        }
      } catch (e) { /* ignore */ }
      route();
      UI.toast('已切换到「' + (sel.options[sel.selectedIndex] || {}).text + '」', 'ok');
    };
  }

  /* ---------------- 权限判断 ---------------- */

  function canModule(m) {
    var p = state.perm || {};
    return (p.modules || []).indexOf(m) >= 0;
  }
  function canCap(c) {
    var p = state.perm || {};
    return !!(p.caps || {})[c];
  }
  function canWrite() { return canCap('write'); }

  /* 菜单项能不能显示：带 cap 的看能力，带 m: 的看模块，其余默认可见 */
  function navAllowed(n) {
    if (n.cap) return canCap(n.cap);
    if (n.key && n.key.indexOf('m:') === 0) return canModule(n.key.slice(2));
    return true;
  }

  function buildNav() {
    var nav = $('nav');

    /* 先按权限过滤出可见项 */
    var visible = NAV.filter(function (n) { return n.group || navAllowed(n); });

    /* 去掉后面没有子项的空分组 */
    var out = [];
    for (var i = 0; i < visible.length; i++) {
      var n = visible[i];
      if (n.group) {
        var hasChild = false;
        for (var j = i + 1; j < visible.length; j++) {
          if (visible[j].group) break;
          hasChild = true;
          break;
        }
        if (hasChild) out.push('<div class="nav-group">' + UI.esc(n.group) + '</div>');
        continue;
      }
      out.push('<button class="nav-item" data-key="' + n.key + '">' +
        '<span class="ico">' + n.icon + '</span>' + UI.esc(n.title) + '</button>');
    }
    nav.innerHTML = out.join('');
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
    /* 手动改 hash 想进没权限的页面，直接挡回去 */
    if (!navAllowed(nav)) {
      var fallback = NAV.filter(function (n) { return !n.group && navAllowed(n); })[0];
      if (fallback && fallback.key !== nav.key) {
        location.hash = '#/' + fallback.key;
        return;
      }
      $('view').innerHTML = UI.empty('当前账号没有可访问的页面，请联系店主开通权限');
      return;
    }
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
    if (nav.key === 'staff') return renderStaff(view);
    if (nav.key === 'tenants') return renderTenants(view);
    if (nav.key === 'license') return renderLicense(view);
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
            { k: 'api_base', label: '服务器地址', ph: 'https://你的域名' },
            { k: 'app_version', label: '当前版本号', ph: '1.1.0' },
            { k: 'install_note', label: '安装说明', type: 'textarea' }
          ]
        },
        {
          title: '网址显示方式', fields: [
            { k: 'url_display', label: 'App「我的」页里的服务器网址怎么显示', type: 'select',
              options: [
                { v: 'encrypted', t: '加密显示（推荐，别人抄不走域名）' },
                { v: 'plain', t: '明文显示（https://...）' }
              ] }
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
            var ctl;
            if (f.type === 'textarea') {
              ctl = '<textarea data-s="' + f.k + '">' + UI.esc(v) + '</textarea>';
            } else if (f.type === 'select') {
              ctl = '<select data-s="' + f.k + '">' +
                (f.options || []).map(function (o) {
                  return '<option value="' + UI.esc(o.v) + '"' +
                    (String(v) === o.v ? ' selected' : '') + '>' + UI.esc(o.t) + '</option>';
                }).join('') + '</select>';
            } else {
              ctl = '<input type="text" data-s="' + f.k + '" value="' + UI.esc(v) +
                '" placeholder="' + UI.esc(f.ph || '') + '">';
            }
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

  /* ---------------- 软件激活码 ---------------- */

  var LC = { page: 1, size: 20, kw: '', status: '', kind: '' };

  var LC_KINDS = ['试用码', '正式码', '续期码', '演示码', '内部码'];
  var LC_UNITS = ['小时', '天', '周', '月', '季', '年', '永久'];

  function lcBadge(s) {
    var cls = 'gray';
    if (s === '生效中' || s === '已激活') cls = 'ok';
    else if (s === '已停用') cls = 'bad';
    else if (s === '已过期') cls = 'warn';
    else if (s === '未激活') cls = 'info';
    return '<span class="badge ' + cls + '">' + UI.esc(s) + '</span>';
  }

  /** 通用 CSV 导出（带 BOM，Excel 打开不乱码） */
  function csvOut(name, head, keys, rows) {
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

  async function renderLicense(view) {
    view.innerHTML = UI.loading();
    try {
      var s = await API.get('admin/license-stats');
      var def = s.settings || {};

      var cards = [
        { k: '激活码总数', v: UI.num(s.codes_total),
          d: '未激活 ' + UI.num(s.codes_unused) + ' · 已激活 ' + UI.num(s.codes_active), cls: 'rose' },
        { k: '生效设备', v: UI.num(s.devices),
          d: '7 天内到期 ' + UI.num(s.expiring) + ' 台', cls: s.expiring > 0 ? 'bad' : 'ok' },
        { k: '累计充能', v: UI.num(Math.round((s.boost_minutes || 0) / 1440)) + ' 天',
          d: '所有设备累加' },
        { k: '随卡充值', v: UI.money(s.credit_total || 0), d: '已发放到会员钱包', cls: 'ok' }
      ];
      var html = '<div class="grid g4">' + cards.map(function (c) {
        return '<div class="card stat"><div class="k">' + c.k + '</div>' +
          '<div class="v ' + (c.cls || '') + '">' + c.v + '</div>' +
          '<div class="d">' + UI.esc(c.d) + '</div></div>';
      }).join('') + '</div>';

      /* 生成 */
      html += '<div class="card" style="margin:16px 0">' +
        '<div class="rc-head"><strong>生成激活码</strong>' +
          '<span class="td-sub">装完 App 第一次打开必须输入，没激活进不了主界面；一张码可按设备数授权多台</span>' +
          (def.enabled === '1' ? '' : '<span class="badge bad">激活闸门已关闭</span>') +
        '</div>' +
        '<div class="rc-grid">' +
          '<label class="field"><span>种类</span><select id="lcKind">' +
            LC_KINDS.map(function (k) { return '<option value="' + k + '">' + k + '</option>'; }).join('') +
          '</select></label>' +
          '<label class="field"><span>授权时长</span><div class="row-inline">' +
            '<input type="number" id="lcDurVal" value="1" min="0" step="1" inputmode="numeric" style="width:88px">' +
            '<select id="lcDurUnit">' + LC_UNITS.map(function (u) {
              return '<option value="' + u + '"' + (u === '年' ? ' selected' : '') + '>' + u + '</option>';
            }).join('') + '</select></div></label>' +
          '<label class="field"><span>每张可激活设备数</span><input type="number" id="lcDevices" value="1" min="1" max="100" step="1" inputmode="numeric"></label>' +
          '<label class="field"><span>生成数量</span><input type="number" id="lcCount" value="10" min="1" max="500" step="1" inputmode="numeric"></label>' +
          '<label class="field"><span>随卡充值（元）</span><input type="number" id="lcAmount" value="0" min="0" step="1" inputmode="decimal"></label>' +
          '<label class="field"><span>随卡赠送（元）</span><input type="number" id="lcBonus" value="0" min="0" step="1" inputmode="decimal"></label>' +
          '<label class="field"><span>随卡积分</span><input type="number" id="lcPoints" value="0" min="0" step="1" inputmode="numeric"></label>' +
          '<label class="field"><span>码前缀</span><input type="text" id="lcPrefix" value="' + UI.esc(def.prefix || 'MYA') + '" maxlength="6" placeholder="MYA"></label>' +
          '<label class="field"><span>生效日期</span><input type="date" id="lcStart"></label>' +
          '<label class="field"><span>码有效期至</span><input type="date" id="lcExpire" value="' + rcAddDays(Number(def.default_days || 365)) + '"></label>' +
          '<label class="field"><span>批次</span><input type="text" id="lcBatch" placeholder="留空自动用时间戳"></label>' +
          '<label class="field"><span>备注</span><input type="text" id="lcNote" placeholder="如：2026 春季开店铺货（App 端可见提示）"></label>' +
        '</div>' +
        '<div class="rc-presets">' +
          '<span class="td-sub">常用时长：</span>' +
          [['1', '小时'], ['1', '天'], ['7', '天'], ['1', '月'], ['3', '月'], ['1', '年'], ['0', '永久']].map(function (p, i) {
            return '<button type="button" class="chip-btn" data-lcdur="' + p[0] + '|' + p[1] + '">' +
              (p[1] === '永久' ? '永久' : p[0] + p[1]) + '</button>';
          }).join('') +
          '<span class="td-sub" style="margin-left:16px">随卡：</span>' +
          [0, 100, 200, 500, 1000].map(function (v) {
            return '<button type="button" class="chip-btn" data-lcamt="' + v + '">' + (v === 0 ? '不充值' : '¥' + v) + '</button>';
          }).join('') +
        '</div>' +
        '<div class="rc-foot">' +
          '<span class="td-sub" id="lcPreview">—</span><div style="flex:1"></div>' +
          '<button class="btn ghost" id="lcExport">导出全部 CSV</button>' +
          '<button class="btn primary" id="lcGen">立即生成</button>' +
        '</div>' +
      '</div>';

      /* 授权设置 */
      html += '<div class="card" style="margin-bottom:16px">' +
        '<div class="rc-head"><strong>授权设置</strong>' +
          '<span class="td-sub">关闭后 App 不再要求激活（老客户应急用，正常保持开启）</span></div>' +
        '<div class="rc-grid">' +
          '<label class="field"><span>激活闸门</span><select id="lcEnabled">' +
            '<option value="1"' + (def.enabled === '1' ? ' selected' : '') + '>开启（必须激活）</option>' +
            '<option value="0"' + (def.enabled !== '1' ? ' selected' : '') + '>关闭（谁都能用）</option>' +
          '</select></label>' +
          '<label class="field"><span>默认有效期（天）</span><input type="number" id="lcDefaultDays" value="' + Number(def.default_days || 365) + '" min="0" max="3650" step="1"></label>' +
          '<label class="field"><span>到期宽限（天）</span><input type="number" id="lcGrace" value="' + Number(def.grace_days || 7) + '" min="0" max="365" step="1"></label>' +
          '<label class="field"><span>联系门店文案</span><input type="text" id="lcContact" value="' + UI.esc(def.contact || '') + '" placeholder="请联系门店获取激活码"></label>' +
          '<label class="field" style="grid-column:1/-1"><span>App 激活页提示</span><input type="text" id="lcNotice" value="' + UI.esc(def.notice || '') + '" placeholder="本软件需激活后使用，激活码可向门店索取。"></label>' +
        '</div>' +
        '<div class="rc-foot"><div style="flex:1"></div>' +
          '<button class="btn primary" id="lcSaveSettings">保存设置</button></div>' +
      '</div>';

      /* 列表 */
      html += '<div class="toolbar">' +
        '<input class="search" id="lcKw" placeholder="搜激活码 / 备注">' +
        '<select id="lcStatusSel" class="rc-select">' +
          ['', '未激活', '已激活', '已停用', '已过期'].map(function (v) {
            return '<option value="' + v + '">' + (v === '' ? '全部状态' : v) + '</option>';
          }).join('') + '</select>' +
        '<select id="lcKindSel" class="rc-select">' +
          [''].concat(LC_KINDS).map(function (v) {
            return '<option value="' + v + '">' + (v === '' ? '全部种类' : v) + '</option>';
          }).join('') + '</select>' +
        '<div style="flex:1"></div><span class="td-sub" id="lcTotal"></span>' +
      '</div>' +
      '<div class="card" style="padding:0;overflow:hidden"><div id="lcTable">' + UI.loading() + '</div></div>' +
      '<div id="lcPager" class="rc-pager"></div>' +
      '<div id="lcLogs" style="margin-top:18px"></div>';

      view.innerHTML = html;
      bindLicense(view);
      await loadLicenseCodes(view);
    } catch (e) {
      view.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  function bindLicense(view) {
    var $v = function (id) { return view.querySelector('#' + id); };

    function preview() {
      var val = Number($v('lcDurVal').value) || 0;
      var unit = $v('lcDurUnit').value;
      var cnt = Number($v('lcCount').value) || 0;
      var dev = Number($v('lcDevices').value) || 1;
      var amt = Number($v('lcAmount').value) || 0;
      var bonus = Number($v('lcBonus').value) || 0;
      var pts = Number($v('lcPoints').value) || 0;
      var parts = ['每张 ' + (unit === '永久' ? '永久' : val + unit), dev + ' 台设备'];
      if (amt + bonus > 0) parts.push('随卡 ' + UI.money(amt + bonus));
      if (pts > 0) parts.push('送 ' + pts + ' 积分');
      $v('lcPreview').textContent = '将生成 ' + cnt + ' 张 · ' + parts.join(' · ');
    }

    ['lcDurVal', 'lcDurUnit', 'lcCount', 'lcDevices', 'lcAmount', 'lcBonus', 'lcPoints']
      .forEach(function (id) { $v(id).addEventListener('input', preview); });
    $v('lcDurUnit').addEventListener('change', preview);
    preview();

    view.querySelectorAll('[data-lcdur]').forEach(function (b) {
      b.onclick = function () {
        var p = b.getAttribute('data-lcdur').split('|');
        $v('lcDurVal').value = p[0];
        $v('lcDurUnit').value = p[1];
        if (p[1] === '永久') $v('lcDurVal').value = 0;
        preview();
      };
    });
    view.querySelectorAll('[data-lcamt]').forEach(function (b) {
      b.onclick = function () { $v('lcAmount').value = b.getAttribute('data-lcamt'); preview(); };
    });

    $v('lcGen').onclick = async function () {
      var unit = $v('lcDurUnit').value;
      var body = {
        kind: $v('lcKind').value,
        duration_value: unit === '永久' ? 0 : (Number($v('lcDurVal').value) || 0),
        duration_unit: unit,
        max_devices: Number($v('lcDevices').value) || 1,
        count: Number($v('lcCount').value) || 1,
        amount: Number($v('lcAmount').value) || 0,
        bonus: Number($v('lcBonus').value) || 0,
        points: Number($v('lcPoints').value) || 0,
        prefix: $v('lcPrefix').value.trim() || 'MYA',
        start_at: $v('lcStart').value,
        expire_at: $v('lcExpire').value,
        batch: $v('lcBatch').value.trim(),
        note: $v('lcNote').value.trim()
      };
      if (unit !== '永久' && body.duration_value <= 0) {
        UI.toast('授权时长要大于 0，永久码请把单位选成「永久」', 'bad');
        return;
      }
      if (body.count > 500) { UI.toast('一次最多生成 500 张', 'bad'); return; }
      if (body.start_at && body.expire_at && body.start_at > body.expire_at) {
        UI.toast('生效日期不能晚于有效期', 'bad');
        return;
      }
      $v('lcGen').disabled = true;
      try {
        var res = await API.post('admin/license-generate', body);
        UI.toast('已生成 ' + res.count + ' 张，批次 ' + res.batch, 'ok');
        showLicenseCodes(res, body);
        LC.page = 1;
        await renderLicense(view);
      } catch (e) {
        UI.toast(e.message, 'bad');
        $v('lcGen').disabled = false;
      }
    };

    $v('lcExport').onclick = async function () {
      try {
        var res = await API.get('admin/license-export');
        var rows = res.rows || [];
        if (!rows.length) { UI.toast('还没有激活码', 'bad'); return; }
        csvOut('激活码-' + rcDate(new Date()) + '.csv',
          ['激活码', '种类', '授权时长', '设备上限', '已激活', '随卡金额', '赠送', '积分', '生效日期', '有效期至', '状态', '批次', '备注', '生成时间'],
          ['code_pretty', 'kind', 'duration_text', 'max_devices', 'used_count', 'amount', 'bonus', 'points', 'start_at', 'expire_at', 'status', 'batch', 'note', 'created_at'],
          rows);
        UI.toast('已导出 ' + rows.length + ' 张', 'ok');
      } catch (e) { UI.toast(e.message, 'bad'); }
    };

    $v('lcSaveSettings').onclick = async function () {
      var b = $v('lcSaveSettings');
      b.disabled = true;
      try {
        await API.post('admin/license-settings', {
          license_enabled: $v('lcEnabled').value,
          license_default_days: Number($v('lcDefaultDays').value) || 0,
          license_grace_days: Number($v('lcGrace').value) || 0,
          license_contact: $v('lcContact').value.trim(),
          license_notice: $v('lcNotice').value.trim(),
          license_prefix: $v('lcPrefix').value.trim() || 'MYA'
        });
        UI.toast('授权设置已保存', 'ok');
      } catch (e) { UI.toast(e.message, 'bad'); }
      b.disabled = false;
    };

    var kw = $v('lcKw');
    var timer = null;
    kw.oninput = function () {
      clearTimeout(timer);
      timer = setTimeout(function () { LC.kw = kw.value.trim(); LC.page = 1; loadLicenseCodes(view); }, 320);
    };
    $v('lcStatusSel').onchange = function () { LC.status = this.value; LC.page = 1; loadLicenseCodes(view); };
    $v('lcKindSel').onchange = function () { LC.kind = this.value; LC.page = 1; loadLicenseCodes(view); };
  }

  async function loadLicenseCodes(view) {
    var wrap = view.querySelector('#lcTable');
    var pager = view.querySelector('#lcPager');
    var totalEl = view.querySelector('#lcTotal');
    if (!wrap) return;
    wrap.innerHTML = UI.loading();
    pager.innerHTML = '';
    try {
      var res = await API.get('admin/license-list', {
        page: LC.page, size: LC.size, kw: LC.kw, status: LC.status, kind: LC.kind
      });
      var rows = res.rows || [];
      if (totalEl) totalEl.textContent = '共 ' + UI.num(res.total) + ' 张';

      if (!rows.length) {
        wrap.innerHTML = UI.empty(LC.kw || LC.status || LC.kind ? '没有匹配的激活码' : '还没有激活码，在上面生成一批吧', '🔑');
        return;
      }

      var body = rows.map(function (r) {
        var used = '<span class="td-main">' + r.used_count + ' / ' + r.max_devices + '</span>';
        var money = (r.amount || r.bonus || r.points)
          ? UI.money((r.amount || 0) + (r.bonus || 0)) + (r.points ? '<div class="td-sub">' + r.points + ' 积分</div>' : '')
          : '<span class="td-sub">—</span>';
        var valid = (r.start_at || r.expire_at)
          ? UI.esc((r.start_at || '不限') + ' ~ ' + (r.expire_at || '长期'))
          : '<span class="td-sub">长期有效</span>';
        var acts = '<button class="btn sm ghost" data-lcdev="' + r.id + '">设备</button> ';
        if (r.used_count > 0) {
          acts += '<button class="btn sm ghost" data-lcboost="' + r.id + '">充能</button> ';
        }
        acts += '<button class="btn sm ghost" data-lcvoid="' + r.id + '" data-void="' + (r.status === '已停用' ? 0 : 1) + '">' +
                (r.status === '已停用' ? '恢复' : '停用') + '</button> ';
        acts += '<button class="btn sm danger" data-lcdel="' + r.id + '">删除</button>';
        return '<tr>' +
          '<td><div class="mono td-main">' + UI.esc(r.code_pretty) + '</div>' +
            '<div class="td-sub">' + UI.esc(r.batch || '—') + (r.note ? ' · ' + UI.esc(r.note) : '') + '</div></td>' +
          '<td>' + UI.badge(r.kind) + '</td>' +
          '<td class="td-main">' + (r.permanent ? '永久' : UI.esc(r.duration_text)) + '</td>' +
          '<td>' + used + '</td>' +
          '<td>' + money + '</td>' +
          '<td class="td-sub">' + valid + '</td>' +
          '<td>' + lcBadge(r.status) + '</td>' +
          '<td class="td-actions">' + acts + '</td>' +
        '</tr>';
      }).join('');

      wrap.innerHTML = '<div style="overflow-x:auto"><table><thead><tr>' +
        '<th>激活码 / 批次</th><th>种类</th><th>授权时长</th><th>设备</th><th>随卡充值</th>' +
        '<th>码有效期</th><th>状态</th><th></th></tr></thead><tbody>' + body + '</tbody></table></div>';

      var pages = Math.max(1, Math.ceil((res.total || 0) / LC.size));
      pager.innerHTML = '<span class="td-sub">第 ' + LC.page + ' / ' + pages + ' 页</span>' +
        (LC.page > 1 ? '<button class="btn sm ghost" id="lcPrev">上一页</button>' : '') +
        (LC.page < pages ? '<button class="btn sm ghost" id="lcNext">下一页</button>' : '');
      var prev = pager.querySelector('#lcPrev');
      var next = pager.querySelector('#lcNext');
      if (prev) prev.onclick = function () { LC.page--; loadLicenseCodes(view); };
      if (next) next.onclick = function () { LC.page++; loadLicenseCodes(view); };

      wrap.querySelectorAll('[data-lcdev]').forEach(function (b) {
        b.onclick = function () { showDevices(Number(b.getAttribute('data-lcdev'))); };
      });
      wrap.querySelectorAll('[data-lcboost]').forEach(function (b) {
        b.onclick = function () {
          var id = Number(b.getAttribute('data-lcboost'));
          var row = rows.find(function (x) { return Number(x.id) === id; });
          boostDialog(id, row);
        };
      });
      wrap.querySelectorAll('[data-lcvoid]').forEach(function (b) {
        b.onclick = function () {
          var id = Number(b.getAttribute('data-lcvoid'));
          var toVoid = b.getAttribute('data-void') === '1';
          if (!toVoid) {
            API.post('admin/license-void', { id: id, void: 0 }).then(function () {
              UI.toast('已恢复', 'ok');
              loadLicenseCodes(view);
            }).catch(function (e) { UI.toast(e.message, 'bad'); });
            return;
          }
          UI.confirm('停用激活码',
            '停用后这张码下的所有设备立刻无法使用 App，已激活的资料还在服务器上，恢复后可以继续用。确定停用？',
            function () {
              API.post('admin/license-void', { id: id, void: 1 }).then(function () {
                UI.toast('已停用', 'ok');
                loadLicenseCodes(view);
              }).catch(function (e) { UI.toast(e.message, 'bad'); });
            }, true);
        };
      });
      wrap.querySelectorAll('[data-lcdel]').forEach(function (b) {
        b.onclick = function () {
          var id = Number(b.getAttribute('data-lcdel'));
          UI.confirm('删除激活码', '删除后这张码和它的设备记录一起消失，且无法恢复。确定删除？', function () {
            API.post('admin/license-delete', { id: id }).then(function () {
              UI.toast('已删除', 'ok');
              loadLicenseCodes(view);
            }).catch(function (e) { UI.toast(e.message, 'bad'); });
          }, true);
        };
      });
    } catch (e) {
      wrap.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  /** 生成结果：列出明文码，支持一键复制全部 */
  function showLicenseCodes(res, body) {
    var rows = res.rows || [];
    var all = rows.map(function (r) { return r.code; }).join('\n');
    var html = '<p class="td-sub" style="margin:0 0 10px">批次 ' + UI.esc(res.batch) + ' · ' +
      UI.esc(body.kind) + ' · ' + (body.duration_unit === '永久' ? '永久' : body.duration_value + body.duration_unit) +
      ' · ' + body.max_devices + ' 台/张 · 共 ' + rows.length + ' 张。这些码只在这里显示一次，请先导出或复制保存。</p>' +
      '<div style="max-height:340px;overflow:auto;border:1px solid #eee;border-radius:10px;padding:10px 12px;background:#fcfafb">' +
      rows.map(function (r) { return '<div class="mono" style="padding:3px 0">' + UI.esc(r.code) + '</div>'; }).join('') +
      '</div>';
    UI.modal({
      title: '已生成 ' + rows.length + ' 张激活码',
      body: html,
      buttons: [
        { label: '复制全部', kind: 'ghost', onClick: function (m) {
            copyText(all).then(function () { UI.toast('已复制 ' + rows.length + ' 张码', 'ok'); m.close(); })
              .catch(function () { UI.toast('复制失败，请手动选中', 'bad'); });
          } },
        { label: '关闭', kind: 'primary' }
      ]
    });
  }

  /** 设备明细 */
  async function showDevices(codeId) {
    var m = UI.modal({ title: '设备授权', body: UI.loading(), wide: true });
    try {
      var res = await API.get('admin/license-devices', codeId > 0 ? { code_id: codeId } : {});
      var rows = res.rows || [];
      if (!rows.length) {
        m.body.innerHTML = UI.empty('这张码还没有设备激活', '📱');
        return;
      }
      m.body.innerHTML = '<div style="overflow-x:auto"><table><thead><tr>' +
        '<th>设备</th><th>激活码</th><th>版本</th><th>激活时间</th><th>剩余</th><th>最近在线</th><th>状态</th><th></th>' +
        '</tr></thead><tbody>' + rows.map(function (d) {
          return '<tr>' +
            '<td><div class="td-main mono">' + UI.esc(d.device_short) + '</div>' +
              '<div class="td-sub">' + UI.esc(d.device_name || '未命名设备') + ' · ' + UI.esc(d.platform || 'iOS') + '</div></td>' +
            '<td class="mono td-sub">' + UI.esc(d.code_pretty) + '</td>' +
            '<td class="td-sub">' + UI.esc(d.app_version || '—') + '</td>' +
            '<td class="td-sub">' + UI.fmtDate(d.activated_at) + '</td>' +
            '<td class="td-main">' + UI.esc(d.left_text) + '</td>' +
            '<td class="td-sub">' + UI.fmtDate(d.last_seen_at) + '</td>' +
            '<td>' + lcBadge(d.status) + '</td>' +
            '<td class="td-actions">' + (d.status === '已解绑'
              ? '<span class="td-sub">名额已收回</span>'
              : '<button class="btn sm ghost" data-dvoid="' + d.id + '" data-void="' +
                  (d.status === '已停用' ? 0 : 1) + '">' + (d.status === '已停用' ? '恢复' : '停用') + '</button> ' +
                '<button class="btn sm ghost" data-dunbind="' + d.id + '">解绑</button>') +
            '</td>' +
          '</tr>';
        }).join('') + '</tbody></table></div>';

      m.body.querySelectorAll('[data-dunbind]').forEach(function (b) {
        b.onclick = function () {
          UI.confirm('解绑这台设备',
            '解绑只做两件事：把这张码的 1 个设备名额收回来，并让这台手机下次打开时要求重新激活。\n' +
            '板块里的客户、相册、护理步骤、预约、收款一条都不会动，服务器上原样保留。\n' +
            '换手机时先在这里解绑旧机，再让新机用同一张激活码激活即可。',
            async function () {
              try {
                await API.post('admin/license-device-unbind', { id: Number(b.getAttribute('data-dunbind')) });
                UI.toast('已解绑，名额可以给新手机用了', 'ok');
                m.close();
                showDevices(codeId);
              } catch (e) { UI.toast(e.message, 'bad'); }
            }, false, '确认解绑');
        };
      });

      m.body.querySelectorAll('[data-dvoid]').forEach(function (b) {
        b.onclick = async function () {
          try {
            await API.post('admin/license-device-void', {
              id: Number(b.getAttribute('data-dvoid')),
              void: Number(b.getAttribute('data-void'))
            });
            UI.toast('已更新', 'ok');
            m.close();
            showDevices(codeId);
          } catch (e) { UI.toast(e.message, 'bad'); }
        };
      });
    } catch (e) {
      m.body.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  /** 充能：给单台设备或整张码下的所有设备延长授权 */
  function boostDialog(codeId, row) {
    var html = '<div class="rc-grid" style="grid-template-columns:1fr 1fr">' +
      '<label class="field"><span>延长天数</span><input type="number" id="lcBoostDays" value="30" min="1" max="3650" step="1"></label>' +
      '<label class="field"><span>作用范围</span><select id="lcBoostTarget">' +
        '<option value="code">这张码下所有设备（' + (row ? row.used_count : 0) + ' 台）</option>' +
        '<option value="device">只给单台设备（下一屏选）</option>' +
      '</select></label>' +
      '<label class="field" style="grid-column:1/-1"><span>备注</span><input type="text" id="lcBoostNote" placeholder="如：客户续费一年"></label>' +
      '</div>' +
      '<p class="td-sub" style="margin:10px 0 0">已在有效期内的设备从原到期时间往后顺延；永久授权的设备不受影响。</p>';
    var m = UI.modal({
      title: '充能续期 · ' + (row ? row.code_pretty : ''),
      body: html,
      buttons: [
        { label: '取消', kind: 'ghost' },
        { label: '确定充能', kind: 'primary', onClick: async function () {
            var target = m.body.querySelector('#lcBoostTarget').value;
            var days = Number(m.body.querySelector('#lcBoostDays').value) || 0;
            var note = m.body.querySelector('#lcBoostNote').value.trim();
            if (days <= 0) { UI.toast('天数要大于 0', 'bad'); return; }
            if (target === 'device') { m.close(); boostSingleDevice(codeId, days, note); return; }
            try {
              var r = await API.post('admin/license-boost', { id: codeId, target: 'code', days: days, note: note });
              UI.toast('已为 ' + r.updated + ' 台设备充能 +' + days + ' 天', 'ok');
              m.close();
              var v = document.querySelector('#view');
              if (v) loadLicenseCodes(v);
            } catch (e) { UI.toast(e.message, 'bad'); }
          } }
      ]
    });
  }

  /** 只给一台设备充能：先拉设备列表让用户选 */
  async function boostSingleDevice(codeId, days, note) {
    var m = UI.modal({ title: '选择要充能的设备', body: UI.loading(), wide: true });
    try {
      var res = await API.get('admin/license-devices', { code_id: codeId });
      var rows = res.rows || [];
      if (!rows.length) { m.body.innerHTML = UI.empty('这张码还没有设备', '📱'); return; }
      m.body.innerHTML = '<div style="overflow-x:auto"><table><thead><tr>' +
        '<th>设备</th><th>激活时间</th><th>剩余</th><th>状态</th><th></th></tr></thead><tbody>' +
        rows.map(function (d) {
          return '<tr><td><div class="td-main mono">' + UI.esc(d.device_short) + '</div>' +
            '<div class="td-sub">' + UI.esc(d.device_name || '未命名') + '</div></td>' +
            '<td class="td-sub">' + UI.fmtDate(d.activated_at) + '</td>' +
            '<td class="td-main">' + UI.esc(d.left_text) + '</td>' +
            '<td>' + lcBadge(d.status) + '</td>' +
            '<td class="td-actions"><button class="btn sm primary" data-dboost="' + d.id + '">充能 +' + days + ' 天</button></td></tr>';
        }).join('') + '</tbody></table></div>';
      m.body.querySelectorAll('[data-dboost]').forEach(function (b) {
        b.onclick = async function () {
          try {
            var r = await API.post('admin/license-boost', {
              id: Number(b.getAttribute('data-dboost')), target: 'device', days: days, note: note
            });
            UI.toast('已充能至 ' + (r.expire_at || '永久'), 'ok');
            m.close();
            var v = document.querySelector('#view');
            if (v) loadLicenseCodes(v);
          } catch (e) { UI.toast(e.message, 'bad'); }
        };
      });
    } catch (e) { m.body.innerHTML = UI.empty(e.message, '⚠️'); }
  }

  /* ---------------- 员工管理 ---------------- */

  var ROLE_CACHE = null;
  var MODULE_LABEL = {
    packages: '套餐', members: '会员', mentors: '导师', products: '产品', agents: '代理',
    orders: '拿货', customers: '客户', photos: '相册', compares: '对比图', payments: '收款',
    subs: '套餐开通', wallet: '钱包流水', appointments: '预约', steps: '护理步骤',
    notes: '客户笔记', claims: '产品领用'
  };
  var CAP_LABEL = {
    write: '允许修改数据', staff: '员工管理', settings: '系统设置',
    backup: '数据备份', sms: '短信通道', recharge: '充值卡',
    license: '激活码授权', sync: 'App 同步'
  };

  async function loadRoles() {
    if (ROLE_CACHE) return ROLE_CACHE;
    ROLE_CACHE = await API.get('staff/roles');
    return ROLE_CACHE;
  }

  function permBadges(p) {
    var caps = p.caps || {};
    var out = [];
    if (!caps.write) out.push('<span class="badge gray">只读</span>');
    if (caps.staff) out.push('<span class="badge info">员工</span>');
    if (caps.settings) out.push('<span class="badge info">设置</span>');
    if (caps.recharge) out.push('<span class="badge info">充值</span>');
    if (caps.backup) out.push('<span class="badge info">备份</span>');
    if (caps.sms) out.push('<span class="badge info">短信</span>');
    return out.join(' ');
  }

  /* ---------------- 板块管理 ---------------- */

  /**
   * 一个激活码 = 一个板块。
   * 这里列出所有板块，点「进入」就把顶栏切过去，之后所有页面都只看那一块的数据。
   */
  async function renderTenants(view) {
    var kw = '';
    var data = null;

    async function load() {
      try {
        data = await API.get('admin/tenant-list', kw ? { kw: kw } : null);
      } catch (e) {
        view.innerHTML = UI.empty(e.message, '⚠️');
        return;
      }
      paint();
    }

    function card(t) {
      var c = t.counts || {};
      var on = (data && data.current) === t.id;
      var off = t.status !== '正常';
      var nums = [
        ['客户', c.customers || 0],
        ['照片', c.photos || 0],
        ['步骤', c.steps || 0],
        ['产品', c.products || 0],
        ['预约', c.appointments || 0]
      ].map(function (x) {
        return '<div><b>' + UI.num(x[1]) + '</b><span>' + x[0] + '</span></div>';
      }).join('');

      var title = t.id === 0 ? '默认板块' : (t.shop_name || t.name || ('板块 #' + t.id));
      var sub = [];
      if (t.name && t.name !== title) sub.push('使用者 ' + t.name);
      if (t.phone) sub.push(t.phone);
      if (t.code) sub.push(t.code);
      if (t.license_left) sub.push('授权 ' + t.license_left);

      return '<div class="tenant-card' + (on ? ' on' : '') + '" data-id="' + t.id + '">' +
        '<div class="tenant-head">' +
          '<div style="flex:1;min-width:0">' +
            '<div class="tenant-name">' + UI.esc(title) + '</div>' +
            '<div class="tenant-sub">' + UI.esc(sub.join(' · ') || '还没有归属人') + '</div>' +
          '</div>' +
          (on ? '<span class="tenant-badge">当前</span>' : '') +
          (off ? '<span class="tenant-badge off">已停用</span>' : '') +
          (t.restore_flag ? '<span class="tenant-badge">待恢复</span>' : '') +
        '</div>' +
        '<div class="tenant-nums">' + nums + '</div>' +
        '<div class="tenant-acts">' +
          (on
            ? (t.id === 0 ? '' : '<button class="btn ghost sm" data-act="leave">回到默认板块</button>')
            : '<button class="btn primary sm" data-act="enter">进入这个板块</button>') +
          '<button class="btn ghost sm" data-act="backup">⬇ 备份下载</button>' +
          '<button class="btn ghost sm" data-act="restore">恢复到手机</button>' +
          '<button class="btn ghost sm" data-act="edit">编辑</button>' +
          '<button class="btn ghost sm" data-act="toggle">' + (off ? '启用' : '停用') + '</button>' +
          (t.id === 0 ? '' : '<button class="btn ghost sm" data-act="del">删除</button>') +
        '</div>' +
      '</div>';
    }

    function paint() {
      var rows = (data && data.rows) || [];
      var total = rows.length;
      view.innerHTML =
        '<div class="card" style="margin-bottom:16px">' +
          '<div class="rc-head">' +
            '<strong>板块管理</strong>' +
            '<span class="td-sub">每个激活码对应一个人、一块独立资料区。客户、相册、护理步骤、产品、预约都只属于自己那块，和别人不掺和</span>' +
          '</div>' +
          '<div class="bk-actions" style="margin-top:12px">' +
            '<label class="field" style="flex:1;min-width:200px"><span>搜索</span>' +
              '<input type="text" id="tnKw" value="' + UI.esc(kw) + '" placeholder="姓名 / 电话 / 板块名 / 激活码"></label>' +
            '<button class="btn ghost" id="tnSearch">搜索</button>' +
            '<button class="btn primary" id="tnNew">手工开一个板块</button>' +
          '</div>' +
          '<p class="td-sub" style="margin-top:10px">共 ' + total + ' 个板块。正常情况下不需要手工建：客户在 App 里输激活码并填姓名电话，系统会自动给他开板块。</p>' +
        '</div>' +
        (rows.length
          ? '<div class="tenant-grid">' + rows.map(card).join('') + '</div>'
          : UI.empty('还没有板块', '🗂️'));

      var sBtn = $('tnSearch');
      if (sBtn) sBtn.onclick = function () { kw = ($('tnKw').value || '').trim(); load(); };
      var kIn = $('tnKw');
      if (kIn) kIn.onkeydown = function (e) { if (e.key === 'Enter') { kw = kIn.value.trim(); load(); } };
      var nBtn = $('tnNew');
      if (nBtn) nBtn.onclick = newTenant;

      view.querySelectorAll('.tenant-card').forEach(function (el) {
        var id = parseInt(el.getAttribute('data-id'), 10);
        var t = rows.filter(function (x) { return x.id === id; })[0];
        if (!t) return;
        el.querySelectorAll('[data-act]').forEach(function (b) {
          b.onclick = function () { act(b.getAttribute('data-act'), t); };
        });
      });
    }

    async function act(a, t) {
      if (a === 'enter' || a === 'leave') {
        API.setTenant(a === 'leave' ? 0 : t.id);
        try {
          state.settings = await API.get('settings/get') || {};
          if (state.settings.shop_name) {
            $('sideShopName').textContent = state.settings.shop_name;
            document.title = state.settings.shop_name + ' · 管理后台';
          }
        } catch (e) { /* ignore */ }
        await initTenantPicker();
        route();
        UI.toast(a === 'leave' ? '已回到默认板块' : ('已进入「' + (t.shop_name || t.name) + '」'), 'ok');
        return;
      }

      if (a === 'backup') {
        var nm = t.shop_name || t.name || ('板块 #' + t.id);
        UI.confirm('备份并下载「' + nm + '」',
          '把这一个板块的全部资料打成压缩包：客户、相册、护理步骤、预约、产品、会员、收款、充值卡、授权记录，连同图片和视频。\n只含这一个板块，不含别人的数据。资料多的时候要等十几秒。',
          async function () {
            UI.toast('正在打包，请稍候…');
            try {
              var r = await API.post('admin/tenant-export', { id: t.id });
              await API.download('admin/tenant-export-download', { id: t.id, file: r.file }, r.file);
              UI.toast('已下载 · ' + r.rows + ' 条数据 / ' + r.media + ' 个文件 / ' + r.size_text, 'ok');
              load();
            } catch (e) { UI.toast(e.message, 'bad'); }
          }, false, '开始备份');
        return;
      }

      if (a === 'restore') {
        UI.confirm('恢复到手机',
          '标记之后，' + (t.shop_name || t.name) + ' 下次打开 App 或激活时，会自动把服务器上的全部资料下载到手机并覆盖本机数据。确认吗？',
          async function () {
            try {
              await API.post('admin/tenant-restore', { id: t.id });
              UI.toast('已标记，等他打开 App 就会自动恢复', 'ok');
              load();
            } catch (e) { UI.toast(e.message, 'bad'); }
          });
        return;
      }

      if (a === 'toggle') {
        var next = t.status === '正常' ? '停用' : '正常';
        try {
          await API.post('admin/tenant-save', { id: t.id, status: next });
          UI.toast('已' + (next === '正常' ? '启用' : '停用'), 'ok');
          load();
        } catch (e) { UI.toast(e.message, 'bad'); }
        return;
      }

      if (a === 'del') {
        UI.confirm('删除板块',
          '会连同这个板块里的客户、相册、步骤、产品、预约一起删掉，不能恢复。确认删除「' + (t.shop_name || t.name) + '」？',
          async function () {
            try {
              await API.post('admin/tenant-delete', { id: t.id });
              UI.toast('板块已删除', 'ok');
              load();
            } catch (e) { UI.toast(e.message, 'bad'); }
          }, true);
        return;
      }

      if (a === 'edit') editTenant(t);
    }

    function editTenant(t) {
      var m = UI.modal({
        title: '编辑板块',
        body:
          '<div style="display:grid;gap:12px">' +
            '<label class="field"><span>使用者姓名</span><input type="text" id="teName" value="' + UI.esc(t.name || '') + '"></label>' +
            '<label class="field"><span>手机号</span><input type="text" id="tePhone" value="' + UI.esc(t.phone || '') + '"></label>' +
            '<label class="field"><span>板块名称（显示在 App 上）</span><input type="text" id="teShop" value="' + UI.esc(t.shop_name || '') + '"></label>' +
            '<label class="field"><span>备注</span><input type="text" id="teNote" value="' + UI.esc(t.note || '') + '"></label>' +
          '</div>',
        buttons: [
          { label: '取消', kind: 'ghost' },
          { label: '保存', kind: 'primary', onClick: async function (mm) {
              try {
                await API.post('admin/tenant-save', {
                  id: t.id,
                  name: $('teName').value.trim(),
                  phone: $('tePhone').value.trim(),
                  shop_name: $('teShop').value.trim(),
                  note: $('teNote').value.trim()
                });
                mm.close();
                UI.toast('已保存', 'ok');
                load();
              } catch (e) { UI.toast(e.message, 'bad'); }
            } }
        ]
      });
      return m;
    }

    function newTenant() {
      UI.modal({
        title: '手工开一个板块',
        body:
          '<div style="display:grid;gap:12px">' +
            '<label class="field"><span>使用者姓名</span><input type="text" id="tnName" placeholder="例如 宁子"></label>' +
            '<label class="field"><span>手机号</span><input type="text" id="tnPhone" placeholder="用于认人，同一个人换码不会丢数据"></label>' +
            '<label class="field"><span>板块名称</span><input type="text" id="tnShop" placeholder="留空则用姓名"></label>' +
          '</div>' +
          '<p class="td-sub" style="margin-top:10px">建好之后在「激活码」页生成一张码，把码发给他；他激活时填同样的姓名电话，资料就落进这块。</p>',
        buttons: [
          { label: '取消', kind: 'ghost' },
          { label: '创建', kind: 'primary', onClick: async function (m) {
              try {
                await API.post('admin/tenant-create', {
                  name: $('tnName').value.trim(),
                  phone: $('tnPhone').value.trim(),
                  shop_name: $('tnShop').value.trim()
                });
                m.close();
                UI.toast('板块已创建', 'ok');
                load();
              } catch (e) { UI.toast(e.message, 'bad'); }
            } }
        ]
      });
    }

    await load();
  }

  async function renderStaff(view) {
    try {
      var rolesInfo = await loadRoles();
      var roles = rolesInfo.roles || [];
      var roleMap = {};
      roles.forEach(function (r) { roleMap[r.key] = r; });

      var rows = await API.get('staff/list');

      var html = '<div class="toolbar">' +
        '<div class="td-sub">共 ' + rows.length + ' 个账号 · 权限分「角色预设」和「单独调整」两层</div>' +
        '<div style="flex:1"></div>' +
        '<button class="btn primary" id="addStaff">+ 添加员工</button>' +
        '</div>' +
        '<div class="card" style="padding:0;overflow:hidden">' +
        '<table class="table"><thead><tr>' +
        '<th>姓名</th><th>账号</th><th>手机号</th><th>岗位</th><th>权限</th><th>状态</th><th>最近登录</th><th style="width:190px">操作</th>' +
        '</tr></thead><tbody>' +
        rows.map(function (r) {
          var isMe = state.admin && r.id === state.admin.id;
          return '<tr>' +
            '<td><strong>' + UI.esc(r.name) + '</strong>' + (isMe ? ' <span class="badge info">我</span>' : '') +
              (r.note ? '<div class="td-sub">' + UI.esc(r.note) + '</div>' : '') + '</td>' +
            '<td class="td-sub">' + UI.esc(r.email || '—') + '</td>' +
            '<td class="td-sub">' + UI.esc(r.phone || '—') + '</td>' +
            '<td>' + UI.esc(r.role_label) + '</td>' +
            '<td>' + permBadges(r.perm) + '</td>' +
            '<td>' + UI.badge(r.status) + '</td>' +
            '<td class="td-sub">' + UI.esc(r.last_login ? String(r.last_login).slice(0, 16) : '—') + '</td>' +
            '<td>' +
              '<button class="btn ghost sm" data-edit="' + r.id + '">编辑</button> ' +
              '<button class="btn ghost sm" data-pwd="' + r.id + '">改密码</button> ' +
              (isMe ? '' : '<button class="btn ghost sm" data-del="' + r.id + '">删除</button>') +
            '</td>' +
          '</tr>';
        }).join('') +
        '</tbody></table></div>';

      view.innerHTML = html;

      view.querySelector('#addStaff').onclick = function () { openStaffForm(null, roles, roleMap, view); };
      view.querySelectorAll('[data-edit]').forEach(function (b) {
        b.onclick = function () {
          var id = +b.getAttribute('data-edit');
          var row = rows.filter(function (x) { return x.id === id; })[0];
          openStaffForm(row, roles, roleMap, view);
        };
      });
      view.querySelectorAll('[data-pwd]').forEach(function (b) {
        b.onclick = function () {
          var id = +b.getAttribute('data-pwd');
          var row = rows.filter(function (x) { return x.id === id; })[0];
          openPasswordReset(row, view);
        };
      });
      view.querySelectorAll('[data-del]').forEach(function (b) {
        b.onclick = function () {
          var id = +b.getAttribute('data-del');
          var row = rows.filter(function (x) { return x.id === id; })[0];
          UI.confirm('确定删除员工「' + row.name + '」？删除后该账号立即失效。', async function () {
            try {
              await API.post('staff/delete', { id: id });
              UI.toast('已删除', 'ok');
              renderStaff(view);
            } catch (e) { UI.toast(e.message, 'bad'); }
          });
        };
      });
    } catch (e) {
      view.innerHTML = UI.empty(e.message, '⚠️');
    }
  }

  function openStaffForm(row, roles, roleMap, view) {
    var isNew = !row;
    var curRole = row ? row.role : 'therapist';
    var curPerm = row ? (row.perm || {}) : null;

    var body =
      '<div class="form-grid">' +
        '<label class="field"><span>姓名</span><input type="text" id="sfName" value="' + UI.esc(row ? row.name : '') + '" placeholder="张小美"></label>' +
        '<label class="field"><span>账号（邮箱）</span><input type="text" id="sfEmail" value="' + UI.esc(row ? row.email : '') + '" placeholder="lily@meiyan.local"></label>' +
        '<label class="field"><span>手机号</span><input type="text" id="sfPhone" value="' + UI.esc(row ? row.phone : '') + '" placeholder="选填"></label>' +
        '<label class="field"><span>岗位备注</span><input type="text" id="sfNote" value="' + UI.esc(row ? row.note : '') + '" placeholder="如：美容师 1 号"></label>' +
        (isNew ? '<label class="field"><span>初始密码（至少 6 位）</span><input type="text" id="sfPass" placeholder="员工首次登录用"></label>' : '') +
        '<label class="field"><span>状态</span><select id="sfStatus">' +
          '<option value="正常"' + (row && row.status === '正常' ? ' selected' : '') + '>正常</option>' +
          '<option value="停用"' + (row && row.status === '停用' ? ' selected' : '') + '>停用</option>' +
        '</select></label>' +
      '</div>' +
      '<div style="margin-top:6px"><strong style="font-size:13px">岗位角色</strong></div>' +
      '<div class="role-list">' +
        roles.map(function (r) {
          return '<label class="role-item"><input type="radio" name="sfRole" value="' + r.key + '"' +
            (curRole === r.key ? ' checked' : '') + '>' +
            '<div><strong>' + UI.esc(r.label) + '</strong>' +
            '<div class="td-sub">' + UI.esc(r.desc) + '</div></div></label>';
        }).join('') +
      '</div>' +
      '<label class="chk-line" style="margin-top:10px"><input type="checkbox" id="sfCustom">' +
        '<span>单独调整这个账号的权限（不勾选就完全按角色预设）</span></label>' +
      '<div id="sfCustomBox" hidden>' +
        '<div style="margin:10px 0 6px"><strong style="font-size:13px">能访问的模块</strong></div>' +
        '<div class="chk-grid">' +
          Object.keys(MODULE_LABEL).map(function (m) {
            var on = curPerm && (curPerm.modules || []).indexOf(m) >= 0;
            return '<label class="chk-line"><input type="checkbox" data-mod="' + m + '"' + (on ? ' checked' : '') + '>' +
              '<span>' + MODULE_LABEL[m] + '</span></label>';
          }).join('') +
        '</div>' +
        '<div style="margin:12px 0 6px"><strong style="font-size:13px">能做的操作</strong></div>' +
        '<div class="chk-grid">' +
          Object.keys(CAP_LABEL).map(function (c) {
            var on = curPerm && (curPerm.caps || {})[c];
            return '<label class="chk-line"><input type="checkbox" data-cap="' + c + '"' + (on ? ' checked' : '') + '>' +
              '<span>' + CAP_LABEL[c] + '</span></label>';
          }).join('') +
        '</div>' +
      '</div>';

    var m = UI.modal({
      title: isNew ? '添加员工' : '编辑员工 · ' + row.name,
      wide: true,
      body: body,
      buttons: [
        { label: '取消', kind: 'ghost', onClick: function (api) { api.close(); } },
        {
          label: isNew ? '添加' : '保存', kind: 'primary',
          onClick: async function (api) {
            var body2 = {
              name: api.body.querySelector('#sfName').value.trim(),
              email: api.body.querySelector('#sfEmail').value.trim(),
              phone: api.body.querySelector('#sfPhone').value.trim(),
              note: api.body.querySelector('#sfNote').value.trim(),
              status: api.body.querySelector('#sfStatus').value,
              role: (api.body.querySelector('input[name="sfRole"]:checked') || {}).value || 'therapist'
            };
            if (!body2.name) { UI.toast('请填写姓名', 'bad'); return; }
            if (isNew) {
              body2.password = api.body.querySelector('#sfPass').value;
              if (!body2.password || body2.password.length < 6) { UI.toast('初始密码至少 6 位', 'bad'); return; }
            } else {
              body2.id = row.id;
            }
            if (api.body.querySelector('#sfCustom').checked) {
              body2.modules = [];
              api.body.querySelectorAll('[data-mod]').forEach(function (c) {
                if (c.checked) body2.modules.push(c.getAttribute('data-mod'));
              });
              body2.caps = {};
              api.body.querySelectorAll('[data-cap]').forEach(function (c) {
                body2.caps[c.getAttribute('data-cap')] = c.checked ? 1 : 0;
              });
            }
            api.setBusy(true);
            try {
              await API.post('staff/save', body2);
              UI.toast(isNew ? '员工已添加' : '已保存', 'ok');
              api.close();
              renderStaff(view);
            } catch (e) {
              UI.toast(e.message, 'bad');
              api.setBusy(false);
            }
          }
        }
      ]
    });

    var chk = m.body.querySelector('#sfCustom');
    var box = m.body.querySelector('#sfCustomBox');
    if (curPerm && !isNew) {
      /* 已有单独权限的就自动展开 */
      var preset = roleMap[curRole];
      var same = preset && JSON.stringify(preset.modules) === JSON.stringify(curPerm.modules || []);
      if (!same) { chk.checked = true; box.hidden = false; }
    }
    chk.onchange = function () { box.hidden = !chk.checked; };
  }

  function openPasswordReset(row, view) {
    var m = UI.modal({
      title: '重置密码 · ' + row.name,
      body: '<label class="field"><span>新密码（至少 6 位）</span>' +
            '<input type="text" id="npw" placeholder="告诉员工后请其自行修改"></label>',
      buttons: [
        { label: '取消', kind: 'ghost', onClick: function (api) { api.close(); } },
        {
          label: '重置', kind: 'primary',
          onClick: async function (api) {
            var v = api.body.querySelector('#npw').value;
            if (!v || v.length < 6) { UI.toast('新密码至少 6 位', 'bad'); return; }
            api.setBusy(true);
            try {
              await API.post('staff/password', { id: row.id, password: v });
              UI.toast('密码已重置', 'ok');
              api.close();
              renderStaff(view);
            } catch (e) {
              UI.toast(e.message, 'bad');
              api.setBusy(false);
            }
          }
        }
      ]
    });
    setTimeout(function () { try { m.body.querySelector('#npw').focus(); } catch (e) {} }, 60);
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
