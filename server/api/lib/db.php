<?php
/**
 * 数据层：MySQL
 * 首次访问自动建表并写入默认数据
 */
declare(strict_types=1);

function db_config(): array
{
    $cfgFile = __DIR__ . '/../config.php';
    if (file_exists($cfgFile)) {
        $c = require $cfgFile;
        if (is_array($c)) return $c;
    }
    /* 没有 config.php 时退回环境变量，避免把密码写死在代码里 */
    return [
        'host' => getenv('MEIYAN_DB_HOST') ?: '127.0.0.1',
        'port' => (int)(getenv('MEIYAN_DB_PORT') ?: 3306),
        'database' => getenv('MEIYAN_DB_NAME') ?: 'meiyan',
        'username' => getenv('MEIYAN_DB_USER') ?: 'meiyan',
        'password' => getenv('MEIYAN_DB_PASS') ?: '',
        'charset' => 'utf8mb4',
    ];
}

function db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) return $pdo;

    $c = db_config();
    $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=%s',
        $c['host'], (int)$c['port'], $c['database'], $c['charset'] ?? 'utf8mb4');
    $pdo = new PDO($dsn, $c['username'], $c['password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
    $pdo->exec("SET time_zone = '+08:00'");

    if (!table_exists($pdo, 'settings')) {
        init_schema($pdo);
        seed_data($pdo);
    }
    // 老库升级：补齐钱包、充值卡与备份相关结构
    if (!table_exists($pdo, 'recharge_cards') || !table_exists($pdo, 'backups')) {
        init_schema($pdo);
        migrate_schema($pdo);
        seed_recharge($pdo);
    }
    return $pdo;
}

function table_exists(PDO $db, string $name): bool
{
    $st = $db->prepare('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?');
    $st->execute([$name]);
    return (int)$st->fetchColumn() > 0;
}

function column_exists(PDO $db, string $table, string $column): bool
{
    $st = $db->prepare('SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?');
    $st->execute([$table, $column]);
    return (int)$st->fetchColumn() > 0;
}

/** 补字段（MySQL 5.7 不支持 ADD COLUMN IF NOT EXISTS） */
function add_column(PDO $db, string $table, string $column, string $definition): void
{
    if (column_exists($db, $table, $column)) return;
    $db->exec("ALTER TABLE `$table` ADD COLUMN `$column` $definition");
}

/** 老库升级：给 members 加钱包字段 */
function migrate_schema(PDO $db): void
{
    add_column($db, 'members', 'balance', "DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT '账户余额'");
    add_column($db, 'members', 'total_recharge', "DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT '累计充值'");
    add_column($db, 'members', 'total_spent', "DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT '累计消费'");
    add_column($db, 'members', 'total_points', "INT NOT NULL DEFAULT 0 COMMENT '累计获得积分'");
}

function init_schema(PDO $db): void
{
    $sql = [];

    $sql[] = "CREATE TABLE IF NOT EXISTS admins (
        id INT AUTO_INCREMENT PRIMARY KEY,
        email VARCHAR(120) UNIQUE,
        phone VARCHAR(30),
        name VARCHAR(60),
        pass_hash VARCHAR(255) NOT NULL,
        role VARCHAR(20) NOT NULL DEFAULT 'owner',
        status VARCHAR(20) NOT NULL DEFAULT '正常',
        created_at DATETIME NOT NULL,
        last_login DATETIME NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS members (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(60) NOT NULL,
        phone VARCHAR(30) UNIQUE,
        email VARCHAR(120),
        pass_hash VARCHAR(255),
        level VARCHAR(30) DEFAULT '普通会员',
        status VARCHAR(20) DEFAULT '正常',
        package_id INT NULL,
        expire_at DATETIME NULL,
        points INT DEFAULT 0,
        balance DECIMAL(12,2) NOT NULL DEFAULT 0,
        total_recharge DECIMAL(12,2) NOT NULL DEFAULT 0,
        total_spent DECIMAL(12,2) NOT NULL DEFAULT 0,
        total_points INT NOT NULL DEFAULT 0,
        avatar VARCHAR(255),
        note TEXT,
        source VARCHAR(20) DEFAULT '后台',
        created_at DATETIME NOT NULL,
        updated_at DATETIME NULL,
        KEY idx_phone (phone)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS mentors (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(60) NOT NULL,
        title VARCHAR(80),
        tags VARCHAR(255),
        phone VARCHAR(30),
        photo VARCHAR(255),
        intro TEXT,
        status VARCHAR(20) DEFAULT '在岗',
        sort INT DEFAULT 10,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS products (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(120) NOT NULL,
        brand VARCHAR(80),
        price DECIMAL(10,2) DEFAULT 0,
        stock INT DEFAULT 0,
        specs TEXT,
        stages VARCHAR(255),
        steps TEXT,
        cover VARCHAR(255),
        `desc` TEXT,
        status VARCHAR(20) DEFAULT '在售',
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS agents (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(60) NOT NULL,
        phone VARCHAR(30),
        wechat VARCHAR(60),
        region VARCHAR(120),
        level VARCHAR(30) DEFAULT '一级代理',
        discount INT DEFAULT 65,
        parent_id INT NULL,
        joined_at DATE NULL,
        status VARCHAR(20) DEFAULT '合作中',
        note TEXT,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS agent_orders (
        id INT AUTO_INCREMENT PRIMARY KEY,
        agent_id INT NULL,
        product_name VARCHAR(120),
        spec VARCHAR(120),
        qty DECIMAL(10,2) DEFAULT 0,
        unit_price DECIMAL(10,2) DEFAULT 0,
        amount DECIMAL(12,2) DEFAULT 0,
        paid DECIMAL(12,2) DEFAULT 0,
        at DATETIME NULL,
        note TEXT,
        created_at DATETIME NOT NULL,
        KEY idx_agent (agent_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS customers (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(60) NOT NULL,
        phone VARCHAR(30),
        member_id INT NULL,
        stage VARCHAR(60),
        progress INT DEFAULT 0,
        quoted DECIMAL(10,2) DEFAULT 0,
        note TEXT,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS photos (
        id INT AUTO_INCREMENT PRIMARY KEY,
        customer_id INT NULL,
        phase VARCHAR(20) DEFAULT '使用前',
        url VARCHAR(255) NOT NULL,
        note VARCHAR(255),
        created_at DATETIME NOT NULL,
        KEY idx_cust (customer_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS compares (
        id INT AUTO_INCREMENT PRIMARY KEY,
        customer_id INT NULL,
        title VARCHAR(120),
        before_url VARCHAR(255),
        after_url VARCHAR(255),
        note VARCHAR(255),
        created_at DATETIME NOT NULL,
        KEY idx_cust (customer_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS payments (
        id INT AUTO_INCREMENT PRIMARY KEY,
        customer_id INT NULL,
        member_id INT NULL,
        amount DECIMAL(12,2) DEFAULT 0,
        method VARCHAR(30) DEFAULT '微信',
        status VARCHAR(30) DEFAULT '已收款',
        paid_at DATETIME NULL,
        note VARCHAR(255),
        created_at DATETIME NOT NULL,
        KEY idx_cust (customer_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS packages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(120) NOT NULL,
        price DECIMAL(10,2) DEFAULT 0,
        days INT DEFAULT 30,
        items TEXT,
        `desc` TEXT,
        badge VARCHAR(30),
        status VARCHAR(20) DEFAULT '上架',
        sort INT DEFAULT 10,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS member_packages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        member_id INT NULL,
        package_id INT NULL,
        amount DECIMAL(12,2) DEFAULT 0,
        started_at DATETIME NULL,
        expire_at DATETIME NULL,
        status VARCHAR(20) DEFAULT '生效中',
        note VARCHAR(255),
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS settings (
        k VARCHAR(60) PRIMARY KEY,
        v TEXT
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS sms_providers (
        id INT AUTO_INCREMENT PRIMARY KEY,
        code VARCHAR(30) UNIQUE,
        name VARCHAR(60),
        enabled TINYINT DEFAULT 0,
        config TEXT,
        sign VARCHAR(60),
        tpl_code VARCHAR(120),
        tpl_notice VARCHAR(120),
        sort INT DEFAULT 10,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS sms_logs (
        id INT AUTO_INCREMENT PRIMARY KEY,
        provider VARCHAR(60),
        phone VARCHAR(30),
        template VARCHAR(120),
        content VARCHAR(255),
        status VARCHAR(20),
        resp TEXT,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS sms_codes (
        id INT AUTO_INCREMENT PRIMARY KEY,
        phone VARCHAR(30),
        code VARCHAR(10),
        purpose VARCHAR(30),
        expire_at DATETIME,
        used TINYINT DEFAULT 0,
        created_at DATETIME NOT NULL,
        KEY idx_phone (phone)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS member_tokens (
        token VARCHAR(80) PRIMARY KEY,
        member_id INT NOT NULL,
        expire_at DATETIME NOT NULL,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    $sql[] = "CREATE TABLE IF NOT EXISTS admin_tokens (
        token VARCHAR(80) PRIMARY KEY,
        admin_id INT NOT NULL,
        expire_at DATETIME NOT NULL,
        created_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    /* ---------------- 充值卡 ---------------- */
    $sql[] = "CREATE TABLE IF NOT EXISTS recharge_cards (
        id INT AUTO_INCREMENT PRIMARY KEY,
        card_no VARCHAR(40) NOT NULL UNIQUE COMMENT '卡号',
        card_secret VARCHAR(40) NOT NULL COMMENT '卡密',
        card_type VARCHAR(20) NOT NULL DEFAULT '余额卡' COMMENT '余额卡/积分卡/组合卡/体验卡',
        amount DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT '充值金额',
        bonus DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT '赠送金额',
        points INT NOT NULL DEFAULT 0 COMMENT '赠送积分',
        days INT NOT NULL DEFAULT 0 COMMENT '赠送会员天数',
        batch VARCHAR(40) NOT NULL DEFAULT '' COMMENT '生成批次',
        start_at DATE NULL COMMENT '生效日期',
        expire_at DATE NULL COMMENT '有效期至',
        status VARCHAR(20) NOT NULL DEFAULT '未使用' COMMENT '未使用/已使用/已作废/已过期',
        used_by INT NULL COMMENT '使用会员ID',
        used_name VARCHAR(60) NULL COMMENT '使用会员名',
        used_at DATETIME NULL COMMENT '使用时间',
        note VARCHAR(255) NULL,
        created_by VARCHAR(120) NULL,
        created_at DATETIME NOT NULL,
        KEY idx_batch (batch),
        KEY idx_status (status),
        KEY idx_used (used_by)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    /* ---------------- 钱包流水 ---------------- */
    $sql[] = "CREATE TABLE IF NOT EXISTS wallet_logs (
        id INT AUTO_INCREMENT PRIMARY KEY,
        member_id INT NOT NULL,
        kind VARCHAR(20) NOT NULL DEFAULT '充值' COMMENT '充值/消费/赠送/调整/积分',
        amount DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT '本次变动金额（可为负）',
        points INT NOT NULL DEFAULT 0 COMMENT '本次变动积分（可为负）',
        balance_after DECIMAL(12,2) NOT NULL DEFAULT 0,
        points_after INT NOT NULL DEFAULT 0,
        ref VARCHAR(60) NULL COMMENT '关联单号/卡号',
        note VARCHAR(255) NULL,
        created_at DATETIME NOT NULL,
        KEY idx_member (member_id),
        KEY idx_kind (kind)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    /* ---------------- 数据备份 ---------------- */
    $sql[] = "CREATE TABLE IF NOT EXISTS backups (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(160) NOT NULL COMMENT '备份文件名',
        file VARCHAR(255) NOT NULL COMMENT '相对 backups/ 的路径',
        size BIGINT NOT NULL DEFAULT 0 COMMENT '文件大小（字节）',
        rows_total INT NOT NULL DEFAULT 0 COMMENT '导出数据行数',
        photos INT NOT NULL DEFAULT 0 COMMENT '打包图片数',
        scope VARCHAR(120) NULL COMMENT '备份范围',
        note VARCHAR(255) NULL,
        created_by VARCHAR(120) NULL,
        created_at DATETIME NOT NULL,
        KEY idx_created (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

    foreach ($sql as $s) {
        $db->exec($s);
    }
}

function seed_data(PDO $db): void
{
    $now = date('Y-m-d H:i:s');

    $settings = [
        'shop_name' => '美颜相册',
        'shop_slogan' => '专业皮肤管理',
        'before_label' => '使用前',
        'after_label' => '使用后',
        'contact_phone' => '',
        'contact_wechat' => '',
        'pay_qr' => '',
        'api_base' => 'https://meiyan.shengka.net',
        'app_version' => '1.1.0',
        'ipa_file' => 'BeautyAlbum.ipa',
        'ipa_size' => '',
        'install_note' => '',
        'notice' => '',
        'sms_enabled' => '0',
        'sms_default' => '',
        'sms_debug_code' => '1',
        'admin_invite' => '',
        'recharge_enabled' => '1',
        'recharge_prefix' => 'MY',
        'recharge_default_days' => '365',
        'recharge_min' => '1',
        'recharge_notice' => '充值卡仅限本店会员使用，一经使用不可退换。',
    ];
    $st = $db->prepare('INSERT INTO settings(k,v) VALUES(?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)');
    foreach ($settings as $k => $v) {
        $st->execute([$k, $v]);
    }

    $pkgs = [
        ['体验卡 · 单次', 99, 7, "基础清洁 × 1 次\n补水导入 × 1 次", '新客体验，含皮肤检测一次', '体验', 10],
        ['基础护理套餐', 1980, 90, "深层清洁 × 4 次\n补水导入 × 4 次\n面膜护理 × 4 次", '适合日常保养，三个月周期', '热销', 20],
        ['进阶焕肤套餐', 3980, 180, "深层清洁 × 6 次\n光电焕肤 × 3 次\n精华导入 × 6 次\n面膜护理 × 6 次", '针对暗沉、粗糙肤质，六个月周期', '', 30],
        ['尊享年卡', 9800, 365, "全年不限次基础护理\n光电项目 × 12 次\n专属顾问 1 对 1\n生日礼遇", '全年无忧，含专属皮肤管理顾问', '尊享', 40],
    ];
    $pst = $db->prepare('INSERT INTO packages(name,price,days,items,`desc`,badge,status,sort,created_at) VALUES(?,?,?,?,?,?,?,?,?)');
    foreach ($pkgs as $p) {
        $pst->execute([$p[0], $p[1], $p[2], $p[3], $p[4], $p[5], '上架', $p[6], $now]);
    }

    $providers = [
        ['aliyun', '阿里云短信', '{"access_key_id":"","access_key_secret":"","region":"cn-hangzhou"}', 10],
        ['tencent', '腾讯云短信', '{"secret_id":"","secret_key":"","sdk_app_id":"","region":"ap-guangzhou"}', 20],
        ['huawei', '华为云短信', '{"app_key":"","app_secret":"","endpoint":"https://smsapi.cn-north-4.myhuaweicloud.com"}', 30],
        ['yunpian', '云片网络', '{"apikey":""}', 40],
        ['cloopen', '容联云通讯', '{"account_sid":"","auth_token":"","app_id":"","server":"https://app.cloopen.com"}', 50],
        ['luosimao', '螺丝帽', '{"api_key":""}', 60],
        ['smsbao', '短信宝', '{"user":"","pass":""}', 70],
        ['submail', '赛邮 SUBMAIL', '{"appid":"","appkey":"","project":""}', 80],
        ['sendcloud', 'SendCloud（邮件）', '{"api_user":"","api_key":"","from":"","from_name":""}', 90],
        ['custom', '自定义 HTTP 接口', '{"url":"","method":"POST","headers":"","body":"","success_key":"code","success_value":"0"}', 100],
    ];
    $sst = $db->prepare('INSERT IGNORE INTO sms_providers(code,name,config,sort,created_at) VALUES(?,?,?,?,?)');
    foreach ($providers as $p) {
        $sst->execute([$p[0], $p[1], $p[2], $p[3], $now]);
    }
}

/** 老库升级时补充值相关默认设置 */
function seed_recharge(PDO $db): void
{
    $defaults = [
        'recharge_enabled' => '1',
        'recharge_prefix' => 'MY',
        'recharge_default_days' => '365',
        'recharge_min' => '1',
        'recharge_notice' => '充值卡仅限本店会员使用，一经使用不可退换。',
    ];
    $st = $db->prepare('INSERT INTO settings(k,v) VALUES(?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)');
    foreach ($defaults as $k => $v) $st->execute([$k, $v]);
}
