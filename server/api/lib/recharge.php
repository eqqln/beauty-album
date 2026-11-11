<?php
/**
 * 充值卡与会员钱包
 */
declare(strict_types=1);

/** 卡号：前缀 + 年月日 + 6 位随机（大写字母数字，去混淆字符） */
function card_no_new(string $prefix = 'MY'): string
{
    $p = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $prefix) ?: 'MY');
    if (strlen($p) > 6) $p = substr($p, 0, 6);
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $tail = '';
    for ($i = 0; $i < 6; $i++) $tail .= $chars[random_int(0, strlen($chars) - 1)];
    return $p . date('ymd') . $tail;
}

/** 卡密：12 位，去掉了 0/O/1/I 等易混字符 */
function card_secret_new(int $len = 12): string
{
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $s = '';
    for ($i = 0; $i < $len; $i++) $s .= $chars[random_int(0, strlen($chars) - 1)];
    return $s;
}

/** 用户输入卡号统一化：去空格、转大写 */
function card_no_norm(string $v): string
{
    return strtoupper(preg_replace('/[\s\-]/', '', $v) ?? '');
}

/** 卡密统一化 */
function card_secret_norm(string $v): string
{
    return strtoupper(preg_replace('/[\s\-]/', '', $v) ?? '');
}

/** 把已过有效期的卡批量标记（轻量，每次列表/充值前调用一次） */
function card_mark_expired(): void
{
    $today = date('Y-m-d');
    db()->prepare("UPDATE recharge_cards SET status='已过期' WHERE status='未使用' AND expire_at IS NOT NULL AND expire_at < ?")
        ->execute([$today]);
}

/** 写钱包流水 */
function wallet_log(int $memberId, string $kind, float $amount, int $points,
                    float $balanceAfter, int $pointsAfter,
                    ?string $ref = null, ?string $note = null): void
{
    /* 流水的板块跟着会员走，不跟着当前请求走 —— 后台给别的板块调账时也不会串 */
    $tid = 0;
    try {
        $st = db()->prepare('SELECT tenant_id FROM members WHERE id=?');
        $st->execute([$memberId]);
        $v = $st->fetchColumn();
        if ($v !== false && $v !== null) $tid = (int)$v;
    } catch (Throwable $e) {
    }
    db()->prepare('INSERT INTO wallet_logs(member_id,kind,amount,points,balance_after,points_after,ref,note,created_at,tenant_id) VALUES(?,?,?,?,?,?,?,?,?,?)')
        ->execute([$memberId, $kind, $amount, $points, $balanceAfter, $pointsAfter, $ref, $note, now(), $tid]);
}

/** 卡的面额合计（充值金额 + 赠送金额） */
function card_total(array $card): float
{
    return round((float)($card['amount'] ?? 0) + (float)($card['bonus'] ?? 0), 2);
}

/** 卡的面额描述，例如「¥100 + 赠 ¥20 · 200 积分」 */
function card_label(array $card): string
{
    $parts = [];
    $amt = (float)($card['amount'] ?? 0);
    $bonus = (float)($card['bonus'] ?? 0);
    if ($amt > 0) $parts[] = '¥' . rtrim(rtrim(number_format($amt, 2, '.', ''), '0'), '.');
    if ($bonus > 0) $parts[] = '赠 ¥' . rtrim(rtrim(number_format($bonus, 2, '.', ''), '0'), '.');
    if ((int)($card['points'] ?? 0) > 0) $parts[] = (int)$card['points'] . ' 积分';
    if ((int)($card['days'] ?? 0) > 0) $parts[] = (int)$card['days'] . ' 天';
    return $parts ? implode(' · ', $parts) : '空卡';
}
