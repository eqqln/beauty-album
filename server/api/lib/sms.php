<?php
/**
 * 短信通道：多家厂商统一封装
 * 每个通道实现 send(cfg, phone, tplId, vars, sign) => ['ok'=>bool,'msg'=>string,'raw'=>string]
 */
declare(strict_types=1);

function http_req(string $url, array $opt = []): array
{
    $ch = curl_init($url);
    $headers = $opt['headers'] ?? [];
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 20,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_SSL_VERIFYHOST => 0,
        CURLOPT_HTTPHEADER => $headers,
    ]);
    if (isset($opt['body'])) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, $opt['body']);
        if (!isset($opt['method'])) curl_setopt($ch, CURLOPT_POST, true);
    }
    if (!empty($opt['method'])) {
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $opt['method']);
    }
    if (!empty($opt['basic'])) {
        curl_setopt($ch, CURLOPT_USERPWD, $opt['basic']);
    }
    $resp = curl_exec($ch);
    $err = curl_error($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($resp === false) {
        return ['code' => 0, 'body' => $err];
    }
    return ['code' => $code, 'body' => (string)$resp];
}

/* ============ 阿里云 ============ */
function sms_aliyun(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $ak = $cfg['access_key_id'] ?? '';
    $sk = $cfg['access_key_secret'] ?? '';
    if (!$ak || !$sk) return ['ok' => false, 'msg' => '未配置 AccessKey'];
    $params = [
        'AccessKeyId' => $ak,
        'Action' => 'SendSms',
        'Format' => 'JSON',
        'PhoneNumbers' => $phone,
        'RegionId' => $cfg['region'] ?? 'cn-hangzhou',
        'SignName' => $sign,
        'SignatureMethod' => 'HMAC-SHA1',
        'SignatureNonce' => bin2hex(random_bytes(8)),
        'SignatureVersion' => '1.0',
        'TemplateCode' => $tpl,
        'TemplateParam' => json_encode($vars, JSON_UNESCAPED_UNICODE),
        'Timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
        'Version' => '2017-05-25',
    ];
    ksort($params);
    $q = [];
    foreach ($params as $k => $v) {
        $q[] = rawurlencode($k) . '=' . rawurlencode((string)$v);
    }
    $qs = implode('&', $q);
    $sts = 'POST&' . rawurlencode('/') . '&' . rawurlencode($qs);
    $sig = base64_encode(hash_hmac('sha1', $sts, $sk . '&', true));
    $url = 'https://dysmsapi.aliyuncs.com/?Signature=' . rawurlencode($sig) . '&' . $qs;
    $r = http_req($url, ['method' => 'POST']);
    $j = json_decode($r['body'], true);
    $ok = isset($j['Code']) && $j['Code'] === 'OK';
    return ['ok' => $ok, 'msg' => $j['Message'] ?? ('HTTP ' . $r['code']), 'raw' => $r['body']];
}

/* ============ 腾讯云 ============ */
function sms_tencent(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $sid = $cfg['secret_id'] ?? '';
    $skey = $cfg['secret_key'] ?? '';
    $appid = $cfg['sdk_app_id'] ?? '';
    if (!$sid || !$skey || !$appid) return ['ok' => false, 'msg' => '未配置 SecretId/SecretKey/SdkAppId'];
    $host = 'sms.tencentcloudapi.com';
    $service = 'sms';
    $action = 'SendSms';
    $version = '2021-01-11';
    $region = $cfg['region'] ?? 'ap-guangzhou';
    $payload = json_encode([
        'PhoneNumberSet' => ['+86' . $phone],
        'SmsSdkAppId' => (string)$appid,
        'SignName' => $sign,
        'TemplateId' => (string)$tpl,
        'TemplateParamSet' => array_values(array_map('strval', $vars)),
    ], JSON_UNESCAPED_UNICODE);

    $ts = time();
    $date = gmdate('Y-m-d', $ts);
    $ct = 'application/json; charset=utf-8';
    $canonical = "POST\n/\n\ncontent-type:$ct\nhost:$host\n";
    $scope = $date . '/' . $service . '/tc3_request';
    $toSign = "TC3-HMAC-SHA256\n$ts\n$scope\n" . hash('sha256', $canonical);
    $kDate = hash_hmac('sha256', $date, 'TC3' . $skey, true);
    $kSvc = hash_hmac('sha256', $service, $kDate, true);
    $kSign = hash_hmac('sha256', 'tc3_request', $kSvc, true);
    $sig = hash_hmac('sha256', $toSign, $kSign);
    $auth = "TC3-HMAC-SHA256 Credential=$sid/$scope, SignedHeaders=content-type;host, Signature=$sig";

    $r = http_req('https://' . $host, [
        'headers' => [
            'Authorization: ' . $auth,
            'Content-Type: ' . $ct,
            'Host: ' . $host,
            'X-TC-Action: ' . $action,
            'X-TC-Timestamp: ' . $ts,
            'X-TC-Version: ' . $version,
            'X-TC-Region: ' . $region,
        ],
        'body' => $payload,
        'method' => 'POST',
    ]);
    $j = json_decode($r['body'], true);
    $resp = $j['Response'] ?? [];
    $ok = isset($resp['SendStatusSet'][0]['Code']) && $resp['SendStatusSet'][0]['Code'] === 'Ok';
    return ['ok' => $ok, 'msg' => $resp['Error']['Message'] ?? ($resp['SendStatusSet'][0]['Message'] ?? 'HTTP ' . $r['code']), 'raw' => $r['body']];
}

/* ============ 华为云 ============ */
function sms_huawei(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $key = $cfg['app_key'] ?? '';
    $secret = $cfg['app_secret'] ?? '';
    if (!$key || !$secret) return ['ok' => false, 'msg' => '未配置 AppKey/AppSecret'];
    $endpoint = rtrim($cfg['endpoint'] ?? 'https://smsapi.cn-north-4.myhuaweicloud.com', '/');
    $nonce = bin2hex(random_bytes(16));
    $created = gmdate('Y-m-d\TH:i:s\Z');
    $passwd = base64_encode(hash('sha256', $nonce . $created . $secret, true));
    $wsse = sprintf(
        'UsernameToken Username="%s",PasswordDigest="%s",Nonce="%s",Created="%s"',
        $key, $passwd, $nonce, $created
    );
    $payload = json_encode([
        'from' => $sign,
        'to' => [$phone],
        'templateId' => $tpl,
        'templateParas' => array_values(array_map('strval', $vars)),
    ], JSON_UNESCAPED_UNICODE);
    $r = http_req($endpoint . '/sms/batchSendSms/v1', [
        'headers' => [
            'Content-Type: application/json;charset=UTF-8',
            'Authorization: WSSE realm="SDP",profile="UsernameToken",type="Appkey"',
            'X-WSSE: ' . $wsse,
        ],
        'body' => $payload,
        'method' => 'POST',
    ]);
    $j = json_decode($r['body'], true);
    $ok = isset($j['code']) && (string)$j['code'] === '000000';
    return ['ok' => $ok, 'msg' => $j['description'] ?? ('HTTP ' . $r['code']), 'raw' => $r['body']];
}

/* ============ 云片 ============ */
function sms_yunpian(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $apikey = $cfg['apikey'] ?? '';
    if (!$apikey) return ['ok' => false, 'msg' => '未配置 apikey'];
    $tplVal = '';
    foreach ($vars as $k => $v) {
        $tplVal .= '#' . $k . '#=' . $v . '&';
    }
    $post = [
        'apikey' => $apikey,
        'mobile' => $phone,
        'tpl_id' => $tpl,
        'tpl_value' => rtrim($tplVal, '&'),
    ];
    $r = http_req('https://sms.yunpian.com/v2/sms/tpl_single_send.json', [
        'headers' => ['Accept: application/json;charset=utf-8', 'Content-Type: application/x-www-form-urlencoded;charset=utf-8'],
        'body' => http_build_query($post),
        'method' => 'POST',
    ]);
    $j = json_decode($r['body'], true);
    $ok = isset($j['code']) && (int)$j['code'] === 0;
    return ['ok' => $ok, 'msg' => $j['msg'] ?? ('HTTP ' . $r['code']), 'raw' => $r['body']];
}

/* ============ 容联云 ============ */
function sms_cloopen(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $sid = $cfg['account_sid'] ?? '';
    $token = $cfg['auth_token'] ?? '';
    $appid = $cfg['app_id'] ?? '';
    if (!$sid || !$token || !$appid) return ['ok' => false, 'msg' => '未配置账号信息'];
    $server = rtrim($cfg['server'] ?? 'https://app.cloopen.com', '/');
    $ts = date('YmdHis');
    $sig = strtoupper(md5($sid . $token . $ts));
    $url = $server . ':8883/2013-12-26/Accounts/' . $sid . '/SMS/TemplateSMS?sig=' . $sig;
    $payload = json_encode([
        'to' => $phone,
        'appId' => $appid,
        'templateId' => $tpl,
        'datas' => array_values(array_map('strval', $vars)),
    ], JSON_UNESCAPED_UNICODE);
    $r = http_req($url, [
        'headers' => ['Content-Type: application/json;charset=utf-8', 'Accept: application/json'],
        'body' => $payload,
        'method' => 'POST',
        'basic' => base64_encode($sid . ':' . $ts),
    ]);
    $j = json_decode($r['body'], true);
    $ok = isset($j['statusCode']) && (string)$j['statusCode'] === '000000';
    return ['ok' => $ok, 'msg' => $j['statusMsg'] ?? ('HTTP ' . $r['code']), 'raw' => $r['body']];
}

/* ============ 螺丝帽 ============ */
function sms_luosimao(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $key = $cfg['api_key'] ?? '';
    if (!$key) return ['ok' => false, 'msg' => '未配置 API Key'];
    $text = tpl_render($tpl, $vars);
    $r = http_req('https://sms-api.luosimao.com/v1/send.json', [
        'headers' => ['Content-Type: application/x-www-form-urlencoded'],
        'body' => http_build_query(['mobile' => $phone, 'message' => $text]),
        'method' => 'POST',
        'basic' => 'api:' . $key,
    ]);
    $j = json_decode($r['body'], true);
    $ok = isset($j['error']) && (int)$j['error'] === 0;
    return ['ok' => $ok, 'msg' => $j['msg'] ?? ('HTTP ' . $r['code']), 'raw' => $r['body']];
}

/* ============ 短信宝 ============ */
function sms_smsbao(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $user = $cfg['user'] ?? '';
    $pass = $cfg['pass'] ?? '';
    if (!$user || !$pass) return ['ok' => false, 'msg' => '未配置账号'];
    $text = tpl_render($tpl, $vars);
    $url = 'https://api.smsbao.com/sms?' . http_build_query([
        'u' => $user,
        'p' => md5($pass),
        'm' => $phone,
        'c' => $text,
    ]);
    $r = http_req($url);
    $body = trim($r['body']);
    $ok = $body === '0';
    $map = ['0' => '发送成功', '30' => '密码错误', '40' => '账号不存在', '41' => '余额不足', '43' => 'IP地址限制', '50' => '内容含敏感词', '51' => '手机号不正确'];
    return ['ok' => $ok, 'msg' => $map[$body] ?? $body, 'raw' => $r['body']];
}

/* ============ SUBMAIL ============ */
function sms_submail(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $appid = $cfg['appid'] ?? '';
    $appkey = $cfg['appkey'] ?? '';
    if (!$appid || !$appkey) return ['ok' => false, 'msg' => '未配置 appid/appkey'];
    $post = [
        'appid' => $appid,
        'signature' => $appkey,
        'to' => $phone,
        'project' => $cfg['project'] ?? $tpl,
        'vars' => json_encode($vars, JSON_UNESCAPED_UNICODE),
    ];
    $r = http_req('https://api.mysubmail.com/message/xsend.json', [
        'headers' => ['Content-Type: application/x-www-form-urlencoded'],
        'body' => http_build_query($post),
        'method' => 'POST',
    ]);
    $j = json_decode($r['body'], true);
    $ok = isset($j['status']) && (string)$j['status'] === 'success';
    return ['ok' => $ok, 'msg' => $j['msg'] ?? ('HTTP ' . $r['code']), 'raw' => $r['body']];
}

/* ============ SendCloud 邮件 ============ */
function sms_sendcloud(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $user = $cfg['api_user'] ?? '';
    $key = $cfg['api_key'] ?? '';
    if (!$user || !$key) return ['ok' => false, 'msg' => '未配置 api_user/api_key'];
    $to = filter_var($phone, FILTER_VALIDATE_EMAIL) ? $phone : '';
    if (!$to) return ['ok' => false, 'msg' => 'SendCloud 为邮件通道，需要传入邮箱地址'];
    $post = [
        'apiUser' => $user,
        'apiKey' => $key,
        'from' => $cfg['from'] ?? '',
        'fromName' => $cfg['from_name'] ?? '美颜相册',
        'to' => $to,
        'subject' => '美颜相册通知',
        'html' => tpl_render($tpl, $vars),
    ];
    $r = http_req('https://api.sendcloud.net/apiv2/mail/send', [
        'body' => http_build_query($post),
        'method' => 'POST',
    ]);
    $j = json_decode($r['body'], true);
    $ok = isset($j['result']) && $j['result'] === true;
    return ['ok' => $ok, 'msg' => $j['message'] ?? ('HTTP ' . $r['code']), 'raw' => $r['body']];
}

/* ============ 自定义 HTTP ============ */
function sms_custom(array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    $url = $cfg['url'] ?? '';
    if (!$url) return ['ok' => false, 'msg' => '未配置接口地址'];
    $map = array_merge($vars, ['phone' => $phone, 'sign' => $sign, 'template' => $tpl]);
    $bodyTpl = $cfg['body'] ?? '';
    $body = '';
    if ($bodyTpl !== '') {
        $body = tpl_render($bodyTpl, $map);
    } else {
        $body = http_build_query($map);
    }
    $headers = ['Content-Type: application/json'];
    $rawHeaders = trim((string)($cfg['headers'] ?? ''));
    if ($rawHeaders !== '') {
        $headers = array_values(array_filter(array_map('trim', explode("\n", $rawHeaders))));
    }
    $r = http_req($url, [
        'headers' => $headers,
        'body' => $body,
        'method' => strtoupper($cfg['method'] ?? 'POST'),
    ]);
    $key = $cfg['success_key'] ?? '';
    $val = $cfg['success_value'] ?? '';
    $ok = false;
    if ($key !== '') {
        $j = json_decode($r['body'], true);
        if (is_array($j)) {
            $cur = $j;
            foreach (explode('.', $key) as $seg) {
                $cur = is_array($cur) && array_key_exists($seg, $cur) ? $cur[$seg] : null;
            }
            $ok = (string)$cur === (string)$val;
        }
    } else {
        $ok = $r['code'] >= 200 && $r['code'] < 300;
    }
    return ['ok' => $ok, 'msg' => $ok ? '成功' : ('HTTP ' . $r['code']), 'raw' => $r['body']];
}

/* ============ 调度 ============ */

function sms_dispatch(string $code, array $cfg, string $phone, string $tpl, array $vars, string $sign): array
{
    switch ($code) {
        case 'aliyun':   return sms_aliyun($cfg, $phone, $tpl, $vars, $sign);
        case 'tencent':  return sms_tencent($cfg, $phone, $tpl, $vars, $sign);
        case 'huawei':   return sms_huawei($cfg, $phone, $tpl, $vars, $sign);
        case 'yunpian':  return sms_yunpian($cfg, $phone, $tpl, $vars, $sign);
        case 'cloopen':  return sms_cloopen($cfg, $phone, $tpl, $vars, $sign);
        case 'luosimao': return sms_luosimao($cfg, $phone, $tpl, $vars, $sign);
        case 'smsbao':   return sms_smsbao($cfg, $phone, $tpl, $vars, $sign);
        case 'submail':  return sms_submail($cfg, $phone, $tpl, $vars, $sign);
        case 'sendcloud':return sms_sendcloud($cfg, $phone, $tpl, $vars, $sign);
        case 'custom':   return sms_custom($cfg, $phone, $tpl, $vars, $sign);
        default:         return ['ok' => false, 'msg' => '未知通道：' . $code];
    }
}

function setting_get(string $k, string $def = ''): string
{
    $st = db()->prepare('SELECT v FROM settings WHERE k=?');
    $st->execute([$k]);
    $r = $st->fetchColumn();
    return $r === false ? $def : (string)$r;
}

function setting_set(string $k, string $v): void
{
    $st = db()->prepare('INSERT INTO settings(k,v) VALUES(?,?) ON DUPLICATE KEY UPDATE v=VALUES(v)');
    $st->execute([$k, $v]);
}

function sms_provider_row(string $code): ?array
{
    $st = db()->prepare('SELECT * FROM sms_providers WHERE code=?');
    $st->execute([$code]);
    $r = $st->fetch();
    return $r ?: null;
}

function sms_active_provider(): ?array
{
    $code = setting_get('sms_default', '');
    if ($code !== '') {
        $r = sms_provider_row($code);
        if ($r && (int)$r['enabled'] === 1) return $r;
    }
    $r = db()->query('SELECT * FROM sms_providers WHERE enabled=1 ORDER BY sort LIMIT 1')->fetch();
    return $r ?: null;
}

/** 发送验证码：返回 [ok, msg, debugCode|null] */
function sms_send_code(string $phone, string $purpose = 'login'): array
{
    $code = rand_code(6);
    $expire = date('Y-m-d H:i:s', time() + 300);

    $p = sms_active_provider();
    $debug = setting_get('sms_debug_code', '1') === '1';

    if (!$p) {
        if (!$debug) return [false, '后台未启用任何短信通道，请联系管理员', null];
        db()->prepare('INSERT INTO sms_codes(phone,code,purpose,expire_at,used,created_at) VALUES(?,?,?,?,0,?)')
            ->execute([$phone, $code, $purpose, $expire, now()]);
        return [true, '未配置短信通道，验证码已生成（调试模式）', $code];
    }

    $cfg = json_decode((string)$p['config'], true) ?: [];
    $sign = (string)($p['sign'] ?? '');
    $tpl = $purpose === 'notice' ? (string)($p['tpl_notice'] ?? '') : (string)($p['tpl_code'] ?? '');
    if ($tpl === '') $tpl = (string)($p['tpl_code'] ?? '');
    $vars = ['code' => $code];

    $res = sms_dispatch((string)$p['code'], $cfg, $phone, $tpl, $vars, $sign);

    db()->prepare('INSERT INTO sms_logs(provider,phone,template,content,status,resp,created_at) VALUES(?,?,?,?,?,?,?)')
        ->execute([$p['name'], $phone, $tpl, '验证码 ' . $code, $res['ok'] ? '成功' : '失败', mb_substr((string)($res['raw'] ?? ''), 0, 800), now()]);

    if ($res['ok']) {
        db()->prepare('INSERT INTO sms_codes(phone,code,purpose,expire_at,used,created_at) VALUES(?,?,?,?,0,?)')
            ->execute([$phone, $code, $purpose, $expire, now()]);
        return [true, '验证码已发送', null];
    }
    if ($debug) {
        db()->prepare('INSERT INTO sms_codes(phone,code,purpose,expire_at,used,created_at) VALUES(?,?,?,?,0,?)')
            ->execute([$phone, $code, $purpose, $expire, now()]);
        return [true, '短信通道发送失败（调试模式已放行）：' . ($res['msg'] ?? ''), $code];
    }
    return [false, '短信发送失败：' . ($res['msg'] ?? '未知错误'), null];
}

function sms_verify_code(string $phone, string $code, string $purpose = 'login'): bool
{
    $st = db()->prepare('SELECT id FROM sms_codes WHERE phone=? AND code=? AND purpose=? AND used=0 AND expire_at>? ORDER BY id DESC LIMIT 1');
    $st->execute([$phone, $code, $purpose, now()]);
    $id = $st->fetchColumn();
    if (!$id) return false;
    db()->prepare('UPDATE sms_codes SET used=1 WHERE id=?')->execute([$id]);
    return true;
}
