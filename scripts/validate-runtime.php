<?php
declare(strict_types=1);

function reject(string $message): never
{
    fwrite(STDERR, "Configuration rejected: {$message}\n");
    exit(1);
}

$mode = getenv('TEMPLATE_MODE') ?: 'production';
if (!in_array($mode, ['production', 'local-test'], true)) {
    reject('TEMPLATE_MODE must be production or local-test.');
}
foreach (['DATASOURCES_DEFAULT_HOST', 'DATASOURCES_DEFAULT_DATABASE', 'DATASOURCES_DEFAULT_USERNAME', 'DATASOURCES_DEFAULT_PASSWORD', 'SECURITY_SALT', 'APP_FULL_BASE_URL', 'PASSBOLT_KEY_EMAIL', 'EMAIL_DEFAULT_FROM', 'EMAIL_TRANSPORT_DEFAULT_HOST', 'EMAIL_TRANSPORT_DEFAULT_PORT'] as $variable) {
    $value = getenv($variable);
    if ($value === false || trim($value) === '' || str_contains($value, '${{') || str_contains($value, 'REPLACE_')) {
        reject("{$variable} must be explicitly configured.");
    }
}
foreach (['SECURITY_SALT' => 64, 'DATASOURCES_DEFAULT_PASSWORD' => 32] as $variable => $minimum) {
    if (strlen((string)getenv($variable)) < $minimum) {
        reject("{$variable} is too short.");
    }
}
foreach (['PASSBOLT_KEY_EMAIL', 'EMAIL_DEFAULT_FROM'] as $variable) {
    if (!filter_var(getenv($variable), FILTER_VALIDATE_EMAIL)) {
        reject("{$variable} must be a valid email address.");
    }
}
$url = parse_url((string)getenv('APP_FULL_BASE_URL'));
if (!$url || empty($url['host']) || isset($url['user']) || isset($url['pass']) || isset($url['query']) || isset($url['fragment']) || (isset($url['path']) && $url['path'] !== '' && $url['path'] !== '/')) {
    reject('APP_FULL_BASE_URL must be an origin, without credentials, query or subpath.');
}
if (!preg_match('/^[a-zA-Z0-9.-]+$/D', $url['host'])) {
    reject('APP_FULL_BASE_URL host must be a plain DNS name or IPv4 literal.');
}
if (getenv('PORT') !== '8080') {
    reject('PORT is fixed at 8080.');
}
$port = filter_var(getenv('EMAIL_TRANSPORT_DEFAULT_PORT'), FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 65535]]);
if (!$port) {
    reject('EMAIL_TRANSPORT_DEFAULT_PORT is invalid.');
}
foreach (['PASSBOLT_PLUGINS_SELF_REGISTRATION_ENABLED' => 'false', 'PASSBOLT_PLUGINS_SMTP_SETTINGS_ENABLED' => 'false', 'PASSBOLT_PLUGINS_JWT_AUTHENTICATION_ENABLED' => 'true', 'DEBUG' => 'false', 'PASSBOLT_SECURITY_FULLBASEURL_ENFORCE' => 'true', 'PASSBOLT_SECURITY_PREVENT_EMAIL_ENUMERATION' => 'true'] as $variable => $expected) {
    if (getenv($variable) !== $expected) {
        reject("{$variable} must remain {$expected}.");
    }
}
foreach (['DATASOURCES_DEFAULT_URL', 'EMAIL_TRANSPORT_DEFAULT_URL', 'PASSBOLT_GPG_SERVER_KEY_PRIVATE_FILE', 'PASSBOLT_GPG_SERVER_KEY_PUBLIC_FILE'] as $variable) {
    if (getenv($variable)) {
        reject("{$variable} overrides are outside this recipe.");
    }
}
if ($mode === 'production') {
    if (($url['scheme'] ?? '') !== 'https' || in_array($url['host'], ['localhost', '127.0.0.1', '::1'], true)) {
        reject('Production requires a public HTTPS origin.');
    }
    foreach (['EMAIL_TRANSPORT_DEFAULT_USERNAME', 'EMAIL_TRANSPORT_DEFAULT_PASSWORD'] as $variable) {
        if (!getenv($variable) || str_contains((string)getenv($variable), 'REPLACE_')) {
            reject("Production requires real {$variable}.");
        }
    }
    if (getenv('EMAIL_TRANSPORT_DEFAULT_TLS') !== 'true' || getenv('PASSBOLT_SSL_FORCE') !== 'true' || getenv('PASSBOLT_SECURITY_COOKIE_SECURE') !== 'true') {
        reject('Production requires STARTTLS, forced HTTPS and secure cookies.');
    }
    $smtp = (string)getenv('EMAIL_TRANSPORT_DEFAULT_HOST');
    if (in_array($smtp, ['localhost', '127.0.0.1', '::1', 'smtp'], true) || str_ends_with($smtp, '.invalid') || str_ends_with($smtp, '.test')) {
        reject('A local SMTP sink is not a production mail service.');
    }
} elseif (($url['scheme'] ?? '') !== 'http' || $url['host'] !== '127.0.0.1' || ($url['port'] ?? null) !== 18424 || getenv('RAILWAY_ENVIRONMENT_ID')) {
    reject('local-test is restricted to http://127.0.0.1:18424 and forbidden on Railway.');
}
