select
    question,
    answer_type,
    count(*) as answers,
    avg(confidence) as mean_confidence,
    min(judged_at) as first_judged,
    max(judged_at) as last_judged
from ticket_judgments
group by 1, 2
order by 1, 2
