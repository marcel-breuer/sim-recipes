<?php

namespace Tests\Feature;

use Tests\TestCase;

class ApiContractTest extends TestCase
{
    public function test_openapi_contract_contains_the_supported_core_operations(): void
    {
        $contractPath = dirname(base_path()).'/docs/openapi.json';
        $contract = json_decode((string) file_get_contents($contractPath), true, 512, JSON_THROW_ON_ERROR);

        self::assertSame('3.1.0', $contract['openapi']);
        self::assertSame('v1', $contract['info']['version']);
        self::assertArrayHasKey('/health', $contract['paths']);
        self::assertArrayHasKey('/cameras', $contract['paths']);
        self::assertArrayHasKey('/categories', $contract['paths']);
        self::assertArrayHasKey('/recipes', $contract['paths']);
        self::assertArrayHasKey('/recipes/{recipe}', $contract['paths']);
        self::assertArrayHasKey('get', $contract['paths']['/recipes']);
        self::assertArrayHasKey('post', $contract['paths']['/recipes']);
        self::assertContains('#/components/parameters/Page', array_map(
            static fn (array $parameter): string => $parameter['$ref'] ?? '',
            $contract['paths']['/recipes']['get']['parameters']
        ));
    }

    public function test_contract_matches_the_runtime_error_and_pagination_shapes(): void
    {
        $contractPath = dirname(base_path()).'/docs/openapi.json';
        $contract = json_decode((string) file_get_contents($contractPath), true, 512, JSON_THROW_ON_ERROR);

        self::assertArrayHasKey('ErrorEnvelope', $contract['components']['schemas']);
        self::assertArrayHasKey('PageEnvelope', $contract['components']['schemas']);
        self::assertArrayHasKey('401', $contract['paths']['/auth/apple']['post']['responses']);
        self::assertArrayHasKey('422', $contract['paths']['/auth/apple']['post']['responses']);
    }
}
