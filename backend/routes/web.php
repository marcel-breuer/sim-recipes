<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    $language = request()->getPreferredLanguage(['de', 'en']) ?? 'en';

    return view('landing', [
        'language' => $language,
    ]);
})->middleware('landing.csp')->name('landing');
