<?php

namespace Tests\Unit;

use Tests\TestCase;

class AnalyticsConfigurationTest extends TestCase
{
    public function test_only_well_formed_analytics_ids_are_used_for_tag_loading(): void
    {
        $original = [
            'GTM_CONTAINER_ID' => getenv('GTM_CONTAINER_ID'),
            'GA4_MEASUREMENT_ID' => getenv('GA4_MEASUREMENT_ID'),
        ];

        try {
            putenv('GTM_CONTAINER_ID=not-a-container');
            putenv('GA4_MEASUREMENT_ID=G-ABC123?extra=1');
            $_ENV['GTM_CONTAINER_ID'] = 'not-a-container';
            $_ENV['GA4_MEASUREMENT_ID'] = 'G-ABC123?extra=1';

            $invalid = require config_path('analytics.php');

            $this->assertTrue($invalid['consent_enabled']);
            $this->assertNull($invalid['gtm_container_id']);
            $this->assertNull($invalid['ga4_measurement_id']);

            putenv('GTM_CONTAINER_ID=GTM-ABC123');
            putenv('GA4_MEASUREMENT_ID=G-ABC123');
            $_ENV['GTM_CONTAINER_ID'] = 'GTM-ABC123';
            $_ENV['GA4_MEASUREMENT_ID'] = 'G-ABC123';

            $valid = require config_path('analytics.php');

            $this->assertTrue($valid['consent_enabled']);
            $this->assertSame('GTM-ABC123', $valid['gtm_container_id']);
            $this->assertSame('G-ABC123', $valid['ga4_measurement_id']);
        } finally {
            foreach ($original as $key => $value) {
                if ($value === false) {
                    putenv($key);
                    unset($_ENV[$key]);
                } else {
                    putenv("{$key}={$value}");
                    $_ENV[$key] = $value;
                }
            }
        }
    }
}
