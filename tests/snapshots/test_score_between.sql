select *
from ref_judgments
where question = 'urgency'
  and answer_type = 'score'
  and (score < 0 or score > 2)
