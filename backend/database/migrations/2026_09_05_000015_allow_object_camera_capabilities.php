<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement('alter table camera_capabilities drop constraint camera_capabilities_value_type_check');
        DB::statement("alter table camera_capabilities add constraint camera_capabilities_value_type_check check (value_type in ('enum', 'integer', 'decimal', 'boolean', 'text', 'object'))");
    }

    public function down(): void
    {
        DB::statement("update camera_capabilities set value_type = 'text' where value_type = 'object'");
        DB::statement('alter table camera_capabilities drop constraint camera_capabilities_value_type_check');
        DB::statement("alter table camera_capabilities add constraint camera_capabilities_value_type_check check (value_type in ('enum', 'integer', 'decimal', 'boolean', 'text'))");
    }
};
