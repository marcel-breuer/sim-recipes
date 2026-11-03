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
            ->assertDontSee('simrecipes-camera.png', false)
            ->assertDontSee('github.com', false)
            ->assertSee('href="https://marcel-breuer.dev/impressum" target="_blank" rel="noopener noreferrer"', false)
            ->assertSee('href="https://marcel-breuer.dev/datenschutz" target="_blank" rel="noopener noreferrer"', false);
    }

    public function test_landing_page_has_no_consent_ui_or_google_tracking_and_uses_a_self_only_policy(): void
    {
        $this->get('/')
            ->assertOk()
            ->assertDontSee('consent-root', false)
            ->assertDontSee('cookie-consent.js', false)
            ->assertDontSee('google-analytics.com', false)
            ->assertDontSee('googletagmanager.com', false)
            ->assertDontSee('data-analytics-event', false)
            ->assertHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; font-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'")
            ->assertHeader('Referrer-Policy', 'strict-origin');
    }
}
