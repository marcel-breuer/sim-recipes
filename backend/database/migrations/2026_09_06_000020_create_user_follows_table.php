<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('user_follows', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('follower_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUlid('followed_id')->constrained('users')->cascadeOnDelete();
            $table->timestampsTz();

            $table->unique(['follower_id', 'followed_id']);
            $table->index(['followed_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('user_follows');
    }
};
