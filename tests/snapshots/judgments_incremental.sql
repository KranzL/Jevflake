with jevflake_source as (

    select
        
        ticket_id,
        
        to_variant(object_construct_keep_null('subject', subject, 'body', body)) as jevflake_state
    from ref_stg_tickets
    where ticket_id is not null and ((subject is not null) or (body is not null))

),

jevflake_hashed as (

    select
        *,
        md5(to_json(jevflake_state)) as state_hash
    from jevflake_source
    where jevflake_state is not null

),

jevflake_fresh as (

    select *
    from jevflake_hashed as fresh
    
    where not exists (
        select 1
        from "ANALYTICS"."PUBLIC"."MODEL" as judged
        where judged.state_hash = fresh.state_hash
          
          and judged.ticket_id = fresh.ticket_id
          
    )
    

),

jevflake_asked_fresh as (

    select
        
        ticket_id,
        
        state_hash,
        ANALYTICS.jevflake.jev_ask(jevflake_state, parse_json('{"has_contact_info": {"instructions": "The text contains a phone number or an email address", "type": "noul"}, "ticket_type": {"criteria": {"billing": "Charges and refunds", "technical": "Bugs and errors"}, "instructions": "Which team should handle this ticket", "type": "choice"}}')) as response
    from jevflake_fresh

),

jevflake_stale_0 as (

    select *
    from jevflake_hashed as stale
    where exists (
        select 1
        from "ANALYTICS"."PUBLIC"."MODEL" as judged
        where judged.state_hash = stale.state_hash
          
          and judged.ticket_id = stale.ticket_id
          
    )
    and not exists (
        select 1
        from "ANALYTICS"."PUBLIC"."MODEL" as judged
        where judged.state_hash = stale.state_hash
          
          and judged.ticket_id = stale.ticket_id
          
          and judged.question = 'ticket_type'
          and (judged.question_hash = 'fcf78b64d235614f2e4d20f8b2f645b5' or (judged.question_hash is null and judged.questions_hash = '8710a5f09653a3b85fe4d05a66f77c0e'))
    )

),

jevflake_asked_0 as (

    select
        
        ticket_id,
        
        state_hash,
        ANALYTICS.jevflake.jev_ask(jevflake_state, parse_json('{"ticket_type": {"criteria": {"billing": "Charges and refunds", "technical": "Bugs and errors"}, "instructions": "Which team should handle this ticket", "type": "choice"}}')) as response
    from jevflake_stale_0

),

jevflake_stale_1 as (

    select *
    from jevflake_hashed as stale
    where exists (
        select 1
        from "ANALYTICS"."PUBLIC"."MODEL" as judged
        where judged.state_hash = stale.state_hash
          
          and judged.ticket_id = stale.ticket_id
          
    )
    and not exists (
        select 1
        from "ANALYTICS"."PUBLIC"."MODEL" as judged
        where judged.state_hash = stale.state_hash
          
          and judged.ticket_id = stale.ticket_id
          
          and judged.question = 'has_contact_info'
          and (judged.question_hash = '8ff657fc04e1fe4c532b48cb61dbcaaf' or (judged.question_hash is null and judged.questions_hash = '8710a5f09653a3b85fe4d05a66f77c0e'))
    )

),

jevflake_asked_1 as (

    select
        
        ticket_id,
        
        state_hash,
        ANALYTICS.jevflake.jev_ask(jevflake_state, parse_json('{"has_contact_info": {"instructions": "The text contains a phone number or an email address", "type": "noul"}}')) as response
    from jevflake_stale_1

),

jevflake_asked as (

    select * from jevflake_asked_fresh
    
    
    union all
    select * from jevflake_asked_0
    
    union all
    select * from jevflake_asked_1
    
    

)

select
    
    asked.ticket_id,
    
    answers.key::varchar as question,
    answers.value:type::varchar as answer_type,
    answers.value:noul::float as noul,
    answers.value:choice::varchar as choice,
    answers.value:score::float as score,
    answers.value:confidence::float as confidence,
    answers.value:probabilities as probabilities,
    answers.value:error::varchar as error,
    answers.value as answer,
    answers.value:model::varchar as model,
    asked.state_hash,
    case answers.key::varchar when 'ticket_type' then 'fcf78b64d235614f2e4d20f8b2f645b5' when 'has_contact_info' then '8ff657fc04e1fe4c532b48cb61dbcaaf' end as question_hash,
    '8710a5f09653a3b85fe4d05a66f77c0e'::varchar as questions_hash,
    sysdate() as judged_at
from jevflake_asked as asked,
    lateral flatten(input => asked.response:answers) as answers
