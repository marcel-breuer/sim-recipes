<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('camera_capabilities', function (Blueprint $table): void {
            $table->string('evidence_level')->default('catalog_only');
            $table->text('evidence_source')->nullable();
            $table->string('verified_firmware')->nullable();
            $table->timestampTz('verified_at')->nullable();
        });

        DB::statement("alter table camera_capabilities add constraint camera_capabilities_evidence_level_check check (evidence_level in ('catalog_only', 'manufacturer_documented', 'camera_verified'))");
        DB::statement("alter table camera_capabilities add constraint camera_capabilities_evidence_source_check check (evidence_level = 'catalog_only' or evidence_source is not null)");
        DB::statement("alter table camera_capabilities add constraint camera_capabilities_verified_evidence_check check (evidence_level <> 'camera_verified' or (evidence_source is not null and verified_firmware is not null and verified_at is not null))");
    }

    public function down(): void
    {
        DB::statement('alter table camera_capabilities drop constraint if exists camera_capabilities_verified_evidence_check');
        DB::statement('alter table camera_capabilities drop constraint if exists camera_capabilities_evidence_source_check');
        DB::statement('alter table camera_capabilities drop constraint if exists camera_capabilities_evidence_level_check');

        Schema::table('camera_capabilities', function (Blueprint $table): void {
            $table->dropColumn(['evidence_level', 'evidence_source', 'verified_firmware', 'verified_at']);
        });
    }
};
