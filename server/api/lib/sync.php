<?php
/**
 * App ↔ 后台 双向同步
 *
 * 设计要点：
 * 1. App 端所有实体主键是 UUID，后台表主键是自增 INT。
 *    两边用 uid VARCHAR(36) 做映射键，子表用 client_uid / agent_uid 字符串直接引用父表，
 *    这样任何一侧都能独立构造完整对象，不需要把 INT id 翻译成 UUID。
 * 2. 增量靠 updated_at；App 推送时带 client_updated_at，服务端取 max 后落库。
 * 3. 后台手工新建的行也会补一个 uid，保证能被 App 拉到。
 */

/** 同步模块定义：app 字段 => 数据库字段 */
function sync_modules(): array
{
    return [
        'customers' => [
            'table' => 'customers',
            'map' => [
                'name' => 'name', 'phone' => 'phone', 'note' => 'note',
                'quoted_price' => 'quoted', 'stage' => 'stage', 'progress' => 'progress',
                'created_at' => 'created_at',
            ],
            'ints' => ['progress'],
            'floats' => ['quoted'],
        ],
        'photos' => [
            'table' => 'photos',
            /* photos.url 是 NOT NULL，App 端刚拍还没上传时没有 URL，给个空串兜底 */
            'defaults' => ['url' => ''],
            'map' => [
                'client_uid' => 'client_uid', 'phase' => 'phase', 'url' => 'url',
                'tag' => 'tag', 'file_name' => 'file_name', 'caption' => 'note',
                'kind' => 'kind', 'duration' => 'duration', 'thumb_name' => 'thumb_name',
                'thumb_url' => 'thumb_url', 'size_bytes' => 'size_bytes',
                'created_at' => 'created_at',
            ],
            'ints' => ['size_bytes'],
            'floats' => ['duration'],
        ],
        'compares' => [
            'table' => 'compares',
            'map' => [
                'client_uid' => 'client_uid', 'title' => 'title',
                'before_url' => 'before_url', 'after_url' => 'after_url',
                'note' => 'note', 'created_at' => 'created_at',
            ],
            'ints' => [],
            'floats' => [],
        ],
        'payments' => [
            'table' => 'payments',
            'map' => [
                'client_uid' => 'client_uid', 'amount' => 'amount', 'method' => 'method',
                'status' => 'status', 'note' => 'note', 'created_at' => 'created_at',
            ],
            'ints' => [],
            'floats' => ['amount'],
        ],
        'steps' => [
            'table' => 'client_steps',
            'map' => [
                'client_uid' => 'client_uid', 'title' => 'title', 'done' => 'done',
                'done_at' => 'done_at', 'note' => 'note', 'sort' => 'sort',
                'created_at' => 'created_at',
            ],
            'ints' => ['done', 'sort'],
            'floats' => [],
        ],
        'notes' => [
            'table' => 'client_notes',
            'map' => [
                'client_uid' => 'client_uid', 'content' => 'content',
                'created_at' => 'created_at',
            ],
            'ints' => [],
            'floats' => [],
        ],
        'claims' => [
            'table' => 'product_claims',
            'map' => [
                'client_uid' => 'client_uid', 'product_uid' => 'product_uid',
                'product_name' => 'product_name', 'spec_name' => 'spec_name',
                'quantity' => 'qty', 'claimed' => 'claimed', 'claimed_at' => 'claimed_at',
                'note' => 'note', 'created_at' => 'created_at',
            ],
            'ints' => ['qty', 'claimed'],
            'floats' => [],
        ],
        'teachers' => [
            'table' => 'mentors',
            'map' => [
                'name' => 'name', 'title' => 'title', 'phone' => 'phone',
                'intro' => 'intro', 'tags' => 'tags', 'photo' => 'photo',
                'available' => 'status', 'sort_index' => 'sort', 'created_at' => 'created_at',
            ],
            'ints' => ['sort'],
            'floats' => [],
            'special' => ['available', 'tags'],
        ],
        'products' => [
            'table' => 'products',
            'map' => [
                'name' => 'name', 'brand' => 'brand', 'category' => 'category',
                'intro' => 'desc', 'stage' => 'stages', 'usage_steps' => 'usage_steps',
                'images' => 'images', 'price' => 'price', 'stock' => 'stock',
                'specs' => 'specs', 'created_at' => 'created_at',
            ],
            'ints' => ['stock'],
            'floats' => ['price'],
            'special' => ['usage_steps', 'images', 'specs'],
        ],
        'agents' => [
            'table' => 'agents',
            'map' => [
                'name' => 'name', 'phone' => 'phone', 'wechat' => 'wechat',
                'region' => 'region', 'level' => 'level', 'discount' => 'discount',
                'parent_uid' => 'parent_uid', 'client_uids' => 'client_uids',
                'note' => 'note', 'joined_at' => 'joined_at', 'created_at' => 'created_at',
            ],
            'ints' => ['discount'],
            'floats' => [],
            'special' => ['client_uids'],
        ],
        'agent_orders' => [
            'table' => 'agent_orders',
            'map' => [
                'agent_uid' => 'agent_uid', 'product_uid' => 'product_uid',
                'product_name' => 'product_name', 'spec_name' => 'spec',
                'quantity' => 'qty', 'unit_price' => 'unit_price', 'paid' => 'paid',
                'note' => 'note', 'created_at' => 'created_at',
            ],
            'ints' => [],
            'floats' => ['qty', 'unit_price', 'paid'],
        ],
        'appointments' => [
            'table' => 'appointments',
            'map' => [
                'teacher_uid' => 'teacher_uid', 'teacher_name' => 'teacher_name',
                'client_uid' => 'client_uid', 'client_name' => 'client_name',
                'phone' => 'phone', 'service' => 'service', 'date' => 'at',
                'duration' => 'duration', 'status' => 'status', 'note' => 'note',
                'created_at' => 'created_at',
            ],
            'ints' => ['duration'],
            'floats' => [],
        ],
    ];
}

/** App 的 ISO8601 → MySQL DATETIME */
function sync_dt($v): ?string
{
    if ($v === null || $v === '') return null;
    if (is_numeric($v)) {
        $n = (float)$v;
        if ($n > 1e11) $n /= 1000.0;          // 毫秒
        return date('Y-m-d H:i:s', (int)$n);
    }
    $t = strtotime((string)$v);
    return $t === false ? null : date('Y-m-d H:i:s', $t);
}

/** MySQL DATETIME → App 的 ISO8601（带时区，Swift 的 ISO8601DateFormatter 直接吃） */
function sync_iso($v): ?string
{
    if ($v === null || $v === '' || $v === '0000-00-00 00:00:00') return null;
    $t = strtotime((string)$v);
    return $t === false ? null : date('c', $t);
}

function sync_uuid(): string
{
    $d = random_bytes(16);
    $d[6] = chr((ord($d[6]) & 0x0f) | 0x40);
    $d[8] = chr((ord($d[8]) & 0x3f) | 0x80);
    return strtoupper(vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($d), 4)));
}

/** 后台建行时补 uid */
function sync_ensure_uid(string $table, int $id): string
{
    $st = db()->prepare("SELECT uid FROM `$table` WHERE id=?");
    $st->execute([$id]);
    $uid = (string)$st->fetchColumn();
    if ($uid !== '') return $uid;
    $uid = sync_uuid();
    db()->prepare("UPDATE `$table` SET uid=? WHERE id=?")->execute([$uid, $id]);
    return $uid;
}

/**
 * 数值类型判定：ints/floats 里既可能写 App 字段名，也可能写数据库列名
 * （例如 customers 的 quoted_price => quoted），两种都要认。
 */
function sync_is(string $appKey, string $dbKey, array $list): bool
{
    return in_array($appKey, $list, true) || in_array($dbKey, $list, true);
}

/** 行 → App 结构 */
function sync_row_out(array $row, array $def): array
{
    $special = $def['special'] ?? [];
    $out = ['uid' => (string)($row['uid'] ?? '')];

    foreach ($def['map'] as $appKey => $dbKey) {
        $v = $row[$dbKey] ?? null;

        if (in_array($appKey, $special, true)) {
            if ($appKey === 'available') {
                $out[$appKey] = ($v === '在岗' || $v === null || $v === '');
            } elseif ($appKey === 'tags') {
                $out[$appKey] = $v === null || $v === ''
                    ? []
                    : array_values(array_filter(array_map('trim', preg_split('/[,，、]/u', (string)$v))));
            } elseif ($appKey === 'client_uids' || $appKey === 'images') {
                $j = json_decode((string)$v, true);
                $out[$appKey] = is_array($j) ? $j : [];
            } elseif ($appKey === 'usage_steps') {
                $out[$appKey] = $v === null || $v === ''
                    ? []
                    : array_values(array_filter(array_map('trim', preg_split('/\r\n|\r|\n/u', (string)$v))));
            } elseif ($appKey === 'specs') {
                $j = json_decode((string)$v, true);
                $out[$appKey] = is_array($j) ? $j : [];
            }
            continue;
        }

        if (in_array($appKey, ['created_at', 'done_at', 'claimed_at', 'joined_at', 'date'], true)) {
            $out[$appKey] = sync_iso($v);
            continue;
        }
        if (sync_is($appKey, $dbKey, $def['ints'])) {
            $out[$appKey] = $v === null ? 0 : (int)$v;
            continue;
        }
        if (sync_is($appKey, $dbKey, $def['floats'])) {
            $out[$appKey] = $v === null ? 0.0 : (float)$v;
            continue;
        }
        $out[$appKey] = $v === null ? '' : (string)$v;
    }

    $out['updated_at'] = sync_iso($row['updated_at'] ?? null);
    if (array_key_exists('field_ts', $row)) {
        $ft = json_decode((string)$row['field_ts'], true);
        $out['field_ts'] = is_array($ft) ? $ft : [];
    }
    return $out;
}

/** App 结构 → 行 */
function sync_row_in(array $rec, array $def): array
{
    $special = $def['special'] ?? [];
    $row = [];

    foreach ($def['map'] as $appKey => $dbKey) {
        if (!array_key_exists($appKey, $rec)) {
            if (isset($def['defaults'][$appKey])) $row[$dbKey] = $def['defaults'][$appKey];
            continue;
        }
        $v = $rec[$appKey];

        if (in_array($appKey, $special, true)) {
            if ($appKey === 'available') {
                $row[$dbKey] = $v ? '在岗' : '休息';
            } elseif ($appKey === 'tags') {
                $row[$dbKey] = is_array($v) ? implode(',', $v) : (string)$v;
            } elseif ($appKey === 'client_uids' || $appKey === 'images' || $appKey === 'specs') {
                $row[$dbKey] = json_encode($v, JSON_UNESCAPED_UNICODE);
            } elseif ($appKey === 'usage_steps') {
                $row[$dbKey] = is_array($v) ? implode("\n", $v) : (string)$v;
            }
            continue;
        }

        if (in_array($appKey, ['created_at', 'done_at', 'claimed_at', 'joined_at', 'date'], true)) {
            $row[$dbKey] = sync_dt($v);
            continue;
        }
        if (sync_is($appKey, $dbKey, $def['ints'])) {
            $row[$dbKey] = $v === null || $v === '' ? 0 : (int)$v;
            continue;
        }
        if (sync_is($appKey, $dbKey, $def['floats'])) {
            $row[$dbKey] = $v === null || $v === '' ? 0 : (float)$v;
            continue;
        }
        $row[$dbKey] = $v === null ? '' : (string)$v;
    }

    return $row;
}

/** 拉取：since 为空则全量 */
function sync_pull(?string $since): array
{
    $sinceDt = sync_dt($since);
    $out = ['server_time' => date('c'), 'since' => $since, 'data' => []];

    foreach (sync_modules() as $name => $def) {
        $table = $def['table'];
        $cols = array_values(array_unique(array_merge(['id', 'uid', 'updated_at', 'created_at', 'field_ts'], array_values($def['map']))));
        $cols = array_values(array_filter($cols, function ($c) use ($table) {
            return column_exists(db(), $table, $c);
        }));
        $sel = implode(',', array_map(function ($c) { return "`$c`"; }, $cols));

        $sql = "SELECT $sel FROM `$table`";
        $params = [];
        if ($sinceDt !== null && column_exists(db(), $table, 'updated_at')) {
            $sql .= ' WHERE (updated_at IS NULL OR updated_at >= ?)';
            $params[] = $sinceDt;
        }
        $sql .= ' ORDER BY id ASC LIMIT 20000';
        $st = db()->prepare($sql);
        $st->execute($params);

        $rows = [];
        foreach ($st->fetchAll() as $r) {
            /* 后台手工建的老行没有 uid，补一个，App 才能识别 */
            if (empty($r['uid'])) {
                $r['uid'] = sync_ensure_uid($table, (int)$r['id']);
            }
            $rows[] = sync_row_out($r, $def);
        }
        $out['data'][$name] = $rows;
    }

    /* 店铺设置不是行式数据，单独拼一条 */
    $out['data']['settings'] = [sync_settings_out()];

    $out['counts'] = array_map('count', $out['data']);
    return $out;
}

/**
 * 推送：按字段做合并，不再整行覆盖
 *
 * 客户端可以带 field_ts = {"字段名":"时间"}：
 *   - 带了这个字段，说明是"局部修改"，只处理 field_ts 里出现的列
 *   - 每一列单独比时间：客户端比服务端新才覆盖，否则保留服务端的值
 *   - 没带 field_ts（老版本 App）退回整行 LWW，行为与以前一致
 *
 * 返回里带 merged 列表，客户端可据此把被拒绝的字段改回服务端的值。
 */
function sync_push(array $payload): array
{
    $mods = sync_modules();
    $result = [];

    foreach ($payload as $name => $records) {
        /* 店铺设置走单独通道 */
        if ($name === 'settings') {
            if (is_array($records) && $records) {
                $rec = is_array(reset($records)) ? reset($records) : $records;
                sync_settings_in($rec);
                $result['settings'] = ['saved' => 1, 'skipped' => 0];
            }
            continue;
        }
        if (!isset($mods[$name]) || !is_array($records)) continue;

        $def = $mods[$name];
        $table = $def['table'];
        $hasFieldTs = column_exists(db(), $table, 'field_ts');
        $ok = 0;
        $skip = 0;
        $merged = [];

        foreach ($records as $rec) {
            if (!is_array($rec)) { $skip++; continue; }
            $uid = trim((string)($rec['uid'] ?? ''));
            if ($uid === '' || strlen($uid) > 36) { $skip++; continue; }

            $row = sync_row_in($rec, $def);
            $row = array_filter($row, function ($v) { return $v !== null; });

            /* 只保留表里真实存在的列 */
            $row = array_filter($row, function ($v, $k) use ($table) {
                return column_exists(db(), $table, $k);
            }, ARRAY_FILTER_USE_BOTH);

            $row['uid'] = $uid;
            if (column_exists(db(), $table, 'updated_at')) {
                $row['updated_at'] = sync_dt($rec['updated_at'] ?? null) ?? now();
            }
            if (column_exists(db(), $table, 'created_at') && empty($row['created_at'])) {
                $row['created_at'] = now();
            }

            /* 客户端字段时间戳：App 字段名 -> 数据库列名 */
            $ftsIn = [];
            if ($hasFieldTs && isset($rec['field_ts']) && is_array($rec['field_ts'])) {
                foreach ($rec['field_ts'] as $ak => $tv) {
                    $dk = $def['map'][$ak] ?? $ak;
                    if (column_exists(db(), $table, $dk)) $ftsIn[$dk] = (string)$tv;
                }
            }
            $partial = !empty($ftsIn);

            $st = db()->prepare("SELECT * FROM `$table` WHERE uid=? LIMIT 1");
            $st->execute([$uid]);
            $exist = $st->fetch();

            try {
                if (!$exist) {
                    /* 新行：全量插入，field_ts 按客户端给的填 */
                    if ($hasFieldTs) {
                        $ft = [];
                        foreach ($row as $col => $v) {
                            if ($col === 'uid') continue;
                            $ft[$col] = $ftsIn[$col] ?? (string)$row['updated_at'];
                        }
                        $row['field_ts'] = json_encode($ft, JSON_UNESCAPED_UNICODE);
                    }
                    $cols = array_keys($row);
                    $ph = implode(',', array_fill(0, count($cols), '?'));
                    $colsSql = implode(',', array_map(function ($c) { return "`$c`"; }, $cols));
                    db()->prepare("INSERT INTO `$table` ($colsSql) VALUES ($ph)")->execute(array_values($row));
                    $ok++;
                    continue;
                }

                /* 已有行：整行 LWW（老客户端 / 没带 field_ts） */
                if (!$partial) {
                    $serverTs = !empty($exist['updated_at']) ? strtotime((string)$exist['updated_at']) : false;
                    $clientTs = !empty($row['updated_at']) ? strtotime((string)$row['updated_at']) : false;
                    if ($serverTs !== false && $clientTs !== false && $serverTs > $clientTs + 1) {
                        $skip++;
                        continue;
                    }
                    $sets = [];
                    $vals = [];
                    $ft = $hasFieldTs ? (json_decode((string)($exist['field_ts'] ?? ''), true) ?: []) : [];
                    foreach ($row as $k => $v) {
                        $sets[] = "`$k`=?";
                        $vals[] = $v;
                        if ($hasFieldTs && $k !== 'uid') $ft[$k] = (string)$row['updated_at'];
                    }
                    if ($hasFieldTs) {
                        $sets[] = "`field_ts`=?";
                        $vals[] = json_encode($ft, JSON_UNESCAPED_UNICODE);
                    }
                    $vals[] = $exist['id'];
                    db()->prepare("UPDATE `$table` SET " . implode(',', $sets) . " WHERE id=?")->execute($vals);
                    $ok++;
                    continue;
                }

                /* 已有行 + 带 field_ts：逐列比时间 */
                $serverFts = json_decode((string)($exist['field_ts'] ?? ''), true);
                if (!is_array($serverFts)) $serverFts = [];
                $existTs = !empty($exist['updated_at']) ? strtotime((string)$exist['updated_at']) : 0;

                $sets = [];
                $vals = [];
                $maxTs = 0;
                $rejected = [];

                foreach ($row as $col => $v) {
                    if ($col === 'uid') continue;
                    if (!array_key_exists($col, $ftsIn)) continue;      // 客户端没动这列，保持服务端值

                    $cTs = strtotime($ftsIn[$col]);
                    $sTs = isset($serverFts[$col]) ? strtotime((string)$serverFts[$col]) : $existTs;
                    if ($cTs === false) $cTs = max($existTs + 1, time());
                    if ($sTs === false) $sTs = 0;

                    if ($cTs >= $sTs) {
                        $sets[] = "`$col`=?";
                        $vals[] = $v;
                        $serverFts[$col] = date('c', $cTs);
                        if ($cTs > $maxTs) $maxTs = $cTs;
                    } else {
                        $rejected[$col] = $exist[$col] ?? null;         // 服务端更新，回传服务端的值
                    }
                }

                if ($sets) {
                    $sets[] = "`updated_at`=?";
                    $vals[] = date('Y-m-d H:i:s', max($maxTs, $existTs));
                    $sets[] = "`field_ts`=?";
                    $vals[] = json_encode($serverFts, JSON_UNESCAPED_UNICODE);
                    $vals[] = $exist['id'];
                    db()->prepare("UPDATE `$table` SET " . implode(',', $sets) . " WHERE id=?")->execute($vals);
                    $ok++;
                } else {
                    $skip++;
                }

                if ($rejected) {
                    $merged[] = ['uid' => $uid, 'fields' => $rejected];
                }
            } catch (Throwable $e) {
                $skip++;
            }
        }

        $result[$name] = ['saved' => $ok, 'skipped' => $skip];
        if ($merged) $result[$name]['merged'] = $merged;
    }

    return $result;
}

function sync_delete(array $payload): array
{
    $mods = sync_modules();
    $out = [];
    foreach ($payload as $name => $uids) {
        if (!isset($mods[$name]) || !is_array($uids)) continue;
        $table = $mods[$name]['table'];
        $n = 0;
        foreach ($uids as $uid) {
            $uid = trim((string)$uid);
            if ($uid === '') continue;
            db()->prepare("DELETE FROM `$table` WHERE uid=?")->execute([$uid]);
            $n++;
        }
        $out[$name] = $n;
    }
    return $out;
}

/** 汇总：给后台「同步概览」用 */
function sync_stats(): array
{
    $out = [];
    foreach (sync_modules() as $name => $def) {
        try {
            $out[$name] = (int)db()->query("SELECT COUNT(*) FROM `{$def['table']}`")->fetchColumn();
        } catch (Throwable $e) {
            $out[$name] = 0;
        }
    }
    return $out;
}


/* =========================================================
   店铺设置（单条记录，存在 settings 键值表里）
   ========================================================= */

function sync_settings_out(): array
{
    $features = json_decode((string)setting_get('app_features', '{}'), true);
    $steps = json_decode((string)setting_get('step_template', '[]'), true);

    return [
        'uid' => 'shop',
        'shop_name' => setting_get('shop_name', '我的美容院'),
        'before_label' => setting_get('before_label', '使用前'),
        'after_label' => setting_get('after_label', '使用后'),
        'wechat_qr' => setting_get('wechat_qr', ''),
        'alipay_qr' => setting_get('alipay_qr', ''),
        'pay_link' => setting_get('pay_link', ''),
        'pay_note' => setting_get('pay_note', ''),
        'step_template' => is_array($steps) ? array_values($steps) : [],
        'features' => is_array($features) ? $features : new stdClass(),
        'home_layout' => setting_get('home_layout', '竖排列表'),
        'home_columns' => (int)setting_get('home_columns', '2'),
        'home_limit' => (int)setting_get('home_limit', '0'),
        'show_cover' => (int)setting_get('show_cover', '1'),
        'updated_at' => setting_get('app_settings_updated', date('c')),
    ];
}

function sync_settings_in(array $rec): void
{
    $strKeys = ['shop_name', 'before_label', 'after_label', 'wechat_qr', 'alipay_qr',
                'pay_link', 'pay_note', 'home_layout'];
    foreach ($strKeys as $k) {
        if (array_key_exists($k, $rec)) setting_set($k, (string)$rec[$k]);
    }

    foreach (['home_columns', 'home_limit', 'show_cover'] as $k) {
        if (array_key_exists($k, $rec)) setting_set($k, (string)(int)$rec[$k]);
    }

    if (array_key_exists('step_template', $rec)) {
        $v = $rec['step_template'];
        if (is_array($v)) setting_set('step_template', json_encode(array_values($v), JSON_UNESCAPED_UNICODE));
    }

    if (array_key_exists('features', $rec)) {
        $v = $rec['features'];
        if (is_array($v)) setting_set('app_features', json_encode($v, JSON_UNESCAPED_UNICODE));
    }

    setting_set('app_settings_updated', date('c'));
}
