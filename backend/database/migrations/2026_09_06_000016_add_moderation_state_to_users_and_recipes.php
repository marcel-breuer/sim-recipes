<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->boolean('is_admin')->default(false)->after('password');
            $table->boolean('is_suspended')->default(false)->after('is_admin');
        });

        Schema::table('recipes', function (Blueprint $table): void {
            $table->boolean('is_hidden')->default(false)->after('status');
            $table->timestampTz('moderated_at')->nullable()->after('is_hidden');
            $table->string('moderation_reason')->nullable()->after('moderated_at');
            $table->index(['status', 'is_hidden', 'published_at']);
        });
    }

    public function down(): void
    {
        Schema::table('recipes', function (Blueprint $table): void {
            $table->dropIndex(['status', 'is_hidden', 'published_at']);
            $table->dropColumn(['is_hidden', 'moderated_at', 'moderation_reason']);
        });

        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn(['is_admin', 'is_suspended']);
        });
    }
};
