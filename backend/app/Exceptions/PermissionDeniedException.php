<?php

namespace App\Exceptions;

use Symfony\Component\HttpKernel\Exception\HttpException;

class PermissionDeniedException extends HttpException
{
    public function __construct(string $permission = '')
    {
        $msg = $permission
            ? "Permission denied: {$permission}"
            : 'Permission denied.';
        parent::__construct(403, $msg);
    }
}
