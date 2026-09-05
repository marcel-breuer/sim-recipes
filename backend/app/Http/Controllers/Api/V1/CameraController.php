<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Resources\Api\V1\CameraCapabilityResource;
use App\Http\Resources\Api\V1\CameraModelResource;
use App\Models\CameraModel;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class CameraController
{
    public function index(): AnonymousResourceCollection
    {
        $cameras = CameraModel::query()
            ->where('is_supported', true)
            ->with('capabilities')
            ->orderBy('manufacturer')
            ->orderBy('name')
            ->get();

        return CameraModelResource::collection($cameras);
    }

    public function show(string $camera): CameraModelResource
    {
        return new CameraModelResource($this->findSupportedCamera($camera));
    }

    public function capabilities(string $camera): AnonymousResourceCollection
    {
        $cameraModel = $this->findSupportedCamera($camera);

        return CameraCapabilityResource::collection(
            $cameraModel->capabilities()->orderBy('setting_key')->get(),
        );
    }

    private function findSupportedCamera(string $identifier): CameraModel
    {
        return CameraModel::query()
            ->where('is_supported', true)
            ->where(function ($query) use ($identifier): void {
                $query->whereKey($identifier)->orWhere('slug', $identifier);
            })
            ->with('capabilities')
            ->firstOrFail();
    }
}
