<?php

namespace Tests\Feature;

use Tests\TestCase;

class LandingAssetTest extends TestCase
{
    public function test_landing_page_references_the_approved_example_photo(): void
    {
        $this->get('/')
            ->assertOk()
            ->assertSee('/images/example-street.jpg', false)
            ->assertSee('A quiet stone street at blue hour with warm window light', false);

        $this->assertFileIsReadable(public_path('images/example-street.jpg'));
    }
}
