<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recipe_views', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('recipe_id')
                ->constrained('recipes')
                ->cascadeOnDelete();
            $table->foreignUlid('viewer_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->string('anonymous_key')->nullable();
            $table->timestampTz('viewed_at')->useCurrent();

            $table->index(['recipe_id', 'viewed_at']);
            $table->index('viewer_id');
            $table->index('anonymous_key');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('recipe_views');
    }
};
