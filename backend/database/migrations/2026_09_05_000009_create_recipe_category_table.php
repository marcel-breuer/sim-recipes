<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('category_recipe', function (Blueprint $table) {
            $table->foreignUlid('recipe_id')
                ->constrained('recipes')
                ->cascadeOnDelete();
            $table->foreignUlid('category_id')
                ->constrained('categories')
                ->cascadeOnDelete();

            $table->primary(['recipe_id', 'category_id']);
            $table->index('category_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('category_recipe');
    }
};
