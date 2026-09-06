<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('camera_models', function (Blueprint $table): void {
            $table->jsonb('unsupported_recipe_settings')->default('[]');
            $table->jsonb('transport_metadata')->default('{}');
        });
    }

    public function down(): void
    {
        Schema::table('camera_models', function (Blueprint $table): void {
            $table->dropColumn(['unsupported_recipe_settings', 'transport_metadata']);
        });
    }
};
