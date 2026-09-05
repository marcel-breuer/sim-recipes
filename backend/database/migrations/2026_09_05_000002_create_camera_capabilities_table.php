<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('camera_capabilities', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('camera_model_id')
                ->constrained('camera_models')
                ->cascadeOnDelete();
            $table->string('setting_key');
            $table->string('display_name');
            $table->string('value_type');
            $table->jsonb('allowed_values')->nullable();
            $table->decimal('minimum', 8, 3)->nullable();
            $table->decimal('maximum', 8, 3)->nullable();
            $table->decimal('step', 8, 3)->nullable();
            $table->string('transport_identifier')->nullable();
            $table->jsonb('custom_slot_metadata')->nullable();
            $table->timestampsTz();

            $table->unique(['camera_model_id', 'setting_key']);
            $table->index('camera_model_id');
        });

        DB::statement("alter table camera_capabilities add constraint camera_capabilities_value_type_check check (value_type in ('enum', 'integer', 'decimal', 'boolean', 'text'))");
        DB::statement('alter table camera_capabilities add constraint camera_capabilities_range_check check (minimum is null or maximum is null or minimum <= maximum)');
        DB::statement('alter table camera_capabilities add constraint camera_capabilities_step_check check (step is null or step > 0)');
    }

    public function down(): void
    {
        Schema::dropIfExists('camera_capabilities');
    }
};
