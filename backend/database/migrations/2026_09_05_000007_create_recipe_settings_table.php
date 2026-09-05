<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recipe_settings', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('recipe_id')
                ->constrained('recipes')
                ->cascadeOnDelete();
            $table->foreignUlid('camera_capability_id')
                ->constrained('camera_capabilities')
                ->restrictOnDelete();
            $table->string('setting_key');
            $table->jsonb('value');
            $table->timestampsTz();

            $table->unique(['recipe_id', 'setting_key']);
            $table->index('camera_capability_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('recipe_settings');
    }
};
