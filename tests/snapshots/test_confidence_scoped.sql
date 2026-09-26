select *
from ref_judgments
where answer_type in ('choice', 'score')
  and confidence < 0.5
  
  and question = 'ticket_type'
