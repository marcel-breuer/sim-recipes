<?php

namespace Database\Seeders;

use App\Models\CameraCapability;
use App\Models\CameraModel;
use Illuminate\Database\Seeder;

class CameraCapabilitySeeder extends Seeder
{
    /**
     * Seed the supported Fujifilm camera capability definitions.
     *
     * Transport identifiers are stable application keys. They are not claims
     * about Fujifilm USB/PTP property identifiers; those remain adapter-level
     * concerns and are only enabled after hardware verification.
     */
    public function run(): void
    {
        $this->seedCamera(
            slug: 'fujifilm-x-s20',
            name: 'X-S20',
            modelIdentifier: 'X-S20',
            slotNames: ['C1', 'C2', 'C3', 'C4'],
            filmSimulations: [
                'AUTO', 'PROVIA/STANDARD', 'Velvia/VIVID', 'ASTIA/SOFT',
                'CLASSIC CHROME', 'REALA ACE', 'PRO Neg. Hi', 'PRO Neg. Std',
                'CLASSIC Neg.', 'NOSTALGIC Neg.', 'ETERNA/CINEMA',
                'ETERNA BLEACH BYPASS', 'ACROS', 'ACROS+Ye FILTER',
                'ACROS+R FILTER', 'ACROS+G FILTER', 'MONOCHROME',
                'MONOCHROME+Ye FILTER', 'MONOCHROME+R FILTER',
                'MONOCHROME+G FILTER', 'SEPIA',
            ],
            isoRange: [
                'minimum' => 80,
                'manual_minimum' => 160,
                'manual_maximum' => 12800,
                'extended_values' => [80, 100, 125, 25600, 51200],
            ],
            transportMetadata: [
                'property_reads' => 'provisional',
                'recipe_writes' => 'unverified',
                'note' => 'X-S20 vendor-property encodings require hardware verification.',
            ],
        );

        $this->seedCamera(
            slug: 'fujifilm-x-t5',
            name: 'X-T5',
            modelIdentifier: 'X-T5',
            slotNames: ['C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7'],
            filmSimulations: [
                'PROVIA/STANDARD', 'Velvia/VIVID', 'ASTIA/SOFT', 'CLASSIC CHROME',
                'REALA ACE', 'PRO Neg. Hi', 'PRO Neg. Std', 'CLASSIC Neg.',
                'NOSTALGIC Neg.', 'ETERNA/CINEMA', 'ETERNA BLEACH BYPASS',
                'ACROS', 'ACROS+Ye FILTER', 'ACROS+R FILTER', 'ACROS+G FILTER',
                'MONOCHROME', 'MONOCHROME+Ye FILTER', 'MONOCHROME+R FILTER',
                'MONOCHROME+G FILTER', 'SEPIA',
            ],
            isoRange: [
                'minimum' => 64,
                'manual_minimum' => 125,
                'manual_maximum' => 12800,
                'extended_values' => [64, 80, 100, 25600, 51200],
            ],
            transportMetadata: [
                'property_reads' => 'unverified',
                'recipe_writes' => 'unverified',
                'note' => 'No X-T5 vendor-property mapping is enabled until hardware verification.',
            ],
        );
    }

    /**
     * @param  array<int, string>  $slotNames
     * @param  array<int, string>  $filmSimulations
     * @param  array{minimum: int, manual_minimum: int, manual_maximum: int, extended_values: array<int, int>}  $isoRange
     * @param  array<string, string>  $transportMetadata
     */
    private function seedCamera(
        string $slug,
        string $name,
        string $modelIdentifier,
        array $slotNames,
        array $filmSimulations,
        array $isoRange,
        array $transportMetadata,
    ): void {
        $camera = CameraModel::updateOrCreate(
            ['slug' => $slug],
            [
                'manufacturer' => 'Fujifilm',
                'name' => $name,
                'model_identifier' => $modelIdentifier,
                'is_supported' => true,
                'unsupported_recipe_settings' => ['monochromatic_color', 'smooth_skin_effect'],
                'transport_metadata' => $transportMetadata,
            ],
        );

        $customSlotMetadata = [
            'slot_names' => $slotNames,
            'slot_count' => count($slotNames),
            'supports_overwrite_warning' => true,
        ];

        $capabilities = [
            [
                'setting_key' => 'film_simulation',
                'display_name' => 'Film Simulation',
                'value_type' => 'enum',
                'allowed_values' => $filmSimulations,
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
                    'WHITE PRIORITY', 'AUTO', 'AMBIENCE PRIORITY', 'CUSTOM 1',
                    'CUSTOM 2', 'CUSTOM 3', 'COLOR TEMPERATURE', 'DAYLIGHT',
                    'SHADE', 'FLUORESCENT LIGHT-1', 'FLUORESCENT LIGHT-2',
                    'FLUORESCENT LIGHT-3', 'INCANDESCENT', 'UNDERWATER',
                ],
                'transport_identifier' => 'image_quality.white_balance',
            ],
            [
                'setting_key' => 'white_balance_shift',
                'display_name' => 'White Balance Shift',
                'value_type' => 'object',
                'allowed_values' => ['axes' => ['warm_cool', 'green_magenta']],
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
                'minimum' => $isoRange['minimum'],
                'maximum' => 51200,
                'step' => 1,
                'custom_slot_metadata' => [
                    'manual_range' => [
                        'minimum' => $isoRange['manual_minimum'],
                        'maximum' => $isoRange['manual_maximum'],
                        'increment_ev' => '1/3',
                    ],
                    'extended_values' => $isoRange['extended_values'],
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
