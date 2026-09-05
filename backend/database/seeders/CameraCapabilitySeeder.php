<?php

namespace Database\Seeders;

use App\Models\CameraCapability;
use App\Models\CameraModel;
use Illuminate\Database\Seeder;

class CameraCapabilitySeeder extends Seeder
{
    /**
     * Seed the supported Fujifilm X-S20 capability definition.
     *
     * The transport identifiers are stable application keys. They are not
     * claims about Fujifilm's USB/PTP property identifiers; those are resolved
     * by the camera research and transport-adapter work.
     */
    public function run(): void
    {
        $camera = CameraModel::updateOrCreate(
            ['slug' => 'fujifilm-x-s20'],
            [
                'manufacturer' => 'Fujifilm',
                'name' => 'X-S20',
                'model_identifier' => 'X-S20',
                'is_supported' => true,
            ],
        );

        $customSlotMetadata = [
            'slot_names' => ['C1', 'C2', 'C3', 'C4'],
            'slot_count' => 4,
            'supports_overwrite_warning' => true,
        ];

        $capabilities = [
            [
                'setting_key' => 'film_simulation',
                'display_name' => 'Film Simulation',
                'value_type' => 'enum',
                'allowed_values' => [
                    'AUTO',
                    'PROVIA/STANDARD',
                    'Velvia/VIVID',
                    'ASTIA/SOFT',
                    'CLASSIC CHROME',
                    'REALA ACE',
                    'PRO Neg. Hi',
                    'PRO Neg. Std',
                    'CLASSIC Neg.',
                    'NOSTALGIC Neg.',
                    'ETERNA/CINEMA',
                    'ETERNA BLEACH BYPASS',
                    'ACROS',
                    'ACROS+Ye FILTER',
                    'ACROS+R FILTER',
                    'ACROS+G FILTER',
                    'MONOCHROME',
                    'MONOCHROME+Ye FILTER',
                    'MONOCHROME+R FILTER',
                    'MONOCHROME+G FILTER',
                    'SEPIA',
                ],
                'transport_identifier' => 'image_quality.film_simulation',
            ],
            [
                'setting_key' => 'dynamic_range',
                'display_name' => 'Dynamic Range',
                'value_type' => 'enum',
                'allowed_values' => ['AUTO', '100%', '200%', '400%'],
                'transport_identifier' => 'image_quality.dynamic_range',
            ],
            [
                'setting_key' => 'grain_effect',
                'display_name' => 'Grain Effect',
                'value_type' => 'object',
                'allowed_values' => [
                    'roughness' => ['OFF', 'WEAK', 'STRONG'],
                    'size' => ['SMALL', 'LARGE'],
                ],
                'custom_slot_metadata' => [
                    'fields' => [
                        'roughness' => ['required' => true],
                        'size' => ['required' => true],
                    ],
                ],
                'transport_identifier' => 'image_quality.grain_effect',
            ],
            [
                'setting_key' => 'color_chrome_effect',
                'display_name' => 'Color Chrome Effect',
                'value_type' => 'enum',
                'allowed_values' => ['OFF', 'WEAK', 'STRONG'],
                'transport_identifier' => 'image_quality.color_chrome_effect',
            ],
            [
                'setting_key' => 'color_chrome_fx_blue',
                'display_name' => 'Color Chrome FX Blue',
                'value_type' => 'enum',
                'allowed_values' => ['OFF', 'WEAK', 'STRONG'],
                'transport_identifier' => 'image_quality.color_chrome_fx_blue',
            ],
            [
                'setting_key' => 'white_balance',
                'display_name' => 'White Balance',
                'value_type' => 'enum',
                'allowed_values' => [
                    'WHITE PRIORITY',
                    'AUTO',
                    'AMBIENCE PRIORITY',
                    'CUSTOM 1',
                    'CUSTOM 2',
                    'CUSTOM 3',
                    'COLOR TEMPERATURE',
                    'DAYLIGHT',
                    'SHADE',
                    'FLUORESCENT LIGHT-1',
                    'FLUORESCENT LIGHT-2',
                    'FLUORESCENT LIGHT-3',
                    'INCANDESCENT',
                    'UNDERWATER',
                ],
                'transport_identifier' => 'image_quality.white_balance',
            ],
            [
                'setting_key' => 'white_balance_shift',
                'display_name' => 'White Balance Shift',
                'value_type' => 'object',
                'allowed_values' => [
                    'axes' => ['warm_cool', 'green_magenta'],
                ],
                'minimum' => -9,
                'maximum' => 9,
                'step' => 1,
                'custom_slot_metadata' => [
                    'value_format' => ['warm_cool' => 'integer', 'green_magenta' => 'integer'],
                ],
                'transport_identifier' => 'image_quality.white_balance_shift',
            ],
            [
                'setting_key' => 'highlight_tone',
                'display_name' => 'Highlight Tone',
                'value_type' => 'integer',
                'minimum' => -2,
                'maximum' => 4,
                'step' => 1,
                'transport_identifier' => 'image_quality.tone_curve.highlights',
            ],
            [
                'setting_key' => 'shadow_tone',
                'display_name' => 'Shadow Tone',
                'value_type' => 'integer',
                'minimum' => -2,
                'maximum' => 4,
                'step' => 1,
                'transport_identifier' => 'image_quality.tone_curve.shadows',
            ],
            [
                'setting_key' => 'color',
                'display_name' => 'Color',
                'value_type' => 'integer',
                'minimum' => -4,
                'maximum' => 4,
                'step' => 1,
                'transport_identifier' => 'image_quality.color',
            ],
            [
                'setting_key' => 'sharpness',
                'display_name' => 'Sharpness',
                'value_type' => 'integer',
                'minimum' => -4,
                'maximum' => 4,
                'step' => 1,
                'transport_identifier' => 'image_quality.sharpness',
            ],
            [
                'setting_key' => 'high_iso_noise_reduction',
                'display_name' => 'High ISO Noise Reduction',
                'value_type' => 'integer',
                'minimum' => -4,
                'maximum' => 4,
                'step' => 1,
                'transport_identifier' => 'image_quality.high_iso_nr',
            ],
            [
                'setting_key' => 'clarity',
                'display_name' => 'Clarity',
                'value_type' => 'integer',
                'minimum' => -5,
                'maximum' => 5,
                'step' => 1,
                'transport_identifier' => 'image_quality.clarity',
            ],
            [
                'setting_key' => 'iso',
                'display_name' => 'ISO',
                'value_type' => 'integer',
                'minimum' => 80,
                'maximum' => 51200,
                'step' => 1,
                'custom_slot_metadata' => [
                    'manual_range' => ['minimum' => 160, 'maximum' => 12800, 'increment_ev' => '1/3'],
                    'extended_values' => [80, 100, 125, 25600, 51200],
                    'auto_modes' => ['AUTO1', 'AUTO2', 'AUTO3'],
                ],
                'transport_identifier' => 'shooting.iso',
            ],
            [
                'setting_key' => 'exposure_compensation',
                'display_name' => 'Exposure Compensation Recommendation',
                'value_type' => 'decimal',
                'minimum' => -5,
                'maximum' => 5,
                'step' => 0.333,
                'custom_slot_metadata' => [
                    'unit' => 'EV',
                    'increment' => '1/3',
                ],
                'transport_identifier' => 'shooting.exposure_compensation',
            ],
        ];

        foreach ($capabilities as $capability) {
            $capability['camera_model_id'] = $camera->id;
            $capability['custom_slot_metadata'] = array_replace_recursive(
                $customSlotMetadata,
                $capability['custom_slot_metadata'] ?? [],
            );

            CameraCapability::updateOrCreate(
                [
                    'camera_model_id' => $camera->id,
                    'setting_key' => $capability['setting_key'],
                ],
                $capability,
            );
        }
    }
}
