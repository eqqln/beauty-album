/* ===========================================================
   模块定义：字段 / 表单 / 列表展示全部由此驱动
   =========================================================== */
(function () {
  'use strict';

  var LV_MEMBER = ['普通会员', '银卡会员', '金卡会员', '黑卡会员'];
  var LV_AGENT = ['合伙人', '总代', '一级代理', '二级代理', '零售'];
  var LV_DISCOUNT = { '合伙人': 45, '总代': 55, '一级代理': 65, '二级代理': 75, '零售': 100 };
  var ST_AGENT = ['合作中', '暂停', '已终止'];
  var PAY_METHOD = ['微信', '支付宝', '现金', '银行卡', '转账', '其他'];
  var PAY_STATUS = ['已收款', '部分收款', '未收款', '已退款'];

  window.SCHEMA = [
    /* ---------------- 套餐 ---------------- */
    {
      key: 'packages', table: 'packages', title: '套餐', icon: '🎁',
      sub: '设置套餐内容与价格，App 端展示并支持开通',
      order: 'sort', asc: true, defaults: { status: '上架', sort: 10 },
      fields: [
        { k: 'name', label: '套餐名称', type: 'text', required: true, main: true },
        { k: 'price', label: '价格（元）', type: 'money', required: true, table: true },
        { k: 'days', label: '有效期（天）', type: 'num', required: true, table: true, def: 30 },
        { k: 'items', label: '包含内容', type: 'textarea', ph: '每行一项，例如：\n深层清洁 × 4 次\n补水导入 × 4 次', table: true, chip: true },
        { k: 'desc', label: '套餐说明', type: 'textarea' },
        { k: 'badge', label: '角标文字', type: 'text', ph: '如：热销 / 新品（留空不显示）' },
        { k: 'status', label: '状态', type: 'select', opts: ['上架', '下架'], table: true, badge: true },
        { k: 'sort', label: '排序（小的在前）', type: 'num', def: 10 }
      ]
    },

    /* ---------------- 会员 ---------------- */
    {
      key: 'members', table: 'members', title: '会员', icon: '👤',
      sub: 'App 端注册的用户，可分配等级、套餐与到期时间',
      order: 'created_at', asc: false, defaults: { level: '普通会员', status: '正常' },
      fields: [
        { k: 'name', label: '姓名', type: 'text', required: true, main: true },
        { k: 'phone', label: '手机号', type: 'text', table: true },
        { k: 'email', label: '邮箱', type: 'text' },
        { k: 'level', label: '会员等级', type: 'select', opts: LV_MEMBER, table: true, badge: true },
        { k: 'status', label: '状态', type: 'select', opts: ['正常', '停用', '已过期'], table: true, badge: true },
        { k: 'package_id', label: '当前套餐', type: 'ref', ref: { table: 'packages', label: 'name' }, table: true },
        { k: 'expire_at', label: '到期时间', type: 'date', table: true },
        { k: 'points', label: '积分', type: 'num', def: 0 },
        { k: 'note', label: '备注', type: 'textarea' }
      ]
    },

    /* ---------------- 导师 ---------------- */
    {
      key: 'mentors', table: 'mentors', title: '导师', icon: '🎓',
      sub: '导师档案，App 端预约与展示',
      order: 'sort', asc: true, defaults: { status: '在岗', sort: 10 },
      fields: [
        { k: 'name', label: '姓名', type: 'text', required: true, main: true },
        { k: 'title', label: '职位 / 职称', type: 'text', table: true },
        { k: 'tags', label: '擅长标签', type: 'tags', ph: '逗号分隔，如：皮肤管理,抗衰,美体', table: true },
        { k: 'phone', label: '联系电话', type: 'text' },
        { k: 'photo', label: '照片', type: 'image', table: true, thumb: true },
        { k: 'intro', label: '简介', type: 'textarea' },
        { k: 'status', label: '状态', type: 'select', opts: ['在岗', '休假', '离职'], table: true, badge: true },
        { k: 'sort', label: '排序', type: 'num', def: 10 }
      ]
    },

    /* ---------------- 产品 ---------------- */
    {
      key: 'products', table: 'products', title: '产品', icon: '📦',
      sub: '产品档案、规格、适用阶段与使用步骤',
      order: 'created_at', asc: false, defaults: { status: '在售', stock: 0 },
      fields: [
        { k: 'name', label: '产品名称', type: 'text', required: true, main: true },
        { k: 'brand', label: '品牌', type: 'text', table: true },
        { k: 'cover', label: '封面图', type: 'image', table: true, thumb: true },
        { k: 'price', label: '参考价（元）', type: 'money', table: true },
        { k: 'stock', label: '库存', type: 'num', table: true },
        { k: 'specs', label: '规格', type: 'textarea', ph: '每行一个规格，可带价格：\n30ml|298\n50ml|458', table: true, chip: true },
        { k: 'stages', label: '适用阶段', type: 'tags', ph: '逗号分隔，如：清洁期,导入期,巩固期', table: true },
        { k: 'steps', label: '使用步骤', type: 'textarea', ph: '每行一步' },
        { k: 'desc', label: '产品说明', type: 'textarea' },
        { k: 'status', label: '状态', type: 'select', opts: ['在售', '停售'], table: true, badge: true }
      ]
    },

    /* ---------------- 代理 ---------------- */
    {
      key: 'agents', table: 'agents', title: '代理', icon: '🤝',
      sub: '代理档案、等级折扣与上下级关系',
      order: 'created_at', asc: false, defaults: { level: '一级代理', discount: 65, status: '合作中' },
      fields: [
        { k: 'name', label: '姓名', type: 'text', required: true, main: true },
        { k: 'phone', label: '手机号', type: 'text', table: true },
        { k: 'wechat', label: '微信号', type: 'text' },
        { k: 'region', label: '地区 / 门店', type: 'text', table: true },
        { k: 'level', label: '代理等级', type: 'select', opts: LV_AGENT, table: true, badge: true, discountOf: true },
        { k: 'discount', label: '拿货折扣（%）', type: 'num', table: true, hint: '65 表示 6.5 折' },
        { k: 'parent_id', label: '上级代理', type: 'ref', ref: { table: 'agents', label: 'name' }, table: true },
        { k: 'joined_at', label: '加入时间', type: 'date', table: true },
        { k: 'status', label: '状态', type: 'select', opts: ST_AGENT, table: true, badge: true },
        { k: 'note', label: '备注', type: 'textarea' }
      ],
      discountMap: LV_DISCOUNT
    },

    /* ---------------- 拿货记录 ---------------- */
    {
      key: 'orders', table: 'agent_orders', title: '拿货', icon: '🧾',
      sub: '代理拿货明细与结算',
      order: 'at', asc: false, defaults: { qty: 1 },
      fields: [
        { k: 'agent_id', label: '代理', type: 'ref', ref: { table: 'agents', label: 'name' }, required: true, main: true, table: true },
        { k: 'product_name', label: '产品', type: 'text', table: true },
        { k: 'spec', label: '规格', type: 'text' },
        { k: 'qty', label: '数量', type: 'num', required: true, table: true },
        { k: 'unit_price', label: '单价', type: 'money', table: true },
        { k: 'amount', label: '金额', type: 'money', table: true, auto: function (r) { return (Number(r.qty) || 0) * (Number(r.unit_price) || 0); } },
        { k: 'paid', label: '已付', type: 'money', table: true },
        { k: 'at', label: '拿货时间', type: 'date', table: true },
        { k: 'note', label: '备注', type: 'textarea' }
      ]
    },

    /* ---------------- 客户 ---------------- */
    {
      key: 'customers', table: 'customers', title: '客户', icon: '💁',
      sub: '到店客户档案、流程进度与联系方式',
      order: 'created_at', asc: false, defaults: { stage: '待开始', progress: 0 },
      fields: [
        { k: 'name', label: '客户姓名', type: 'text', required: true, main: true },
        { k: 'phone', label: '联系方式', type: 'text', table: true },
        { k: 'member_id', label: '关联会员', type: 'ref', ref: { table: 'members', label: 'name' }, table: true },
        { k: 'stage', label: '当前环节', type: 'text', table: true },
        { k: 'progress', label: '已完成步数', type: 'num', table: true, def: 0 },
        { k: 'quoted', label: '应收金额', type: 'money', table: true },
        { k: 'note', label: '备注', type: 'textarea' }
      ]
    },

    /* ---------------- 相册图片 ---------------- */
    {
      key: 'photos', table: 'photos', title: '相册图片', icon: '🖼',
      sub: '客户使用前 / 使用后照片',
      order: 'created_at', asc: false, defaults: { phase: '使用前' },
      fields: [
        { k: 'customer_id', label: '所属客户', type: 'ref', ref: { table: 'customers', label: 'name' }, required: true, main: true, table: true },
        { k: 'phase', label: '阶段', type: 'select', opts: ['使用前', '使用后'], table: true, badge: true },
        { k: 'url', label: '照片', type: 'image', required: true, table: true, thumb: true },
        { k: 'note', label: '说明', type: 'textarea' }
      ]
    },

    /* ---------------- 对比图 ---------------- */
    {
      key: 'compares', table: 'compares', title: '对比图', icon: '↔️',
      sub: '使用前 / 使用后对比，App 端可左右滑动查看',
      order: 'created_at', asc: false, defaults: {},
      fields: [
        { k: 'customer_id', label: '所属客户', type: 'ref', ref: { table: 'customers', label: 'name' }, required: true, main: true, table: true },
        { k: 'title', label: '标题', type: 'text', table: true },
        { k: 'before_url', label: '使用前', type: 'image', table: true, thumb: true },
        { k: 'after_url', label: '使用后', type: 'image', table: true, thumb: true },
        { k: 'note', label: '说明', type: 'textarea' }
      ]
    },

    /* ---------------- 收款 ---------------- */
    {
      key: 'payments', table: 'payments', title: '收款', icon: '💰',
      sub: '收款流水与欠款核对',
      order: 'paid_at', asc: false, defaults: { method: '微信', status: '已收款' },
      fields: [
        { k: 'customer_id', label: '客户', type: 'ref', ref: { table: 'customers', label: 'name' }, main: true, table: true },
        { k: 'member_id', label: '会员', type: 'ref', ref: { table: 'members', label: 'name' }, table: true },
        { k: 'amount', label: '金额（元）', type: 'money', required: true, table: true },
        { k: 'method', label: '收款方式', type: 'select', opts: PAY_METHOD, table: true },
        { k: 'status', label: '状态', type: 'select', opts: PAY_STATUS, table: true, badge: true },
        { k: 'paid_at', label: '收款时间', type: 'date', table: true },
        { k: 'note', label: '备注', type: 'textarea' }
      ]
    },

    /* ---------------- 开通记录 ---------------- */
    {
      key: 'subs', table: 'member_packages', title: '套餐开通', icon: '📋',
      sub: '会员开通套餐的记录与到期时间',
      order: 'started_at', asc: false, defaults: { status: '生效中' },
      fields: [
        { k: 'member_id', label: '会员', type: 'ref', ref: { table: 'members', label: 'name' }, required: true, main: true, table: true },
        { k: 'package_id', label: '套餐', type: 'ref', ref: { table: 'packages', label: 'name' }, required: true, table: true },
        { k: 'amount', label: '实收金额', type: 'money', table: true },
        { k: 'started_at', label: '开通时间', type: 'date', table: true },
        { k: 'expire_at', label: '到期时间', type: 'date', table: true },
        { k: 'status', label: '状态', type: 'select', opts: ['生效中', '已到期', '已取消'], table: true, badge: true },
        { k: 'note', label: '备注', type: 'textarea' }
      ]
    }
  ];

  window.SCHEMA_MAP = {};
  window.SCHEMA.forEach(function (m) { window.SCHEMA_MAP[m.key] = m; });

  window.ENUMS = {
    LV_MEMBER: LV_MEMBER,
    LV_AGENT: LV_AGENT,
    LV_DISCOUNT: LV_DISCOUNT,
    PAY_METHOD: PAY_METHOD,
    PAY_STATUS: PAY_STATUS
  };
})();
