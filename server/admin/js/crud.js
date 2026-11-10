/* ===========================================================
   通用列表 + 表单
   =========================================================== */
(function () {
  'use strict';

  var REF_OPTS = {
    package_id: 'packages',
    member_id: 'members',
    customer_id: 'customers',
    agent_id: 'agents',
    parent_id: 'agents'
  };

  var optCache = {};

  async function loadOptions(type) {
    if (optCache[type]) return optCache[type];
    try {
      var rows = await API.options(type);
      optCache[type] = rows || [];
    } catch (e) {
      optCache[type] = [];
    }
    return optCache[type];
  }

  function clearOptionCache() { optCache = {}; }

  function cell(mod, f, row) {
    var v = row[f.k];
    if (f.thumb) {
      if (!v) return '<span class="td-sub">—</span>';
      return '<img class="thumb" src="' + UI.esc(v) + '" alt="" loading="lazy" ' +
             'onerror="this.style.opacity=.3">';
    }
    if (f.type === 'money') {
      var m = UI.money(v);
      if (f.signed) {
        var n = Number(v || 0);
        if (n > 0) return '<span class="up">+' + m + '</span>';
        if (n < 0) return '<span class="down">-' + UI.money(Math.abs(n)) + '</span>';
      }
      return m;
    }
    if (f.type === 'date' || f.type === 'datetime') return UI.fmtDate(v, f.type === 'datetime');
    if (f.badge) {
      if (v === null || v === undefined || v === '') return '<span class="td-sub">—</span>';
      var shown = v;
      if (f.opts) {
        f.opts.forEach(function (o) {
          if (o && typeof o === 'object' && String(o.v) === String(v)) shown = o.t;
        });
      }
      return UI.badge(shown);
    }
    if (f.type === 'tags') {
      if (!v) return '<span class="td-sub">—</span>';
      return String(v).split(/[,，]/).filter(Boolean).slice(0, 3)
        .map(function (t) { return '<span class="chip">' + UI.esc(t.trim()) + '</span>'; }).join('');
    }
    if (f.chip) {
      if (!v) return '<span class="td-sub">—</span>';
      var lines = String(v).split(/\r?\n/).filter(Boolean);
      return '<span class="td-sub">' + UI.esc(lines[0]) + (lines.length > 1 ? ' 等 ' + lines.length + ' 项' : '') + '</span>';
    }
    if (f.type === 'num' && f.signed) {
      var p = Number(v || 0);
      if (p > 0) return '<span class="up">+' + UI.num(p) + '</span>';
      if (p < 0) return '<span class="down">' + UI.num(p) + '</span>';
      return '0';
    }
    if (f.ref) {
      if (f.ref.showKey && row[f.ref.showKey]) return UI.esc(row[f.ref.showKey]);
      if (!v) return '<span class="td-sub">—</span>';
      return '<span class="td-sub">#' + UI.esc(v) + '</span>';
    }
    if (v === null || v === undefined || v === '') return '<span class="td-sub">—</span>';
    return UI.esc(v);
  }

  function rowHtml(mod, row) {
    var cells = '';
    var cols = mod.fields.filter(function (f) { return f.table || f.main; });
    cols.forEach(function (f) {
      var isMain = !!f.main;
      var content = cell(mod, f, row);
      if (isMain && !f.thumb && f.type !== 'badge') {
        content = '<div class="td-main">' + content + '</div>' +
          '<div class="td-sub">' + UI.fmtDate(row.created_at) + '</div>';
      }
      cells += '<td>' + content + '</td>';
    });
    var acts = '';
    if (mod.rowActions) {
      mod.rowActions.forEach(function (a) {
        acts += '<button class="btn sm ghost" data-act="' + UI.esc(a.key) + '" data-id="' + row.id + '">' +
                UI.esc(a.label) + '</button> ';
      });
    }
    if (!mod.readonly) {
      acts += '<button class="btn sm ghost" data-edit="' + row.id + '">编辑</button> ' +
              '<button class="btn sm danger" data-del="' + row.id + '">删除</button>';
    }
    cells += '<td class="td-actions">' + acts + '</td>';
    return '<tr>' + cells + '</tr>';
  }

  /* ---------------- 表单 ---------------- */

  async function buildForm(mod, row, onChange) {
    var wrap = document.createElement('div');
    wrap.style.display = 'flex';
    wrap.style.flexDirection = 'column';
    wrap.style.gap = '14px';
    var values = Object.assign({}, mod.defaults || {}, row || {});

    for (var i = 0; i < mod.fields.length; i++) {
      var f = mod.fields[i];
      var field = document.createElement('label');
      field.className = 'field';
      var label = '<span>' + UI.esc(f.label) + (f.required ? ' *' : '') + '</span>';
      var control = '';

      if (f.ro) {
        var shown = f.type === 'money' ? UI.money(values[f.k]) : (values[f.k] === null || values[f.k] === undefined || values[f.k] === '' ? '—' : String(values[f.k]));
        field.innerHTML = label + '<div class="ro-box">' + UI.esc(shown) + '</div>' +
          '<span class="td-sub">只读，请在「充值卡 → 手动调账」或会员钱包里修改</span>';
        wrap.appendChild(field);
        continue;
      }

      if (f.type === 'textarea') {
        control = '<textarea data-k="' + f.k + '" placeholder="' + UI.esc(f.ph || '') + '">' +
                  UI.esc(values[f.k] || '') + '</textarea>';
      } else if (f.type === 'select') {
        control = '<select data-k="' + f.k + '">' + (f.opts || []).map(function (o) {
          var val = (o && typeof o === 'object') ? o.v : o;
          var txt = (o && typeof o === 'object') ? o.t : o;
          return '<option value="' + UI.esc(val) + '"' + (String(values[f.k]) === String(val) ? ' selected' : '') + '>' + UI.esc(txt) + '</option>';
        }).join('') + '</select>';
      } else if (f.type === 'num' || f.type === 'money') {
        control = '<input type="number" step="' + (f.type === 'money' ? '0.01' : '1') +
                  '" data-k="' + f.k + '" value="' + UI.esc(values[f.k] === null || values[f.k] === undefined ? '' : values[f.k]) + '">';
      } else if (f.type === 'date') {
        var dv = values[f.k] ? String(values[f.k]).slice(0, 10) : '';
        control = '<input type="date" data-k="' + f.k + '" value="' + UI.esc(dv) + '">';
      } else if (f.type === 'datetime') {
        var dtv = values[f.k] ? String(values[f.k]).replace(' ', 'T').slice(0, 16) : '';
        control = '<input type="datetime-local" data-k="' + f.k + '" value="' + UI.esc(dtv) + '">';
      } else if (f.type === 'ref') {
        var type = REF_OPTS[f.k] || f.ref.table;
        var opts = await loadOptions(type);
        var vk = f.ref.valueKey || 'id';
        var cur = values[f.k] === null || values[f.k] === undefined ? '' : String(values[f.k]);
        control = '<select data-k="' + f.k + '"><option value="">— 不选 —</option>' +
          opts.map(function (o) {
            var label2 = o.name || ('#' + o.id);
            if (o.phone) label2 += ' · ' + o.phone;
            if (o.price !== undefined && o.price !== null) label2 += ' · ' + UI.money(o.price);
            var val = o[vk] === undefined || o[vk] === null ? '' : String(o[vk]);
            return '<option value="' + UI.esc(val) + '"' + (val === cur ? ' selected' : '') + '>' +
                   UI.esc(label2) + '</option>';
          }).join('') + '</select>';
      } else if (f.type === 'image') {
        control = '<div style="display:flex;gap:10px;align-items:center">' +
          '<div class="thumb-box" style="width:72px;height:72px;border-radius:10px;overflow:hidden;background:#f6f0f2;flex:0 0 auto;display:flex;align-items:center;justify-content:center;font-size:11px;color:#94868c">' +
          (values[f.k] ? '<img src="' + UI.esc(values[f.k]) + '" style="width:100%;height:100%;object-fit:cover">' : '无图') +
          '</div>' +
          '<button type="button" class="btn ghost sm" data-upload="' + f.k + '">上传图片</button>' +
          '<input type="file" accept="image/*" data-file="' + f.k + '" hidden>' +
          '<input type="hidden" data-k="' + f.k + '" value="' + UI.esc(values[f.k] || '') + '"></div>';
      } else if (f.type === 'tags') {
        control = '<input type="text" data-k="' + f.k + '" placeholder="' + UI.esc(f.ph || '逗号分隔') + '" value="' + UI.esc(values[f.k] || '') + '">';
      } else {
        control = '<input type="text" data-k="' + f.k + '" placeholder="' + UI.esc(f.ph || '') + '" value="' + UI.esc(values[f.k] === null || values[f.k] === undefined ? '' : values[f.k]) + '">';
      }

      field.innerHTML = label + control + (f.hint ? '<span class="td-sub">' + UI.esc(f.hint) + '</span>' : '');
      wrap.appendChild(field);
    }

    // 图片上传
    wrap.querySelectorAll('[data-upload]').forEach(function (btn) {
      var key = btn.getAttribute('data-upload');
      var input = wrap.querySelector('[data-file="' + key + '"]');
      btn.onclick = function () { input.click(); };
      input.onchange = async function () {
        var file = input.files && input.files[0];
        if (!file) return;
        btn.textContent = '上传中…';
        btn.disabled = true;
        try {
          var url = await API.upload(file);
          var hidden = wrap.querySelector('input[data-k="' + key + '"]');
          hidden.value = url;
          var box = btn.parentNode.querySelector('.thumb-box');
          box.innerHTML = '<img src="' + UI.esc(url) + '" style="width:100%;height:100%;object-fit:cover">';
          if (onChange) onChange(key, url);
          UI.toast('图片已上传', 'ok');
        } catch (e) {
          UI.toast(e.message, 'bad');
        }
        btn.textContent = '上传图片';
        btn.disabled = false;
      };
    });

    // 等级联动折扣
    if (mod.discountMap) {
      var lv = wrap.querySelector('[data-k="level"]');
      var dc = wrap.querySelector('[data-k="discount"]');
      var manual = false;
      if (dc) dc.addEventListener('input', function () { manual = true; });
      if (lv && dc) {
        lv.addEventListener('change', function () {
          if (manual) return;
          var v = mod.discountMap[lv.value];
          if (v) dc.value = v;
        });
      }
    }

    wrap.collect = function () {
      var out = {};
      mod.fields.forEach(function (f) {
        if (f.ro) return;
        var el = wrap.querySelector('[data-k="' + f.k + '"]');
        if (!el) return;
        var v = el.value;
        if (f.type === 'num') out[f.k] = v === '' ? null : Number(v);
        else if (f.type === 'money') out[f.k] = v === '' ? 0 : Number(v);
        else out[f.k] = v;
      });
      return out;
    };

    return wrap;
  }

  /* ---------------- 列表页 ---------------- */

  var state = {};

  async function render(container, key) {
    var mod = SCHEMA_MAP[key];
    if (!mod) { container.innerHTML = UI.empty('模块不存在'); return; }
    if (!state[key]) state[key] = { page: 1, kw: '' };
    var st = state[key];

    container.innerHTML =
      '<div class="toolbar">' +
        '<input class="search" id="kwInput" placeholder="搜索 ' + UI.esc(mod.title) + '" value="' + UI.esc(st.kw) + '">' +
        '<div style="flex:1"></div>' +
        (mod.readonly ? '<span class="td-sub">只读记录</span>'
                      : '<button class="btn primary" id="addBtn">+ 新建' + UI.esc(mod.title) + '</button>') +
      '</div>' +
      '<div class="card" style="padding:0;overflow:hidden"><div id="tableWrap">' + UI.loading() + '</div></div>' +
      '<div id="pager" style="margin-top:14px;display:flex;gap:8px;align-items:center;justify-content:flex-end"></div>';

    var kwInput = container.querySelector('#kwInput');
    var timer = null;
    kwInput.oninput = function () {
      clearTimeout(timer);
      timer = setTimeout(function () {
        st.kw = kwInput.value.trim();
        st.page = 1;
        loadTable();
      }, 320);
    };

    var addBtn = container.querySelector('#addBtn');
    if (addBtn) addBtn.onclick = function () { openForm(key, null, loadTable); };

    async function loadTable() {
      var wrap = container.querySelector('#tableWrap');
      var pager = container.querySelector('#pager');
      wrap.innerHTML = UI.loading();
      pager.innerHTML = '';
      try {
        var res = await API.list(key, { kw: st.kw, page: st.page, size: 30 });
        var rows = res.rows || [];
        if (!rows.length) {
          wrap.innerHTML = UI.empty(st.kw ? '没有找到匹配的记录' : '还没有数据，点右上角新建', mod.icon);
          return;
        }
        var cols = mod.fields.filter(function (f) { return f.table || f.main; });
        var head = cols.map(function (f) { return '<th>' + UI.esc(f.label) + '</th>'; }).join('') + '<th></th>';
        var body = rows.map(function (r) { return rowHtml(mod, r); }).join('');
        wrap.innerHTML = '<div style="overflow-x:auto"><table><thead><tr>' + head +
          '</tr></thead><tbody>' + body + '</tbody></table></div>';

        wrap.querySelectorAll('[data-edit]').forEach(function (b) {
          b.onclick = function () {
            var id = Number(b.getAttribute('data-edit'));
            var row = rows.find(function (r) { return Number(r.id) === id; });
            openForm(key, row, loadTable);
          };
        });
        wrap.querySelectorAll('[data-act]').forEach(function (b) {
          b.onclick = function () {
            var id = Number(b.getAttribute('data-id'));
            var row = rows.find(function (r) { return Number(r.id) === id; });
            var runner = (window.ROW_ACTION_RUNNERS || {})[b.getAttribute('data-act')];
            if (runner && row) runner(row, loadTable);
          };
        });
        wrap.querySelectorAll('[data-del]').forEach(function (b) {
          b.onclick = function () {
            var id = Number(b.getAttribute('data-del'));
            UI.confirm('删除确认', '删除后无法恢复，确定要删除这条' + mod.title + '记录吗？', async function () {
              try {
                await API.del(key, id);
                UI.toast('已删除', 'ok');
                loadTable();
              } catch (e) { UI.toast(e.message, 'bad'); }
            }, true);
          };
        });

        // 分页
        var total = res.total || 0;
        var pages = Math.max(1, Math.ceil(total / 30));
        pager.innerHTML =
          '<span class="td-sub">共 ' + total + ' 条 · 第 ' + st.page + '/' + pages + ' 页</span>' +
          (st.page > 1 ? '<button class="btn sm ghost" id="prevPage">上一页</button>' : '') +
          (st.page < pages ? '<button class="btn sm ghost" id="nextPage">下一页</button>' : '');
        var prev = pager.querySelector('#prevPage');
        var next = pager.querySelector('#nextPage');
        if (prev) prev.onclick = function () { st.page--; loadTable(); };
        if (next) next.onclick = function () { st.page++; loadTable(); };
      } catch (e) {
        wrap.innerHTML = UI.empty(e.message, '⚠️');
      }
    }

    loadTable();
  }

  async function openForm(key, row, after) {
    var mod = SCHEMA_MAP[key];
    clearOptionCache();
    var form = await buildForm(mod, row);
    var m = UI.modal({
      title: (row ? '编辑' : '新建') + mod.title,
      body: form,
      wide: mod.fields.length > 7,
      buttons: [
        { label: '取消', kind: 'ghost' },
        {
          label: '保存', kind: 'primary',
          onClick: async function (mm) {
            var data = form.collect();
            var missing = mod.fields.filter(function (f) { return f.required && !String(data[f.k] || '').trim(); });
            if (missing.length) { UI.toast('请填写：' + missing.map(function (f) { return f.label; }).join('、'), 'bad'); return; }
            mm.setBusy(true);
            try {
              if (row && row.id) data.id = row.id;
              await API.save(key, data);
              mm.close();
              UI.toast('已保存', 'ok');
              clearOptionCache();
              if (after) after();
            } catch (e) {
              UI.toast(e.message, 'bad');
              mm.setBusy(false);
            }
          }
        }
      ]
    });
    return m;
  }

  window.CRUD = { render: render, openForm: openForm, clearOptionCache: clearOptionCache, loadOptions: loadOptions };
})();
