<?php
declare(strict_types=1);

function bearer(): string
{
    $h = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!$h) {
        $h = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    }
    if (!$h && function_exists('apache_request_headers')) {
        $hs = apache_request_headers();
        foreach ($hs as $k => $v) {
            if (strtolower($k) === 'authorization') { $h = $v; break; }
        }
    }
    if (preg_match('/Bearer\s+(.+)/i', (string)$h, $m)) return trim($m[1]);
    return '';
}

/* ---------------- 后台管理员 ---------------- */

function admin_issue(int $id): string
{
    $t = token_new();
    $exp = date('Y-m-d H:i:s', time() + 86400 * 14);
    db()->prepare('INSERT INTO admin_tokens(token,admin_id,expire_at,created_at) VALUES(?,?,?,?)')
        ->execute([$t, $id, $exp, now()]);
    db()->prepare('DELETE FROM admin_tokens WHERE expire_at < ?')->execute([now()]);
    return $t;
}

function admin_current(): ?array
{
    $t = bearer();
    if ($t === '') return null;
    $st = db()->prepare('SELECT a.* FROM admin_tokens t JOIN admins a ON a.id=t.admin_id WHERE t.token=? AND t.expire_at>?');
    $st->execute([$t, now()]);
    $r = $st->fetch();
    return $r ?: null;
}

function admin_required(): array
{
    $a = admin_current();
    if (!$a) fail('登录已失效，请重新登录', 401);
    return $a;
}

function admin_out(array $a): array
{
    return [
        'id' => (int)$a['id'],
        'email' => $a['email'],
        'phone' => $a['phone'],
        'name' => $a['name'] ?: ($a['email'] ?: '管理员'),
        'role' => $a['role'],
        'status' => $a['status'] ?? '正常',
        'note' => $a['note'] ?? '',
        'tenant_id' => (int)($a['tenant_id'] ?? 0),
        'perm' => function_exists('perm_out') ? perm_out($a) : null,
    ];
}

/* ---------------- 会员（App 端） ---------------- */

function member_issue(int $id): string
{
    $t = token_new();
    $exp = date('Y-m-d H:i:s', time() + 86400 * 90);
    db()->prepare('INSERT INTO member_tokens(token,member_id,expire_at,created_at) VALUES(?,?,?,?)')
        ->execute([$t, $id, $exp, now()]);
    db()->prepare('DELETE FROM member_tokens WHERE expire_at < ?')->execute([now()]);
    return $t;
}

function member_current(): ?array
{
    $t = bearer();
    if ($t === '') return null;
    $st = db()->prepare('SELECT m.* FROM member_tokens t JOIN members m ON m.id=t.member_id WHERE t.token=? AND t.expire_at>?');
    $st->execute([$t, now()]);
    $r = $st->fetch();
    return $r ?: null;
}

function member_required(): array
{
    $m = member_current();
    if (!$m) fail('请先登录', 401);
    return $m;
}

function member_out(array $m): array
{
    $pkg = null;
    if (!empty($m['package_id'])) {
        $st = db()->prepare('SELECT id,name,price,days,items,`desc`,badge FROM packages WHERE id=?');
        $st->execute([(int)$m['package_id']]);
        $pkg = $st->fetch() ?: null;
    }
    return [
        'id' => (int)$m['id'],
        'name' => $m['name'],
        'phone' => $m['phone'],
        'email' => $m['email'],
        'level' => $m['level'],
        'status' => $m['status'],
        'points' => (int)$m['points'],
        'balance' => round((float)($m['balance'] ?? 0), 2),
        'total_recharge' => round((float)($m['total_recharge'] ?? 0), 2),
        'total_spent' => round((float)($m['total_spent'] ?? 0), 2),
        'total_points' => (int)($m['total_points'] ?? 0),
        'expire_at' => $m['expire_at'],
        'package' => $pkg,
        'created_at' => $m['created_at'],
    ];
}
