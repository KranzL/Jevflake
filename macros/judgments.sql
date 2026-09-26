{% macro questions_hash(questions) %}
  {{ return(local_md5(tojson(questions, sort_keys=true) ~ '|' ~ jevflake.model_name())) }}
{% endmacro %}


{% macro question_hashes(questions) %}
  {% set hashes = {} %}
  {% for name, question in questions.items() %}
    {% do hashes.update({name: local_md5(tojson(question, sort_keys=true) ~ '|' ~ jevflake.model_name())}) %}
  {% endfor %}
  {{ return(hashes) }}
{% endmacro %}


{% macro judgments(relation, key, state, questions) %}
  {% set keys = [key] if key is string else key %}
  {% if keys | length == 0 or questions | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: judgments needs at least one key column and one question') }}
  {% endif %}
  {% for column in keys %}
    {% do jevflake.assert_identifier(column, 'key column') %}
  {% endfor %}
  {% set names = questions.keys() | list %}
  {% set hashes = jevflake.question_hashes(questions) %}
  {% set hash = jevflake.questions_hash(questions) %}
  {% do log('jevflake: judging ' ~ names | length ~ ' questions (' ~ names | join(', ') ~ ') over ' ~ keys | length ~ ' key columns', info=true) %}

with jevflake_source as (

    select
        {% for column in keys %}
        {{ column }},
        {% endfor %}
        {{ jevflake.state_expression(state) }} as jevflake_state
    from {{ relation }}
    where {% for column in keys %}{{ column }} is not null and {% endfor %}{{ jevflake.state_not_null_predicate(state) }}

),

jevflake_hashed as (

    select
        *,
        md5(to_json(jevflake_state)) as state_hash
    from jevflake_source
    where jevflake_state is not null

),

jevflake_fresh as (

    select *
    from jevflake_hashed as fresh
    {% if is_incremental() %}
    where not exists (
        select 1
        from {{ this }} as judged
        where judged.state_hash = fresh.state_hash
          {% for column in keys %}
          and judged.{{ column }} = fresh.{{ column }}
          {% endfor %}
    )
    {% endif %}

),

jevflake_asked_fresh as (

    select
        {% for column in keys %}
        {{ column }},
        {% endfor %}
        state_hash,
        {{ jevflake.function_name('jev_ask') }}(jevflake_state, {{ jevflake.json_literal(questions) }}) as response
    from jevflake_fresh

){% if is_incremental() %}{% for name in names %},

jevflake_stale_{{ loop.index0 }} as (

    select *
    from jevflake_hashed as stale
    where exists (
        select 1
        from {{ this }} as judged
        where judged.state_hash = stale.state_hash
          {% for column in keys %}
          and judged.{{ column }} = stale.{{ column }}
          {% endfor %}
    )
    and not exists (
        select 1
        from {{ this }} as judged
        where judged.state_hash = stale.state_hash
          {% for column in keys %}
          and judged.{{ column }} = stale.{{ column }}
          {% endfor %}
          and judged.question = {{ jevflake.sql_string(name) }}
          and (judged.question_hash = {{ jevflake.sql_string(hashes[name]) }} or (judged.question_hash is null and judged.questions_hash = {{ jevflake.sql_string(hash) }}))
    )

),

jevflake_asked_{{ loop.index0 }} as (

    select
        {% for column in keys %}
        {{ column }},
        {% endfor %}
        state_hash,
        {{ jevflake.function_name('jev_ask') }}(jevflake_state, {{ jevflake.json_literal({name: questions[name]}) }}) as response
    from jevflake_stale_{{ loop.index0 }}

){% endfor %}{% endif %},

jevflake_asked as (

    select * from jevflake_asked_fresh
    {% if is_incremental() %}
    {% for name in names %}
    union all
    select * from jevflake_asked_{{ loop.index0 }}
    {% endfor %}
    {% endif %}

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
    case answers.key::varchar{% for name in names %} when {{ jevflake.sql_string(name) }} then {{ jevflake.sql_string(hashes[name]) }}{% endfor %} end as question_hash,
    {{ jevflake.sql_string(hash) }}::varchar as questions_hash,
    sysdate() as judged_at
from jevflake_asked as asked,
    lateral flatten(input => asked.response:answers) as answers

{% endmacro %}


{% macro review_queue(relation, noul_low=0.2, noul_high=0.8, min_confidence=0.5) %}
{% do jevflake.assert_number(noul_low, 'noul_low') %}
{% do jevflake.assert_number(noul_high, 'noul_high') %}
{% do jevflake.assert_number(min_confidence, 'min_confidence') %}

select *
from {{ relation }}
where answer_type = 'error'
   or (answer_type = 'noul' and noul > {{ noul_low }} and noul < {{ noul_high }})
   or (answer_type in ('choice', 'score') and confidence < {{ min_confidence }})

{% endmacro %}
