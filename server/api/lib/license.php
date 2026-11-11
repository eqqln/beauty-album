<?php
/**
 * 软件激活码与设备授权
 *
 * 一张激活码 = 种类 + 授权时长（小时/天/周/月/季/年/永久）+ 设备数 + 随卡充值。
 * App 安装后首次打开必须兑换激活码；兑换后服务器签发 license_key 与设备同步凭证，
 * 之后所有资料全自动同步，不需要再手动登录店铺账号。
 * 后台可停用（作废）、删除、批量导出、充能续期。
 */
declare(strict_types=1);

/** 时长单位 → 分钟。月按 30 天、季按 90 天、年按 365 天 */
function license_units(): array
{
    return ['小时' => 60, '天' => 1440, '周' => 10080,
            '月' => 43200, '季' => 129600, '年' => 525600, '永久' => 0];
}

function license_minutes(int $value, string $unit): int
{
    $map = license_units();
    if (!array_key_exists($unit, $map)) fail('时长单位不支持：' . $unit);
    if ($unit === '永久') return 0;
    return max(1, min(100000, $value)) * $map[$unit];
}

/** 后台列表展示用 */
function license_duration_text(int $value, string $unit): string
{
    return $unit === '永久' ? '永久' : $value . $unit;
}

/** 把分钟数转成「几小时 / 几天」的短文案，App 也能用 */
function license_left_text(?string $expireAt): string
{
    if ($expireAt === null || $expireAt === '' || $expireAt === '0000-00-00 00:00:00') return '永久授权';
    $sec = strtotime((string)$expireAt) - time();
    if ($sec <= 0) return '已到期';
    if ($sec < 3600) return max(1, (int)ceil($sec / 60)) . ' 分钟';
    if ($sec < 86400) return (int)ceil($sec / 3600) . ' 小时';
    $d = (int)ceil($sec / 86400);
    if ($d >= 365) return round($d / 365, 1) . ' 年';
    if ($d >= 30) return round($d / 30, 1) . ' 个月';
    return $d . ' 天';
}

function license_seconds_left(?string $expireAt): ?int
{
    if ($expireAt === null || $expireAt === '' || $expireAt === '0000-00-00 00:00:00') return null;
    $t = strtotime((string)$expireAt);
    return $t === false ? null : max(0, $t - time());
}

/** 用户输入归一化：去空格横杠、转大写 */
function license_code_norm(string $v): string
{
    return strtoupper(preg_replace('/[\s\-_]/', '', $v) ?? '');
}

/** 生成激活码：前缀 + 12 位随机，去掉 0/O/1/I 等易混字符 */
function license_code_new(string $prefix = 'MYA'): string
{
    $p = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $prefix) ?: 'MYA');
    if (strlen($p) > 6) $p = substr($p, 0, 6);
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $s = '';
    for ($i = 0; $i < 12; $i++) $s .= $chars[random_int(0, strlen($chars) - 1)];
    return $p . $s;
}

/** 展示用：MYAXXXXXXXXXXXX → MYA-XXXX-XXXX-XXXX */
function license_code_pretty(string $code): string
{
    $c = license_code_norm($code);
    if (strlen($c) <= 3) return $c;
    return substr($c, 0, 3) . '-' . implode('-', str_split(substr($c, 3), 4));
}

function license_key_new(): string
{
    return bin2hex(random_bytes(24));
}

function license_setting(string $k, string $def = ''): string
{
    return setting_get($k, $def);
}

/** 激活 / 充能流水 */
function license_log(string $action, ?int $codeId, ?string $code, ?int $activationId,
                     ?string $deviceId, int $minutes = 0, float $amount = 0,
                     string $note = '', string $by = ''): void
{
    try {
        db()->prepare('INSERT INTO activation_logs(code_id,code,activation_id,device_id,action,minutes,amount,note,created_by,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)')
            ->execute([$codeId, $code, $activationId, $deviceId, $action, $minutes, $amount, $note, $by, now()]);
    } catch (Throwable $e) {
    }
}

/** 把过了有效期的码和设备批量标记 */
function license_mark_expired(): void
{
    $today = date('Y-m-d');
    db()->prepare("UPDATE activation_codes SET status='已过期' WHERE status IN ('未激活','已激活') AND expire_at IS NOT NULL AND expire_at < ?")
        ->execute([$today]);
    db()->prepare("UPDATE activations SET status='已过期' WHERE status='生效中' AND expire_at IS NOT NULL AND expire_at < ?")
        ->execute([now()]);
}

/** 用会员 token 找会员（member_tokens 与 auth.php 的口径一致） */
function license_member_by_token(string $token): ?array
{
    if ($token === '') return null;
    $st = db()->prepare('SELECT m.* FROM member_tokens t JOIN members m ON m.id=t.member_id WHERE t.token=? AND t.expire_at>? LIMIT 1');
    $st->execute([$token, now()]);
    $r = $st->fetch();
    return $r ?: null;
}

/**
 * 随卡充值：金额、赠送、积分一次入账到会员钱包。
 * 同一个设备凭证只允许领一次，重复调用直接返回已领结果。
 */
function license_wallet_credit(int $activationId, array $code, ?array $member): array
{
    $amount = round((float)($code['amount'] ?? 0) + (float)($code['bonus'] ?? 0), 2);
    $points = (int)($code['points'] ?? 0);
    $empty  = ['claimed' => false, 'amount' => 0.0, 'points' => 0, 'balance' => 0.0, 'reason' => ''];

    $st = db()->prepare("SELECT id FROM activation_logs WHERE activation_id=? AND action='充值' LIMIT 1");
    $st->execute([$activationId]);
    if ($st->fetchColumn()) {
        $empty['reason'] = '已领取';
        return $empty;
    }
    if ($amount <= 0 && $points <= 0) {
        $empty['reason'] = '此卡不含充值';
        return $empty;
    }
    if (!$member) {
        $empty['reason'] = '未登录会员，可在「我的」登录后领取';
        return $empty;
    }

    $db = db();
    $db->beginTransaction();
    try {
        $st = $db->prepare('SELECT * FROM members WHERE id=? FOR UPDATE');
        $st->execute([(int)$member['id']]);
        $m = $st->fetch();
        if (!$m) throw new RuntimeException('会员账号不存在');

        $st = $db->prepare("SELECT id FROM activation_logs WHERE activation_id=? AND action='充值' LIMIT 1");
        $st->execute([$activationId]);
        if ($st->fetchColumn()) throw new RuntimeException('已领取');

        $balance = round((float)$m['balance'] + $amount, 2);
        $newPts  = (int)$m['points'] + $points;
        $db->prepare('UPDATE members SET balance=?, points=?, total_recharge=total_recharge+?, total_points=total_points+?, updated_at=? WHERE id=?')
            ->execute([$balance, $newPts, $amount, $points, now(), (int)$m['id']]);
        wallet_log((int)$m['id'], '充值', $amount, $points, $balance, $newPts,
                   (string)($code['code'] ?? ''), '激活码 ' . license_code_pretty((string)($code['code'] ?? '')) . ' 随卡充值');
        license_log('充值', (int)($code['id'] ?? 0), (string)($code['code'] ?? ''),
                    $activationId, null, 0, $amount, '余额 +' . $amount . '，积分 +' . $points, (string)($m['phone'] ?? ''));

        $db->prepare('UPDATE activations SET member_id=?, member_phone=? WHERE id=?')
            ->execute([(int)$m['id'], (string)($m['phone'] ?? ''), $activationId]);
        $db->commit();
        return ['claimed' => true, 'amount' => $amount, 'points' => $points, 'balance' => $balance, 'reason' => ''];
    } catch (Throwable $e) {
        if ($db->inTransaction()) $db->rollBack();
        $empty['reason'] = $e->getMessage();
        return $empty;
    }
}

function license_code_out(array $c): array
{
    $used    = (int)($c['used_count'] ?? 0);
    $max     = (int)($c['max_devices'] ?? 1);
    $value   = (int)($c['duration_value'] ?? 1);
    $unit    = (string)($c['duration_unit'] ?? '年');
    $minutes = (int)($c['duration_minutes'] ?? 0);
    return [
        'id'               => (int)$c['id'],
        'code'             => $c['code'],
        'code_pretty'      => license_code_pretty((string)$c['code']),
        'batch'            => $c['batch'] ?? '',
        'kind'             => $c['kind'] ?? '正式码',
        'duration_value'   => $value,
        'duration_unit'    => $unit,
        'duration_minutes' => $minutes,
        'duration_text'    => license_duration_text($value, $unit),
        'permanent'        => $minutes <= 0,
        'max_devices'      => $max,
        'used_count'       => $used,
        'remain'           => max(0, $max - $used),
        'amount'           => (float)($c['amount'] ?? 0),
        'bonus'            => (float)($c['bonus'] ?? 0),
        'points'           => (int)($c['points'] ?? 0),
        'start_at'         => $c['start_at'] ?: '',
        'expire_at'        => $c['expire_at'] ?: '',
        'status'           => $c['status'],
        'note'             => $c['note'] ?? '',
        'created_by'       => $c['created_by'] ?? '',
        'created_at'       => $c['created_at'],
    ];
}

function license_device_out(array $a): array
{
    return [
        'id'           => (int)$a['id'],
        'code_id'      => (int)$a['code_id'],
        'code_pretty'  => license_code_pretty((string)$a['code']),
        'device_id'    => $a['device_id'],
        'device_short' => substr((string)$a['device_id'], -8),
        'device_name'  => $a['device_name'] ?? '',
        'platform'     => $a['platform'] ?? '',
        'app_version'  => $a['app_version'] ?? '',
        'member_id'    => $a['member_id'] ? (int)$a['member_id'] : null,
        'member_phone' => $a['member_phone'] ?? '',
        'activated_at' => $a['activated_at'],
        'expire_at'    => $a['expire_at'] ?: '',
        'permanent'    => $a['expire_at'] === null,
        'left_text'    => license_left_text($a['expire_at']),
        'seconds_left' => license_seconds_left($a['expire_at']),
        'last_seen_at' => $a['last_seen_at'] ?: '',
        'status'       => $a['status'],
        'note'         => $a['note'] ?? '',
    ];
}

/** 计算授权到期：0 分钟 = 永久；已有未到期授权则顺延（充能语义） */
function license_expire_from(int $minutes, ?string $oldExpire): ?string
{
    if ($minutes <= 0) return null;
    $base = time();
    if ($oldExpire && strtotime($oldExpire) > $base) $base = strtotime($oldExpire);
    return date('Y-m-d H:i:s', $base + $minutes * 60);
}

/**
 * 给设备签发同步凭证：写进 device_tokens，只有 sync/* 接口认它。
 * 后台管理接口仍只认 admin_tokens，设备凭证进不了后台。
 */
function license_issue_sync_token(int $activationId, string $deviceId): string
{
    $t   = token_new();
    $exp = date('Y-m-d H:i:s', time() + 86400 * 3650);
    $db  = db();
    $db->prepare('INSERT INTO device_tokens(token,activation_id,device_id,expire_at,created_at) VALUES(?,?,?,?,?)')
       ->execute([$t, $activationId, $deviceId, $exp, now()]);
    $db->prepare('DELETE FROM device_tokens WHERE device_id=? AND token<>?')->execute([$deviceId, $t]);
    $db->prepare('DELETE FROM device_tokens WHERE expire_at < ?')->execute([now()]);
    return $t;
}

/** 设备同步凭证是否有效（激活过、未停用、未过期） */
function device_token_valid(): bool
{
    $t = bearer();
    if ($t === '') return false;
    $st = db()->prepare("SELECT a.id FROM device_tokens d JOIN activations a ON a.id=d.activation_id
                         WHERE d.token=? AND d.expire_at>? AND a.status='生效中'
                           AND (a.expire_at IS NULL OR a.expire_at>?) LIMIT 1");
    $st->execute([$t, now(), now()]);
    return (bool)$st->fetchColumn();
}

/** sync/* 的守卫：管理员 token 或有效设备凭证，二选一 */
function sync_authorize(): void
{
    $a = admin_current();
    if ($a) {
        perm_check_cap($a, 'sync');
        return;
    }
    if (device_token_valid()) return;
    fail('软件未激活或授权已失效，请重新激活', 401);
}

/** 上传的守卫：管理员（有 write 能力）或已激活设备 */
function upload_authorize(): void
{
    $a = admin_current();
    if ($a) {
        perm_check_cap($a, 'write');
        return;
    }
    if (device_token_valid()) return;
    fail('软件未激活或授权已失效，请重新激活', 401);
}

/**
 * 兑换激活码。参数：code / device_id / device_name / platform / app_version / member_token
 * 返回 App 需要持久化的授权信息 + 自动同步凭证。
 */
function license_redeem(array $in): array
{
    $codeRaw    = license_code_norm((string)($in['code'] ?? ''));
    $deviceId   = trim((string)($in['device_id'] ?? ''));
    $deviceName = trim((string)($in['device_name'] ?? ''));
    $platform   = trim((string)($in['platform'] ?? ''));
    $appVersion = trim((string)($in['app_version'] ?? ''));
    $memberTok  = trim((string)($in['member_token'] ?? ''));

    if ($codeRaw === '') fail('请输入激活码');
    if ($deviceId === '' || strlen($deviceId) > 80) fail('设备编号异常，请重装 App 后重试');

    license_mark_expired();
    $db    = db();
    $now   = now();
    $today = date('Y-m-d');

    $db->beginTransaction();
    try {
        $st = $db->prepare('SELECT * FROM activation_codes WHERE code=? FOR UPDATE');
        $st->execute([$codeRaw]);
        $c = $st->fetch();
        if (!$c) throw new RuntimeException('激活码不存在，请核对后重试');
        if ($c['status'] === '已停用') throw new RuntimeException('这张激活码已作废，请联系门店');
        if ($c['status'] === '已过期') throw new RuntimeException('这张激活码已过期，请联系门店换发');
        if (!empty($c['start_at']) && $c['start_at'] > $today) {
            throw new RuntimeException('这张激活码 ' . $c['start_at'] . ' 起才可用');
        }
        if (!empty($c['expire_at']) && $c['expire_at'] < $today) {
            throw new RuntimeException('这张激活码已于 ' . $c['expire_at'] . ' 过期');
        }

        $max     = max(1, (int)$c['max_devices']);
        $minutes = (int)($c['duration_minutes'] ?? 0);

        $st = $db->prepare('SELECT * FROM activations WHERE code_id=? AND device_id=? LIMIT 1');
        $st->execute([(int)$c['id'], $deviceId]);
        $same = $st->fetch();
        if ($same && $same['status'] === '已停用') {
            throw new RuntimeException('这台设备已被停用，请联系门店');
        }

        // 该设备旧的生效授权：作为顺延基准，然后解绑，避免一台设备挂多张有效凭证
        $st = $db->prepare("SELECT * FROM activations WHERE device_id=? AND status IN ('生效中','已过期') AND id<>? ORDER BY id DESC");
        $st->execute([$deviceId, $same ? (int)$same['id'] : 0]);
        $old   = $st->fetchAll();
        $carry = null;
        foreach ($old as $o) {
            if ($o['expire_at'] === null) $carry = 'permanent';
            elseif ($carry !== 'permanent' && $o['expire_at'] &&
                    (!$carry || strtotime($o['expire_at']) > strtotime($carry))) $carry = $o['expire_at'];
            $db->prepare("UPDATE activations SET status='已解绑', note=? WHERE id=?")
                ->execute(['换用新激活码 ' . license_code_pretty($codeRaw), (int)$o['id']]);
            license_log('解绑', (int)$o['code_id'], (string)$o['code'], (int)$o['id'],
                        $deviceId, 0, 0, '换用新激活码', 'App');
        }

        $expire = $minutes <= 0 ? null : license_expire_from($minutes, $carry === 'permanent' ? null : $carry);
        $key    = license_key_new();

        if ($same) {
            $actId = (int)$same['id'];
            $db->prepare('UPDATE activations SET license_key=?, device_name=?, platform=?, app_version=?, activated_at=?, expire_at=?, last_seen_at=?, status=?, member_id=?, member_phone=?, note=? WHERE id=?')
                ->execute([$key, $deviceName, $platform, $appVersion, $now, $expire, $now, '生效中',
                           $same['member_id'], $same['member_phone'], $same['note'], $actId]);
        } else {
            if ((int)$c['used_count'] >= $max) {
                throw new RuntimeException('这张激活码的 ' . $max . ' 台设备名额已用完，请联系门店');
            }
            $db->prepare('INSERT INTO activations(code_id,code,device_id,device_name,platform,app_version,license_key,activated_at,expire_at,last_seen_at,status) VALUES(?,?,?,?,?,?,?,?,?,?,?)')
                ->execute([(int)$c['id'], $codeRaw, $deviceId, $deviceName, $platform, $appVersion,
                           $key, $now, $expire, $now, '生效中']);
            $actId = (int)$db->lastInsertId();
            $db->prepare("UPDATE activation_codes SET used_count=used_count+1, status='已激活' WHERE id=?")
                ->execute([(int)$c['id']]);
        }

        license_log('激活', (int)$c['id'], $codeRaw, $actId, $deviceId, $minutes, 0,
                    ($same ? '重新激活' : '首次激活') . ' · ' .
                    license_duration_text((int)$c['duration_value'], (string)$c['duration_unit']), 'App');
        $syncToken = license_issue_sync_token($actId, $deviceId);
        $db->commit();
    } catch (Throwable $e) {
        if ($db->inTransaction()) $db->rollBack();
        fail($e->getMessage());
    }

    // 充值放在事务外，钱包失败不影响激活本身
    $member = license_member_by_token($memberTok);
    $credit = license_wallet_credit($actId, [
        'id' => (int)$c['id'], 'code' => $codeRaw,
        'amount' => (float)$c['amount'], 'bonus' => (float)$c['bonus'], 'points' => (int)$c['points'],
    ], $member);

    return [
        'license_key'   => $key,
        'sync_token'    => $syncToken,
        'device_id'     => $deviceId,
        'code'          => license_code_pretty($codeRaw),
        'kind'          => (string)$c['kind'],
        'duration_text' => license_duration_text((int)$c['duration_value'], (string)$c['duration_unit']),
        'expire_at'     => $expire ?: '',
        'permanent'     => $expire === null,
        'left_text'     => license_left_text($expire),
        'seconds_left'  => license_seconds_left($expire),
        'grace_days'    => (int)license_setting('license_grace_days', '7'),
        'recharge'      => $credit,
        'notice'        => license_setting('license_notice', ''),
        'contact'       => license_setting('license_contact', '请联系门店获取激活码'),
        'shop_name'     => setting_get('shop_name', '美颜相册'),
    ];
}

/** 启动 / 回前台复核 */
function license_verify(array $in): array
{
    $deviceId = trim((string)($in['device_id'] ?? ''));
    $key      = trim((string)($in['license_key'] ?? ''));
    $appVer   = trim((string)($in['app_version'] ?? ''));
    if ($deviceId === '' || $key === '') fail('缺少授权信息，请重新激活', 403);

    license_mark_expired();
    $st = db()->prepare('SELECT * FROM activations WHERE device_id=? AND license_key=? LIMIT 1');
    $st->execute([$deviceId, $key]);
    $a = $st->fetch();
    if (!$a) fail('本机授权不存在，请重新输入激活码', 403);
    if ($a['status'] === '已停用') fail('这台设备已被门店停用，请联系门店', 403);
    if ($a['status'] === '已解绑') fail('本机授权已解绑，请重新激活', 403);
    if ($a['status'] === '已过期' || ($a['expire_at'] && strtotime($a['expire_at']) <= time())) {
        fail('软件授权已到期，请输入新的激活码充能续期', 403);
    }

    db()->prepare('UPDATE activations SET last_seen_at=?, app_version=? WHERE id=?')
        ->execute([now(), $appVer, (int)$a['id']]);

    // 同步凭证若丢失（清过缓存 / 换机恢复），这里补发一张
    $st = db()->prepare('SELECT token FROM device_tokens WHERE activation_id=? AND expire_at>? LIMIT 1');
    $st->execute([(int)$a['id'], now()]);
    $syncToken = (string)$st->fetchColumn();
    if ($syncToken === '') $syncToken = license_issue_sync_token((int)$a['id'], $deviceId);

    return [
        'active'       => true,
        'code'         => license_code_pretty((string)$a['code']),
        'expire_at'    => $a['expire_at'] ?: '',
        'permanent'    => $a['expire_at'] === null,
        'left_text'    => license_left_text($a['expire_at']),
        'seconds_left' => license_seconds_left($a['expire_at']),
        'sync_token'   => $syncToken,
        'grace_days'   => (int)license_setting('license_grace_days', '7'),
        'device_name'  => $a['device_name'] ?? '',
        'server_time'  => now(),
        'notice'       => license_setting('license_notice', ''),
        'contact'      => license_setting('license_contact', '请联系门店获取激活码'),
        'shop_name'    => setting_get('shop_name', '美颜相册'),
    ];
}

/** App 登录会员后补领随卡充值 */
function license_claim(array $in): array
{
    $key = trim((string)($in['license_key'] ?? ''));
    $tok = trim((string)($in['member_token'] ?? ''));
    $dev = trim((string)($in['device_id'] ?? ''));
    if ($key === '' || $dev === '') fail('缺少授权信息', 403);
    $member = license_member_by_token($tok);
    if (!$member) fail('请先在「我的」登录会员账号', 401);

    $st = db()->prepare('SELECT * FROM activations WHERE license_key=? AND device_id=? LIMIT 1');
    $st->execute([$key, $dev]);
    $a = $st->fetch();
    if (!$a) fail('本机授权不存在', 403);

    $st = db()->prepare('SELECT * FROM activation_codes WHERE id=? LIMIT 1');
    $st->execute([(int)$a['code_id']]);
    $c = $st->fetch();
    if (!$c) fail('激活码记录不存在', 404);

    $credit = license_wallet_credit((int)$a['id'], $c, $member);
    return [
        'credit'  => $credit,
        'balance' => $credit['balance'],
        'member'  => member_out(license_member_by_token($tok) ?: $member),
    ];
}

/** 公开配置：App 启动先读这个，决定要不要弹激活页 */
function license_config(): array
{
    return [
        'required'    => license_setting('license_enabled', '1') === '1',
        'notice'      => license_setting('license_notice', '本软件需激活后使用'),
        'contact'     => license_setting('license_contact', '请联系门店获取激活码'),
        'grace_days'  => (int)license_setting('license_grace_days', '7'),
        'server_time' => now(),
    ];
}
