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
            $valueType = $capability->getAttribute('value_type');
            if (! is_string($valueType) || ! $this->matchesValueType($value, $valueType)) {
                $errors["settings.$index.value"][] = 'The setting value has an invalid type.';

                continue;
            }

            $allowedValues = $capability->getAttribute('allowed_values');
            if (is_string($allowedValues)) {
                $allowedValues = json_decode($allowedValues, true);
            }
            if (! $this->matchesAllowedValues($value, $valueType, $allowedValues)) {
                $errors["settings.$index.value"][] = 'The setting value is not supported by the selected camera.';
            }

            if (is_numeric($value)) {
                $minimum = $capability->getAttribute('minimum');
                $maximum = $capability->getAttribute('maximum');
                if ($minimum !== null && (float) $value < (float) $minimum) {
                    $errors["settings.$index.value"][] = 'The setting value is below the supported range.';
                }
                if ($maximum !== null && (float) $value > (float) $maximum) {
                    $errors["settings.$index.value"][] = 'The setting value is above the supported range.';
                }
            } elseif ($valueType === 'object' && is_array($value)) {
                $minimum = $capability->getAttribute('minimum');
                $maximum = $capability->getAttribute('maximum');
                foreach ($value as $objectValue) {
                    if (! is_numeric($objectValue)) {
                        continue;
                    }
                    if ($minimum !== null && (float) $objectValue < (float) $minimum) {
                        $errors["settings.$index.value"][] = 'The setting value is below the supported range.';
                    }
                    if ($maximum !== null && (float) $objectValue > (float) $maximum) {
                        $errors["settings.$index.value"][] = 'The setting value is above the supported range.';
                    }
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
            'decimal', 'number' => is_int($value) || is_float($value),
            'boolean' => is_bool($value),
            'object' => is_array($value),
            default => is_string($value),
        };
    }

    /**
     * @param  array<int|string, mixed>|null  $allowedValues
     */
    private function matchesAllowedValues(mixed $value, string $valueType, mixed $allowedValues): bool
    {
        if (! is_array($allowedValues)) {
            return true;
        }

        if ($valueType !== 'object') {
            return $this->isAllowedValue($value, $allowedValues);
        }

        if (! is_array($value)) {
            return false;
        }

        if (isset($allowedValues['axes']) && is_array($allowedValues['axes'])) {
            foreach (array_keys($value) as $key) {
                if (! in_array($key, $allowedValues['axes'], true)) {
                    return false;
                }
            }
        }

        foreach ($allowedValues as $key => $options) {
            if ($key === 'axes' || ! array_key_exists($key, $value) || ! is_array($options)) {
                continue;
            }
            if (! $this->isAllowedValue($value[$key], $options)) {
                return false;
            }
        }

        return true;
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
