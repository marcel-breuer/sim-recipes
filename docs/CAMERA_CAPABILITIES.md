# Camera capabilities

The backend seeds one supported camera: the Fujifilm X-S20. Its capability
records drive recipe-setting validation and future UI controls instead of
hard-coding the setting list in an endpoint or client.

The seeded values cover the recipe settings required by `PROJECT_SPEC.md`:
film simulation, dynamic range, grain effect, color chrome effect, color
chrome FX blue, white balance, white balance shift, highlight tone, shadow
tone, color, sharpness, high ISO noise reduction, clarity, ISO, and exposure
compensation recommendation.

The value options and ranges are based on the [Fujifilm X-S20 Owner's
Manual](https://fujifilm-dsc.com/en/manual/x-s20/menu_shooting/image_quality_setting/)
and [technical specifications](https://fujifilm-dsc.com/en/manual/x-s20/technical_notes/spec/).
The four custom-setting banks are represented as `C1` through `C4` metadata
on each capability. Transport identifiers are application-level logical keys;
the actual USB/PTP mapping remains part of the camera research issue.

Run `php artisan db:seed --class=CameraCapabilitySeeder` to seed or refresh
the camera definition. The seeder uses stable natural keys and is safe to run
more than once.
