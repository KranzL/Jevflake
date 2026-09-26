select current.*
from ref_judgments as current
join ANALYTICS.PUBLIC.baseline as baseline
  on baseline.question = current.question
  
  and baseline.ticket_id = current.ticket_id
  
where current.question = 'urgency'
  and (
    current.answer_type != baseline.answer_type
    or (current.answer_type = 'noul' and abs(current.noul - baseline.noul) > 0.05)
    or (current.answer_type = 'score' and abs(current.score - baseline.score) > 0.05)
    or (current.answer_type = 'choice' and current.choice != baseline.choice)
  )
