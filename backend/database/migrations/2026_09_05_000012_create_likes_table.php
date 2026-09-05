<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('likes', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('user_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignUlid('recipe_id')
                ->constrained('recipes')
                ->cascadeOnDelete();
            $table->timestampsTz();

            $table->unique(['user_id', 'recipe_id']);
            $table->index('recipe_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('likes');
    }
};
