select *
from ref_judgments
where question = 'has_contact_info'
  and answer_type = 'noul'
  and (noul < 0 or noul > 0.2)
