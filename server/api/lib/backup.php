<?php
/**
 * 一键备份：把所有业务数据导出为 CSV + 图片，打包成 zip
 */
declare(strict_types=1);

/** 备份文件根目录（优先站点外，避免被直接下载） */
function backup_root(): string
{
    $primary = '/www/meiyan-backups';
    if (@is_dir($primary) && @is_writable($primary)) return $primary;
    if (!@is_dir($primary)) @mkdir($primary, 0755, true);
    if (@is_dir($primary) && @is_writable($primary)) return $primary;

    // 兜底：站点目录（文件名带随机串，不易被猜中）
    $dir = dirname(__DIR__, 2) . '/backups';
    if (!@is_dir($dir)) @mkdir($dir, 0755, true);
    return $dir;
}

/** 人类可读体积 */
function backup_size_text(int $bytes): string
{
    if ($bytes >= 1073741824) return round($bytes / 1073741824, 2) . ' GB';
    if ($bytes >= 1048576) return round($bytes / 1048576, 2) . ' MB';
    if ($bytes >= 1024) return round($bytes / 1024, 1) . ' KB';
    return $bytes . ' B';
}

/**
 * 执行一条 SQL 并转成 CSV 字符串（带 UTF-8 BOM，Excel 直接打开不乱码）
 * @return array{0:string,1:int} [csv, 行数]
 */
function backup_sql_csv(PDO $db, string $sql, ?array $fallbackHeader = null): array
{
    $st = $db->query($sql);
    $fh = fopen('php://temp/maxmemory:4194304', 'w+');
    fwrite($fh, "\xEF\xBB\xBF");

    $header = null;
    $n = 0;
    while ($row = $st->fetch(PDO::FETCH_ASSOC)) {
        if ($header === null) {
            $header = array_keys($row);
            fputcsv($fh, $header);
        }
        fputcsv($fh, array_values($row));
        $n++;
    }
    if ($header === null && $fallbackHeader) {
        fputcsv($fh, $fallbackHeader);
    }
    rewind($fh);
    $csv = (string)stream_get_contents($fh);
    fclose($fh);
    return [$csv, $n];
}

/** 递归收集目录下的文件（相对路径 => 绝对路径） */
function backup_walk(string $dir, string $prefix = ''): array
{
    $out = [];
    if (!is_dir($dir)) return $out;
    $items = @scandir($dir) ?: [];
    foreach ($items as $it) {
        if ($it === '.' || $it === '..') continue;
        $full = $dir . '/' . $it;
        $rel = $prefix === '' ? $it : $prefix . '/' . $it;
        if (is_dir($full)) {
            $out += backup_walk($full, $rel);
        } elseif (is_file($full)) {
            $out[$rel] = $full;
        }
    }
    return $out;
}

/**
 * 生成一份备份
 * @param array  $admin    当前管理员
 * @param string $note     备注
 * @param bool   $withImg  是否打包图片
 * @return array 备份记录
 */
function backup_create(array $admin, string $note = '', bool $withImg = true): array
{
    if (!class_exists('ZipArchive')) {
        throw new RuntimeException('服务器未安装 zip 扩展，无法打包');
    }

    $db = db();
    $root = backup_root();
    $day = date('Ymd');
    $dir = $root . '/' . $day;
    if (!is_dir($dir)) @mkdir($dir, 0755, true);

    $stamp = date('Ymd-His');
    $rand = substr(bin2hex(random_bytes(4)), 0, 8);
    $fileName = 'meiyan-backup-' . $stamp . '-' . $rand . '.zip';
    $abs = $dir . '/' . $fileName;

    $zip = new ZipArchive();
    if ($zip->open($abs, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
        throw new RuntimeException('无法创建备份文件，请检查 backups 目录权限');
    }

    /* ---------------- 各表导出（列名即表头，直接给店主看） ---------------- */
    $exports = [
        '01-会员.csv' => [
            "SELECT m.id AS 编号, m.name AS 姓名, m.phone AS 手机号, m.email AS 邮箱,
                    m.level AS 会员等级, m.status AS 状态, m.balance AS 账户余额, m.points AS 积分,
                    m.total_recharge AS 累计充值, m.total_spent AS 累计消费,
                    p.name AS 当前套餐, m.expire_at AS 到期时间, m.source AS 来源,
                    m.note AS 备注, m.created_at AS 注册时间
             FROM members m LEFT JOIN packages p ON p.id = m.package_id
             ORDER BY m.id",
            ['编号', '姓名', '手机号', '邮箱', '会员等级', '状态', '账户余额', '积分', '累计充值', '累计消费', '当前套餐', '到期时间', '来源', '备注', '注册时间'],
        ],
        '02-客户.csv' => [
            "SELECT c.id AS 编号, c.name AS 姓名, c.phone AS 手机号, m.name AS 关联会员,
                    m.phone AS 会员手机号, c.stage AS 当前环节, c.progress AS 已完成步数,
                    c.quoted AS 应收金额, c.note AS 备注, c.created_at AS 建档时间
             FROM customers c LEFT JOIN members m ON m.id = c.member_id
             ORDER BY c.id",
            ['编号', '姓名', '手机号', '关联会员', '会员手机号', '当前环节', '已完成步数', '应收金额', '备注', '建档时间'],
        ],
        '03-代理.csv' => [
            "SELECT a.id AS 编号, a.name AS 姓名, a.phone AS 手机号, a.wechat AS 微信号,
                    a.region AS 地区门店, a.level AS 代理等级, a.discount AS 拿货折扣,
                    pa.name AS 上级代理, a.joined_at AS 加入时间, a.status AS 状态,
                    a.note AS 备注, a.created_at AS 创建时间
             FROM agents a LEFT JOIN agents pa ON pa.id = a.parent_id
             ORDER BY a.id",
            ['编号', '姓名', '手机号', '微信号', '地区门店', '代理等级', '拿货折扣', '上级代理', '加入时间', '状态', '备注', '创建时间'],
        ],
        '04-导师.csv' => [
            "SELECT id AS 编号, name AS 姓名, title AS 职称, tags AS 擅长标签, phone AS 手机号,
                    status AS 状态, intro AS 简介, photo AS 照片路径, created_at AS 创建时间
             FROM mentors ORDER BY id",
            ['编号', '姓名', '职称', '擅长标签', '手机号', '状态', '简介', '照片路径', '创建时间'],
        ],
        '05-相册图片.csv' => [
            "SELECT p.id AS 编号, c.name AS 客户, c.phone AS 客户手机号, p.phase AS 阶段,
                    p.url AS 图片路径, p.note AS 说明, p.created_at AS 上传时间
             FROM photos p LEFT JOIN customers c ON c.id = p.customer_id
             ORDER BY p.id",
            ['编号', '客户', '客户手机号', '阶段', '图片路径', '说明', '上传时间'],
        ],
        '06-对比图.csv' => [
            "SELECT p.id AS 编号, c.name AS 客户, c.phone AS 客户手机号, p.title AS 标题,
                    p.before_url AS 使用前, p.after_url AS 使用后, p.note AS 说明, p.created_at AS 创建时间
             FROM compares p LEFT JOIN customers c ON c.id = p.customer_id
             ORDER BY p.id",
            ['编号', '客户', '客户手机号', '标题', '使用前', '使用后', '说明', '创建时间'],
        ],
        '07-收款.csv' => [
            "SELECT p.id AS 编号, c.name AS 客户, c.phone AS 客户手机号, m.name AS 会员,
                    p.amount AS 金额, p.method AS 收款方式, p.status AS 状态,
                    p.paid_at AS 收款时间, p.note AS 备注
             FROM payments p
             LEFT JOIN customers c ON c.id = p.customer_id
             LEFT JOIN members m ON m.id = p.member_id
             ORDER BY p.id",
            ['编号', '客户', '客户手机号', '会员', '金额', '收款方式', '状态', '收款时间', '备注'],
        ],
        '08-套餐开通.csv' => [
            "SELECT s.id AS 编号, m.name AS 会员, m.phone AS 手机号, p.name AS 套餐,
                    s.amount AS 实收金额, s.started_at AS 开通时间, s.expire_at AS 到期时间,
                    s.status AS 状态, s.note AS 备注
             FROM member_packages s
             LEFT JOIN members m ON m.id = s.member_id
             LEFT JOIN packages p ON p.id = s.package_id
             ORDER BY s.id",
            ['编号', '会员', '手机号', '套餐', '实收金额', '开通时间', '到期时间', '状态', '备注'],
        ],
        '09-钱包流水.csv' => [
            "SELECT w.id AS 编号, m.name AS 会员, m.phone AS 手机号, w.kind AS 类型,
                    w.amount AS 金额变动, w.points AS 积分变动, w.balance_after AS 变动后余额,
                    w.points_after AS 变动后积分, w.ref AS 关联单号, w.note AS 说明, w.created_at AS 时间
             FROM wallet_logs w LEFT JOIN members m ON m.id = w.member_id
             ORDER BY w.id",
            ['编号', '会员', '手机号', '类型', '金额变动', '积分变动', '变动后余额', '变动后积分', '关联单号', '说明', '时间'],
        ],
        '10-充值卡.csv' => [
            "SELECT id AS 编号, card_no AS 卡号, card_secret AS 卡密, card_type AS 卡类型,
                    amount AS 充值金额, bonus AS 赠送金额, points AS 积分, days AS 会员天数,
                    batch AS 批次, start_at AS 生效日期, expire_at AS 有效期至, status AS 状态,
                    used_name AS 使用人, used_at AS 使用时间, note AS 备注, created_at AS 生成时间
             FROM recharge_cards ORDER BY id",
            ['编号', '卡号', '卡密', '卡类型', '充值金额', '赠送金额', '积分', '会员天数', '批次', '生效日期', '有效期至', '状态', '使用人', '使用时间', '备注', '生成时间'],
        ],
        '11-产品.csv' => [
            "SELECT id AS 编号, name AS 产品名称, brand AS 品牌, price AS 参考价, stock AS 库存,
                    specs AS 规格, stages AS 适用阶段, steps AS 使用步骤, `desc` AS 说明,
                    cover AS 封面图, status AS 状态, created_at AS 创建时间
             FROM products ORDER BY id",
            ['编号', '产品名称', '品牌', '参考价', '库存', '规格', '适用阶段', '使用步骤', '说明', '封面图', '状态', '创建时间'],
        ],
        '12-套餐.csv' => [
            "SELECT id AS 编号, name AS 套餐名称, price AS 价格, days AS 天数,
                    items AS 包含内容, `desc` AS 说明, badge AS 角标, status AS 状态, sort AS 排序
             FROM packages ORDER BY sort, id",
            ['编号', '套餐名称', '价格', '天数', '包含内容', '说明', '角标', '状态', '排序'],
        ],
        '13-拿货记录.csv' => [
            "SELECT o.id AS 编号, a.name AS 代理, a.phone AS 手机号, o.product_name AS 产品,
                    o.spec AS 规格, o.qty AS 数量, o.unit_price AS 单价, o.amount AS 金额,
                    o.paid AS 已付, o.at AS 拿货时间, o.note AS 备注
             FROM agent_orders o LEFT JOIN agents a ON a.id = o.agent_id
             ORDER BY o.id",
            ['编号', '代理', '手机号', '产品', '规格', '数量', '单价', '金额', '已付', '拿货时间', '备注'],
        ],
        '14-系统设置.csv' => [
            "SELECT k AS 配置项, v AS 值 FROM settings ORDER BY k",
            ['配置项', '值'],
        ],
    ];

    $rowsTotal = 0;
    $tables = [];
    foreach ($exports as $name => $def) {
        try {
            [$csv, $n] = backup_sql_csv($db, $def[0], $def[1]);
            $zip->addFromString('data/' . $name, $csv);
            $rowsTotal += $n;
            $tables[] = $name . '(' . $n . ' 行)';
        } catch (Throwable $e) {
            $zip->addFromString('data/' . $name . '.error.txt', '导出失败：' . $e->getMessage());
        }
    }

    /* ---------------- 通讯录汇总（手机号 + 微信号一表带走） ---------------- */
    $contacts = [];
    $push = function (string $type, string $name, ?string $phone, ?string $wechat, string $extra) use (&$contacts) {
        $phone = trim((string)$phone);
        $wechat = trim((string)$wechat);
        if ($phone === '' && $wechat === '') return;
        $contacts[] = [$type, $name, $phone, $wechat, $extra];
    };
    foreach ($db->query('SELECT name, phone, wechat, level, region FROM agents ORDER BY id') as $r) {
        $push('代理', (string)$r['name'], $r['phone'], $r['wechat'], (string)$r['level'] . ' ' . (string)$r['region']);
    }
    foreach ($db->query('SELECT name, phone, level, expire_at FROM members ORDER BY id') as $r) {
        $push('会员', (string)$r['name'], $r['phone'], null, (string)$r['level'] . ' 到期 ' . (string)$r['expire_at']);
    }
    foreach ($db->query('SELECT name, phone, stage FROM customers ORDER BY id') as $r) {
        $push('客户', (string)$r['name'], $r['phone'], null, (string)$r['stage']);
    }
    foreach ($db->query('SELECT name, phone, title FROM mentors ORDER BY id') as $r) {
        $push('导师', (string)$r['name'], $r['phone'], null, (string)$r['title']);
    }
    $fh = fopen('php://temp/maxmemory:4194304', 'w+');
    fwrite($fh, "\xEF\xBB\xBF");
    fputcsv($fh, ['类型', '姓名', '手机号', '微信号', '备注']);
    foreach ($contacts as $c) fputcsv($fh, $c);
    rewind($fh);
    $zip->addFromString('通讯录汇总.csv', (string)stream_get_contents($fh));
    fclose($fh);

    /* ---------------- 图片 ---------------- */
    $imgCount = 0;
    if ($withImg) {
        $uploadDir = dirname(__DIR__, 2) . '/uploads';
        $files = backup_walk($uploadDir);
        foreach ($files as $rel => $full) {
            if (@filesize($full) <= 0) continue;
            if ($zip->addFile($full, 'images/' . $rel)) $imgCount++;
        }
    }

    /* ---------------- 说明文件 ---------------- */
    $readme = "美颜相册 · 数据备份\n"
        . "=====================\n\n"
        . "备份时间：" . now() . "\n"
        . "操作人：" . ($admin['email'] ?? $admin['name'] ?? '') . "\n"
        . "备注：" . ($note !== '' ? $note : '—') . "\n\n"
        . "目录结构\n"
        . "  data/            各业务表 CSV（UTF-8 带 BOM，Excel / WPS 可直接打开）\n"
        . "  通讯录汇总.csv    所有手机号与微信号的汇总表，可直接导入手机通讯录\n"
        . "  images/          相册与产品图片原图（路径与后台一致）\n\n"
        . "包含的数据表\n  " . implode("\n  ", $tables) . "\n\n"
        . "数据量\n"
        . "  数据行数：" . $rowsTotal . "\n"
        . "  图片数量：" . $imgCount . "\n\n"
        . "恢复提示\n"
        . "  1. 会员/客户/代理等 CSV 可直接用 Excel 打开查看或再加工。\n"
        . "  2. 图片按 images/ 下的路径与数据库中的图片地址一一对应。\n"
        . "  3. 如需完整恢复，请让技术人员依据 CSV 与图片重建数据库。\n";
    $zip->addFromString('备份说明.txt', $readme);

    $zip->close();
    @chmod($abs, 0644);

    $size = (int)@filesize($abs);
    $relFile = $day . '/' . $fileName;
    $scope = ($withImg ? '全部数据 + ' . $imgCount . ' 张图片' : '仅数据（不含图片）');

    $st = $db->prepare('INSERT INTO backups(name,file,size,rows_total,photos,scope,note,created_by,created_at) VALUES(?,?,?,?,?,?,?,?,?)');
    $st->execute([$fileName, $relFile, $size, $rowsTotal, $imgCount, $scope, $note !== '' ? $note : null,
                  $admin['email'] ?? $admin['name'] ?? null, now()]);
    $id = (int)$db->lastInsertId();

    $st = $db->prepare('SELECT * FROM backups WHERE id=?');
    $st->execute([$id]);
    $row = $st->fetch() ?: [];
    $row['size_text'] = backup_size_text($size);
    return $row;
}

/** 数据概览（备份页顶部统计） */
function backup_stats(): array
{
    $db = db();
    $g = function (string $sql) use ($db) { return (int)$db->query($sql)->fetchColumn(); };
    $uploadDir = dirname(__DIR__, 2) . '/uploads';
    $files = backup_walk($uploadDir);
    $imgSize = 0;
    foreach ($files as $f) $imgSize += (int)@filesize($f);

    $dbSize = 0;
    try {
        $st = $db->prepare('SELECT COALESCE(SUM(data_length + index_length),0) FROM information_schema.tables WHERE table_schema = DATABASE()');
        $st->execute();
        $dbSize = (int)$st->fetchColumn();
    } catch (Throwable $e) { /* ignore */ }

    return [
        'members' => $g('SELECT COUNT(*) FROM members'),
        'customers' => $g('SELECT COUNT(*) FROM customers'),
        'agents' => $g('SELECT COUNT(*) FROM agents'),
        'photos' => $g('SELECT COUNT(*) FROM photos'),
        'compares' => $g('SELECT COUNT(*) FROM compares'),
        'payments' => $g('SELECT COUNT(*) FROM payments'),
        'wallet' => $g('SELECT COUNT(*) FROM wallet_logs'),
        'cards' => $g('SELECT COUNT(*) FROM recharge_cards'),
        'image_files' => count($files),
        'image_size' => $imgSize,
        'image_size_text' => backup_size_text($imgSize),
        'db_size' => $dbSize,
        'db_size_text' => backup_size_text($dbSize),
        'backups' => $g('SELECT COUNT(*) FROM backups'),
    ];
}
