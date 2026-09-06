<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('moderation_reports', function (Blueprint $table): void {
            $table->text('reviewer_note')->nullable()->after('resolution');
        });
    }

    public function down(): void
    {
        Schema::table('moderation_reports', function (Blueprint $table): void {
            $table->dropColumn('reviewer_note');
        });
    }
};
