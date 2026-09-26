{% test noul_between(model, question, min_value=0, max_value=1) %}
{% do jevflake.assert_number(min_value, 'min_value') %}
{% do jevflake.assert_number(max_value, 'max_value') %}

select *
from {{ model }}
where question = {{ jevflake.sql_string(question) }}
  and answer_type = 'noul'
  and (noul < {{ min_value }} or noul > {{ max_value }})

{% endtest %}


{% test confidence_at_least(model, threshold=0.5, question=none) %}
{% do jevflake.assert_number(threshold, 'threshold') %}

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


{% test score_between(model, question, min_value=0, max_value=none) %}
{% do jevflake.assert_number(min_value, 'min_value') %}
{% if max_value is none %}
  {{ exceptions.raise_compiler_error('jevflake: score_between needs max_value, the highest score your levels allow') }}
{% endif %}
{% do jevflake.assert_number(max_value, 'max_value') %}

select *
from {{ model }}
where question = {{ jevflake.sql_string(question) }}
  and answer_type = 'score'
  and (score < {{ min_value }} or score > {{ max_value }})

{% endtest %}


{% test choice_allowed(model, allowed, question=none) %}
{% if allowed | length == 0 %}
  {{ exceptions.raise_compiler_error('jevflake: choice_allowed needs at least one allowed choice') }}
{% endif %}
{% set quoted = [] %}
{% for option in allowed %}
  {% do quoted.append(jevflake.sql_string(option)) %}
{% endfor %}

select *
from {{ model }}
where answer_type = 'choice'
  and choice not in ({{ quoted | join(', ') }})
  {% if question is not none %}
  and question = {{ jevflake.sql_string(question) }}
  {% endif %}

{% endtest %}


{% test judgment_drift(model, baseline, key, question, tolerance=0.05) %}
{% do jevflake.assert_number(tolerance, 'tolerance') %}
{% set keys = [key] if key is string else key %}
{% if keys | length == 0 %}
  {{ exceptions.raise_compiler_error('jevflake: judgment_drift needs at least one key column') }}
{% endif %}
{% for column in keys %}
  {% do jevflake.assert_identifier(column, 'key column') %}
{% endfor %}
{% if baseline is string %}
  {% do jevflake.assert_dotted_name(baseline, 'baseline table') %}
{% endif %}

select current.*
from {{ model }} as current
join {{ baseline }} as baseline
  on baseline.question = current.question
  {% for column in keys %}
  and baseline.{{ column }} = current.{{ column }}
  {% endfor %}
where current.question = {{ jevflake.sql_string(question) }}
  and (
    current.answer_type != baseline.answer_type
    or (current.answer_type = 'noul' and abs(current.noul - baseline.noul) > {{ tolerance }})
    or (current.answer_type = 'score' and abs(current.score - baseline.score) > {{ tolerance }})
    or (current.answer_type = 'choice' and current.choice != baseline.choice)
  )

{% endtest %}
