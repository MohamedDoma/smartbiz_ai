<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreJournalEntryRequest extends FormRequest
{
    public function authorize(): bool { return true; }

    public function rules(): array
    {
        return [
            'reference'                => ['nullable', 'string', 'max:100'],
            'description'              => ['required', 'string'],
            'date'                     => ['sometimes', 'date'],
            'currency'                 => ['sometimes', 'string', 'max:10'],
            'exchange_rate'            => ['sometimes', 'numeric', 'gt:0'],
            'status'                   => ['sometimes', 'string', 'in:draft,posted,reversed'],
            'lines'                    => ['required', 'array', 'min:2'],
            'lines.*.account_id'       => ['required', 'uuid'],
            'lines.*.debit'            => ['sometimes', 'numeric', 'min:0'],
            'lines.*.credit'           => ['sometimes', 'numeric', 'min:0'],
            'lines.*.description'      => ['nullable', 'string'],
            'lines.*.reporting_amount' => ['nullable', 'numeric'],
        ];
    }

    public function messages(): array
    {
        return [
            'lines.min' => 'A journal entry must have at least 2 lines (debit and credit).',
        ];
    }
}
