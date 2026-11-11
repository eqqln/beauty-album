<?php
/**
 * 员工角色与权限
 *
 * 角色是预设，单个账号可以用 admins.perms 里的 JSON 做覆盖。
 * 权限分两层：
 *   1) modules —— 能看/能改哪些业务模块（对应 modules() 的 key）
 *   2) caps    —— 能进哪些特殊功能（员工管理 / 系统设置 / 备份 / 短信 / 充值卡 / 激活码 / 同步）
 */
declare(strict_types=1);

/** 全部业务模块 key（与 modules() 一一对应） */
function perm_modules_all(): array
{
    return ['packages', 'members', 'mentors', 'products', 'agents', 'orders', 'customers',
            'photos', 'compares', 'payments', 'subs', 'wallet', 'appointments', 'steps',
            'notes', 'claims'];
}

/** 角色预设 */
function perm_roles(): array
{
    $all = perm_modules_all();
    return [
        'owner' => [
            'label'   => '店主',
            'desc'    => '全部权限，含员工管理与系统设置',
            'modules' => $all,
            'caps'    => ['write' => true, 'staff' => true, 'settings' => true,
                          'backup' => true, 'sms' => true, 'recharge' => true,
                          'license' => true, 'sync' => true],
        ],
        'manager' => [
            'label'   => '店长',
            'desc'    => '除员工管理与系统设置外的全部业务',
            'modules' => $all,
            'caps'    => ['write' => true, 'staff' => false, 'settings' => false,
                          'backup' => true, 'sms' => false, 'recharge' => true,
                          'license' => false, 'sync' => true],
        ],
        'therapist' => [
            'label'   => '美容师',
            'desc'    => '客户、预约、护理步骤、笔记、照片、产品',
            'modules' => ['customers', 'appointments', 'steps', 'notes', 'claims',
                          'photos', 'compares', 'mentors', 'products'],
            'caps'    => ['write' => true, 'staff' => false, 'settings' => false,
                          'backup' => false, 'sms' => false, 'recharge' => false,
                          'license' => false, 'sync' => true],
        ],
        'frontdesk' => [
            'label'   => '前台',
            'desc'    => '客户、预约、收款、套餐与会员',
            'modules' => ['customers', 'appointments', 'payments', 'packages',
                          'members', 'subs', 'wallet'],
            'caps'    => ['write' => true, 'staff' => false, 'settings' => false,
                          'backup' => false, 'sms' => false, 'recharge' => true,
                          'license' => false, 'sync' => true],
        ],
        'viewer' => [
            'label'   => '只读',
            'desc'    => '只能查看，不能修改任何数据',
            'modules' => $all,
            'caps'    => ['write' => false, 'staff' => false, 'settings' => false,
                          'backup' => false, 'sms' => false, 'recharge' => false,
                          'license' => false, 'sync' => true],
        ],
    ];
}

/** 老数据里的 staff 归到店长，未知角色一律降级为只读 */
function perm_normalize_role(string $role): string
{
    $map = ['staff' => 'manager', 'admin' => 'owner', 'member' => 'viewer'];
    $role = strtolower(trim($role));
    if (isset($map[$role])) $role = $map[$role];
    return isset(perm_roles()[$role]) ? $role : 'viewer';
}

/**
 * 算出一个账号的最终权限。
 * 角色给基线，admins.perms 里的 JSON 可以再收窄或放宽。
 */
function perm_of(array $admin): array
{
    $roles = perm_roles();
    $role  = perm_normalize_role((string)($admin['role'] ?? 'viewer'));
    $base  = $roles[$role];

    $modules = $base['modules'];
    $caps    = $base['caps'];

    $raw = (string)($admin['perms'] ?? '');
    if ($raw !== '') {
        $ov = json_decode($raw, true);
        if (is_array($ov)) {
            if (isset($ov['modules']) && is_array($ov['modules'])) {
                $valid   = perm_modules_all();
                $modules = array_values(array_intersect(
                    array_map('strval', $ov['modules']), $valid
                ));
            }
            if (isset($ov['caps']) && is_array($ov['caps'])) {
                foreach ($caps as $k => $v) {
                    if (array_key_exists($k, $ov['caps'])) $caps[$k] = (bool)$ov['caps'][$k];
                }
            }
        }
    }

    return [
        'role'    => $role,
        'label'   => $roles[$role]['label'],
        'modules' => $modules,
        'caps'    => $caps,
    ];
}

/** 模块 + 读写校验 */
function perm_check_module(array $admin, string $module, bool $write): void
{
    $p = perm_of($admin);
    if (!in_array($module, $p['modules'], true)) {
        fail('当前账号没有「' . $module . '」的权限', 403);
    }
    if ($write && empty($p['caps']['write'])) {
        fail('当前账号是只读权限，不能修改', 403);
    }
}

/** 特殊能力校验 */
function perm_check_cap(array $admin, string $cap): void
{
    $p = perm_of($admin);
    if (empty($p['caps'][$cap])) {
        fail('当前账号没有这项操作权限', 403);
    }
}

/** 登录后返回给前端的权限包 */
function perm_out(array $admin): array
{
    $p = perm_of($admin);
    return [
        'role'    => $p['role'],
        'label'   => $p['label'],
        'modules' => $p['modules'],
        'caps'    => $p['caps'],
    ];
}
