<?php

namespace Database\Seeders;

use App\Models\Category;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class CategorySeeder extends Seeder
{
    public function run(): void
    {
        foreach ([
            'Street', 'Portrait', 'Landscape', 'Travel', 'Architecture', 'Nature',
            'Wildlife', 'Automotive', 'Night', 'Low Light', 'Golden Hour',
            'Black & White', 'Cinematic', 'Vintage', 'Everyday', 'Indoor',
            'Food', 'Documentary',
        ] as $name) {
            Category::firstOrCreate(['slug' => Str::slug($name)], ['name' => $name]);
        }
    }
}
