{% macro packing_drift(baseline, candidate, key) %}
  {% set keys = [key] if key is string else key %}
  {% if keys | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: packing_drift needs at least one key column') }}
  {% endif %}
  {% for column in keys %}
    {% do jevflake.assert_identifier(column, 'key column') %}
  {% endfor %}
  {% if baseline is string %}
    {% do jevflake.assert_dotted_name(baseline, 'baseline table') %}
  {% endif %}
  {% if candidate is string %}
    {% do jevflake.assert_dotted_name(candidate, 'candidate table') %}
  {% endif %}

select
    coalesce(candidate.question, baseline.question) as question,
    count(*) as rows_compared,
    avg(case when candidate.answer_type = 'noul' then abs(candidate.noul - baseline.noul) end) as mean_abs_noul_drift,
    max(case when candidate.answer_type = 'noul' then abs(candidate.noul - baseline.noul) end) as max_abs_noul_drift,
    avg(case when candidate.answer_type = 'score' then abs(candidate.score - baseline.score) end) as mean_abs_score_drift,
    max(case when candidate.answer_type = 'score' then abs(candidate.score - baseline.score) end) as max_abs_score_drift,
    sum(case when candidate.answer_type = 'choice' and candidate.choice != baseline.choice then 1 else 0 end) as choice_mismatches,
    sum(case when candidate.answer_type is distinct from baseline.answer_type then 1 else 0 end) as type_mismatches
from {{ baseline }} as baseline
full outer join {{ candidate }} as candidate
  on baseline.question = candidate.question
  {% for column in keys %}
  and baseline.{{ column }} = candidate.{{ column }}
  {% endfor %}
group by 1
order by 1

{% endmacro %}


{% macro estimate_cost(relation, state, questions, key=none, chars_per_token=4, overhead_tokens=250, price_per_million=0.042) %}
  {% do jevflake.assert_number(chars_per_token, 'chars_per_token') %}
  {% do jevflake.assert_number(overhead_tokens, 'overhead_tokens') %}
  {% do jevflake.assert_number(price_per_million, 'price_per_million') %}
  {% if relation is string %}
    {% do jevflake.assert_dotted_name(relation, 'source table') %}
  {% endif %}
  {% set keys = [] if key is none else ([key] if key is string else key) %}
  {% for column in keys %}
    {% do jevflake.assert_identifier(column, 'key column') %}
  {% endfor %}
  {% if questions | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: estimate_cost needs at least one question') }}
  {% endif %}
  {% set state_json = 'to_json(' ~ jevflake.state_expression(state) ~ ')' %}
  {% set questions_chars = tojson(questions, sort_keys=true) | length %}

select
    count(*) as rows_to_judge,
    coalesce(avg(length({{ state_json }})), 0) as mean_state_chars,
    (coalesce(avg(length({{ state_json }})), 0) + {{ questions_chars }}) / {{ chars_per_token }} + {{ overhead_tokens }} as est_tokens_per_row,
    count(*) * ((coalesce(avg(length({{ state_json }})), 0) + {{ questions_chars }}) / {{ chars_per_token }} + {{ overhead_tokens }}) as est_total_tokens,
    count(*) * ((coalesce(avg(length({{ state_json }})), 0) + {{ questions_chars }}) / {{ chars_per_token }} + {{ overhead_tokens }}) / 1000000 * {{ price_per_million }} as est_usd
from {{ relation }}
where {{ jevflake.state_not_null_predicate(state) }}
  {% for column in keys %}
  and {{ column }} is not null
  {% endfor %}

{% endmacro %}


{% macro judgment_run_stats(relation) %}
  {% if relation is string %}
    {% do jevflake.assert_dotted_name(relation, 'judgments table') %}
  {% endif %}

select
    question,
    answer_type,
    count(*) as answers,
    avg(confidence) as mean_confidence,
    min(judged_at) as first_judged,
    max(judged_at) as last_judged
from {{ relation }}
group by 1, 2
order by 1, 2

{% endmacro %}
