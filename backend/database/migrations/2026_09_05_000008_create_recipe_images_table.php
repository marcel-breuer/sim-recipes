<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recipe_images', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('recipe_id')
                ->constrained('recipes')
                ->cascadeOnDelete();
            $table->string('storage_disk')->default('local');
            $table->string('original_path');
            $table->unsignedBigInteger('original_size_bytes');
            $table->string('mime_type', 100);
            $table->unsignedInteger('width')->nullable();
            $table->unsignedInteger('height')->nullable();
            $table->unsignedSmallInteger('sort_order')->default(0);
            $table->jsonb('derivatives')->nullable();
            $table->string('processing_status')->default('pending');
            $table->timestampsTz();

            $table->unique(['recipe_id', 'sort_order']);
            $table->index(['recipe_id', 'processing_status']);
        });

        DB::statement('alter table recipe_images add constraint recipe_images_size_check check (original_size_bytes > 0 and original_size_bytes <= 26214400)');
        DB::statement('alter table recipe_images add constraint recipe_images_sort_order_check check (sort_order between 0 and 4)');
        DB::statement("alter table recipe_images add constraint recipe_images_processing_status_check check (processing_status in ('pending', 'processing', 'ready', 'failed'))");
    }

    public function down(): void
    {
        Schema::dropIfExists('recipe_images');
    }
};
