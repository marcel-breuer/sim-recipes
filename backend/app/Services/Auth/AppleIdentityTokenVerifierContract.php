<?php

namespace App\Services\Auth;

interface AppleIdentityTokenVerifierContract
{
    public function verify(string $identityToken): AppleIdentity;
}
