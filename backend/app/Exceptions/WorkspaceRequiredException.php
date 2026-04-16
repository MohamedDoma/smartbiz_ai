<?php

namespace App\Exceptions;

use Symfony\Component\HttpKernel\Exception\HttpException;

class WorkspaceRequiredException extends HttpException
{
    public function __construct()
    {
        parent::__construct(400, 'X-Workspace-Id header is required.');
    }
}
