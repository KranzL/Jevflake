{{ config(
    materialized='incremental',
    unique_key=['ticket_id', 'question'],
    on_schema_change='append_new_columns'
) }}

{{ jevflake.judgments(
    relation=ref('support_tickets'),
    key='ticket_id',
    state=['subject', 'body'],
    questions={
        'ticket_type': jevflake.choice_question(
            'Which team should handle this ticket',
            {
                'billing': 'Charges, refunds, invoices, plans',
                'technical': 'Bugs, crashes, errors, slow pages',
                'account': 'Login, access, profile changes',
                'other': 'Feedback, ideas, or nothing to do'
            }
        ),
        'urgency': jevflake.score_question(
            'How urgent is this ticket',
            [
                'No action needed or no time pressure',
                'Needs a reply in the normal queue',
                'Customer is blocked or losing money right now'
            ]
        ),
        'has_contact_info': jevflake.noul_question(
            'The text contains a phone number or an email address'
        )
    }
) }}
