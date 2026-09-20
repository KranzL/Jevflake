{% test noul_between(model, question, min_value=0, max_value=1) %}

select *
from {{ model }}
where question = {{ jevflake.sql_string(question) }}
  and answer_type = 'noul'
  and (noul < {{ min_value }} or noul > {{ max_value }})

{% endtest %}


{% test confidence_at_least(model, threshold=0.5, question=none) %}

select *
from {{ model }}
where answer_type in ('choice', 'score')
  and confidence < {{ threshold }}
  {% if question is not none %}
  and question = {{ jevflake.sql_string(question) }}
  {% endif %}

{% endtest %}


{% test no_errors(model) %}

select *
from {{ model }}
where answer_type = 'error'

{% endtest %}
