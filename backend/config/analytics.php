<?php

$gtmContainerId = trim((string) env('GTM_CONTAINER_ID', ''));
$ga4MeasurementId = trim((string) env('GA4_MEASUREMENT_ID', ''));

return [
    'consent_enabled' => $gtmContainerId !== '' || $ga4MeasurementId !== '',
    'gtm_container_id' => preg_match('/^GTM-[A-Z0-9]+$/', $gtmContainerId) === 1 ? $gtmContainerId : null,
    'ga4_measurement_id' => preg_match('/^G-[A-Z0-9]+$/', $ga4MeasurementId) === 1 ? $ga4MeasurementId : null,
];
