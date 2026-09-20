{{ config(
    materialized='incremental',
    unique_key='ticket_id'
) }}

select
    ticket_id,
    {{ jevflake.noul('body', 'The customer is asking for a refund') }} as wants_refund,
    {{ jevflake.choice('body', 'What is the tone of the message', ['calm', 'frustrated', 'happy']) }} as tone
from {{ ref('support_tickets') }}
{% if is_incremental() %}
where ticket_id not in (select ticket_id from {{ this }})
{% endif %}
