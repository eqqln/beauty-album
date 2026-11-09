<?php
/**
 * 安装包（IPA）与 OTA 清单
 */
declare(strict_types=1);

/** dl 目录 */
function ipa_dir(): string
{
    $dir = dirname(__DIR__, 2) . '/dl';
    if (!@is_dir($dir)) @mkdir($dir, 0755, true);
    return $dir;
}

/** 站点对外地址 */
function ipa_base_url(): string
{
    $b = trim(setting_get('api_base', ''));
    if ($b === '') $b = 'https://meiyan.shengka.net';
    return rtrim($b, '/');
}

/** 当前安装包状态 */
function ipa_current(): array
{
    $file = trim(setting_get('ipa_file', ''));
    if ($file === '') $file = 'BeautyAlbum.ipa';

    $path = ipa_dir() . '/' . $file;
    $exists = @is_file($path);
    $size = $exists ? (int)@filesize($path) : 0;
    $base = ipa_base_url();

    return [
        'file' => $file,
        'exists' => $exists,
        'size' => $size,
        'size_text' => backup_size_text($size),
        'mtime' => $exists ? date('Y-m-d H:i:s', (int)@filemtime($path)) : null,
        'app_version' => setting_get('app_version', '1.0.0'),
        'bundle_id' => 'com.meirong.beautyalbum',
        'download_url' => $base . '/dl/' . $file,
        'manifest_url' => $base . '/manifest.plist',
        'install_url' => 'itms-services://?action=download-manifest&url=' . $base . '/manifest.plist',
        'icon_small' => $base . '/dl/icon-57.png',
        'icon_large' => $base . '/dl/icon-512.png',
    ];
}

/** 按当前版本重新生成 manifest.plist */
function ipa_write_manifest(?string $version = null): bool
{
    $info = ipa_current();
    $ver = ($version !== null && trim($version) !== '') ? trim($version) : $info['app_version'];
    $title = setting_get('shop_name', '美颜相册');
    if ($title === '') $title = '美颜相册';
    $base = ipa_base_url();
    $file = $info['file'];

    $esc = function (string $s): string {
        return htmlspecialchars($s, ENT_QUOTES | ENT_XML1, 'UTF-8');
    };

    $xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n"
        . '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' . "\n"
        . '<plist version="1.0">' . "\n"
        . '<dict>' . "\n"
        . "  <key>items</key>\n"
        . "  <array>\n"
        . "    <dict>\n"
        . "      <key>assets</key>\n"
        . "      <array>\n"
        . "        <dict>\n"
        . "          <key>kind</key>\n"
        . "          <string>software-package</string>\n"
        . "          <key>url</key>\n"
        . '          <string>' . $esc($base . '/dl/' . $file) . "</string>\n"
        . "        </dict>\n"
        . "        <dict>\n"
        . "          <key>kind</key>\n"
        . "          <string>display-image</string>\n"
        . "          <key>url</key>\n"
        . '          <string>' . $esc($base . '/dl/icon-57.png') . "</string>\n"
        . "        </dict>\n"
        . "        <dict>\n"
        . "          <key>kind</key>\n"
        . "          <string>full-size-image</string>\n"
        . "          <key>url</key>\n"
        . '          <string>' . $esc($base . '/dl/icon-512.png') . "</string>\n"
        . "        </dict>\n"
        . "      </array>\n"
        . "      <key>metadata</key>\n"
        . "      <dict>\n"
        . "        <key>bundle-identifier</key>\n"
        . '        <string>' . $esc($info['bundle_id']) . "</string>\n"
        . "        <key>bundle-version</key>\n"
        . '        <string>' . $esc($ver) . "</string>\n"
        . "        <key>kind</key>\n"
        . "        <string>software</string>\n"
        . "        <key>title</key>\n"
        . '        <string>' . $esc($title) . "</string>\n"
        . "        <key>subtitle</key>\n"
        . "        <string>美容院客户相册</string>\n"
        . "      </dict>\n"
        . "    </dict>\n"
        . "  </array>\n"
        . "</dict>\n"
        . "</plist>\n";

    $path = dirname(__DIR__, 2) . '/manifest.plist';
    $ok = @file_put_contents($path, $xml) !== false;
    if ($ok) @chmod($path, 0644);
    return $ok;
}
