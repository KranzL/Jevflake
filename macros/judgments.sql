{% macro questions_hash(questions) %}
  {{ return(local_md5(tojson(questions, sort_keys=true) ~ '|' ~ jevflake.model_name())) }}
{% endmacro %}


{% macro judgments(relation, key, state, questions) %}
  {% set keys = [key] if key is string else key %}
  {% if keys | length == 0 or questions | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: judgments needs at least one key column and one question') }}
  {% endif %}
  {% set hash = jevflake.questions_hash(questions) %}

with jevflake_source as (

    select
        {% for column in keys %}
        {{ column }},
        {% endfor %}
        {{ jevflake.state_expression(state) }} as jevflake_state
    from {{ relation }}
    where {% for column in keys %}{{ column }} is not null{% if not loop.last %} and {% endif %}{% endfor %}

),

jevflake_hashed as (

    select
        *,
        md5(to_json(jevflake_state)) as state_hash
    from jevflake_source
    where jevflake_state is not null

),

jevflake_pending as (

    select *
    from jevflake_hashed as pending
    {% if is_incremental() %}
    where not exists (
        select 1
        from {{ this }} as judged
        where judged.state_hash = pending.state_hash
          and judged.questions_hash = {{ jevflake.sql_string(hash) }}
          {% for column in keys %}
          and judged.{{ column }} = pending.{{ column }}
          {% endfor %}
    )
    {% endif %}

),

jevflake_asked as (

    select
        {% for column in keys %}
        {{ column }},
        {% endfor %}
        state_hash,
        {{ jevflake.function_name('jev_ask') }}(jevflake_state, {{ jevflake.json_literal(questions) }}) as response
    from jevflake_pending

)

select
    {% for column in keys %}
    asked.{{ column }},
    {% endfor %}
    answers.key::varchar as question,
    answers.value:type::varchar as answer_type,
    answers.value:noul::float as noul,
    answers.value:choice::varchar as choice,
    answers.value:score::float as score,
    answers.value:confidence::float as confidence,
    answers.value:probabilities as probabilities,
    answers.value:error::varchar as error,
    answers.value as answer,
    answers.value:model::varchar as model,
    asked.state_hash,
    {{ jevflake.sql_string(hash) }}::varchar as questions_hash,
    sysdate() as judged_at
from jevflake_asked as asked,
    lateral flatten(input => asked.response:answers) as answers

{% endmacro %}


{% macro review_queue(relation, noul_low=0.2, noul_high=0.8, min_confidence=0.5) %}

select *
from {{ relation }}
where answer_type = 'error'
   or (answer_type = 'noul' and noul > {{ noul_low }} and noul < {{ noul_high }})
   or (answer_type in ('choice', 'score') and confidence < {{ min_confidence }})

{% endmacro %}
