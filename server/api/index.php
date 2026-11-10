<?php
/**
 * 美颜相册 · 美容院管理系统 API
 * 入口：/api/index.php?r=模块/动作
 */
declare(strict_types=1);

// 任何警告都不能污染 JSON 输出
@ini_set('display_errors', '0');
error_reporting(E_ALL & ~E_NOTICE & ~E_WARNING & ~E_DEPRECATED);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require __DIR__ . '/lib/util.php';
require __DIR__ . '/lib/db.php';
require __DIR__ . '/lib/auth.php';
require __DIR__ . '/lib/sms.php';
require __DIR__ . '/lib/recharge.php';
require __DIR__ . '/lib/backup.php';
require __DIR__ . '/lib/ipa.php';
require __DIR__ . '/lib/sync.php';

$r = $_GET['r'] ?? '';
if ($r === '' && !empty($_SERVER['PATH_INFO'])) {
    $r = trim($_SERVER['PATH_INFO'], '/');
}
if ($r === '' && !empty($_SERVER['REQUEST_URI'])) {
    $p = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '';
    if (strpos($p, '/api/') === 0) {
        $r = trim(substr($p, 5), '/');
    }
}
$r = trim((string)$r, '/');

/* =========================================================
   模块定义（通用 CRUD）
   ========================================================= */
function modules(): array
{
    return [
        'packages' => [
            'table' => 'packages',
            'fields' => ['name', 'price', 'days', 'items', 'desc', 'badge', 'status', 'sort'],
            'search' => ['name', 'desc'],
            'order' => 'sort ASC, id DESC',
            'ints' => ['days', 'sort'],
            'floats' => ['price'],
        ],
        'members' => [
            'table' => 'members',
            'fields' => ['name', 'phone', 'email', 'level', 'status', 'package_id', 'expire_at', 'points', 'note', 'avatar', 'source'],
            'search' => ['name', 'phone', 'email', 'note'],
            'order' => 'id DESC',
            'ints' => ['package_id', 'points'],
            'floats' => [],
            'hide' => ['pass_hash'],
        ],
        'mentors' => [
            'table' => 'mentors',
            'fields' => ['name', 'title', 'tags', 'phone', 'photo', 'intro', 'status', 'sort'],
            'search' => ['name', 'title', 'tags', 'phone'],
            'order' => 'sort ASC, id DESC',
            'ints' => ['sort'],
            'floats' => [],
        ],
        'products' => [
            'table' => 'products',
            'fields' => ['name', 'brand', 'category', 'price', 'stock', 'specs', 'stages', 'usage_steps', 'steps', 'cover', 'images', 'desc', 'status'],
            'search' => ['name', 'brand', 'stages', 'desc'],
            'order' => 'id DESC',
            'ints' => ['stock'],
            'floats' => ['price'],
        ],
        'agents' => [
            'table' => 'agents',
            'fields' => ['name', 'phone', 'wechat', 'region', 'level', 'discount', 'parent_id', 'joined_at', 'status', 'note'],
            'search' => ['name', 'phone', 'wechat', 'region', 'note'],
            'order' => 'id DESC',
            'ints' => ['discount', 'parent_id'],
            'floats' => [],
        ],
        'orders' => [
            'table' => 'agent_orders',
            'fields' => ['agent_id', 'product_name', 'spec', 'qty', 'unit_price', 'amount', 'paid', 'at', 'note'],
            'search' => ['product_name', 'spec', 'note'],
            'order' => 'id DESC',
            'ints' => ['agent_id'],
            'floats' => ['qty', 'unit_price', 'amount', 'paid'],
        ],
        'customers' => [
            'table' => 'customers',
            'fields' => ['name', 'phone', 'member_id', 'stage', 'progress', 'quoted', 'note'],
            'search' => ['name', 'phone', 'note', 'stage'],
            'order' => 'id DESC',
            'ints' => ['member_id', 'progress'],
            'floats' => ['quoted'],
        ],
        'photos' => [
            'table' => 'photos',
            'fields' => ['customer_id', 'phase', 'url', 'note'],
            'search' => ['note', 'phase'],
            'order' => 'id DESC',
            'ints' => ['customer_id'],
            'floats' => [],
        ],
        'compares' => [
            'table' => 'compares',
            'fields' => ['customer_id', 'title', 'before_url', 'after_url', 'note'],
            'search' => ['title', 'note'],
            'order' => 'id DESC',
            'ints' => ['customer_id'],
            'floats' => [],
        ],
        'payments' => [
            'table' => 'payments',
            'fields' => ['customer_id', 'member_id', 'amount', 'method', 'status', 'paid_at', 'note'],
            'search' => ['note', 'method', 'status'],
            'order' => 'id DESC',
            'ints' => ['customer_id', 'member_id'],
            'floats' => ['amount'],
        ],
        'subs' => [
            'table' => 'member_packages',
            'fields' => ['member_id', 'package_id', 'amount', 'started_at', 'expire_at', 'status', 'note'],
            'search' => ['note', 'status'],
            'order' => 'id DESC',
            'ints' => ['member_id', 'package_id'],
            'floats' => ['amount'],
        ],
        'wallet' => [
            'table' => 'wallet_logs',
            'fields' => ['member_id', 'kind', 'amount', 'points', 'balance_after', 'points_after', 'ref', 'note'],
            'search' => ['ref', 'note', 'kind'],
            'order' => 'id DESC',
            'ints' => ['member_id', 'points', 'points_after'],
            'floats' => ['amount', 'balance_after'],
        ],
        /* ---- App 端同步过来的四类数据，后台可直接管 ---- */
        'appointments' => [
            'table' => 'appointments',
            'fields' => ['teacher_uid', 'teacher_name', 'client_uid', 'client_name', 'phone', 'service', 'at', 'duration', 'status', 'note'],
            'search' => ['teacher_name', 'client_name', 'phone', 'service', 'note'],
            'order' => 'at DESC, id DESC',
            'ints' => ['duration'],
            'floats' => [],
            'dates' => ['at'],
        ],
        'steps' => [
            'table' => 'client_steps',
            'fields' => ['client_uid', 'title', 'done', 'done_at', 'note', 'sort'],
            'search' => ['title', 'note'],
            'order' => 'client_uid ASC, sort ASC, id ASC',
            'ints' => ['done', 'sort'],
            'floats' => [],
            'dates' => ['done_at'],
        ],
        'notes' => [
            'table' => 'client_notes',
            'fields' => ['client_uid', 'content'],
            'search' => ['content'],
            'order' => 'id DESC',
            'ints' => [],
            'floats' => [],
        ],
        'claims' => [
            'table' => 'product_claims',
            'fields' => ['client_uid', 'product_uid', 'product_name', 'spec_name', 'qty', 'claimed', 'claimed_at', 'note'],
            'search' => ['product_name', 'spec_name', 'note'],
            'order' => 'id DESC',
            'ints' => ['qty', 'claimed'],
            'floats' => [],
            'dates' => ['claimed_at'],
        ],
    ];
}

function module_def(string $key): array
{
    $m = modules();
    if (!isset($m[$key])) fail('未知模块：' . $key, 404);
    return $m[$key];
}

/* =========================================================
   路由
   ========================================================= */

try {
    switch ($r) {

        /* ---------- 健康检查 ---------- */
        case 'health':
            ok(['status' => 'ok', 'time' => now()]);

        /* ---------- 站点信息（安装页 / App 启动） ---------- */
        case 'site/info': {
            $keys = ['shop_name', 'shop_slogan', 'before_label', 'after_label', 'contact_phone',
                     'contact_wechat', 'api_base', 'app_version', 'ipa_file', 'ipa_size', 'install_note', 'notice', 'pay_qr',
                     'recharge_enabled', 'recharge_notice', 'recharge_min'];
            $out = [];
            foreach ($keys as $k) $out[$k] = setting_get($k, '');
            $st = db()->query("SELECT COUNT(*) FROM packages WHERE status='上架'");
            $out['package_count'] = (int)$st->fetchColumn();
            /* 是否已有管理员，注册页据此决定是否显示邀请码 */
            $out['has_admin'] = (int)db()->query('SELECT COUNT(*) FROM admins')->fetchColumn() > 0;

            /* 安装包信息，供前台下载页使用 */
            $ipa = ipa_current();
            $out['ipa_exists'] = $ipa['exists'];
            $out['ipa_mtime'] = $ipa['mtime'] ? substr((string)$ipa['mtime'], 0, 10) : '';
            $out['ipa_size'] = $ipa['size_text'];
            $out['ipa_download_url'] = $ipa['download_url'];
            $out['manifest_url'] = $ipa['manifest_url'];
            $out['install_url'] = $ipa['install_url'];
            ok($out);
        }

        /* ---------- 套餐（公开） ---------- */
        case 'packages/list': {
            $rows = db()->query("SELECT id,name,price,days,items,`desc`,badge,sort FROM packages WHERE status='上架' ORDER BY sort ASC, id ASC")->fetchAll();
            foreach ($rows as &$row) {
                $row['price'] = (float)$row['price'];
                $row['days'] = (int)$row['days'];
                $row['items_arr'] = array_values(array_filter(array_map('trim', preg_split('/\r\n|\r|\n/', (string)$row['items']))));
            }
            ok($rows);
        }

        /* =====================================================
           后台：注册 / 登录
           ===================================================== */
        case 'admin/register': {
            $email = inp_str('email');
            $pass = (string)inp('password', '');
            $name = inp_str('name');
            if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) fail('请填写正确的邮箱');
            if (strlen($pass) < 6) fail('密码至少 6 位');

            $cnt = (int)db()->query('SELECT COUNT(*) FROM admins')->fetchColumn();
            if ($cnt > 0) {
                // 已有管理员：需要邀请码
                $invite = setting_get('admin_invite', '');
                if ($invite === '' || inp_str('invite') !== $invite) {
                    fail('系统已有管理员，注册需要邀请码（请在系统设置中查看）');
                }
            }
            $st = db()->prepare('SELECT id FROM admins WHERE email=?');
            $st->execute([$email]);
            if ($st->fetchColumn()) fail('该邮箱已注册');

            $st = db()->prepare('INSERT INTO admins(email,name,pass_hash,role,status,created_at) VALUES(?,?,?,?,?,?)');
            $st->execute([$email, $name ?: explode('@', $email)[0], password_hash($pass, PASSWORD_DEFAULT), $cnt === 0 ? 'owner' : 'staff', '正常', now()]);
            $id = (int)db()->lastInsertId();
            if ($cnt === 0) setting_set('admin_invite', substr(bin2hex(random_bytes(4)), 0, 8));

            $st = db()->prepare('SELECT * FROM admins WHERE id=?');
            $st->execute([$id]);
            $a = $st->fetch();
            ok(['token' => admin_issue($id), 'admin' => admin_out($a)], '注册成功');
        }

        case 'admin/login': {
            $acc = inp_str('email');
            $pass = (string)inp('password', '');
            if ($acc === '' || $pass === '') fail('请输入账号和密码');
            /* 账号支持：邮箱 / 姓名 / 手机号，大小写不敏感 */
            $st = db()->prepare('SELECT * FROM admins WHERE email=? OR name=? OR phone=? LIMIT 1');
            $st->execute([$acc, $acc, $acc]);
            $a = $st->fetch();
            if (!$a) {
                $st = db()->prepare('SELECT * FROM admins WHERE LOWER(email)=? LIMIT 1');
                $st->execute([strtolower($acc)]);
                $a = $st->fetch();
            }
            /* 只输了邮箱前缀（如 admin）也允许登录 */
            if (!$a && strpos($acc, '@') === false) {
                $st = db()->prepare('SELECT * FROM admins WHERE email LIKE ? LIMIT 1');
                $st->execute([$acc . '@%']);
                $a = $st->fetch();
            }
            if (!$a) fail('账号不存在，请用邮箱 / 姓名 / 手机号登录', 401);
            if (!password_verify($pass, (string)$a['pass_hash'])) fail('密码不正确', 401);
            if (($a['status'] ?? '正常') !== '正常') fail('该账号已被停用', 403);
            db()->prepare('UPDATE admins SET last_login=? WHERE id=?')->execute([now(), $a['id']]);
            ok(['token' => admin_issue((int)$a['id']), 'admin' => admin_out($a)], '登录成功');
        }

        case 'admin/me': {
            $a = admin_required();
            ok(admin_out($a));
        }

        case 'admin/logout': {
            $t = bearer();
            if ($t !== '') db()->prepare('DELETE FROM admin_tokens WHERE token=?')->execute([$t]);
            ok(null, '已退出');
        }

        case 'admin/password': {
            $a = admin_required();
            $old = (string)inp('old', '');
            $new = (string)inp('new', '');
            if (!password_verify($old, (string)$a['pass_hash'])) fail('原密码不正确');
            if (strlen($new) < 6) fail('新密码至少 6 位');
            db()->prepare('UPDATE admins SET pass_hash=? WHERE id=?')->execute([password_hash($new, PASSWORD_DEFAULT), $a['id']]);
            ok(null, '密码已修改');
        }

        /* =====================================================
           会员（App 端）
           ===================================================== */
        case 'member/send-code': {
            $phone = inp_str('phone');
            if (!phone_ok($phone)) fail('请填写正确的手机号');
            $st = db()->prepare('SELECT COUNT(*) FROM sms_codes WHERE phone=? AND created_at>?');
            $st->execute([$phone, date('Y-m-d H:i:s', time() - 60)]);
            if ((int)$st->fetchColumn() >= 1) fail('发送太频繁，请 60 秒后再试');

            [$okSend, $msg, $code] = sms_send_code($phone, inp_str('purpose', 'login'));
            if (!$okSend) fail($msg);
            $data = ['sent' => true, 'msg' => $msg];
            if ($code !== null && setting_get('sms_debug_code', '1') === '1') $data['debug_code'] = $code;
            ok($data, $msg);
        }

        case 'member/register': {
            $phone = inp_str('phone');
            $code = inp_str('code');
            $pass = (string)inp('password', '');
            $name = inp_str('name');
            if (!phone_ok($phone)) fail('请填写正确的手机号');
            if (strlen($pass) < 6) fail('密码至少 6 位');
            if (!sms_verify_code($phone, $code, 'login')) fail('验证码不正确或已过期');

            $st = db()->prepare('SELECT id FROM members WHERE phone=?');
            $st->execute([$phone]);
            if ($st->fetchColumn()) fail('该手机号已注册，请直接登录');

            $st = db()->prepare('INSERT INTO members(name,phone,pass_hash,level,status,source,created_at) VALUES(?,?,?,?,?,?,?)');
            $st->execute([$name !== '' ? $name : ('会员' . substr($phone, -4)), $phone,
                          password_hash($pass, PASSWORD_DEFAULT), '普通会员', '正常', 'App', now()]);
            $id = (int)db()->lastInsertId();
            $st = db()->prepare('SELECT * FROM members WHERE id=?');
            $st->execute([$id]);
            ok(['token' => member_issue($id), 'member' => member_out($st->fetch())], '注册成功');
        }

        case 'member/login': {
            $phone = inp_str('phone');
            $pass = (string)inp('password', '');
            $code = inp_str('code');
            if (!phone_ok($phone)) fail('请填写正确的手机号');

            $st = db()->prepare('SELECT * FROM members WHERE phone=?');
            $st->execute([$phone]);
            $m = $st->fetch();
            if (!$m) fail('该手机号还没有注册', 404);

            if ($code !== '') {
                if (!sms_verify_code($phone, $code, 'login')) fail('验证码不正确或已过期');
            } else {
                if (!$m['pass_hash'] || !password_verify($pass, (string)$m['pass_hash'])) fail('手机号或密码不正确', 401);
            }
            if (($m['status'] ?? '正常') === '停用') fail('账号已停用，请联系门店', 403);
            ok(['token' => member_issue((int)$m['id']), 'member' => member_out($m)], '登录成功');
        }

        case 'member/reset': {
            $phone = inp_str('phone');
            $code = inp_str('code');
            $pass = (string)inp('password', '');
            if (strlen($pass) < 6) fail('密码至少 6 位');
            if (!sms_verify_code($phone, $code, 'login')) fail('验证码不正确或已过期');
            $st = db()->prepare('SELECT id FROM members WHERE phone=?');
            $st->execute([$phone]);
            $id = $st->fetchColumn();
            if (!$id) fail('该手机号还没有注册', 404);
            db()->prepare('UPDATE members SET pass_hash=?, updated_at=? WHERE id=?')
                ->execute([password_hash($pass, PASSWORD_DEFAULT), now(), $id]);
            ok(null, '密码已重置，请登录');
        }

        case 'member/me': {
            $m = member_required();
            ok(member_out($m));
        }

        case 'member/update': {
            $m = member_required();
            $name = inp_str('name');
            $email = inp_str('email');
            $avatar = inp_str('avatar');
            db()->prepare('UPDATE members SET name=?, email=?, avatar=?, updated_at=? WHERE id=?')
                ->execute([$name !== '' ? $name : $m['name'], $email, $avatar !== '' ? $avatar : $m['avatar'], now(), $m['id']]);
            $st = db()->prepare('SELECT * FROM members WHERE id=?');
            $st->execute([$m['id']]);
            ok(member_out($st->fetch()), '资料已更新');
        }

        case 'member/logout': {
            $t = bearer();
            if ($t !== '') db()->prepare('DELETE FROM member_tokens WHERE token=?')->execute([$t]);
            ok(null, '已退出');
        }

        /** 会员开通套餐 */
        case 'member/activate': {
            $m = member_required();
            $pid = inp_int('package_id');
            $st = db()->prepare("SELECT * FROM packages WHERE id=? AND status='上架'");
            $st->execute([$pid]);
            $p = $st->fetch();
            if (!$p) fail('套餐不存在或已下架');

            $days = max(1, (int)$p['days']);
            $base = time();
            if (!empty($m['expire_at']) && strtotime((string)$m['expire_at']) > $base) {
                $base = strtotime((string)$m['expire_at']); // 续费顺延
            }
            $expire = date('Y-m-d H:i:s', $base + $days * 86400);

            db()->prepare('INSERT INTO member_packages(member_id,package_id,amount,started_at,expire_at,status,note,created_at) VALUES(?,?,?,?,?,?,?,?)')
                ->execute([$m['id'], $pid, (float)$p['price'], now(), $expire, '生效中', 'App 内开通', now()]);
            db()->prepare('UPDATE members SET package_id=?, expire_at=?, updated_at=? WHERE id=?')
                ->execute([$pid, $expire, now(), $m['id']]);

            $st = db()->prepare('SELECT * FROM members WHERE id=?');
            $st->execute([$m['id']]);
            ok([
                'member' => member_out($st->fetch()),
                'package' => ['id' => (int)$p['id'], 'name' => $p['name'], 'price' => (float)$p['price']],
                'expire_at' => $expire,
            ], '开通成功');
        }

        case 'member/subs': {
            $m = member_required();
            $st = db()->prepare("SELECT s.*, p.name AS package_name FROM member_packages s LEFT JOIN packages p ON p.id=s.package_id WHERE s.member_id=? ORDER BY s.id DESC LIMIT 50");
            $st->execute([$m['id']]);
            ok($st->fetchAll());
        }

        /* =====================================================
           会员钱包：充值 / 余额 / 流水
           ===================================================== */
        case 'member/recharge': {
            $m = member_required();
            if (setting_get('recharge_enabled', '1') !== '1') fail('门店暂未开放充值，请联系客服');

            $no = card_no_norm(inp_str('card_no'));
            $secret = card_secret_norm(inp_str('card_secret'));
            if ($no === '' || $secret === '') fail('请填写卡号与卡密');

            $db = db();
            $today = date('Y-m-d');

            // 先做一次只读校验，避免把无用事务拖长
            $st = $db->prepare('SELECT * FROM recharge_cards WHERE card_no=?');
            $st->execute([$no]);
            $pre = $st->fetch();
            if (!$pre) fail('卡号不存在，请核对后重试');
            if (card_secret_norm((string)$pre['card_secret']) !== $secret) fail('卡密不正确，请核对后重试');
            if ($pre['status'] === '已使用') fail('这张卡已经被使用过了（' . substr((string)$pre['used_at'], 0, 16) . '）');
            if ($pre['status'] === '已作废') fail('这张卡已作废，请联系门店');
            if (!empty($pre['start_at']) && $pre['start_at'] > $today) fail('这张卡还没到生效日期，' . $pre['start_at'] . ' 起可用');
            if (!empty($pre['expire_at']) && $pre['expire_at'] < $today) {
                $db->prepare("UPDATE recharge_cards SET status='已过期' WHERE id=?")->execute([$pre['id']]);
                fail('这张卡已过期（有效期至 ' . $pre['expire_at'] . '）');
            }

            $card = null;
            $newBalance = 0.0;
            $newPoints = 0;
            $newExpire = null;

            $db->beginTransaction();
            try {
                $st = $db->prepare('SELECT * FROM recharge_cards WHERE id=? FOR UPDATE');
                $st->execute([$pre['id']]);
                $card = $st->fetch();
                if (!$card || $card['status'] !== '未使用') throw new RuntimeException('这张卡状态已变化，请重新提交');

                $addMoney = card_total($card);
                $addPoints = (int)$card['points'];
                $addDays = (int)$card['days'];

                $newBalance = round((float)$m['balance'] + $addMoney, 2);
                $newPoints = (int)$m['points'] + $addPoints;

                // 赠送会员天数：有未到期时间就顺延，否则从今天算
                $newExpire = $m['expire_at'];
                if ($addDays > 0) {
                    $base = time();
                    if (!empty($m['expire_at']) && strtotime((string)$m['expire_at']) > $base) {
                        $base = strtotime((string)$m['expire_at']);
                    }
                    $newExpire = date('Y-m-d H:i:s', $base + $addDays * 86400);
                }

                $db->prepare('UPDATE members SET balance=?, points=?, total_recharge=total_recharge+?, total_points=total_points+?, expire_at=?, updated_at=? WHERE id=?')
                    ->execute([$newBalance, $newPoints, $addMoney, $addPoints, $newExpire, now(), $m['id']]);
                $db->prepare("UPDATE recharge_cards SET status='已使用', used_by=?, used_name=?, used_at=? WHERE id=?")
                    ->execute([$m['id'], $m['name'], now(), $card['id']]);
                wallet_log((int)$m['id'], '充值', $addMoney, $addPoints, $newBalance, $newPoints,
                           (string)$card['card_no'], '充值卡 ' . $card['card_no'] . '（' . card_label($card) . '）');

                $db->commit();
            } catch (Throwable $e) {
                if ($db->inTransaction()) $db->rollBack();
                fail($e->getMessage());
            }

            $st = $db->prepare('SELECT * FROM members WHERE id=?');
            $st->execute([$m['id']]);
            $fresh = $st->fetch();

            $addMoney = card_total((array)$card);
            $addPoints = (int)$card['points'];

            ok([
                'member' => member_out($fresh),
                'card' => [
                    'card_no' => $card['card_no'],
                    'label' => card_label($card),
                    'amount' => (float)$card['amount'],
                    'bonus' => (float)$card['bonus'],
                    'points' => (int)$card['points'],
                    'days' => (int)$card['days'],
                ],
                'balance' => $newBalance,
                'points' => $newPoints,
            ], '充值成功，到账 ¥' . rtrim(rtrim(number_format($addMoney, 2, '.', ''), '0'), '.') .
               ($addPoints > 0 ? '，积分 +' . $addPoints : ''));
        }

        case 'member/wallet': {
            $m = member_required();
            [$page, $size, $offset] = page_params();
            $db = db();
            $st = $db->prepare('SELECT COUNT(*) FROM wallet_logs WHERE member_id=?');
            $st->execute([$m['id']]);
            $total = (int)$st->fetchColumn();

            $st = $db->prepare("SELECT id,kind,amount,points,balance_after,points_after,ref,note,created_at FROM wallet_logs WHERE member_id=? ORDER BY id DESC LIMIT $size OFFSET $offset");
            $st->execute([$m['id']]);
            $logs = $st->fetchAll();
            foreach ($logs as &$l) {
                $l['amount'] = (float)$l['amount'];
                $l['points'] = (int)$l['points'];
                $l['balance_after'] = (float)$l['balance_after'];
                $l['points_after'] = (int)$l['points_after'];
            }
            ok([
                'balance' => round((float)$m['balance'], 2),
                'points' => (int)$m['points'],
                'total_recharge' => round((float)$m['total_recharge'], 2),
                'total_spent' => round((float)$m['total_spent'], 2),
                'expire_at' => $m['expire_at'],
                'logs' => $logs,
                'total' => $total,
            ]);
        }

        /* =====================================================
           后台：充值卡管理
           ===================================================== */
        case 'admin/recharge-stats': {
            admin_required();
            card_mark_expired();
            $db = db();
            $row = $db->query("SELECT
                COUNT(*) AS total,
                COALESCE(SUM(CASE WHEN status='未使用' THEN 1 ELSE 0 END),0) AS unused,
                COALESCE(SUM(CASE WHEN status='已使用' THEN 1 ELSE 0 END),0) AS used,
                COALESCE(SUM(CASE WHEN status='已作废' THEN 1 ELSE 0 END),0) AS voided,
                COALESCE(SUM(CASE WHEN status='已过期' THEN 1 ELSE 0 END),0) AS expired,
                COALESCE(SUM(CASE WHEN status='未使用' THEN amount+bonus ELSE 0 END),0) AS unused_amount,
                COALESCE(SUM(CASE WHEN status='已使用' THEN amount+bonus ELSE 0 END),0) AS used_amount,
                COALESCE(SUM(CASE WHEN status='未使用' THEN points ELSE 0 END),0) AS unused_points,
                COALESCE(SUM(CASE WHEN status='已使用' THEN points ELSE 0 END),0) AS used_points
                FROM recharge_cards")->fetch() ?: [];
            $today = date('Y-m-d');
            $month = date('Y-m');
            $f = function (string $sql) use ($db) { return (float)$db->query($sql)->fetchColumn(); };
            $g = function (string $sql) use ($db) { return (int)$db->query($sql)->fetchColumn(); };

            ok([
                'total' => (int)($row['total'] ?? 0),
                'unused' => (int)($row['unused'] ?? 0),
                'used' => (int)($row['used'] ?? 0),
                'voided' => (int)($row['voided'] ?? 0),
                'expired' => (int)($row['expired'] ?? 0),
                'unused_amount' => round((float)($row['unused_amount'] ?? 0), 2),
                'used_amount' => round((float)($row['used_amount'] ?? 0), 2),
                'unused_points' => (int)($row['unused_points'] ?? 0),
                'used_points' => (int)($row['used_points'] ?? 0),
                'recharge_today' => $f("SELECT COALESCE(SUM(amount),0) FROM wallet_logs WHERE kind='充值' AND created_at LIKE '$today%'"),
                'recharge_month' => $f("SELECT COALESCE(SUM(amount),0) FROM wallet_logs WHERE kind='充值' AND created_at LIKE '$month%'"),
                'recharge_total' => $f("SELECT COALESCE(SUM(amount),0) FROM wallet_logs WHERE kind='充值'"),
                'recharge_count' => $g("SELECT COUNT(*) FROM wallet_logs WHERE kind='充值'"),
                'balance_total' => $f('SELECT COALESCE(SUM(balance),0) FROM members'),
                'settings' => [
                    'enabled' => setting_get('recharge_enabled', '1'),
                    'prefix' => setting_get('recharge_prefix', 'MY'),
                    'default_days' => setting_get('recharge_default_days', '365'),
                    'notice' => setting_get('recharge_notice', ''),
                ],
            ]);
        }

        case 'admin/recharge-generate': {
            $a = admin_required();
            $count = max(1, min(500, inp_int('count', 10)));
            $amount = round(max(0, inp_float('amount', 0)), 2);
            $bonus = round(max(0, inp_float('bonus', 0)), 2);
            $points = max(0, inp_int('points', 0));
            $days = max(0, min(3650, inp_int('days', 0)));
            $type = inp_str('card_type', '余额卡');
            if (!in_array($type, ['余额卡', '积分卡', '组合卡', '体验卡'], true)) $type = '余额卡';
            if ($amount <= 0 && $bonus <= 0 && $points <= 0 && $days <= 0) {
                fail('充值金额、赠送金额、积分、会员天数至少要填一项');
            }

            $prefix = inp_str('prefix', setting_get('recharge_prefix', 'MY'));
            $start = inp_str('start_at');
            $expire = inp_str('expire_at');
            if ($start !== '' && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $start)) fail('生效日期格式不正确');
            if ($expire !== '' && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $expire)) fail('有效期格式不正确');
            if ($start !== '' && $expire !== '' && $start > $expire) fail('生效日期不能晚于有效期');

            $note = inp_str('note');
            $batch = inp_str('batch');
            if ($batch === '') $batch = 'B' . date('YmdHis');

            $db = db();
            $ins = $db->prepare('INSERT INTO recharge_cards(card_no,card_secret,card_type,amount,bonus,points,days,batch,start_at,expire_at,status,note,created_by,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
            $chk = $db->prepare('SELECT 1 FROM recharge_cards WHERE card_no=?');
            $out = [];

            $db->beginTransaction();
            try {
                for ($i = 0; $i < $count; $i++) {
                    $no = '';
                    for ($try = 0; $try < 10; $try++) {
                        $cand = card_no_new($prefix);
                        $chk->execute([$cand]);
                        if (!$chk->fetchColumn()) { $no = $cand; break; }
                    }
                    if ($no === '') throw new RuntimeException('卡号生成冲突，请稍后重试');
                    $sec = card_secret_new(12);
                    $ins->execute([$no, $sec, $type, $amount, $bonus, $points, $days, $batch,
                                   $start !== '' ? $start : null, $expire !== '' ? $expire : null,
                                   '未使用', $note !== '' ? $note : null,
                                   $a['email'] ?: $a['name'], now()]);
                    $out[] = ['card_no' => $no, 'card_secret' => $sec];
                }
                $db->commit();
            } catch (Throwable $e) {
                if ($db->inTransaction()) $db->rollBack();
                fail('生成失败：' . $e->getMessage());
            }

            ok([
                'batch' => $batch,
                'count' => count($out),
                'cards' => $out,
                'amount' => $amount,
                'bonus' => $bonus,
                'points' => $points,
                'days' => $days,
                'start_at' => $start,
                'expire_at' => $expire,
            ], '已生成 ' . count($out) . ' 张充值卡');
        }

        case 'admin/recharge-list': {
            admin_required();
            card_mark_expired();
            [$page, $size, $offset] = page_params();
            $kw = inp_str('kw');
            $status = inp_str('status');
            $batch = inp_str('batch');
            $type = inp_str('card_type');

            $where = [];
            $args = [];
            if ($kw !== '') {
                $where[] = '(card_no LIKE ? OR card_secret LIKE ? OR used_name LIKE ? OR batch LIKE ? OR note LIKE ?)';
                array_push($args, like($kw), like($kw), like($kw), like($kw), like($kw));
            }
            if ($status !== '') { $where[] = 'status=?'; $args[] = $status; }
            if ($batch !== '') { $where[] = 'batch=?'; $args[] = $batch; }
            if ($type !== '') { $where[] = 'card_type=?'; $args[] = $type; }
            $w = $where ? ' WHERE ' . implode(' AND ', $where) : '';

            $db = db();
            $st = $db->prepare("SELECT COUNT(*) FROM recharge_cards$w");
            $st->execute($args);
            $total = (int)$st->fetchColumn();

            $st = $db->prepare("SELECT * FROM recharge_cards$w ORDER BY id DESC LIMIT $size OFFSET $offset");
            $st->execute($args);
            $rows = $st->fetchAll();
            foreach ($rows as &$r) {
                $r['amount'] = (float)$r['amount'];
                $r['bonus'] = (float)$r['bonus'];
                $r['points'] = (int)$r['points'];
                $r['days'] = (int)$r['days'];
                $r['label'] = card_label($r);
            }

            $batches = $db->query('SELECT batch, COUNT(*) AS n, MIN(created_at) AS t FROM recharge_cards GROUP BY batch ORDER BY t DESC LIMIT 60')->fetchAll();
            foreach ($batches as &$b) $b['n'] = (int)$b['n'];

            ok(['rows' => $rows, 'total' => $total, 'page' => $page, 'size' => $size, 'batches' => $batches]);
        }

        case 'admin/recharge-export': {
            admin_required();
            card_mark_expired();
            $status = inp_str('status');
            $batch = inp_str('batch');
            $where = [];
            $args = [];
            if ($status !== '') { $where[] = 'status=?'; $args[] = $status; }
            if ($batch !== '') { $where[] = 'batch=?'; $args[] = $batch; }
            $w = $where ? ' WHERE ' . implode(' AND ', $where) : '';
            $st = db()->prepare("SELECT card_no,card_secret,card_type,amount,bonus,points,days,batch,start_at,expire_at,status,used_name,used_at,note,created_at FROM recharge_cards$w ORDER BY id DESC LIMIT 5000");
            $st->execute($args);
            $rows = $st->fetchAll();
            foreach ($rows as &$r) {
                $r['amount'] = (float)$r['amount'];
                $r['bonus'] = (float)$r['bonus'];
                $r['points'] = (int)$r['points'];
                $r['days'] = (int)$r['days'];
            }
            ok(['rows' => $rows, 'count' => count($rows)]);
        }

        case 'admin/recharge-save': {
            admin_required();
            $id = inp_int('id');
            $b = body();
            if ($id <= 0) fail('缺少卡 ID');
            $st = db()->prepare('SELECT * FROM recharge_cards WHERE id=?');
            $st->execute([$id]);
            $card = $st->fetch();
            if (!$card) fail('卡不存在', 404);
            if ($card['status'] === '已使用') fail('已使用的卡不能修改');

            $sets = [];
            $args = [];
            $map = [
                'card_type' => 's', 'amount' => 'f', 'bonus' => 'f', 'points' => 'i', 'days' => 'i',
                'start_at' => 'd', 'expire_at' => 'd', 'note' => 's', 'status' => 's',
            ];
            foreach ($map as $k => $t) {
                if (!array_key_exists($k, $b)) continue;
                $v = $b[$k];
                if ($t === 'f') $v = round((float)$v, 2);
                elseif ($t === 'i') $v = (int)$v;
                elseif ($t === 'd') $v = ($v === '' || $v === null) ? null : (string)$v;
                else $v = trim((string)$v);
                $sets[] = "`$k`=?";
                $args[] = $v;
            }
            if (!$sets) fail('没有需要修改的内容');
            $args[] = $id;
            db()->prepare('UPDATE recharge_cards SET ' . implode(',', $sets) . ' WHERE id=?')->execute($args);

            $st = db()->prepare('SELECT * FROM recharge_cards WHERE id=?');
            $st->execute([$id]);
            $row = $st->fetch();
            $row['label'] = card_label($row);
            ok($row, '已保存');
        }

        case 'admin/recharge-void': {
            admin_required();
            $id = inp_int('id');
            $st = db()->prepare('SELECT * FROM recharge_cards WHERE id=?');
            $st->execute([$id]);
            $card = $st->fetch();
            if (!$card) fail('卡不存在', 404);
            if ($card['status'] === '已使用') fail('已使用的卡不能作废');
            $next = $card['status'] === '已作废' ? '未使用' : '已作废';
            db()->prepare('UPDATE recharge_cards SET status=? WHERE id=?')->execute([$next, $id]);
            ok(['status' => $next], $next === '已作废' ? '已作废' : '已恢复为未使用');
        }

        case 'admin/recharge-delete': {
            admin_required();
            $ids = inp('ids', null);
            $id = inp_int('id');
            $list = [];
            if (is_array($ids)) {
                foreach ($ids as $v) { $n = (int)$v; if ($n > 0) $list[] = $n; }
            } elseif ($id > 0) {
                $list[] = $id;
            }
            if (!$list) fail('缺少要删除的卡');
            $ph = implode(',', array_fill(0, count($list), '?'));
            $st = db()->prepare("SELECT COUNT(*) FROM recharge_cards WHERE id IN ($ph) AND status='已使用'");
            $st->execute($list);
            if ((int)$st->fetchColumn() > 0) fail('选中的卡里有已使用的记录，不能删除');
            $st = db()->prepare("DELETE FROM recharge_cards WHERE id IN ($ph)");
            $st->execute($list);
            ok(['deleted' => $st->rowCount()], '已删除 ' . $st->rowCount() . ' 张卡');
        }

        /* =====================================================
           后台：会员钱包
           ===================================================== */
        case 'admin/member-wallet': {
            admin_required();
            $mid = inp_int('member_id');
            if ($mid <= 0) fail('请选择会员');
            $st = db()->prepare('SELECT * FROM members WHERE id=?');
            $st->execute([$mid]);
            $m = $st->fetch();
            if (!$m) fail('会员不存在', 404);
            [$page, $size, $offset] = page_params();
            $st = db()->prepare("SELECT id,kind,amount,points,balance_after,points_after,ref,note,created_at FROM wallet_logs WHERE member_id=? ORDER BY id DESC LIMIT $size OFFSET $offset");
            $st->execute([$mid]);
            $logs = $st->fetchAll();
            foreach ($logs as &$l) {
                $l['amount'] = (float)$l['amount'];
                $l['points'] = (int)$l['points'];
                $l['balance_after'] = (float)$l['balance_after'];
                $l['points_after'] = (int)$l['points_after'];
            }
            ok([
                'member' => member_out($m),
                'logs' => $logs,
            ]);
        }

        case 'admin/wallet-adjust': {
            admin_required();
            $mid = inp_int('member_id');
            $amount = round(inp_float('amount', 0), 2);
            $points = inp_int('points', 0);
            $kind = inp_str('kind', '调整');
            $note = inp_str('note', '后台调整');
            if ($mid <= 0) fail('请选择会员');
            if ($amount == 0 && $points == 0) fail('金额与积分不能同时为 0');

            $db = db();
            $db->beginTransaction();
            try {
                $st = $db->prepare('SELECT * FROM members WHERE id=? FOR UPDATE');
                $st->execute([$mid]);
                $m = $st->fetch();
                if (!$m) throw new RuntimeException('会员不存在');

                $newBalance = round((float)$m['balance'] + $amount, 2);
                if ($newBalance < 0) throw new RuntimeException('扣减后余额为负（当前余额 ¥' . number_format((float)$m['balance'], 2, '.', '') . '）');
                $newPoints = (int)$m['points'] + $points;
                if ($newPoints < 0) throw new RuntimeException('扣减后积分为负（当前积分 ' . (int)$m['points'] . '）');

                $db->prepare('UPDATE members SET balance=?, points=?, updated_at=? WHERE id=?')
                    ->execute([$newBalance, $newPoints, now(), $mid]);
                // 只有「充值」类型才计入累计充值，赠送/调整不算
                if ($amount > 0 && $kind === '充值') {
                    $db->prepare('UPDATE members SET total_recharge=total_recharge+? WHERE id=?')->execute([$amount, $mid]);
                }
                if ($points > 0) {
                    $db->prepare('UPDATE members SET total_points=total_points+? WHERE id=?')->execute([$points, $mid]);
                }
                wallet_log($mid, $kind, $amount, $points, $newBalance, $newPoints, null, $note);
                $db->commit();
            } catch (Throwable $e) {
                if ($db->inTransaction()) $db->rollBack();
                fail($e->getMessage());
            }

            $st = db()->prepare('SELECT * FROM members WHERE id=?');
            $st->execute([$mid]);
            ok(member_out($st->fetch()), '余额已更新');
        }

        /* =====================================================
           后台：一键备份
           ===================================================== */
        case 'admin/backup-stats': {
            admin_required();
            ok(backup_stats());
        }

        case 'admin/backup-create': {
            $a = admin_required();
            $note = inp_str('note');
            $withImg = (int)inp('with_images', 1) === 1;
            @set_time_limit(0);
            try {
                $row = backup_create($a, $note, $withImg);
            } catch (Throwable $e) {
                fail('备份失败：' . $e->getMessage());
            }
            ok($row, '备份完成，共 ' . $row['rows_total'] . ' 行数据' .
               ($row['photos'] > 0 ? '、' . $row['photos'] . ' 张图片' : ''));
        }

        case 'admin/backup-list': {
            admin_required();
            [$page, $size, $offset] = page_params();
            $db = db();
            $total = (int)$db->query('SELECT COUNT(*) FROM backups')->fetchColumn();
            $rows = $db->query("SELECT * FROM backups ORDER BY id DESC LIMIT $size OFFSET $offset")->fetchAll();
            foreach ($rows as &$r) {
                $r['size'] = (int)$r['size'];
                $r['rows_total'] = (int)$r['rows_total'];
                $r['photos'] = (int)$r['photos'];
                $r['size_text'] = backup_size_text((int)$r['size']);
                $r['exists'] = is_file(backup_root() . '/' . $r['file']);
            }
            ok(['rows' => $rows, 'total' => $total, 'page' => $page, 'size' => $size]);
        }

        case 'admin/backup-download': {
            admin_required();
            $id = inp_int('id');
            $st = db()->prepare('SELECT * FROM backups WHERE id=?');
            $st->execute([$id]);
            $row = $st->fetch();
            if (!$row) fail('备份记录不存在', 404);
            $path = backup_root() . '/' . $row['file'];
            if (!is_file($path)) fail('备份文件已不存在，可能已被删除');

            while (ob_get_level() > 0) @ob_end_clean();
            header('Content-Type: application/zip');
            header('Content-Disposition: attachment; filename="' . $row['name'] . '"');
            header('Content-Length: ' . filesize($path));
            header('Cache-Control: no-store');
            @readfile($path);
            exit;
        }

        case 'admin/backup-delete': {
            admin_required();
            $id = inp_int('id');
            $st = db()->prepare('SELECT * FROM backups WHERE id=?');
            $st->execute([$id]);
            $row = $st->fetch();
            if (!$row) fail('备份记录不存在', 404);
            $path = backup_root() . '/' . $row['file'];
            if (is_file($path)) @unlink($path);
            db()->prepare('DELETE FROM backups WHERE id=?')->execute([$id]);
            ok(null, '已删除该备份');
        }

        /* =====================================================
           后台：安装包（IPA）上传
           ===================================================== */
        case 'admin/ipa-info': {
            admin_required();
            ok(ipa_current());
        }

        case 'admin/ipa-upload': {
            admin_required();
            if (empty($_FILES['file'])) fail('没有收到文件，请重新选择 .ipa 安装包');
            $f = $_FILES['file'];
            if ((int)($f['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
                $map = [
                    UPLOAD_ERR_INI_SIZE => '文件超过服务器上传上限',
                    UPLOAD_ERR_FORM_SIZE => '文件超过表单上限',
                    UPLOAD_ERR_PARTIAL => '文件只上传了一部分，请重试',
                    UPLOAD_ERR_NO_FILE => '没有选择文件',
                    UPLOAD_ERR_NO_TMP_DIR => '服务器缺少临时目录',
                    UPLOAD_ERR_CANT_WRITE => '服务器写入失败',
                    UPLOAD_ERR_EXTENSION => '上传被服务器扩展中断',
                ];
                fail($map[(int)$f['error']] ?? ('上传失败，错误码 ' . $f['error']));
            }
            $ext = strtolower(pathinfo((string)$f['name'], PATHINFO_EXTENSION));
            if ($ext !== 'ipa') fail('只接受 .ipa 安装包');
            if ((int)$f['size'] <= 0) fail('文件为空，请重新导出安装包');
            if ((int)$f['size'] > 300 * 1024 * 1024) fail('安装包不能超过 300MB');

            $dir = ipa_dir();
            if (!@is_dir($dir)) fail('dl 目录不存在且无法创建');
            $fileName = 'BeautyAlbum.ipa';
            $dest = $dir . '/' . $fileName;
            if (!@move_uploaded_file($f['tmp_name'], $dest)) fail('保存失败，请检查 dl 目录权限');
            @chmod($dest, 0644);

            $version = inp_str('version');
            if ($version !== '') setting_set('app_version', $version);
            setting_set('ipa_file', $fileName);
            setting_set('ipa_size', backup_size_text((int)@filesize($dest)));
            ipa_write_manifest($version !== '' ? $version : null);

            ok(ipa_current(), '安装包已更新为 ' . backup_size_text((int)@filesize($dest)));
        }

        /* =====================================================
           概览统计
           ===================================================== */
        case 'stats/overview': {
            admin_required();
            $db = db();
            $today = date('Y-m-d');
            $month = date('Y-m');
            $g = function (string $sql) use ($db) { return (int)$db->query($sql)->fetchColumn(); };
            $f = function (string $sql) use ($db) { return (float)$db->query($sql)->fetchColumn(); };

            ok([
                'members' => $g('SELECT COUNT(*) FROM members'),
                'members_today' => $g("SELECT COUNT(*) FROM members WHERE created_at LIKE '$today%'"),
                'customers' => $g('SELECT COUNT(*) FROM customers'),
                'photos' => $g('SELECT COUNT(*) FROM photos'),
                'compares' => $g('SELECT COUNT(*) FROM compares'),
                'mentors' => $g('SELECT COUNT(*) FROM mentors'),
                'products' => $g('SELECT COUNT(*) FROM products'),
                'agents' => $g('SELECT COUNT(*) FROM agents'),
                'packages' => $g("SELECT COUNT(*) FROM packages WHERE status='上架'"),
                'subs' => $g("SELECT COUNT(*) FROM member_packages WHERE status='生效中'"),
                'income_month' => $f("SELECT COALESCE(SUM(amount),0) FROM payments WHERE status='已收款' AND paid_at LIKE '$month%'"),
                'income_total' => $f("SELECT COALESCE(SUM(amount),0) FROM payments WHERE status='已收款'"),
                'unpaid' => $f("SELECT COALESCE(SUM(amount),0) FROM payments WHERE status IN ('未收款','部分收款')"),
                'sms_today' => $g("SELECT COUNT(*) FROM sms_logs WHERE created_at LIKE '$today%'"),
                'cards_unused' => $g("SELECT COUNT(*) FROM recharge_cards WHERE status='未使用'"),
                'cards_total' => $g('SELECT COUNT(*) FROM recharge_cards'),
                'recharge_month' => $f("SELECT COALESCE(SUM(amount),0) FROM wallet_logs WHERE kind='充值' AND created_at LIKE '$month%'"),
                'recharge_total' => $f("SELECT COALESCE(SUM(amount),0) FROM wallet_logs WHERE kind='充值'"),
                'balance_total' => $f('SELECT COALESCE(SUM(balance),0) FROM members'),
                'recent_recharges' => $db->query("SELECT w.id,w.amount,w.points,w.balance_after,w.ref,w.created_at,m.name AS member FROM wallet_logs w LEFT JOIN members m ON m.id=w.member_id WHERE w.kind='充值' ORDER BY w.id DESC LIMIT 6")->fetchAll(),
                'recent_members' => $db->query('SELECT id,name,phone,level,status,created_at FROM members ORDER BY id DESC LIMIT 6')->fetchAll(),
                'recent_payments' => $db->query('SELECT p.id,p.amount,p.method,p.status,p.paid_at,c.name AS customer FROM payments p LEFT JOIN customers c ON c.id=p.customer_id ORDER BY p.id DESC LIMIT 6')->fetchAll(),
            ]);
        }

        /* =====================================================
           App ↔ 后台 双向同步
           ===================================================== */
        case 'sync/pull': {
            admin_required();
            $since = inp_str('since');
            ok(sync_pull($since !== '' ? $since : null));
        }

        case 'sync/push': {
            admin_required();
            $b = body();
            $payload = $b['data'] ?? $b;
            if (!is_array($payload)) fail('数据格式不对');
            ok(['saved' => sync_push($payload), 'server_time' => date('c')], '同步完成');
        }

        case 'sync/delete': {
            admin_required();
            $b = body();
            $payload = $b['data'] ?? $b;
            if (!is_array($payload)) fail('数据格式不对');
            ok(sync_delete($payload), '已删除');
        }

        case 'sync/stats': {
            admin_required();
            ok(['counts' => sync_stats(), 'modules' => array_keys(sync_modules())]);
        }

        /** App 端登录后台账号做全店同步 */
        case 'sync/login': {
            $acc = inp_str('account');
            $pass = (string)inp('password', '');
            if ($acc === '' || $pass === '') fail('请输入账号和密码');
            $st = db()->prepare('SELECT * FROM admins WHERE email=? LIMIT 1');
            $st->execute([$acc]);
            $a = $st->fetch();
            if (!$a) {
                $st = db()->prepare('SELECT * FROM admins WHERE LOWER(name)=? OR phone=? LIMIT 1');
                $st->execute([strtolower($acc), $acc]);
                $a = $st->fetch();
            }
            if (!$a || !password_verify($pass, (string)$a['pass_hash'])) fail('账号或密码不正确', 401);
            if (($a['status'] ?? '正常') !== '正常') fail('该账号已被停用', 403);
            db()->prepare('UPDATE admins SET last_login=? WHERE id=?')->execute([now(), $a['id']]);
            ok([
                'token' => admin_issue((int)$a['id']),
                'admin' => admin_out($a),
                'counts' => sync_stats(),
            ], '登录成功');
        }

        /* =====================================================
           通用 CRUD
           ===================================================== */
        case 'list': {
            admin_required();
            $key = inp_str('m');
            $def = module_def($key);
            [$page, $size, $offset] = page_params();
            $kw = inp_str('kw');
            $where = '';
            $args = [];
            if ($kw !== '' && $def['search']) {
                $parts = [];
                foreach ($def['search'] as $f) {
                    $parts[] = "`$f` LIKE ?";
                    $args[] = like($kw);
                }
                $where = ' WHERE (' . implode(' OR ', $parts) . ')';
            }
            // 附加筛选
            foreach (['customer_id', 'member_id', 'agent_id', 'package_id', 'phase', 'status', 'client_uid', 'agent_uid', 'teacher_uid'] as $f) {
                $v = inp($f, null);
                if ($v !== null && $v !== '') {
                    $where .= ($where === '' ? ' WHERE ' : ' AND ') . "`$f` = ?";
                    $args[] = $v;
                }
            }
            $table = $def['table'];
            $st = db()->prepare("SELECT COUNT(*) FROM $table$where");
            $st->execute($args);
            $total = (int)$st->fetchColumn();

            $st = db()->prepare("SELECT * FROM $table$where ORDER BY {$def['order']} LIMIT $size OFFSET $offset");
            $st->execute($args);
            $rows = $st->fetchAll();

            /* 子表带 client_uid / agent_uid 时，回填父级名字，列表里直接显示人名而不是 UUID */
            if ($rows && column_exists(db(), $table, 'client_uid')) {
                $uids = array_values(array_unique(array_filter(array_column($rows, 'client_uid'))));
                if ($uids) {
                    $ph = implode(',', array_fill(0, count($uids), '?'));
                    $nm = db()->prepare("SELECT uid, name FROM customers WHERE uid IN ($ph)");
                    $nm->execute($uids);
                    $map = [];
                    foreach ($nm->fetchAll() as $x) $map[(string)$x['uid']] = $x['name'];
                    foreach ($rows as &$row) {
                        $row['client_name'] = $map[(string)($row['client_uid'] ?? '')] ?? '';
                    }
                    unset($row);
                }
            }

            if (!empty($def['hide'])) {
                foreach ($rows as &$row) {
                    foreach ($def['hide'] as $h) unset($row[$h]);
                }
                unset($row);
            }
            ok(['rows' => $rows, 'total' => $total, 'page' => $page, 'size' => $size]);
        }

        case 'save': {
            admin_required();
            $key = inp_str('m');
            $def = module_def($key);
            $b = body();
            $id = (int)($b['id'] ?? 0);
            $data = pick($b, $def['fields']);

            foreach ($def['ints'] as $f) {
                if (array_key_exists($f, $data) && $data[$f] !== '' && $data[$f] !== null) $data[$f] = (int)$data[$f];
                elseif (array_key_exists($f, $data) && ($data[$f] === '' || $data[$f] === null)) $data[$f] = null;
            }
            foreach ($def['floats'] as $f) {
                if (array_key_exists($f, $data)) $data[$f] = (float)$data[$f];
            }
            /* 日期列：App 传来的 ISO8601 或后台 datetime-local 都统一成 DATETIME */
            foreach (($def['dates'] ?? []) as $f) {
                if (array_key_exists($f, $data)) $data[$f] = sync_dt($data[$f]);
            }

            // 拿货金额自动计算
            if ($key === 'orders') {
                $qty = (float)($data['qty'] ?? 0);
                $up = (float)($data['unit_price'] ?? 0);
                if (empty($data['amount'])) $data['amount'] = round($qty * $up, 2);
            }
            // 开通记录自动算到期
            if ($key === 'subs') {
                if (empty($data['started_at'])) $data['started_at'] = now();
                if (empty($data['expire_at']) && !empty($data['package_id'])) {
                    $st = db()->prepare('SELECT days FROM packages WHERE id=?');
                    $st->execute([(int)$data['package_id']]);
                    $d = (int)$st->fetchColumn();
                    if ($d > 0) $data['expire_at'] = date('Y-m-d H:i:s', strtotime((string)$data['started_at']) + $d * 86400);
                }
            }

            /* 后台新建的行也补 uid + updated_at，App 才能拉到并回写 */
            $hasUid = column_exists(db(), $def['table'], 'uid');
            $hasUpd = column_exists(db(), $def['table'], 'updated_at');

            if ($id > 0) {
                if (!$data) fail('没有需要更新的字段');
                if ($hasUpd) $data['updated_at'] = now();
                $sets = [];
                $args = [];
                foreach ($data as $k => $v) {
                    $sets[] = "`$k`=?";
                    $args[] = $v;
                }
                $args[] = $id;
                $st = db()->prepare("UPDATE {$def['table']} SET " . implode(',', $sets) . ' WHERE id=?');
                $st->execute($args);
                $st = db()->prepare("SELECT * FROM {$def['table']} WHERE id=?");
                $st->execute([$id]);
                ok($st->fetch(), '已保存');
            }

            $data['created_at'] = now();
            if ($hasUid) $data['uid'] = sync_uuid();
            if ($hasUpd) $data['updated_at'] = now();
            $cols = array_keys($data);
            $quoted = array_map(function ($c) { return "`$c`"; }, $cols);
            $st = db()->prepare("INSERT INTO {$def['table']}(" . implode(',', $quoted) . ') VALUES(' . rtrim(str_repeat('?,', count($cols)), ',') . ')');
            $st->execute(array_values($data));
            $newId = (int)db()->lastInsertId();
            $st = db()->prepare("SELECT * FROM {$def['table']} WHERE id=?");
            $st->execute([$newId]);
            ok($st->fetch(), '已新增');
        }

        case 'delete': {
            admin_required();
            $key = inp_str('m');
            $def = module_def($key);
            $id = inp_int('id');
            if ($id <= 0) fail('缺少 id');
            db()->prepare("DELETE FROM {$def['table']} WHERE id=?")->execute([$id]);
            ok(null, '已删除');
        }

        /** 下拉选项（客户 / 会员 / 套餐 / 代理） */
        case 'options': {
            admin_required();
            $type = inp_str('type');
            switch ($type) {
                case 'customers':
                    $rows = db()->query('SELECT id, uid, name, phone FROM customers ORDER BY id DESC LIMIT 500')->fetchAll();
                    break;
                case 'mentors':
                    $rows = db()->query('SELECT id, uid, name, phone FROM mentors ORDER BY sort ASC, id ASC LIMIT 500')->fetchAll();
                    break;
                case 'products':
                    $rows = db()->query('SELECT id, uid, name, price FROM products ORDER BY id DESC LIMIT 500')->fetchAll();
                    break;
                case 'members':
                    $rows = db()->query('SELECT id, name, phone FROM members ORDER BY id DESC LIMIT 500')->fetchAll();
                    break;
                case 'packages':
                    $rows = db()->query('SELECT id, name, price FROM packages ORDER BY sort ASC, id ASC')->fetchAll();
                    break;
                case 'agents':
                    $rows = db()->query('SELECT id, uid, name, level FROM agents ORDER BY id DESC LIMIT 500')->fetchAll();
                    break;
                default:
                    fail('未知选项类型');
            }
            ok($rows);
        }

        /* =====================================================
           系统设置
           ===================================================== */
        case 'settings/get': {
            admin_required();
            $rows = db()->query('SELECT k,v FROM settings')->fetchAll();
            $out = [];
            foreach ($rows as $row) $out[$row['k']] = $row['v'];
            $out['admin_invite'] = setting_get('admin_invite', '');
            ok($out);
        }

        case 'settings/save': {
            admin_required();
            $b = body();
            $allow = ['shop_name', 'shop_slogan', 'before_label', 'after_label', 'contact_phone',
                      'contact_wechat', 'pay_qr', 'api_base', 'app_version', 'ipa_file', 'ipa_size',
                      'install_note', 'notice', 'sms_enabled', 'sms_default', 'sms_debug_code',
                      'recharge_enabled', 'recharge_prefix', 'recharge_default_days', 'recharge_min', 'recharge_notice',
                      /* App 端设置项，与 IPA 的 AppSettings 一一对应 */
                      'wechat_qr', 'alipay_qr', 'pay_link', 'pay_note',
                      'step_template', 'app_features', 'home_layout', 'home_columns', 'home_limit', 'show_cover'];
            foreach ($allow as $k) {
                if (array_key_exists($k, $b)) setting_set($k, (string)$b[$k]);
            }
            ok(null, '设置已保存');
        }

        /* =====================================================
           短信
           ===================================================== */
        case 'sms/providers': {
            admin_required();
            $rows = db()->query('SELECT * FROM sms_providers ORDER BY sort ASC')->fetchAll();
            foreach ($rows as &$row) {
                $cfg = json_decode((string)$row['config'], true) ?: [];
                foreach ($cfg as $k => $v) {
                    if ($v !== '') $cfg[$k] = '******';
                }
                $row['config_masked'] = $cfg;
                $row['enabled'] = (int)$row['enabled'];
            }
            ok($rows);
        }

        case 'sms/provider-save': {
            admin_required();
            $code = inp_str('code');
            $row = sms_provider_row($code);
            if (!$row) fail('通道不存在');
            $b = body();

            if (array_key_exists('config', $b) && is_array($b['config'])) {
                $old = json_decode((string)$row['config'], true) ?: [];
                foreach ($b['config'] as $k => $v) {
                    if ($v === '******') continue;
                    $old[$k] = $v;
                }
                db()->prepare('UPDATE sms_providers SET config=? WHERE code=?')
                    ->execute([json_encode($old, JSON_UNESCAPED_UNICODE), $code]);
            }
            if (array_key_exists('sign', $b)) {
                db()->prepare('UPDATE sms_providers SET sign=? WHERE code=?')->execute([(string)$b['sign'], $code]);
            }
            if (array_key_exists('tpl_code', $b)) {
                db()->prepare('UPDATE sms_providers SET tpl_code=? WHERE code=?')->execute([(string)$b['tpl_code'], $code]);
            }
            if (array_key_exists('tpl_notice', $b)) {
                db()->prepare('UPDATE sms_providers SET tpl_notice=? WHERE code=?')->execute([(string)$b['tpl_notice'], $code]);
            }
            if (array_key_exists('enabled', $b)) {
                $on = (int)$b['enabled'];
                db()->prepare('UPDATE sms_providers SET enabled=? WHERE code=?')->execute([$on, $code]);
                if ($on === 1) setting_set('sms_default', $code);
                elseif (setting_get('sms_default', '') === $code) {
                    $n = db()->query('SELECT code FROM sms_providers WHERE enabled=1 ORDER BY sort LIMIT 1')->fetchColumn();
                    setting_set('sms_default', $n ?: '');
                }
            }
            ok(null, '已保存');
        }

        case 'sms/test': {
            admin_required();
            $code = inp_str('code');
            $phone = inp_str('phone');
            if (!phone_ok($phone)) fail('请填写正确的手机号');
            $row = sms_provider_row($code);
            if (!$row) fail('通道不存在');
            $cfg = json_decode((string)$row['config'], true) ?: [];
            $tpl = (string)($row['tpl_code'] ?? '');
            $res = sms_dispatch($code, $cfg, $phone, $tpl, ['code' => '123456'], (string)($row['sign'] ?? ''));
            db()->prepare('INSERT INTO sms_logs(provider,phone,template,content,status,resp,created_at) VALUES(?,?,?,?,?,?,?)')
                ->execute([$row['name'], $phone, $tpl, '测试发送', $res['ok'] ? '成功' : '失败', mb_substr((string)($res['raw'] ?? ''), 0, 800), now()]);
            if (!$res['ok']) fail('发送失败：' . ($res['msg'] ?? '未知错误'));
            ok(['raw' => $res['raw'] ?? ''], '测试短信已发送');
        }

        case 'sms/logs': {
            admin_required();
            [$page, $size, $offset] = page_params();
            $total = (int)db()->query('SELECT COUNT(*) FROM sms_logs')->fetchColumn();
            $rows = db()->query("SELECT * FROM sms_logs ORDER BY id DESC LIMIT $size OFFSET $offset")->fetchAll();
            ok(['rows' => $rows, 'total' => $total]);
        }

        /* =====================================================
           文件上传
           ===================================================== */
        case 'upload': {
            admin_required();
            if (empty($_FILES['file'])) fail('没有收到文件');
            $f = $_FILES['file'];
            if ($f['error'] !== UPLOAD_ERR_OK) fail('上传失败，错误码 ' . $f['error']);
            if ($f['size'] > 12 * 1024 * 1024) fail('图片不能超过 12MB');
            $info = @getimagesize($f['tmp_name']);
            if (!$info) fail('只能上传图片文件');
            $ext = image_type_to_extension($info[2], false) ?: 'jpg';
            if (!in_array($ext, ['jpeg', 'jpg', 'png', 'gif', 'webp'], true)) $ext = 'jpg';
            $sub = 'uploads/' . date('Ym');
            $dir = dirname(__DIR__) . '/' . $sub;
            if (!is_dir($dir)) @mkdir($dir, 0755, true);
            $name = date('dHis') . '-' . bin2hex(random_bytes(4)) . '.' . $ext;
            $path = $dir . '/' . $name;
            if (!move_uploaded_file($f['tmp_name'], $path)) fail('保存文件失败，请检查目录权限');
            @chmod($path, 0644);
            ok(['url' => '/' . $sub . '/' . $name], '上传成功');
        }

        /* =====================================================
           App 端数据同步（客户 / 进度）
           ===================================================== */
        case 'member/customers': {
            $m = member_required();
            $st = db()->prepare('SELECT id,name,phone,stage,progress,quoted,note,created_at FROM customers WHERE member_id=? ORDER BY id DESC LIMIT 200');
            $st->execute([$m['id']]);
            ok($st->fetchAll());
        }

        default:
            fail('接口不存在：' . $r, 404);
    }
} catch (Throwable $e) {
    fail('服务器错误：' . $e->getMessage(), 500);
}
