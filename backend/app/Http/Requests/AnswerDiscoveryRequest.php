<?php
namespace App\Http\Requests;
use Illuminate\Foundation\Http\FormRequest;

class AnswerDiscoveryRequest extends FormRequest
{
    public function authorize(): bool { return true; }

    public function rules(): array
    {
        return [
            'message_id' => ['required', 'uuid'],
            'answers'    => ['required', 'array', 'min:1'],
            'answers.*.answer' => ['required', 'string', 'min:1'],
            'locale'     => ['sometimes', 'string', 'in:ar,en'],
        ];
    }
}
