# Camera capabilities

The backend seeds two supported cameras: the Fujifilm X-S20 and X-T5. Their
capability records drive recipe-setting validation and future UI controls
instead of hard-coding the setting list in an endpoint or client.

The seeded values cover the recipe settings required by `PROJECT_SPEC.md`:
film simulation, dynamic range, grain effect, color chrome effect, color
chrome FX blue, white balance, white balance shift, highlight tone, shadow
tone, color, sharpness, high ISO noise reduction, clarity, ISO, and exposure
compensation recommendation.

The value options and ranges are based on the [Fujifilm X-S20 Owner's
Manual](https://fujifilm-dsc.com/en/manual/x-s20/menu_shooting/image_quality_setting/)
and [technical specifications](https://fujifilm-dsc.com/en/manual/x-s20/technical_notes/spec/),
plus the [Fujifilm X-T5 Owner's Manual](https://fujifilm-dsc.com/en/manual/x-t5/menu_shooting/image_quality_setting/)
and [technical specifications](https://fujifilm-dsc.com/en/manual/x-t5/technical_notes/spec/).
The X-S20 exposes four custom-setting banks (`C1` through `C4`); the X-T5
exposes seven (`C1` through `C7`). Unsupported recipe settings are listed
explicitly on each camera response. `monochromatic_color` and
`smooth_skin_effect` are currently outside SimRecipes' recipe capability set
for both models.

Transport identifiers are application-level logical keys. The X-T5 has no
enabled USB/PTP property mapping, and X-S20 property reads remain provisional;
recipe writes must continue to report the existing unverified limitation.

Run `php artisan db:seed --class=CameraCapabilitySeeder` to seed or refresh
the camera definition. The seeder uses stable natural keys and is safe to run
more than once.
