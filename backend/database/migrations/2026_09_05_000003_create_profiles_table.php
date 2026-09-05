<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('profiles', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('user_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->string('username')->unique();
            $table->string('profile_image_path')->nullable();
            $table->foreignUlid('camera_model_id')
                ->nullable()
                ->constrained('camera_models')
                ->nullOnDelete();
            $table->text('biography')->nullable();
            $table->timestampsTz();

            $table->unique('user_id');
            $table->index('camera_model_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('profiles');
    }
};
