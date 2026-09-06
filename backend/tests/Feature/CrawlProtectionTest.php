<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CrawlProtectionTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_admin_responses_are_marked_non_indexable(): void
    {
        $admin = User::factory()->create();
        $admin->forceFill(['is_admin' => true])->save();
        Sanctum::actingAs($admin->fresh());

        $this->getJson('/api/v1/admin/users')
            ->assertOk()
            ->assertHeader('X-Robots-Tag', 'noindex, nofollow, noarchive, nosnippet');
    }

    public function test_public_landing_page_remains_indexable_and_has_no_remote_assets(): void
    {
        $response = $this->get('/');

        $response->assertOk()
            ->assertSee('https://simrecipes.marcel-breuer.dev/', false)
            ->assertDontSee('href="http://', false)
            ->assertDontSee('src="http://', false)
            ->assertDontSee('fonts.googleapis.com', false)
            ->assertDontSee('fonts.gstatic.com', false)
            ->assertDontSee('github.com', false);
    }
}
