<?php
namespace App\Http\Requests;
use Illuminate\Foundation\Http\FormRequest;

class StartDiscoveryRequest extends FormRequest
{
    public function authorize(): bool { return true; }

    public function rules(): array
    {
        return [
            'business_description' => ['required', 'string', 'min:20'],
        ];
    }

    public function messages(): array
    {
        return [
            'business_description.min' => 'Please provide at least 20 characters describing your business.',
        ];
    }
}
