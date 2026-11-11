<?php
declare(strict_types=1);

/* ---------------- 输出 ---------------- */

function ok($data = null, string $msg = 'ok'): void
{
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => true, 'msg' => $msg, 'data' => $data], JSON_UNESCAPED_UNICODE);
    exit;
}

function fail(string $msg, int $code = 400, $extra = null): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => false, 'msg' => $msg, 'data' => $extra], JSON_UNESCAPED_UNICODE);
    exit;
}

/* ---------------- 输入 ---------------- */

function body(): array
{
    static $b = null;
    if ($b !== null) return $b;
    $raw = file_get_contents('php://input');
    $j = json_decode($raw ?: '', true);
    $b = is_array($j) ? $j : [];
    if (!$b && $_POST) $b = $_POST;
    return $b;
}

function inp(string $key, $def = null)
{
    $b = body();
    if (array_key_exists($key, $b)) return $b[$key];
    if (array_key_exists($key, $_GET)) return $_GET[$key];
    return $def;
}

function inp_str(string $key, string $def = ''): string
{
    $v = inp($key, $def);
    if (is_array($v)) return $def;
    return trim((string)$v);
}

function inp_int(string $key, int $def = 0): int
{
    $v = inp($key, $def);
    return (int)$v;
}

function inp_float(string $key, float $def = 0): float
{
    $v = inp($key, $def);
    return (float)$v;
}

/* ---------------- 通用 ---------------- */

function now(): string
{
    return date('Y-m-d H:i:s');
}

function phone_ok(string $p): bool
{
    return (bool)preg_match('/^1[3-9]\d{9}$/', $p);
}

function rand_code(int $len = 6): string
{
    $s = '';
    for ($i = 0; $i < $len; $i++) $s .= random_int(0, 9);
    return $s;
}

function token_new(): string
{
    return bin2hex(random_bytes(24));
}

function client_ip(): string
{
    return $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '';
}

/** 只保留白名单字段 */
function pick(array $src, array $fields): array
{
    $out = [];
    foreach ($fields as $f) {
        if (array_key_exists($f, $src)) $out[$f] = $src[$f];
    }
    return $out;
}

/** 简单分页 */
function page_params(): array
{
    $page = max(1, inp_int('page', 1));
    $size = min(200, max(1, inp_int('size', 50)));
    return [$page, $size, ($page - 1) * $size];
}

/** 关键词搜索的 LIKE 值 */
function like(string $kw): string
{
    return '%' . str_replace(['%', '_'], ['\%', '\_'], $kw) . '%';
}

/** 写操作日志（可选） */
function slog(string $act, string $detail = ''): void
{
    // 保留扩展位：当前仅记录到 error_log，避免额外表开销
    if (getenv('MEIYAN_DEBUG')) {
        error_log('[meiyan] ' . $act . ' ' . $detail);
    }
}

/* ---------------- 短信模板占位 ---------------- */

function tpl_render(string $tpl, array $vars): string
{
    foreach ($vars as $k => $v) {
        $tpl = str_replace('${' . $k . '}', (string)$v, $tpl);
    }
    return $tpl;
}

/* ---------------- 服务器地址混淆 ----------------
 * 后台「系统设置 → 网址显示方式」可以在「加密 / 明文」之间切换。
 * 加密算法与 App 端 ServerURL.swift 必须完全一致：
 *   逐字节 XOR 固定密钥，再标准 Base64，去掉尾部 '='。
 * 注意：这是防止随手抄走域名的混淆，不是密码学意义上的加密。
 */

function url_codec_key(): string
{
    return 'MYA2026K';
}

function url_encode(string $plain): string
{
    if ($plain === '') return '';
    $k = url_codec_key();
    $n = strlen($k);
    $o = '';
    for ($i = 0, $len = strlen($plain); $i < $len; $i++) {
        $o .= chr(ord($plain[$i]) ^ ord($k[$i % $n]));
    }
    return rtrim(base64_encode($o), '=');
}

function url_decode(string $cipher): string
{
    if ($cipher === '') return '';
    $c = $cipher;
    $pad = strlen($c) % 4;
    if ($pad > 0) $c .= str_repeat('=', 4 - $pad);
    $raw = base64_decode($c, true);
    if ($raw === false) return '';
    $k = url_codec_key();
    $n = strlen($k);
    $o = '';
    for ($i = 0, $len = strlen($raw); $i < $len; $i++) {
        $o .= chr(ord($raw[$i]) ^ ord($k[$i % $n]));
    }
    return $o;
}

/** 后台开关：'encrypted' 只显示混淆串，'plain' 显示明文 */
function url_display_mode(): string
{
    $m = setting_get_global('url_display', 'encrypted');
    return $m === 'plain' ? 'plain' : 'encrypted';
}

/** 按当前开关决定对外给哪个形态 */
function url_public(string $plain): string
{
    if ($plain === '') return '';
    return url_display_mode() === 'plain' ? $plain : url_encode($plain);
}
