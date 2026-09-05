<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('camera_models', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->string('manufacturer');
            $table->string('name');
            $table->string('slug')->unique();
            $table->string('model_identifier')->nullable()->unique();
            $table->boolean('is_supported')->default(false);
            $table->timestampsTz();

            $table->index(['manufacturer', 'is_supported']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('camera_models');
    }
};
