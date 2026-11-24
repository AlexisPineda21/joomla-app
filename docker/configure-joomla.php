<?php

/**
 * Ajusta configuration.php de Joomla con las variables de entorno del contenedor.
 *
 * - Base de datos: host, usuario, contrasena y nombre (vienen de Terraform / compose).
 * - Valkey: cache (DB 0) y sesiones (DB 1) con el manejador Redis de Joomla.
 *
 * Se ejecuta en cada arranque y es idempotente: si no hay cambios, no escribe.
 * Uso: php configure-joomla.php /ruta/configuration.php
 */

declare(strict_types=1);

$file = $argv[1] ?? '';

if ($file === '' || !is_file($file)) {
    fwrite(STDERR, "[configure-joomla] No existe el archivo de configuracion: {$file}\n");
    exit(1);
}

$settings = [];

$database = [
    'host'     => 'JOOMLA_DB_HOST',
    'user'     => 'JOOMLA_DB_USER',
    'password' => 'JOOMLA_DB_PASSWORD',
    'db'       => 'JOOMLA_DB_NAME',
];

foreach ($database as $key => $variable) {
    $value = getenv($variable);

    if ($value !== false && $value !== '') {
        $settings[$key] = $value;
    }
}

$redisHost = (string) getenv('JOOMLA_REDIS_HOST');
$redisPort = (int) (getenv('JOOMLA_REDIS_PORT') ?: 6379);

if ($redisHost !== '') {
    $settings += [
        'caching'                   => 1,
        'cache_handler'             => 'redis',
        'redis_persist'             => 1,
        'redis_server_host'         => $redisHost,
        'redis_server_port'         => $redisPort,
        'redis_server_auth'         => '',
        'redis_server_db'           => 0,
        'session_handler'           => 'redis',
        'session_redis_persist'     => 1,
        'session_redis_server_host' => $redisHost,
        'session_redis_server_port' => $redisPort,
        'session_redis_server_auth' => '',
        'session_redis_server_db'   => 1,
    ];
}

$original = (string) file_get_contents($file);
$code     = $original;
$changed  = [];

foreach ($settings as $key => $value) {
    $line    = "\tpublic \$" . $key . ' = ' . var_export($value, true) . ';';
    $pattern = '/^\s*public \$' . preg_quote($key, '/') . '\s*=.*?;\s*$/m';

    if (preg_match($pattern, $code, $current) === 1) {
        if (trim($current[0]) === trim($line)) {
            continue;
        }

        $code = (string) preg_replace_callback($pattern, static fn () => $line, $code, 1);
    } else {
        $end  = (int) strrpos($code, '}');
        $code = substr($code, 0, $end) . $line . "\n" . substr($code, $end);
    }

    $changed[] = $key;
}

if ($changed === []) {
    echo "[configure-joomla] configuration.php ya estaba al dia\n";
    exit(0);
}

$temporary = $file . '.tmp';

if (file_put_contents($temporary, $code) === false || !rename($temporary, $file)) {
    fwrite(STDERR, "[configure-joomla] No se pudo escribir {$file}\n");
    exit(1);
}

@chown($file, 'www-data');
@chgrp($file, 'www-data');
chmod($file, 0444);

echo '[configure-joomla] configuration.php actualizado: ' . implode(', ', $changed) . "\n";
