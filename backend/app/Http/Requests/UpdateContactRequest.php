<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class UpdateContactRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true; // Authorization handled by middleware
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'type'       => ['sometimes', 'string', 'in:customer,supplier,both'],
            'name'       => ['sometimes', 'string', 'max:255'],
            'phone'      => ['nullable', 'string', 'max:50'],
            'email'      => ['nullable', 'string', 'email', 'max:255'],
            'address'    => ['nullable', 'string', 'max:2000'],
            'tax_number' => ['nullable', 'string', 'max:100'],
        ];
    }
}
