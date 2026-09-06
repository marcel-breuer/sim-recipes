<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\UpdateProfileRequest;
use App\Http\Resources\Api\V1\ProfileResource;
use App\Models\Profile;
use App\Models\User;
use App\Models\UserBlock;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class ProfileController extends Controller
{
    public function show(string $username): ProfileResource
    {
        $profile = $this->profileQuery()
            ->where('username', $username)
            ->firstOrFail();

        abort_if(
            User::query()->whereKey($profile->user_id)->where('is_suspended', true)->exists(),
            404,
        );
        abort_if(
            request()->user() instanceof User
                && UserBlock::query()
                    ->where('blocker_id', request()->user()->getKey())
                    ->where('blocked_user_id', $profile->user_id)
                    ->exists(),
            404,
        );

        return new ProfileResource($profile);
    }

    public function mine(): ProfileResource
    {
        $profile = $this->profileQuery()
            ->where('user_id', request()->user()->getKey())
            ->first();

        abort_if($profile === null, 404, 'Create a profile before requesting it.');

        return new ProfileResource($profile);
    }

    public function update(UpdateProfileRequest $request): ProfileResource
    {
        $user = $request->user();
        $profile = DB::transaction(function () use ($request, $user): Profile {
            $profile = Profile::query()->firstOrNew(['user_id' => $user->getKey()]);
            $profile->fill($request->safe()->only([
                'username',
                'camera_model_id',
                'biography',
            ]));

            $profileImagePath = $profile->getAttribute('profile_image_path');
            if ($request->boolean('remove_profile_image') && is_string($profileImagePath)) {
                Storage::disk()->delete($profileImagePath);
                $profile->setAttribute('profile_image_path', null);
            }

            if ($request->hasFile('profile_image')) {
                if (is_string($profileImagePath)) {
                    Storage::disk()->delete($profileImagePath);
                }

                $profile->setAttribute('profile_image_path', $request->file('profile_image')->store(
                    'profiles/'.$user->getKey(),
                ));
            }

            $profile->setAttribute('user_id', $user->getKey());
            $profile->save();

            return $profile;
        });

        return new ProfileResource($this->profileQuery()->findOrFail($profile->getKey()));
    }

    /**
     * @return Builder<Profile>
     */
    private function profileQuery(): Builder
    {
        return Profile::query()
            ->with([
                'user' => fn ($query) => $query
                    ->withCount(['followers', 'following'])
                    ->with(['publishedRecipes' => fn ($recipeQuery) => $recipeQuery->with('cameraModel')]),
                'cameraModel',
            ]);
    }
}
