<?php

namespace App\Services\Recipes;

use App\Models\CameraCapability;
use Illuminate\Validation\ValidationException;

class RecipeCapabilityValidator
{
    /**
     * @param  array<int, array{setting_key: string, value: mixed}>  $settings
     */
    public function validate(string $cameraModelID, array $settings): void
    {
        $capabilities = CameraCapability::query()
            ->where('camera_model_id', $cameraModelID)
            ->get()
            ->keyBy('setting_key');
        $errors = [];
        $seenKeys = [];

        foreach ($settings as $index => $setting) {
            $key = $setting['setting_key'];
            if (isset($seenKeys[$key])) {
                $errors["settings.$index.setting_key"][] = 'The setting key must be unique.';

                continue;
            }
            $seenKeys[$key] = true;

            $capability = $capabilities->get($key);
            if (! $capability instanceof CameraCapability) {
                $errors["settings.$index.setting_key"][] = 'The setting is not supported by the selected camera.';

                continue;
            }

            $value = $setting['value'];
            if (! $this->matchesValueType($value, $capability->value_type)) {
                $errors["settings.$index.value"][] = 'The setting value has an invalid type.';

                continue;
            }

            $allowedValues = $capability->getAttribute('allowed_values');
            if (is_string($allowedValues)) {
                $allowedValues = json_decode($allowedValues, true);
            }
            if (is_array($allowedValues) && ! $this->isAllowedValue($value, $allowedValues)) {
                $errors["settings.$index.value"][] = 'The setting value is not supported by the selected camera.';
            }

            if (is_numeric($value)) {
                if ($capability->minimum !== null && (float) $value < (float) $capability->minimum) {
                    $errors["settings.$index.value"][] = 'The setting value is below the supported range.';
                }
                if ($capability->maximum !== null && (float) $value > (float) $capability->maximum) {
                    $errors["settings.$index.value"][] = 'The setting value is above the supported range.';
                }
            }
        }

        if ($errors !== []) {
            throw ValidationException::withMessages($errors);
        }
    }

    private function matchesValueType(mixed $value, string $valueType): bool
    {
        return match ($valueType) {
            'integer' => is_int($value),
            'number' => is_int($value) || is_float($value),
            'boolean' => is_bool($value),
            'object' => is_array($value),
            default => is_string($value),
        };
    }

    /**
     * @param  array<int, mixed>  $allowedValues
     */
    private function isAllowedValue(mixed $value, array $allowedValues): bool
    {
        foreach ($allowedValues as $allowedValue) {
            if ($allowedValue === $value || (is_scalar($allowedValue) && (string) $allowedValue === (string) $value)) {
                return true;
            }
        }

        return false;
    }
}
