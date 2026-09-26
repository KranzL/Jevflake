delete from ANALYTICS.PUBLIC.ticket_judgments
where question not in ('ticket_type', 'has_contact_info');
delete from ANALYTICS.PUBLIC.ticket_judgments as judged
where not exists (
    select 1
    from ANALYTICS.PUBLIC.stg_tickets as source
    where source.ticket_id = judged.ticket_id
)
