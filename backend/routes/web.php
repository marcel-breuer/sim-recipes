<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    $language = request()->getPreferredLanguage(['de', 'en']) ?? 'en';

    return view('landing', [
        'analytics' => config('analytics'),
        'language' => $language,
    ]);
})->middleware('landing.csp')->name('landing');
