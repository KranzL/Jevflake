select *
from ref_ticket_judgments
where answer_type = 'error'
   or (answer_type = 'noul' and noul > 0.2 and noul < 0.8)
   or (answer_type in ('choice', 'score') and confidence < 0.5)
