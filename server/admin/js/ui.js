/* ===========================================================
   通用 UI 工具：Toast / 弹窗 / 格式化
   =========================================================== */
(function () {
  'use strict';

  function esc(s) {
    return String(s === null || s === undefined ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function money(v) {
    var n = Number(v || 0);
    if (!isFinite(n)) n = 0;
    return '¥' + n.toLocaleString('zh-CN', { minimumFractionDigits: n % 1 ? 2 : 0, maximumFractionDigits: 2 });
  }

  function num(v) {
    var n = Number(v || 0);
    return isFinite(n) ? n.toLocaleString('zh-CN') : '0';
  }

  function fmtDate(v, withTime) {
    if (!v) return '—';
    var s = String(v).replace('T', ' ');
    if (s.length >= 16) return withTime === false ? s.slice(0, 10) : s.slice(0, 16);
    return s;
  }

  function toast(msg, type) {
    var root = document.getElementById('toastRoot');
    var el = document.createElement('div');
    el.className = 'toast' + (type ? ' ' + type : '');
    el.textContent = msg;
    root.appendChild(el);
    setTimeout(function () {
      el.style.transition = 'opacity .25s, transform .25s';
      el.style.opacity = '0';
      el.style.transform = 'translateY(6px)';
      setTimeout(function () { el.remove(); }, 260);
    }, type === 'bad' ? 3600 : 2200);
  }

  var modalStack = [];

  function modal(opts) {
    var root = document.getElementById('modalRoot');
    var mask = document.createElement('div');
    mask.className = 'modal-mask';
    mask.innerHTML =
      '<div class="modal' + (opts.wide ? ' wide' : '') + '">' +
        '<div class="modal-head"><h3>' + esc(opts.title || '') + '</h3>' +
          '<button class="icon-btn" data-close="1">✕</button></div>' +
        '<div class="modal-body"></div>' +
        '<div class="modal-foot"></div>' +
      '</div>';
    root.appendChild(mask);
    var body = mask.querySelector('.modal-body');
    var foot = mask.querySelector('.modal-foot');
    if (typeof opts.body === 'string') body.innerHTML = opts.body;
    else if (opts.body) body.appendChild(opts.body);

    var api = {
      el: mask,
      body: body,
      close: function () {
        mask.remove();
        modalStack = modalStack.filter(function (m) { return m !== api; });
        if (opts.onClose) opts.onClose();
      },
      setBusy: function (b) {
        foot.querySelectorAll('button').forEach(function (b2) { b2.disabled = !!b; });
      }
    };
    modalStack.push(api);

    (opts.buttons || []).forEach(function (b) {
      var btn = document.createElement('button');
      btn.className = 'btn ' + (b.kind || 'ghost');
      btn.textContent = b.label;
      btn.onclick = function () {
        if (b.onClick) b.onClick(api);
        else api.close();
      };
      foot.appendChild(btn);
    });
    if (!(opts.buttons || []).length) {
      var c = document.createElement('button');
      c.className = 'btn ghost';
      c.textContent = '关闭';
      c.onclick = api.close;
      foot.appendChild(c);
    }

    mask.addEventListener('click', function (e) {
      if (e.target === mask) api.close();
    });
    mask.querySelector('[data-close]').onclick = api.close;
    return api;
  }

  function confirmBox(title, text, onYes, danger, okLabel) {
    modal({
      title: title,
      body: '<p style="font-size:13.5px;color:#5c4f55;line-height:1.7;white-space:pre-line">' + esc(text) + '</p>',
      buttons: [
        { label: '取消', kind: 'ghost' },
        {
          label: okLabel || (danger ? '确定删除' : '确定'),
          kind: danger ? 'danger' : 'primary',
          onClick: function (m) { m.close(); onYes(); }
        }
      ]
    });
  }

  function loading(text) {
    return '<div class="loading"><span class="spin"></span>' + esc(text || '加载中…') + '</div>';
  }

  function empty(text, icon) {
    return '<div class="empty"><span class="big">' + (icon || '📭') + '</span>' + esc(text || '暂无数据') + '</div>';
  }

  function badge(text) {
    var t = String(text || '');
    var cls = 'gray';
    if (/^(正常|在岗|在售|上架|已收款|生效中|合作中|成功|已使用|已到账)$/.test(t)) cls = 'ok';
    else if (/^(停用|离职|停售|下架|已到期|已终止|失败|已退款|已作废)$/.test(t)) cls = 'bad';
    else if (/^(休假|部分收款|未收款|暂停|已过期)$/.test(t)) cls = 'warn';
    else if (/^(热销|尊享|体验|金卡会员|黑卡会员|合伙人|总代|未使用|余额卡|积分卡|组合卡|体验卡|充值)$/.test(t)) cls = 'info';
    return '<span class="badge ' + cls + '">' + esc(t) + '</span>';
  }

  window.UI = {
    esc: esc, money: money, num: num, fmtDate: fmtDate,
    toast: toast, modal: modal, confirm: confirmBox, confirmBox: confirmBox,
    loading: loading, empty: empty, badge: badge
  };
})();
