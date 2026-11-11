<?php
/**
 * 多板块（多租户）
 *
 * 一个激活码 = 一个板块。使用者激活时填的姓名电话就是这块板块的归属人，
 * 他之后加的客户、相册、护理步骤、产品、预约全都带 tenant_id，
 * 别的板块查不到，后台也串不了。
 *
 * tenant_id = 0 是「默认板块」，改造前的老数据都在这里，行为与单店铺时一致。
 */
declare(strict_types=1);

/**
 * 哪些设置项跟着板块走。
 *
 * 剩下的（license_* / sms_* / app_version / ipa_* / recharge_* / schema_version）
 * 是平台级配置，所有板块共用，改了影响全局。
 */
function tenant_setting_keys(): array
{
    return [
        'shop_name', 'shop_slogan', 'before_label', 'after_label',
        'contact_phone', 'contact_wechat', 'pay_qr', 'notice', 'install_note',
        'wechat_qr', 'alipay_qr', 'pay_link', 'pay_note',
        'step_template', 'app_features', 'home_layout',
        'home_columns', 'home_limit', 'show_cover', 'app_settings_updated',
    ];
}

function tenant_is_scoped_key(string $k): bool
{
    static $keys = null;
    if ($keys === null) $keys = array_flip(tenant_setting_keys());
    return isset($keys[$k]);
}

/** 板块行缓存（按引用取，方便改完失效） */
function &tenant_cache(): array
{
    static $c = [];
    return $c;
}

/** 板块行（带缓存） */
function tenant_row(int $id): ?array
{
    $c = &tenant_cache();
    if (array_key_exists($id, $c)) return $c[$id];
    try {
        $st = db()->prepare('SELECT * FROM tenants WHERE id=?');
        $st->execute([$id]);
        $r = $st->fetch();
        $c[$id] = $r ?: null;
    } catch (Throwable $e) {
        $c[$id] = null;
    }
    return $c[$id];
}

/**
 * 让板块缓存失效。
 *
 * tenant_row 在同一个请求里只查一次库，改完 tenants 行必须调这个，
 * 否则紧接着读回来还是改之前的值（数据库已经对了，返回给前端的却是旧的）。
 */
function tenant_forget(?int $id = null): void
{
    $c = &tenant_cache();
    if ($id === null) $c = [];
    else unset($c[$id]);
}

/**
 * 当前请求属于哪个板块。
 *
 * 优先级：
 * 1. 设备凭证（App 的 sync / upload / 激活复核）→ 看这条授权挂在哪个板块
 * 2. 管理员自己绑了板块（店长/店员）→ 只能是自己的
 * 3. 平台管理员（tenant_id=0）→ 看请求头 X-Tenant-Id，没带就是默认板块
 */
function tenant_current_id(): int
{
    static $resolved = null;
    if ($resolved !== null) return $resolved;

    $resolved = 0;

    /* 1. 设备凭证 */
    $tok = bearer();
    if ($tok !== '') {
        try {
            $st = db()->prepare('SELECT a.tenant_id FROM device_tokens d
                                 JOIN activations a ON a.id = d.activation_id
                                 WHERE d.token=? LIMIT 1');
            $st->execute([$tok]);
            $v = $st->fetchColumn();
            if ($v !== false && $v !== null) {
                $resolved = (int)$v;
                return $resolved;
            }
        } catch (Throwable $e) {
        }
    }

    /* 2/3. 管理员 */
    $a = admin_current();
    if ($a) {
        $own = (int)($a['tenant_id'] ?? 0);
        if ($own > 0) {
            $resolved = $own;
            return $resolved;
        }
        $h = (int)($_SERVER['HTTP_X_TENANT_ID'] ?? 0);
        if ($h > 0) {
            $t = tenant_row($h);
            if ($t && ($t['status'] ?? '') === '正常') $resolved = $h;
        }
    }

    return $resolved;
}

/** 当前板块行 */
function tenant_current(): ?array
{
    return tenant_row(tenant_current_id());
}

/**
 * 给查询拼板块条件。
 * 表里没有 tenant_id 列（老库还没迁移完）时返回空串，不影响可用性。
 */
function tenant_where(string $table, string $alias = ''): array
{
    if (!column_exists(db(), $table, 'tenant_id')) return ['', []];
    $col = $alias !== '' ? "`$alias`.`tenant_id`" : '`tenant_id`';
    return [" $col = ?", [tenant_current_id()]];
}

/** 往已有的 $where/$args 上追加板块条件 */
function tenant_append(string &$where, array &$args, string $table, string $alias = ''): void
{
    [$frag, $vals] = tenant_where($table, $alias);
    if ($frag === '') return;
    $where .= ($where === '' ? ' WHERE 1=1' : '') . ' AND' . $frag;
    foreach ($vals as $v) $args[] = $v;
}

/**
 * 找或建板块。
 *
 * 认人靠电话：同一个人换码 / 续费，不该变成两块空板块把数据丢掉。
 * 所以先按电话找，找到就复用；找不到才新建。
 */
function tenant_ensure(string $name, string $phone, string $code, string $shopName = ''): array
{
    $db  = db();
    $now = now();
    $name = trim($name);
    $phone = trim($phone);
    if ($shopName === '') $shopName = $name !== '' ? $name : '我的板块';

    if ($phone !== '') {
        $st = $db->prepare('SELECT * FROM tenants WHERE phone=? ORDER BY id ASC LIMIT 1');
        $st->execute([$phone]);
        $t = $st->fetch();
        if ($t) {
            /* 名字变了就跟着改，方便后台辨认 */
            if ($name !== '' && $name !== (string)$t['name']) {
                $db->prepare('UPDATE tenants SET name=?, shop_name=? WHERE id=?')
                   ->execute([$name, $shopName, (int)$t['id']]);
                $t['name'] = $name;
                $t['shop_name'] = $shopName;
            }
            return $t;
        }
    }

    $db->prepare('INSERT INTO tenants(name,phone,shop_name,code,status,created_at,last_active_at) VALUES(?,?,?,?,?,?,?)')
       ->execute([$name !== '' ? $name : '未命名', $phone, $shopName, $code, '正常', $now, $now]);
    $id = (int)$db->lastInsertId();

    /* 新板块继承默认板块的店名/标语/前后标签，不至于一进去全是空白 */
    tenant_copy_defaults($id);

    return tenant_row($id) ?: ['id' => $id, 'name' => $name, 'phone' => $phone,
                               'shop_name' => $shopName, 'code' => $code, 'status' => '正常'];
}

/** 新板块套用默认板块的基础设置 */
function tenant_copy_defaults(int $tenantId): void
{
    $keys = ['shop_slogan', 'before_label', 'after_label', 'home_layout',
             'home_columns', 'home_limit', 'show_cover', 'step_template', 'app_features'];
    $st = db()->prepare('SELECT k, v FROM settings WHERE k=?');
    $ins = db()->prepare('INSERT INTO tenant_settings(tenant_id,k,v) VALUES(?,?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)');
    foreach ($keys as $k) {
        $st->execute([$k]);
        $v = $st->fetchColumn();
        if ($v !== false && $v !== null && $v !== '') {
            try { $ins->execute([$tenantId, $k, (string)$v]); } catch (Throwable $e) {}
        }
    }
    /* 店名默认用使用者姓名，不沿用平台的店名 */
    $t = tenant_row($tenantId);
    if ($t) {
        try {
            $ins->execute([$tenantId, 'shop_name', (string)$t['shop_name']]);
        } catch (Throwable $e) {}
    }

    /* 套餐也从默认板块复制一份，新板块的 App 里不会一进去全是空 */
    try {
        $rows = db()->query("SELECT name,price,days,items,`desc`,badge,status,sort
                             FROM packages WHERE tenant_id=0 ORDER BY id ASC")->fetchAll();
        $pi = db()->prepare('INSERT INTO packages(name,price,days,items,`desc`,badge,status,sort,created_at,tenant_id)
                             VALUES(?,?,?,?,?,?,?,?,?,?)');
        foreach ($rows as $r) {
            $pi->execute([$r['name'], $r['price'], $r['days'], $r['items'], $r['desc'],
                          $r['badge'], $r['status'], $r['sort'], now(), $tenantId]);
        }
    } catch (Throwable $e) {
    }
}

/** 板块设置读 */
function tenant_setting_get(int $tenantId, string $k, string $def = ''): string
{
    if ($tenantId <= 0) return setting_get_global($k, $def);
    try {
        $st = db()->prepare('SELECT v FROM tenant_settings WHERE tenant_id=? AND k=?');
        $st->execute([$tenantId, $k]);
        $r = $st->fetchColumn();
        if ($r !== false && $r !== null && $r !== '') return (string)$r;
    } catch (Throwable $e) {
    }
    /* 板块没单独设过就退回全局默认 */
    return setting_get_global($k, $def);
}

/** 板块设置写 */
function tenant_setting_set(int $tenantId, string $k, string $v): void
{
    if ($tenantId <= 0) {
        setting_set_global($k, $v);
        return;
    }
    try {
        db()->prepare('INSERT INTO tenant_settings(tenant_id,k,v) VALUES(?,?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)')
            ->execute([$tenantId, $k, $v]);
    } catch (Throwable $e) {
    }
}

/** 板块对外结构（后台列表 / App 激活返回都用它） */
function tenant_out(array $t): array
{
    return [
        'id' => (int)$t['id'],
        'name' => (string)($t['name'] ?? ''),
        'phone' => (string)($t['phone'] ?? ''),
        'shop_name' => (string)($t['shop_name'] ?? ''),
        'code' => (string)($t['code'] ?? ''),
        'status' => (string)($t['status'] ?? '正常'),
        'note' => (string)($t['note'] ?? ''),
        'restore_flag' => (int)($t['restore_flag'] ?? 0),
        'restore_at' => $t['restore_at'] ?? null,
        'restored_at' => $t['restored_at'] ?? null,
        'device_count' => (int)($t['device_count'] ?? 0),
        'last_active_at' => $t['last_active_at'] ?? null,
        'created_at' => $t['created_at'] ?? null,
    ];
}

/** 重新数一遍板块的设备数 */
function tenant_sync_device_count(int $tenantId): void
{
    try {
        $st = db()->prepare("SELECT COUNT(*) FROM activations WHERE tenant_id=? AND status='生效中'");
        $st->execute([$tenantId]);
        $n = (int)$st->fetchColumn();
        db()->prepare('UPDATE tenants SET device_count=? WHERE id=?')->execute([$n, $tenantId]);
        tenant_forget($tenantId);
    } catch (Throwable $e) {
    }
}

/** 标记活跃 */
function tenant_touch(int $tenantId): void
{
    if ($tenantId < 0) return;
    try {
        db()->prepare('UPDATE tenants SET last_active_at=? WHERE id=?')->execute([now(), $tenantId]);
        tenant_forget($tenantId);
    } catch (Throwable $e) {
    }
}

/** 统计某板块的数据量（后台板块列表里显示） */
function tenant_counts(int $tenantId): array
{
    $out = [];
    $map = ['customers' => 'customers', 'photos' => 'photos', 'steps' => 'client_steps',
            'products' => 'products', 'appointments' => 'appointments', 'members' => 'members'];
    foreach ($map as $label => $table) {
        try {
            if (!column_exists(db(), $table, 'tenant_id')) { $out[$label] = 0; continue; }
            $st = db()->prepare("SELECT COUNT(*) FROM `$table` WHERE tenant_id=?");
            $st->execute([$tenantId]);
            $out[$label] = (int)$st->fetchColumn();
        } catch (Throwable $e) {
            $out[$label] = 0;
        }
    }
    return $out;
}

/** 把上传目录按板块分开放，避免文件名撞车 */
function tenant_upload_dir(): string
{
    $id = tenant_current_id();
    return $id > 0 ? 't' . $id : '';
}
