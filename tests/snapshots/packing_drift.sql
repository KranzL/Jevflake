select
    coalesce(candidate.question, baseline.question) as question,
    count(*) as rows_compared,
    avg(case when candidate.answer_type = 'noul' then abs(candidate.noul - baseline.noul) end) as mean_abs_noul_drift,
    max(case when candidate.answer_type = 'noul' then abs(candidate.noul - baseline.noul) end) as max_abs_noul_drift,
    avg(case when candidate.answer_type = 'score' then abs(candidate.score - baseline.score) end) as mean_abs_score_drift,
    max(case when candidate.answer_type = 'score' then abs(candidate.score - baseline.score) end) as max_abs_score_drift,
    sum(case when candidate.answer_type = 'choice' and candidate.choice != baseline.choice then 1 else 0 end) as choice_mismatches,
    sum(case when candidate.answer_type is distinct from baseline.answer_type then 1 else 0 end) as type_mismatches
from baseline_judgments as baseline
full outer join candidate_judgments as candidate
  on baseline.question = candidate.question
  
  and baseline.ticket_id = candidate.ticket_id
  
group by 1
order by 1
