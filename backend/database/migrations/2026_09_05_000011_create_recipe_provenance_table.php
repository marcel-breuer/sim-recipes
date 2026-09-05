<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('recipe_provenances', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('copied_recipe_id')
                ->constrained('recipes')
                ->cascadeOnDelete();
            $table->foreignUlid('source_recipe_id')
                ->constrained('recipes')
                ->restrictOnDelete();
            $table->foreignUlid('source_author_id')
                ->nullable()
                ->constrained('users')
                ->nullOnDelete();
            $table->foreignUlid('copied_by_user_id')
                ->constrained('users')
                ->cascadeOnDelete();
            $table->timestampsTz();

            $table->unique('copied_recipe_id');
            $table->index('source_recipe_id');
            $table->index('source_author_id');
            $table->index('copied_by_user_id');
        });

        DB::statement('alter table recipe_provenances add constraint recipe_provenance_not_self_check check (copied_recipe_id <> source_recipe_id)');
    }

    public function down(): void
    {
        Schema::dropIfExists('recipe_provenances');
    }
};
