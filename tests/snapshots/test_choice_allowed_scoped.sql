select *
from ref_judgments
where answer_type = 'choice'
  and choice not in ('billing', 'technical')
  
  and question = 'ticket_type'
