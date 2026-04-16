<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreAccountRequest extends FormRequest
{
    public function authorize(): bool { return true; }

    public function rules(): array
    {
        return [
            'code'      => ['required', 'string', 'max:50'],
            'name'      => ['required', 'string', 'max:255'],
            'type'      => ['required', 'string', 'in:asset,liability,equity,revenue,expense'],
            'parent_id' => ['nullable', 'uuid'],
        ];
    }
}
