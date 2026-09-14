# Example photography

## Approved assets

| Asset | Use | Source and rights | Alt text |
| --- | --- | --- | --- |
| `backend/public/images/example-street.jpg` | Landing-page recipe preview and README | Original SimRecipes artwork, cleared for use and modification in this repository and its landing page. No third-party source or attribution is required. | A quiet stone street at blue hour with warm window light |

The committed file is an optimized 1122 × 1402 JPEG derivative. It contains
no GPS coordinates or other location metadata. Do not replace it with a
downloaded image unless the replacement's source, license, attribution, and
hosting/modification rights are recorded here first.

## Validation

The landing page and README reference the same asset path. A lightweight
repository check should confirm the file exists before release:

```sh
test -s backend/public/images/example-street.jpg
rg -n 'example-street\.jpg' README.md backend/resources/views/landing.blade.php
```
