<?php
declare(strict_types=1);

if (getenv('RAILWAY_ENVIRONMENT_ID')) {
    exit(1);
}
$server = stream_socket_server('tcp://0.0.0.0:2525', $errorCode, $errorMessage);
if (!$server) {
    fwrite(STDERR, "Fixture bind failed.\n");
    exit(1);
}
while (true) {
    $client = @stream_socket_accept($server, 30);
    if (!$client) {
        continue;
    }
    stream_set_timeout($client, 10);
    fwrite($client, "220 private-smtp-fixture ESMTP\r\n");
    $message = '';
    $recipient = '';
    while (($line = fgets($client)) !== false) {
        $command = strtoupper(strtok(trim($line), ' '));
        if ($command === 'EHLO' || $command === 'HELO') {
            fwrite($client, "250 private-smtp-fixture\r\n");
        } elseif ($command === 'MAIL' || $command === 'RSET' || $command === 'NOOP') {
            fwrite($client, "250 OK\r\n");
        } elseif ($command === 'RCPT') {
            $recipient = trim(substr($line, 5));
            fwrite($client, "250 OK\r\n");
        } elseif ($command === 'DATA') {
            fwrite($client, "354 End with dot\r\n");
            while (($data = fgets($client)) !== false && rtrim($data, "\r\n") !== '.') {
                $message .= str_starts_with($data, '..') ? substr($data, 1) : $data;
            }
            $file = '/spool/' . bin2hex(random_bytes(12)) . '.json';
            if (file_put_contents($file, json_encode(['recipient' => $recipient, 'message' => $message], JSON_THROW_ON_ERROR)) === false) {
                fwrite($client, "451 Spool unavailable\r\n");
            } else {
                fwrite($client, "250 Queued\r\n");
            }
        } elseif ($command === 'QUIT') {
            fwrite($client, "221 Bye\r\n");
            break;
        } else {
            fwrite($client, "502 Not implemented\r\n");
        }
    }
    fclose($client);
}
exit(1);
