
===== moonshine_user_roles =====
CREATE TABLE `moonshine_user_roles` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== moonshine_users =====
CREATE TABLE `moonshine_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `moonshine_user_role_id` bigint unsigned NOT NULL DEFAULT '1',
  `bus_id` bigint unsigned DEFAULT NULL,
  `email` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `color` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `password` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `plain_password` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `avatar` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `remember_token` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `moonshine_users_email_unique` (`email`),
  KEY `moonshine_users_moonshine_user_role_id_foreign` (`moonshine_user_role_id`),
  KEY `moonshine_users_bus_id_foreign` (`bus_id`),
  CONSTRAINT `moonshine_users_bus_id_foreign` FOREIGN KEY (`bus_id`) REFERENCES `buses` (`id`) ON DELETE SET NULL,
  CONSTRAINT `moonshine_users_moonshine_user_role_id_foreign` FOREIGN KEY (`moonshine_user_role_id`) REFERENCES `moonshine_user_roles` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=194 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== schedule_templates =====
CREATE TABLE `schedule_templates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=34 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== schedule_days =====
CREATE TABLE `schedule_days` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `schedule_template_id` bigint unsigned NOT NULL,
  `weekday` tinyint NOT NULL COMMENT '1-7: Понедельник-Воскресенье',
  `time` time DEFAULT NULL COMMENT 'Время начала экскурсии',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `schedule_days_schedule_template_id_weekday_unique` (`schedule_template_id`,`weekday`),
  CONSTRAINT `schedule_days_schedule_template_id_foreign` FOREIGN KEY (`schedule_template_id`) REFERENCES `schedule_templates` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=95 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== excursions =====
CREATE TABLE `excursions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `schedule_template_id` bigint unsigned NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `direction` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'west',
  `date_time` datetime DEFAULT NULL,
  `price` decimal(10,2) DEFAULT NULL,
  `actual_amount` decimal(10,2) DEFAULT NULL,
  `price_adult_without_entry` decimal(10,2) DEFAULT NULL,
  `price_adult_with_entry` decimal(10,2) DEFAULT NULL,
  `price_adult_seller_commission` decimal(5,2) DEFAULT '10.00',
  `price_adult_partner_commission` decimal(5,2) DEFAULT '10.00',
  `price_child_without_entry` decimal(10,2) DEFAULT NULL,
  `price_child_with_entry` decimal(10,2) DEFAULT NULL,
  `price_child_seller_commission` decimal(5,2) DEFAULT '10.00',
  `price_child_partner_commission` decimal(5,2) DEFAULT '10.00',
  `price_senior_without_entry` decimal(10,2) DEFAULT NULL,
  `price_senior_with_entry` decimal(10,2) DEFAULT NULL,
  `price_senior_seller_commission` decimal(5,2) DEFAULT '10.00',
  `price_senior_partner_commission` decimal(5,2) DEFAULT '10.00',
  `price_disabled_without_entry` decimal(10,2) DEFAULT NULL,
  `price_disabled_with_entry` decimal(10,2) DEFAULT NULL,
  `price_disabled_seller_commission` decimal(5,2) DEFAULT '10.00',
  `price_disabled_partner_commission` decimal(5,2) DEFAULT '10.00',
  `price_special_without_entry` decimal(10,2) DEFAULT NULL,
  `price_special_with_entry` decimal(10,2) DEFAULT NULL,
  `price_special_seller_commission` decimal(5,2) DEFAULT '10.00',
  `price_special_partner_commission` decimal(5,2) DEFAULT '10.00',
  `max_seats` int NOT NULL DEFAULT '100',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `excursions_schedule_template_id_foreign` (`schedule_template_id`),
  CONSTRAINT `excursions_schedule_template_id_foreign` FOREIGN KEY (`schedule_template_id`) REFERENCES `schedule_templates` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB AUTO_INCREMENT=1435 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== stops =====
CREATE TABLE `stops` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `order` int NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=46 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== excursion_prices =====
CREATE TABLE `excursion_prices` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `passenger_type` enum('adult','child','senior','disabled','special','concession') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `price` decimal(10,2) DEFAULT NULL,
  `price_without_entry` decimal(10,2) DEFAULT NULL,
  `price_with_entry` decimal(10,2) DEFAULT NULL,
  `seller_commission_percent` decimal(5,2) NOT NULL DEFAULT '10.00',
  `partner_commission_percent` decimal(5,2) NOT NULL DEFAULT '10.00',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `excursion_prices_excursion_id_passenger_type_unique` (`excursion_id`,`passenger_type`),
  CONSTRAINT `excursion_prices_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5784 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== staff_prices =====
CREATE TABLE `staff_prices` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `staff_type` enum('driver','guide') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `min_passengers` int NOT NULL DEFAULT '0',
  `max_passengers` int DEFAULT NULL,
  `price` decimal(10,2) NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_staff_price` (`excursion_id`,`staff_type`,`min_passengers`,`max_passengers`),
  CONSTRAINT `staff_prices_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2075 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== buses =====
CREATE TABLE `buses` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `number` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT 'Номер автобуса (например, "123" или "А123БВ")',
  `model` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Модель автобуса (например, "Mercedes Sprinter")',
  `capacity` int NOT NULL DEFAULT '50' COMMENT 'Вместимость - количество мест',
  `license_plate` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'Государственный номер',
  `is_active` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Активен ли автобус',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `buses_number_unique` (`number`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== bus_seats =====
CREATE TABLE `bus_seats` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `seat_number` int NOT NULL,
  `status` enum('available','booked','reserved') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'available',
  `booked_by` bigint unsigned DEFAULT NULL,
  `booked_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `bus_seats_excursion_id_seat_number_unique` (`excursion_id`,`seat_number`),
  KEY `bus_seats_booked_by_foreign` (`booked_by`),
  CONSTRAINT `bus_seats_booked_by_foreign` FOREIGN KEY (`booked_by`) REFERENCES `moonshine_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `bus_seats_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=68936 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== bookings =====
CREATE TABLE `bookings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `weekday` tinyint DEFAULT NULL COMMENT '1-7: Понедельник-Воскресенье',
  `time` time DEFAULT NULL COMMENT 'Время начала экскурсии',
  `excursion_date` date DEFAULT NULL COMMENT 'Конкретная дата экскурсии (YYYY-MM-DD)',
  `bus_seat_id` bigint unsigned NOT NULL,
  `booked_by` bigint unsigned NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `debt` decimal(10,2) NOT NULL DEFAULT '0.00',
  `customer_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `customer_phone` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `comment` text COLLATE utf8mb4_unicode_ci,
  `passenger_type` enum('adult','child','senior','disabled','special','concession') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'adult',
  `with_entry` tinyint(1) NOT NULL DEFAULT '0',
  `stop_id` bigint unsigned NOT NULL,
  `booked_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `bookings_excursion_id_foreign` (`excursion_id`),
  KEY `bookings_bus_seat_id_foreign` (`bus_seat_id`),
  KEY `bookings_booked_by_foreign` (`booked_by`),
  KEY `bookings_stop_id_foreign` (`stop_id`),
  CONSTRAINT `bookings_booked_by_foreign` FOREIGN KEY (`booked_by`) REFERENCES `moonshine_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `bookings_bus_seat_id_foreign` FOREIGN KEY (`bus_seat_id`) REFERENCES `bus_seats` (`id`) ON DELETE CASCADE,
  CONSTRAINT `bookings_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `bookings_stop_id_foreign` FOREIGN KEY (`stop_id`) REFERENCES `stops` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1062 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== wallet_transactions =====
CREATE TABLE `wallet_transactions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `booking_id` bigint unsigned DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `description` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `wallet_transactions_user_id_foreign` (`user_id`),
  KEY `wallet_transactions_booking_id_foreign` (`booking_id`),
  CONSTRAINT `wallet_transactions_booking_id_foreign` FOREIGN KEY (`booking_id`) REFERENCES `bookings` (`id`) ON DELETE SET NULL,
  CONSTRAINT `wallet_transactions_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `moonshine_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=1136 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== excursion_user =====
CREATE TABLE `excursion_user` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `role_in_excursion` enum('driver','guide') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `excursion_date` date DEFAULT NULL,
  `time` varchar(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `manual_amount` decimal(10,2) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `excursion_user_excursion_user_role_date_time_unique` (`excursion_id`,`user_id`,`role_in_excursion`,`excursion_date`,`time`),
  KEY `excursion_user_user_id_foreign` (`user_id`),
  KEY `excursion_user_date_time_idx` (`excursion_id`,`user_id`,`excursion_date`,`time`),
  CONSTRAINT `excursion_user_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `excursion_user_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `moonshine_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=259 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== excursion_bus_assignments =====
CREATE TABLE `excursion_bus_assignments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `excursion_date` date NOT NULL,
  `time` varchar(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `bus_id` bigint unsigned NOT NULL,
  `driver_id` bigint unsigned NOT NULL,
  `guide_user_id` bigint unsigned DEFAULT NULL,
  `seat_from` int unsigned NOT NULL,
  `seat_to` int unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `eba_unique_bus_per_excursion_datetime` (`excursion_id`,`excursion_date`,`time`,`bus_id`),
  UNIQUE KEY `eba_unique_driver_per_excursion_datetime` (`excursion_id`,`excursion_date`,`time`,`driver_id`),
  KEY `eba_excursion_datetime_idx` (`excursion_id`,`excursion_date`,`time`),
  KEY `eba_bus_idx` (`bus_id`),
  KEY `eba_driver_idx` (`driver_id`),
  KEY `excursion_bus_assignments_guide_user_id_foreign` (`guide_user_id`),
  CONSTRAINT `excursion_bus_assignments_bus_id_foreign` FOREIGN KEY (`bus_id`) REFERENCES `buses` (`id`) ON DELETE CASCADE,
  CONSTRAINT `excursion_bus_assignments_driver_id_foreign` FOREIGN KEY (`driver_id`) REFERENCES `moonshine_users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `excursion_bus_assignments_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `excursion_bus_assignments_guide_user_id_foreign` FOREIGN KEY (`guide_user_id`) REFERENCES `moonshine_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=34 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== excursion_bus_stop_assignments =====
CREATE TABLE `excursion_bus_stop_assignments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `excursion_date` date NOT NULL,
  `time` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `bus_assignment_id` bigint unsigned NOT NULL,
  `stop_id` bigint unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ex_bus_stop_slot_stop_unique` (`excursion_id`,`excursion_date`,`time`,`stop_id`),
  KEY `excursion_bus_stop_assignments_bus_assignment_id_foreign` (`bus_assignment_id`),
  KEY `excursion_bus_stop_assignments_stop_id_foreign` (`stop_id`),
  CONSTRAINT `excursion_bus_stop_assignments_bus_assignment_id_foreign` FOREIGN KEY (`bus_assignment_id`) REFERENCES `excursion_bus_assignments` (`id`) ON DELETE CASCADE,
  CONSTRAINT `excursion_bus_stop_assignments_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `excursion_bus_stop_assignments_stop_id_foreign` FOREIGN KEY (`stop_id`) REFERENCES `stops` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=67 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== excursion_bus_booking_assignments =====
CREATE TABLE `excursion_bus_booking_assignments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `excursion_date` date NOT NULL,
  `time` time NOT NULL,
  `booking_id` bigint unsigned NOT NULL,
  `bus_assignment_id` bigint unsigned DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `excursion_bus_booking_assignments_booking_id_unique` (`booking_id`),
  KEY `excursion_bus_booking_assignments_bus_assignment_id_foreign` (`bus_assignment_id`),
  KEY `excursion_bus_booking_slot_idx` (`excursion_id`,`excursion_date`,`time`),
  CONSTRAINT `excursion_bus_booking_assignments_booking_id_foreign` FOREIGN KEY (`booking_id`) REFERENCES `bookings` (`id`) ON DELETE CASCADE,
  CONSTRAINT `excursion_bus_booking_assignments_bus_assignment_id_foreign` FOREIGN KEY (`bus_assignment_id`) REFERENCES `excursion_bus_assignments` (`id`) ON DELETE SET NULL,
  CONSTRAINT `excursion_bus_booking_assignments_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=12 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== seat_permissions =====
CREATE TABLE `seat_permissions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `excursion_date` date NOT NULL,
  `seat_number` int NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `seat_perm_unique` (`excursion_id`,`user_id`,`excursion_date`,`seat_number`),
  KEY `seat_permissions_user_id_foreign` (`user_id`),
  CONSTRAINT `seat_permissions_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `seat_permissions_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `moonshine_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== seat_access_requests =====
CREATE TABLE `seat_access_requests` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `excursion_date` date NOT NULL,
  `seat_number` int NOT NULL,
  `status` enum('pending','approved','rejected') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `reviewed_by` bigint unsigned DEFAULT NULL,
  `reviewed_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `seat_access_requests_excursion_id_foreign` (`excursion_id`),
  KEY `seat_access_requests_user_id_foreign` (`user_id`),
  KEY `seat_access_requests_reviewed_by_foreign` (`reviewed_by`),
  KEY `seat_access_requests_status_excursion_id_excursion_date_index` (`status`,`excursion_id`,`excursion_date`),
  CONSTRAINT `seat_access_requests_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `seat_access_requests_reviewed_by_foreign` FOREIGN KEY (`reviewed_by`) REFERENCES `moonshine_users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `seat_access_requests_user_id_foreign` FOREIGN KEY (`user_id`) REFERENCES `moonshine_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== settlements =====
CREATE TABLE `settlements` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `seller_id` bigint unsigned NOT NULL,
  `total_amount` decimal(10,2) NOT NULL,
  `notes` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `settlement_date` date NOT NULL,
  `date_from` date DEFAULT NULL,
  `date_to` date DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `settlements_seller_id_foreign` (`seller_id`),
  CONSTRAINT `settlements_seller_id_foreign` FOREIGN KEY (`seller_id`) REFERENCES `moonshine_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=29 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== settlement_booking =====
CREATE TABLE `settlement_booking` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `settlement_id` bigint unsigned NOT NULL,
  `booking_id` bigint unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `settlement_booking_settlement_id_booking_id_unique` (`settlement_id`,`booking_id`),
  KEY `settlement_booking_booking_id_foreign` (`booking_id`),
  CONSTRAINT `settlement_booking_booking_id_foreign` FOREIGN KEY (`booking_id`) REFERENCES `bookings` (`id`) ON DELETE CASCADE,
  CONSTRAINT `settlement_booking_settlement_id_foreign` FOREIGN KEY (`settlement_id`) REFERENCES `settlements` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=101 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== unscheduled_excursion_dates =====
CREATE TABLE `unscheduled_excursion_dates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `date_time` datetime NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  `deleted_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unscheduled_excursion_dates_excursion_id_date_time_unique` (`excursion_id`,`date_time`),
  CONSTRAINT `unscheduled_excursion_dates_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== cancelled_excursion_dates =====
CREATE TABLE `cancelled_excursion_dates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `date_time` datetime NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `cancelled_excursion_dates_excursion_id_date_time_unique` (`excursion_id`,`date_time`),
  CONSTRAINT `cancelled_excursion_dates_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== excursion_photos =====
CREATE TABLE `excursion_photos` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `image` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `sort_order` int unsigned NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `excursion_photos_excursion_id_foreign` (`excursion_id`),
  CONSTRAINT `excursion_photos_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=34 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== excursion_slot_limits =====
CREATE TABLE `excursion_slot_limits` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `excursion_date` date NOT NULL,
  `time` time NOT NULL,
  `max_seats` int unsigned NOT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `excursion_slot_limits_unique` (`excursion_id`,`excursion_date`,`time`),
  CONSTRAINT `excursion_slot_limits_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== excursion_statement_entries =====
CREATE TABLE `excursion_statement_entries` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `slot_key` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `entry_key` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `value` text COLLATE utf8mb4_unicode_ci,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `excursion_statement_entries_slot_key_entry_key_unique` (`slot_key`,`entry_key`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== demo_booking_requests =====
CREATE TABLE `demo_booking_requests` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `excursion_id` bigint unsigned NOT NULL,
  `stop_id` bigint unsigned DEFAULT NULL,
  `customer_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `customer_phone` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `passengers_count` int unsigned NOT NULL DEFAULT '1',
  `comment` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `status` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'new',
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `demo_booking_requests_excursion_id_foreign` (`excursion_id`),
  KEY `demo_booking_requests_stop_id_foreign` (`stop_id`),
  CONSTRAINT `demo_booking_requests_excursion_id_foreign` FOREIGN KEY (`excursion_id`) REFERENCES `excursions` (`id`) ON DELETE CASCADE,
  CONSTRAINT `demo_booking_requests_stop_id_foreign` FOREIGN KEY (`stop_id`) REFERENCES `stops` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== archived_excursions =====
CREATE TABLE `archived_excursions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `original_excursion_id` bigint unsigned NOT NULL,
  `title` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `date_time` datetime DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `payload` json DEFAULT NULL,
  `archived_reason` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `archived_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `archived_excursions_original_excursion_id_index` (`original_excursion_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1331 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

===== archived_bookings =====
CREATE TABLE `archived_bookings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `original_booking_id` bigint unsigned NOT NULL,
  `original_excursion_id` bigint unsigned NOT NULL,
  `excursion_id` bigint unsigned DEFAULT NULL,
  `bus_seat_id` bigint unsigned DEFAULT NULL,
  `booked_by` bigint unsigned DEFAULT NULL,
  `price` decimal(10,2) DEFAULT NULL,
  `customer_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `customer_phone` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `passenger_type` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `stop_id` bigint unsigned DEFAULT NULL,
  `booked_at` datetime DEFAULT NULL,
  `payload` json DEFAULT NULL,
  `wallet_transactions` json DEFAULT NULL,
  `archived_reason` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `archived_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `archived_bookings_original_booking_id_index` (`original_booking_id`),
  KEY `archived_bookings_original_excursion_id_index` (`original_excursion_id`),
  KEY `archived_bookings_excursion_id_index` (`excursion_id`)
) ENGINE=InnoDB AUTO_INCREMENT=75 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
