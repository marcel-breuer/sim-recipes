<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('recipe_images', function (Blueprint $table): void {
            $table->jsonb('example_context')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('recipe_images', function (Blueprint $table): void {
            $table->dropColumn('example_context');
        });
    }
};
