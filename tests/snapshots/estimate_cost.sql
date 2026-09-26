select
    count(*) as rows_to_judge,
    coalesce(avg(length(to_json(to_variant(object_construct_keep_null('subject', subject, 'body', body))))), 0) as mean_state_chars,
    (coalesce(avg(length(to_json(to_variant(object_construct_keep_null('subject', subject, 'body', body))))), 0) + 281) / 4 + 250 as est_tokens_per_row,
    count(*) * ((coalesce(avg(length(to_json(to_variant(object_construct_keep_null('subject', subject, 'body', body))))), 0) + 281) / 4 + 250) as est_total_tokens,
    count(*) * ((coalesce(avg(length(to_json(to_variant(object_construct_keep_null('subject', subject, 'body', body))))), 0) + 281) / 4 + 250) / 1000000 * 0.042 as est_usd
from stg_tickets
where ((subject is not null) or (body is not null))
  
  and ticket_id is not null
