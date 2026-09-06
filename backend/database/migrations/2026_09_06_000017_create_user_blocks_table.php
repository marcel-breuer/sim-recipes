<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('user_blocks', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('blocker_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUlid('blocked_user_id')->constrained('users')->cascadeOnDelete();
            $table->timestampsTz();

            $table->unique(['blocker_id', 'blocked_user_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('user_blocks');
    }
};
