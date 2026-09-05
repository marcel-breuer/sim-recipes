<?php

namespace Tests\Feature;

use Database\Seeders\CategorySeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CategoryApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_predefined_recipe_categories_are_publicly_available(): void
    {
        $this->seed(CategorySeeder::class);

        $this->getJson('/api/v1/categories')
            ->assertOk()
            ->assertJsonCount(18, 'data')
            ->assertJsonFragment(['name' => 'Black & White', 'slug' => 'black-white']);
    }
}
