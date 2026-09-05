<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recipe_downloads', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('recipe_id')
                ->constrained('recipes')
                ->cascadeOnDelete();
            $table->foreignUlid('user_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignUlid('copied_recipe_id')
                ->nullable()
                ->constrained('recipes')
                ->nullOnDelete();
            $table->timestampTz('created_at')->useCurrent();

            $table->index(['recipe_id', 'created_at']);
            $table->index('user_id');
            $table->index('copied_recipe_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('recipe_downloads');
    }
};
