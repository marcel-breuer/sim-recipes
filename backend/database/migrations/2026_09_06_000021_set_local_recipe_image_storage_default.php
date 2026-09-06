<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement("alter table recipe_images alter column storage_disk set default 'local'");
    }

    public function down(): void
    {
        DB::statement('alter table recipe_images alter column storage_disk drop default');
    }
};
