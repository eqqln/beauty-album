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
            'map' => [
                'client_uid' => 'client_uid', 'phase' => 'phase', 'url' => 'url',
                'tag' => 'tag', 'file_name' => 'file_name', 'caption' => 'note',
                'created_at' => 'created_at',
            ],
            'ints' => [],
            'floats' => [],
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
    return $out;
}

/** App 结构 → 行 */
function sync_row_in(array $rec, array $def): array
{
    $special = $def['special'] ?? [];
    $row = [];

    foreach ($def['map'] as $appKey => $dbKey) {
        if (!array_key_exists($appKey, $rec)) continue;
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
        $cols = array_values(array_unique(array_merge(['id', 'uid', 'updated_at', 'created_at'], array_values($def['map']))));
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

    $out['counts'] = array_map('count', $out['data']);
    return $out;
}

/** 推送：按 uid upsert，返回每个模块的成功条数 */
function sync_push(array $payload): array
{
    $mods = sync_modules();
    $result = [];

    foreach ($payload as $name => $records) {
        if (!isset($mods[$name]) || !is_array($records)) continue;
        $def = $mods[$name];
        $table = $def['table'];
        $ok = 0;
        $skip = 0;

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

            $st = db()->prepare("SELECT id, updated_at FROM `$table` WHERE uid=? LIMIT 1");
            $st->execute([$uid]);
            $exist = $st->fetch();

            /* 较新者胜：后台改过、且比 App 这条更新，就不让 App 覆盖回去 */
            if ($exist && !empty($exist['updated_at']) && !empty($row['updated_at'])) {
                $serverTs = strtotime((string)$exist['updated_at']);
                $clientTs = strtotime((string)$row['updated_at']);
                if ($serverTs !== false && $clientTs !== false && $serverTs > $clientTs + 1) {
                    $skip++;
                    continue;
                }
            }

            try {
                if ($exist) {
                    $sets = [];
                    $vals = [];
                    foreach ($row as $k => $v) { $sets[] = "`$k`=?"; $vals[] = $v; }
                    $vals[] = $exist['id'];
                    db()->prepare("UPDATE `$table` SET " . implode(',', $sets) . " WHERE id=?")->execute($vals);
                } else {
                    $cols = array_keys($row);
                    $ph = implode(',', array_fill(0, count($cols), '?'));
                    $colsSql = implode(',', array_map(function ($c) { return "`$c`"; }, $cols));
                    db()->prepare("INSERT INTO `$table` ($colsSql) VALUES ($ph)")->execute(array_values($row));
                }
                $ok++;
            } catch (Throwable $e) {
                $skip++;
            }
        }

        $result[$name] = ['saved' => $ok, 'skipped' => $skip];
    }

    return $result;
}

/** 删除：App 端删了，后台也要删 */
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
