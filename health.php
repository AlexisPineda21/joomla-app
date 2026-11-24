<?php

/**
 * Endpoint de salud del sitio.
 *
 * Lo consultan el health check del balanceador, el health check de Route 53 y el
 * smoke test del pipeline. Responde 200 si MySQL y Valkey contestan, 503 si no.
 * Incluye el commit desplegado, para que el pipeline compruebe que la version
 * nueva es la que esta atendiendo.
 *
 * Con FAULT_INJECTION=enabled acepta ?simulate=error (HTTP 500) y ?simulate=fatal
 * (error fatal de PHP en el log); sirve para probar las alarmas de CloudWatch.
 */

declare(strict_types=1);

header('Content-Type: application/json');
header('Cache-Control: no-store');

$simulate = (string) ($_GET['simulate'] ?? '');

if ($simulate !== '' && getenv('FAULT_INJECTION') === 'enabled') {
    http_response_code(500);

    if ($simulate === 'fatal') {
        throw new RuntimeException('Fallo simulado en health.php para probar las alarmas');
    }

    echo json_encode(['status' => 'error', 'simulated' => true]);
    exit;
}

function check_database(): string
{
    $address = (string) getenv('JOOMLA_DB_HOST');
    [$host, $port] = array_pad(explode(':', $address, 2), 2, '3306');

    mysqli_report(MYSQLI_REPORT_OFF);
    $mysqli = mysqli_init();

    if ($mysqli === false) {
        return 'error';
    }

    $mysqli->options(MYSQLI_OPT_CONNECT_TIMEOUT, 3);
    $connected = @$mysqli->real_connect(
        $host,
        (string) getenv('JOOMLA_DB_USER'),
        (string) getenv('JOOMLA_DB_PASSWORD'),
        (string) getenv('JOOMLA_DB_NAME'),
        (int) $port
    );

    if (!$connected) {
        return 'error';
    }

    $ok = $mysqli->query('SELECT 1') !== false;
    $mysqli->close();

    return $ok ? 'ok' : 'error';
}

function check_cache(): string
{
    $host = (string) getenv('JOOMLA_REDIS_HOST');

    if ($host === '') {
        return 'disabled';
    }

    try {
        $redis = new Redis();
        $redis->connect($host, (int) (getenv('JOOMLA_REDIS_PORT') ?: 6379), 2.0);
        $pong = $redis->ping();
        $redis->close();

        return ($pong === true || $pong === '+PONG' || $pong === 'PONG') ? 'ok' : 'error';
    } catch (Throwable $e) {
        return 'error';
    }
}

function joomla_version(): string
{
    $source = (string) @file_get_contents(__DIR__ . '/libraries/src/Version.php');
    $parts  = [];

    foreach (['MAJOR', 'MINOR', 'PATCH'] as $name) {
        if (preg_match('/const ' . $name . '_VERSION = (\d+);/', $source, $match) === 1) {
            $parts[] = $match[1];
        }
    }

    return $parts ? implode('.', $parts) : 'desconocida';
}

$started = microtime(true);
$checks  = ['database' => check_database(), 'cache' => check_cache()];
$healthy = !in_array('error', $checks, true);

http_response_code($healthy ? 200 : 503);

echo json_encode([
    'status'     => $healthy ? 'ok' : 'error',
    'checks'     => $checks,
    'joomla'     => joomla_version(),
    'commit'     => getenv('APP_COMMIT') ?: 'local',
    'host'       => gethostname(),
    'elapsed_ms' => (int) round((microtime(true) - $started) * 1000),
]);
