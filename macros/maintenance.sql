{% macro prune_statements(judgments, relation, key, questions) %}
  {% set keys = [key] if key is string else key %}
  {% if keys | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: prune needs at least one key column') }}
  {% endif %}
  {% for column in keys %}
    {% do jevflake.assert_identifier(column, 'key column') %}
  {% endfor %}
  {% if judgments is string %}
    {% do jevflake.assert_dotted_name(judgments, 'judgments table') %}
  {% endif %}
  {% if relation is string %}
    {% do jevflake.assert_dotted_name(relation, 'source table') %}
  {% endif %}
  {% set names = questions.keys() | list if questions is mapping else questions %}
  {% if names | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: prune needs at least one current question name') }}
  {% endif %}
  {% set quoted = [] %}
  {% for name in names %}
    {% do quoted.append(jevflake.sql_string(name)) %}
  {% endfor %}
  {% set statements = [] %}
  {% do statements.append(
    'delete from ' ~ judgments ~ '\n'
    ~ 'where question not in (' ~ quoted | join(', ') ~ ')'
  ) %}
  {% set matches = [] %}
  {% for column in keys %}
    {% do matches.append('source.' ~ column ~ ' = judged.' ~ column) %}
  {% endfor %}
  {% do statements.append(
    'delete from ' ~ judgments ~ ' as judged\n'
    ~ 'where not exists (\n'
    ~ '    select 1\n'
    ~ '    from ' ~ relation ~ ' as source\n'
    ~ '    where ' ~ matches | join('\n      and ') ~ '\n'
    ~ ')'
  ) %}
  {{ return(statements) }}
{% endmacro %}


{% macro prune_orphans(judgments, relation, key, questions, dry_run=false) %}
  {% do jevflake.apply_statements(jevflake.prune_statements(judgments, relation, key, questions), dry_run) %}
{% endmacro %}
