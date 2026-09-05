<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recipes', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('user_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->foreignUlid('camera_model_id')
                ->constrained('camera_models')
                ->restrictOnDelete();
            $table->string('name');
            $table->text('description')->nullable();
            $table->text('recommendation')->nullable();
            $table->string('lens')->nullable();
            $table->string('status')->default('private');
            $table->timestampTz('published_at')->nullable();
            $table->unsignedBigInteger('views_count')->default(0);
            $table->unsignedBigInteger('likes_count')->default(0);
            $table->unsignedBigInteger('downloads_count')->default(0);
            $table->timestampsTz();

            $table->index(['user_id', 'status', 'updated_at']);
            $table->index(['camera_model_id', 'status', 'published_at']);
        });

        DB::statement("alter table recipes add constraint recipes_status_check check (status in ('private', 'published'))");
        DB::statement("alter table recipes add constraint recipes_publication_state_check check ((status = 'private' and published_at is null) or (status = 'published' and published_at is not null))");
    }

    public function down(): void
    {
        Schema::dropIfExists('recipes');
    }
};
