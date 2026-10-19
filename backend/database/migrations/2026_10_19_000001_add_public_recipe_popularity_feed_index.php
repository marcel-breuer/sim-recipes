<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement(<<<'SQL'
            CREATE INDEX recipes_public_popularity_feed_idx
            ON recipes (
                (likes_count * 3 + downloads_count * 5 + views_count) DESC,
                likes_count DESC,
                downloads_count DESC,
                views_count DESC,
                published_at DESC,
                id DESC
            )
            WHERE status = 'published' AND is_hidden = false
            SQL);
    }

    public function down(): void
    {
        DB::statement('DROP INDEX IF EXISTS recipes_public_popularity_feed_idx');
    }
};
