<?php

declare(strict_types=1);

use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\DB;

const SOURCE_ROOT = '/Volumes/ExternalSSD/server_mirrors/77.222.47.218/files/www/excursion.panfilius.ru';

require SOURCE_ROOT . '/vendor/autoload.php';
$app = require SOURCE_ROOT . '/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$outputDirectory = dirname(__DIR__) . '/supabase/.private_import';
if (!is_dir($outputDirectory) && !mkdir($outputDirectory, 0700, true) && !is_dir($outputDirectory)) {
    throw new RuntimeException("Unable to create {$outputDirectory}");
}
chmod($outputDirectory, 0700);

$tableMap = [
    'moonshine_user_roles' => 'app_roles',
    'buses' => 'buses',
    'moonshine_users' => 'profiles',
    'schedule_templates' => 'schedule_templates',
    'schedule_days' => 'schedule_days',
    'excursions' => 'excursions',
    'stops' => 'stops',
    'excursion_prices' => 'excursion_prices',
    'staff_prices' => 'staff_prices',
    'bus_seats' => 'bus_seats',
    'bookings' => 'bookings',
    'wallet_transactions' => 'wallet_transactions',
    'excursion_user' => 'excursion_user',
    'excursion_bus_assignments' => 'excursion_bus_assignments',
    'excursion_bus_stop_assignments' => 'excursion_bus_stop_assignments',
    'excursion_bus_booking_assignments' => 'excursion_bus_booking_assignments',
    'seat_permissions' => 'seat_permissions',
    'seat_access_requests' => 'seat_access_requests',
    'settlements' => 'settlements',
    'settlement_booking' => 'settlement_booking',
    'unscheduled_excursion_dates' => 'unscheduled_excursion_dates',
    'cancelled_excursion_dates' => 'cancelled_excursion_dates',
    'excursion_photos' => 'excursion_photos',
    'excursion_slot_limits' => 'excursion_slot_limits',
    'excursion_statement_entries' => 'excursion_statement_entries',
    'demo_booking_requests' => 'demo_booking_requests',
    'archived_excursions' => 'archived_excursions',
    'archived_bookings' => 'archived_bookings',
];

$domain = [
    'exported_at' => now()->toIso8601String(),
    'source' => 'excursion MySQL local mirror',
    'tables' => [],
];

foreach ($tableMap as $sourceTable => $targetTable) {
    $rows = DB::table($sourceTable)->orderBy('id')->get()->map(static function (object $record) use ($sourceTable): array {
        $row = (array) $record;

        if ($sourceTable === 'moonshine_users') {
            $row = [
                'id' => $row['id'],
                'role_id' => $row['moonshine_user_role_id'],
                'bus_id' => $row['bus_id'],
                'email' => $row['email'],
                'name' => $row['name'],
                'color' => $row['color'],
                'avatar_url' => $row['avatar'],
                'created_at' => $row['created_at'],
                'updated_at' => $row['updated_at'],
            ];
        } elseif ($sourceTable === 'excursion_photos') {
            $row['storage_path'] = $row['image'];
            unset($row['image']);
        }

        foreach ($row as $key => $value) {
            if ($value instanceof DateTimeInterface) {
                $row[$key] = $value->format('Y-m-d H:i:s.uP');
            }
        }

        return $row;
    })->all();

    $domain['tables'][$targetTable] = $rows;
}

$authUsers = DB::table('moonshine_users')->orderBy('id')->get()->map(static function (object $record): array {
    $row = (array) $record;
    return [
        'profile_id' => $row['id'],
        'email' => $row['email'],
        'name' => $row['name'],
        'password' => ($row['plain_password'] ?? '') !== '' ? $row['plain_password'] : null,
        'requires_password_reset' => ($row['plain_password'] ?? '') === '',
    ];
})->all();

$flags = JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR;
file_put_contents($outputDirectory . '/domain_data.json', json_encode($domain, $flags) . PHP_EOL, LOCK_EX);
file_put_contents($outputDirectory . '/auth_users.json', json_encode($authUsers, $flags) . PHP_EOL, LOCK_EX);
chmod($outputDirectory . '/domain_data.json', 0600);
chmod($outputDirectory . '/auth_users.json', 0600);

$counts = [];
foreach ($domain['tables'] as $table => $rows) {
    $counts[$table] = count($rows);
}

echo json_encode([
    'domain_file' => $outputDirectory . '/domain_data.json',
    'auth_file' => $outputDirectory . '/auth_users.json',
    'table_counts' => $counts,
    'auth_users' => count($authUsers),
    'users_requiring_password_reset' => count(array_filter($authUsers, static fn (array $user): bool => $user['requires_password_reset'])),
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL;
