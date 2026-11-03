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

    public function test_landing_page_does_not_render_consent_content_or_google_sources_without_configuration(): void
    {
        config([
            'analytics.consent_enabled' => false,
            'analytics.gtm_container_id' => null,
            'analytics.ga4_measurement_id' => null,
        ]);

        $this->get('/')
            ->assertOk()
            ->assertDontSee('consent-root', false)
            ->assertDontSee('cookie-consent.js', false)
            ->assertDontSee('google-analytics.com', false)
            ->assertDontSee('googletagmanager.com', false)
            ->assertHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; font-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'")
            ->assertHeader('Referrer-Policy', 'strict-origin');
    }

    public function test_consent_ui_is_rendered_only_on_the_landing_page_when_configured(): void
    {
        config([
            'analytics.consent_enabled' => true,
            'analytics.gtm_container_id' => 'GTM-ABC123',
            'analytics.ga4_measurement_id' => 'G-ABC123',
        ]);

        $this->get('/')
            ->assertOk()
            ->assertSee('id="consent-root"', false)
            ->assertSee('Accept all')
            ->assertSee('Reject optional')
            ->assertSee('Configure')
            ->assertSee('src="/js/cookie-consent.js"', false)
            ->assertDontSee('https://www.googletagmanager.com/gtm.js', false)
            ->assertDontSee('https://www.google-analytics.com/g/collect', false)
            ->assertHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' https://www.googletagmanager.com; style-src 'self'; img-src 'self' https://www.google-analytics.com; connect-src 'self' https://www.googletagmanager.com https://www.google-analytics.com https://region1.google-analytics.com; font-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'")
            ->assertHeader('Referrer-Policy', 'strict-origin');

        $this->getJson('/api/v1/health')
            ->assertOk()
            ->assertHeaderMissing('Content-Security-Policy');
    }

    public function test_landing_page_uses_the_requested_consent_language(): void
    {
        config(['analytics.consent_enabled' => true]);

        $this->get('/', ['Accept-Language' => 'de-DE,de;q=0.9,en;q=0.8'])
            ->assertOk()
            ->assertSee('<html lang="de">', false)
            ->assertSee('Alle akzeptieren')
            ->assertSee('Cookie-Einstellungen');
    }
}
