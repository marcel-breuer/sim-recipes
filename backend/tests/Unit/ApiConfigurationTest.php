<?php

namespace Tests\Unit;

use Tests\TestCase;

class ApiConfigurationTest extends TestCase
{
    public function test_api_pagination_defaults_are_configured(): void
    {
        $this->assertSame(20, config('api.pagination.default_per_page'));
        $this->assertSame(100, config('api.pagination.max_per_page'));
    }
}
