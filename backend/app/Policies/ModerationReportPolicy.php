<?php

namespace App\Policies;

use App\Models\ModerationReport;
use App\Models\User;

class ModerationReportPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->is_admin === true;
    }

    public function update(User $user, ModerationReport $report): bool
    {
        return $user->is_admin === true;
    }
}
