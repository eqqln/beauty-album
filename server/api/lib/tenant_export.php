<?php
/**
 * 板块级一键备份：把某一块板（一个人）的全部资料导出成一个 zip
 *
 * 包含：
 *   data.json          完整数据（所有表、所有字段，用于还原）
 *   data/*.csv         同一批数据的中文表头版本（Excel / WPS 直接打开）
 *   media/             这块板的全部图片与视频（路径与数据库里的地址一一对应）
 *   manifest.json      文件清单（大小、校验用）
 *   备份说明.txt        人看的说明
 *
 * 关键点：只导出这一个板块的数据，绝不串到别人的板里。
 */
declare(strict_types=1);

/** 这块板的业务表（表名 => [中文名, 排序字段]） */
function tenant_export_tables(): array
{
    return [
        'customers'       => ['客户', 'id'],
        'photos'          => ['相册与视频', 'id'],
        'compares'        => ['前后对比图', 'id'],
        'appointments'    => ['预约记录', 'id'],
        'client_steps'    => ['护理步骤', 'id'],
        'client_notes'    => ['客户笔记', 'id'],
        'product_claims'  => ['产品领用', 'id'],
        'payments'        => ['收款记录', 'id'],
        'members'         => ['会员', 'id'],
        'member_packages' => ['会员套餐', 'id'],
        'wallet_logs'     => ['钱包流水', 'id'],
        'recharge_cards'  => ['充值卡', 'id'],
        'packages'        => ['套餐', 'id'],
        'products'        => ['产品', 'id'],
        'agents'          => ['代理', 'id'],
        'agent_orders'    => ['拿货记录', 'id'],
        'mentors'         => ['导师', 'id'],
    ];
}

/** 列名中文对照（没列到的保留原名，保证不漏字段） */
function tenant_export_labels(): array
{
    return [
        'id' => '编号', 'uid' => '同步编号', 'tenant_id' => '板块编号',
        'name' => '姓名', 'phone' => '手机号', 'email' => '邮箱', 'wechat' => '微信号',
        'note' => '备注', 'notes' => '备注', 'status' => '状态', 'sort' => '排序',
        'stage' => '当前环节', 'progress' => '完成步数', 'quoted' => '应收金额',
        'level' => '等级', 'source' => '来源', 'title' => '标题', 'tags' => '标签',
        'region' => '地区门店', 'discount' => '拿货折扣', 'parent_id' => '上级代理',
        'joined_at' => '加入时间', 'intro' => '简介', 'photo' => '照片',
        'customer_id' => '客户编号', 'client_uid' => '客户同步编号',
        'member_id' => '会员编号', 'member_phone' => '会员手机号',
        'package_id' => '套餐编号', 'agent_id' => '代理编号', 'agent_uid' => '代理同步编号',
        'teacher_uid' => '老师同步编号', 'teacher_name' => '老师',
        'client_name' => '客户姓名',
        'phase' => '阶段', 'url' => '文件地址', 'file_name' => '文件名',
        'kind' => '类型', 'duration' => '时长（秒）', 'size_bytes' => '文件大小（字节）',
        'thumb_name' => '封面文件名', 'thumb_url' => '封面地址',
        'before_url' => '使用前', 'after_url' => '使用后',
        'before_label' => '使用前标签', 'after_label' => '使用后标签',
        'amount' => '金额', 'method' => '方式', 'paid_at' => '收款时间',
        'balance' => '余额', 'points' => '积分', 'total_recharge' => '累计充值',
        'total_spent' => '累计消费', 'total_points' => '累计积分',
        'balance_after' => '变动后余额', 'points_after' => '变动后积分',
        'ref' => '关联单号', 'expire_at' => '到期时间', 'started_at' => '开通时间',
        'activated_at' => '激活时间', 'created_at' => '创建时间', 'updated_at' => '更新时间',
        'at' => '时间', 'service' => '服务项目', 'done' => '是否完成', 'done_at' => '完成时间',
        'content' => '内容', 'product_uid' => '产品同步编号', 'product_name' => '产品名称',
        'spec_name' => '规格', 'qty' => '数量', 'claimed' => '是否已领', 'claimed_at' => '领取时间',
        'price' => '价格', 'days' => '天数', 'items' => '包含内容', 'desc' => '说明',
        'badge' => '角标', 'brand' => '品牌', 'stock' => '库存', 'specs' => '规格',
        'stages' => '适用阶段', 'steps' => '使用步骤', 'cover' => '封面', 'category' => '分类',
        'images' => '图片', 'usage_steps' => '使用步骤', 'client_uids' => '关联客户',
        'unit_price' => '单价', 'paid' => '已付', 'spec' => '规格',
        'card_no' => '卡号', 'card_secret' => '卡密', 'card_type' => '卡类型',
        'bonus' => '赠送金额', 'batch' => '批次', 'start_at' => '生效日期',
        'used_name' => '使用人', 'used_at' => '使用时间', 'used_by_member' => '使用会员',
        'field_ts' => '字段修改时间',
    ];
}

/** 导出目录：备份根下按板块分开 */
function tenant_export_dir(int $tenantId): string
{
    $dir = backup_root() . '/tenants/t' . $tenantId;
    if (!is_dir($dir)) @mkdir($dir, 0755, true);
    return $dir;
}

/**
 * 收集这块板的媒体文件
 * @return array<string,string> 相对 uploads 的路径 => 绝对路径
 */
function tenant_export_media(int $tenantId): array
{
    $root = dirname(__DIR__, 2) . '/uploads';
    $out = [];

    if ($tenantId > 0) {
        /* 上传时就按 uploads/t{id}/ 分好了，整目录带走 */
        $base = $root . '/t' . $tenantId;
        foreach (backup_walk($base) as $rel => $full) {
            $out['t' . $tenantId . '/' . $rel] = $full;
        }
    } else {
        /* 默认板块的文件在 uploads 根下，但要跳过 t{id} 那些属于别人板块的目录 */
        foreach (@scandir($root) ?: [] as $it) {
            if ($it === '.' || $it === '..') continue;
            $full = $root . '/' . $it;
            if (is_dir($full) && preg_match('/^t\d+$/', $it)) continue;
            if (is_dir($full)) {
                foreach (backup_walk($full, $it) as $rel => $f) $out[$rel] = $f;
            } elseif (is_file($full)) {
                $out[$it] = $full;
            }
        }
    }

    /* 再按数据库里登记过的地址兜一遍：万一有文件没落在标准目录里也不会漏 */
    $extra = tenant_export_db_media($tenantId);
    foreach ($extra as $u) {
        $rel = ltrim($u, '/');
        if (strpos($rel, 'uploads/') !== 0) continue;
        $rel = substr($rel, strlen('uploads/'));
        if ($rel === '' || isset($out[$rel])) continue;
        $abs = $root . '/' . $rel;
        if (is_file($abs)) $out[$rel] = $abs;
    }

    return $out;
}

/** 从数据库字段里捞出媒体地址 */
function tenant_export_db_media(int $tenantId): array
{
    $urls = [];
    $grab = function ($v) use (&$urls) {
        $v = trim((string)$v);
        if ($v === '') return;
        if ($v[0] === '[' || $v[0] === '{') {
            $j = json_decode($v, true);
            if (is_array($j)) {
                array_walk_recursive($j, function ($x) use (&$urls) {
                    if (is_string($x) && strpos($x, '/uploads/') === 0) $urls[] = $x;
                });
                return;
            }
        }
        if (strpos($v, '/uploads/') === 0) $urls[] = $v;
    };

    $cols = [
        'photos'   => ['url', 'thumb_url'],
        'compares' => ['before_url', 'after_url'],
        'products' => ['cover', 'images'],
        'mentors'  => ['photo'],
    ];
    foreach ($cols as $table => $fields) {
        if (!column_exists(db(), $table, 'tenant_id')) continue;
        $sel = implode(',', array_map(function ($c) { return "`$c`"; }, $fields));
        try {
            $st = db()->prepare("SELECT $sel FROM `$table` WHERE tenant_id=?");
            $st->execute([$tenantId]);
            foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $r) {
                foreach ($r as $v) $grab($v);
            }
        } catch (Throwable $e) {
        }
    }

    /* 二维码之类的设置项也可能是本地文件 */
    foreach (['pay_qr', 'wechat_qr', 'alipay_qr'] as $k) {
        $grab(tenant_setting_get($tenantId, $k, ''));
    }
    return $urls;
}

/** 取这块板某张表的全部行 */
function tenant_export_rows(string $table, string $order, int $tenantId): array
{
    if (!column_exists(db(), $table, 'tenant_id')) return [];
    $ob = $order !== '' && column_exists(db(), $table, $order) ? " ORDER BY `$order`" : '';
    $st = db()->prepare("SELECT * FROM `$table` WHERE tenant_id=?$ob");
    $st->execute([$tenantId]);
    return $st->fetchAll(PDO::FETCH_ASSOC) ?: [];
}

/** 取表的所有列名（空表也要能写出表头） */
function tenant_export_columns(string $table): array
{
    try {
        $st = db()->query("SHOW COLUMNS FROM `$table`");
        return array_map(function ($r) { return (string)$r['Field']; }, $st->fetchAll(PDO::FETCH_ASSOC) ?: []);
    } catch (Throwable $e) {
        return [];
    }
}

/**
 * 行转 CSV 文本（UTF-8 BOM，Excel 不乱码）
 *
 * 没有数据时也要写一行表头 —— 空的 0 字节文件打开是一片空白，
 * 店主会以为导出坏了。
 */
function tenant_export_csv(array $rows, array $labels, array $fallbackCols = []): array
{
    $fh = fopen('php://temp/maxmemory:8388608', 'w+');
    fwrite($fh, "\xEF\xBB\xBF");

    $cols = $rows ? array_keys($rows[0]) : $fallbackCols;
    if (!$cols) {
        fclose($fh);
        return ['', 0];
    }
    fputcsv($fh, array_map(function ($c) use ($labels) { return $labels[$c] ?? $c; }, $cols));
    foreach ($rows as $r) {
        fputcsv($fh, array_map(function ($v) {
            if ($v === null) return '';
            if (is_bool($v)) return $v ? '1' : '0';
            return (string)$v;
        }, array_values($r)));
    }
    rewind($fh);
    $csv = (string)stream_get_contents($fh);
    fclose($fh);
    return [$csv, count($rows)];
}

/** 文件名安全化（板块名里可能有 / 或空格） */
function tenant_export_slug(string $s): string
{
    $s = preg_replace('/[^\p{Han}\p{L}\p{N}_-]+/u', '', $s);
    $s = trim((string)$s);
    if ($s === '') $s = '板块';
    return mb_substr($s, 0, 24, 'UTF-8');
}

/**
 * 生成一块板的完整备份
 *
 * @return array 备份信息
 */
function tenant_export_create(int $tenantId, array $admin): array
{
    if (!class_exists('ZipArchive')) {
        throw new RuntimeException('服务器未安装 zip 扩展，无法打包');
    }
    $t = tenant_row($tenantId);
    if (!$t) throw new RuntimeException('板块不存在');

    @set_time_limit(600);
    $db = db();
    $labels = tenant_export_labels();
    $dir = tenant_export_dir($tenantId);
    $who = tenant_export_slug((string)($t['name'] !== '' ? $t['name'] : $t['shop_name']));
    $stamp = date('Ymd-His');
    $fileName = '板块备份-' . $who . '-t' . $tenantId . '-' . $stamp . '.zip';
    $abs = $dir . '/' . $fileName;

    $zip = new ZipArchive();
    if ($zip->open($abs, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
        throw new RuntimeException('无法创建备份文件，请检查备份目录权限');
    }

    /* ---------- 业务数据 ---------- */
    $payload = [
        'meta' => [
            'app' => '美颜相册',
            'schema_version' => SCHEMA_VERSION,
            'exported_at' => now(),
            'exported_by' => (string)($admin['email'] ?? $admin['name'] ?? ''),
            'tenant_id' => $tenantId,
            'tenant_name' => (string)($t['name'] ?? ''),
            'tenant_phone' => (string)($t['phone'] ?? ''),
            'shop_name' => (string)($t['shop_name'] ?? ''),
            'scope' => '单个板块（一个客户/一家店）的全部资料',
        ],
        'tenant' => $t,
        'tenant_settings' => [],
        'tables' => [],
    ];

    /* 板块设置 */
    try {
        $st = $db->prepare('SELECT k, v FROM tenant_settings WHERE tenant_id=? ORDER BY k');
        $st->execute([$tenantId]);
        foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $payload['tenant_settings'][(string)$r['k']] = (string)$r['v'];
        }
    } catch (Throwable $e) {
    }

    $rowsTotal = 0;
    $tableStat = [];
    $i = 0;
    foreach (tenant_export_tables() as $table => $def) {
        [$label, $order] = $def;
        $i++;
        try {
            $rows = tenant_export_rows($table, $order, $tenantId);
            $payload['tables'][$table] = $rows;
            [$csv, $n] = tenant_export_csv($rows, $labels, tenant_export_columns($table));
            $zip->addFromString(sprintf('data/%02d-%s（%s）.csv', $i, $label, $table), $csv);
            $rowsTotal += $n;
            $tableStat[] = $label . ' ' . $n . ' 条';
        } catch (Throwable $e) {
            $zip->addFromString(sprintf('data/%02d-%s.读取失败.txt', $i, $label),
                "表 $table 读取失败：" . $e->getMessage() . "\n");
            $tableStat[] = $label . ' 读取失败';
        }
    }

    /* ---------- 授权信息 ---------- */
    $lic = ['codes' => [], 'activations' => [], 'logs' => []];
    try {
        $st = $db->prepare('SELECT * FROM activation_codes WHERE tenant_id=? ORDER BY id');
        $st->execute([$tenantId]);
        $lic['codes'] = $st->fetchAll(PDO::FETCH_ASSOC) ?: [];
    } catch (Throwable $e) {
    }
    try {
        $st = $db->prepare('SELECT * FROM activations WHERE tenant_id=? ORDER BY id');
        $st->execute([$tenantId]);
        $lic['activations'] = $st->fetchAll(PDO::FETCH_ASSOC) ?: [];
    } catch (Throwable $e) {
    }
    try {
        $codes = array_column($lic['codes'], 'code');
        if ($codes) {
            $ph = implode(',', array_fill(0, count($codes), '?'));
            $st = $db->prepare("SELECT * FROM activation_logs WHERE code IN ($ph) ORDER BY id");
            $st->execute($codes);
            $lic['logs'] = $st->fetchAll(PDO::FETCH_ASSOC) ?: [];
        }
    } catch (Throwable $e) {
    }
    $payload['license'] = $lic;

    $zip->addFromString('data.json',
        json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT));

    /* ---------- 媒体 ---------- */
    $media = tenant_export_media($tenantId);
    $imgCount = 0;
    $imgBytes = 0;
    $manifest = [];
    foreach ($media as $rel => $full) {
        $size = (int)@filesize($full);
        if ($size <= 0) continue;
        if ($zip->addFile($full, 'media/' . $rel)) {
            $imgCount++;
            $imgBytes += $size;
            $manifest[] = ['path' => 'media/' . $rel, 'size' => $size];
        }
    }

    $zip->addFromString('manifest.json', json_encode([
        'tenant_id' => $tenantId,
        'exported_at' => now(),
        'rows_total' => $rowsTotal,
        'media_count' => $imgCount,
        'media_bytes' => $imgBytes,
        'files' => $manifest,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT));

    /* ---------- 说明 ---------- */
    $readme = "美颜相册 · 板块备份\n"
        . "=========================\n\n"
        . "板块：" . ($t['name'] !== '' ? $t['name'] : '未命名') . "（编号 t" . $tenantId . "）\n"
        . "店名：" . ($t['shop_name'] ?? '') . "\n"
        . "手机号：" . ($t['phone'] ?? '') . "\n"
        . "导出时间：" . now() . "\n"
        . "操作人：" . ($admin['email'] ?? $admin['name'] ?? '') . "\n\n"
        . "目录结构\n"
        . "  data.json        完整数据（所有表所有字段，技术人员用它还原）\n"
        . "  data/            同一批数据的中文表头 CSV，Excel / WPS 直接打开\n"
        . "  media/           这块板的全部图片与视频，路径与数据库里的地址一一对应\n"
        . "  manifest.json    文件清单（每个文件的大小）\n\n"
        . "包含的数据（共 " . $rowsTotal . " 条）\n  " . implode("\n  ", $tableStat) . "\n\n"
        . "媒体文件：" . $imgCount . " 个，合计 " . backup_size_text($imgBytes) . "\n\n"
        . "说明\n"
        . "  1. 这份备份只包含这一个板块的资料，不含其他板块。\n"
        . "  2. CSV 的列名已换成中文；data.json 保留原始字段名，用于完整还原。\n"
        . "  3. 图片路径与后台一致，例如 media/t" . $tenantId . "/202611/xxx.jpg 对应\n"
        . "     数据库里的 /uploads/t" . $tenantId . "/202611/xxx.jpg。\n";
    $zip->addFromString('备份说明.txt', $readme);

    $zip->close();
    @chmod($abs, 0644);

    $size = (int)@filesize($abs);

    /* 只保留最近 10 份，避免把磁盘堆满 */
    $old = glob($dir . '/板块备份-*.zip') ?: [];
    if (count($old) > 10) {
        usort($old, function ($a, $b) { return @filemtime($a) <=> @filemtime($b); });
        foreach (array_slice($old, 0, count($old) - 10) as $f) @unlink($f);
    }

    return [
        'file' => $fileName,
        'tenant_id' => $tenantId,
        'rows' => $rowsTotal,
        'media' => $imgCount,
        'size' => $size,
        'size_text' => backup_size_text($size),
        'media_size_text' => backup_size_text($imgBytes),
        'created_at' => now(),
    ];
}

/** 安全解析备份文件路径（只允许本板块目录下的 .zip） */
function tenant_export_path(int $tenantId, string $file): ?string
{
    $file = basename($file);
    if ($file === '' || substr($file, -4) !== '.zip') return null;
    $path = tenant_export_dir($tenantId) . '/' . $file;
    return is_file($path) ? $path : null;
}

/** 已有备份列表 */
function tenant_export_list(int $tenantId): array
{
    $out = [];
    foreach (glob(tenant_export_dir($tenantId) . '/板块备份-*.zip') ?: [] as $f) {
        $out[] = [
            'file' => basename($f),
            'size' => (int)@filesize($f),
            'size_text' => backup_size_text((int)@filesize($f)),
            'at' => date('Y-m-d H:i:s', (int)@filemtime($f)),
        ];
    }
    usort($out, function ($a, $b) { return strcmp($b['at'], $a['at']); });
    return $out;
}
