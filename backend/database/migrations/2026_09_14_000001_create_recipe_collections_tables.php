<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recipe_collections', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('name', 80);
            $table->boolean('is_public')->default(false);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestampsTz();

            $table->unique(['user_id', 'name']);
            $table->index(['user_id', 'sort_order']);
        });

        Schema::create('recipe_collection_recipe', function (Blueprint $table): void {
            $table->foreignUlid('collection_id')->constrained('recipe_collections')->cascadeOnDelete();
            $table->foreignUlid('recipe_id')->constrained('recipes')->cascadeOnDelete();
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestampsTz();

            $table->primary(['collection_id', 'recipe_id']);
            $table->index(['recipe_id', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('recipe_collection_recipe');
        Schema::dropIfExists('recipe_collections');
    }
};
