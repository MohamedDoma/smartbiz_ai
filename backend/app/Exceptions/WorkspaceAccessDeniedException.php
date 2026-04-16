<?php

namespace App\Exceptions;

use Symfony\Component\HttpKernel\Exception\HttpException;

class WorkspaceAccessDeniedException extends HttpException
{
    public function __construct(string $message = 'Access to this workspace is denied.')
    {
        parent::__construct(403, $message);
    }
}
