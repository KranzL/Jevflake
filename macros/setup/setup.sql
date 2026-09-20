{% macro setup(grant_to=[], dry_run=false) %}
  {% set statements = jevflake.network_statements([], grant_to) + jevflake.function_statements(grant_to) %}
  {% do jevflake.apply_statements(statements, dry_run) %}
{% endmacro %}


{% macro setup_network(grant_to=[], callers=[], dry_run=false) %}
  {% do jevflake.apply_statements(jevflake.network_statements(grant_to, callers), dry_run) %}
{% endmacro %}


{% macro setup_functions(grant_to=[], dry_run=false) %}
  {% do jevflake.apply_statements(jevflake.function_statements(grant_to), dry_run) %}
{% endmacro %}


{% macro teardown(dry_run=false) %}
  {% set statements = [] %}
  {% for signature in jevflake.function_signatures() | reverse %}
    {% do statements.append('drop function if exists ' ~ signature) %}
  {% endfor %}
  {% do statements.append('drop integration if exists ' ~ jevflake.integration_name()) %}
  {% do statements.append('drop network rule if exists ' ~ jevflake.network_rule_name()) %}
  {% do jevflake.apply_statements(statements, dry_run) %}
{% endmacro %}


{% macro apply_statements(statements, dry_run) %}
  {% for statement in statements %}
    {% if dry_run %}
      {{ print(statement ~ ';\n') }}
    {% else %}
      {% do run_query(statement) %}
      {{ log('jevflake: ' ~ statement.split('\n')[0], info=true) }}
    {% endif %}
  {% endfor %}
{% endmacro %}


{% macro network_statements(grant_to, callers=[]) %}
  {% set statements = [] %}
  {% do statements.append('create schema if not exists ' ~ jevflake.namespace()) %}
  {% do statements.append(
    'create network rule if not exists ' ~ jevflake.network_rule_name() ~ '\n'
    ~ "  mode = egress\n"
    ~ "  type = host_port\n"
    ~ "  value_list = ('api.typesafe.ai:443')"
  ) %}
  {% do statements.append(
    'create or replace external access integration ' ~ jevflake.integration_name() ~ '\n'
    ~ '  allowed_network_rules = (' ~ jevflake.network_rule_name() ~ ')\n'
    ~ '  allowed_authentication_secrets = (' ~ jevflake.secret_name() ~ ')\n'
    ~ '  enabled = true'
  ) %}
  {% for role in grant_to %}
    {% do statements.append('grant usage on integration ' ~ jevflake.integration_name() ~ ' to role ' ~ role) %}
    {% do statements.append('grant read on secret ' ~ jevflake.secret_name() ~ ' to role ' ~ role) %}
    {% do statements.append('grant usage on schema ' ~ jevflake.namespace() ~ ' to role ' ~ role) %}
    {% do statements.append('grant create function on schema ' ~ jevflake.namespace() ~ ' to role ' ~ role) %}
  {% endfor %}
  {% for role in callers %}
    {% do statements.append('grant usage on schema ' ~ jevflake.namespace() ~ ' to role ' ~ role) %}
  {% endfor %}
  {{ return(statements) }}
{% endmacro %}


{% macro function_statements(grant_to) %}
  {% set ask_json = jevflake.function_name('jev_ask_json') %}
  {% set ask = jevflake.function_name('jev_ask') %}
  {% set statements = [] %}

  {% do statements.append(
    'create or replace function ' ~ ask_json ~ '(state varchar, questions varchar)\n'
    ~ 'returns varchar\n'
    ~ 'language python\n'
    ~ "runtime_version = '" ~ var('jevflake_python_version', '3.11') ~ "'\n"
    ~ "packages = ('pandas', 'requests')\n"
    ~ 'external_access_integrations = (' ~ jevflake.integration_name() ~ ')\n'
    ~ "secrets = ('api_key' = " ~ jevflake.secret_name() ~ ')\n'
    ~ "handler = 'ask'\n"
    ~ 'as\n$$' ~ jevflake.handler_source() ~ '$$'
  ) %}

  {% for state_type in ['variant', 'varchar'] %}
    {% set state = 'state' if state_type == 'variant' else 'to_variant(state)' %}

    {% do statements.append(
      'create or replace function ' ~ ask ~ '(state ' ~ state_type ~ ', questions variant)\n'
      ~ 'returns variant\n'
      ~ 'as\n$$\n'
      ~ 'parse_json(' ~ ask_json ~ '(to_json(' ~ state ~ '), to_json(questions)))\n'
      ~ '$$'
    ) %}

    {% do statements.append(
      'create or replace function ' ~ jevflake.function_name('jev_noul') ~ '(state ' ~ state_type ~ ', instructions varchar)\n'
      ~ 'returns float\n'
      ~ 'as\n$$\n'
      ~ ask ~ '(' ~ state ~ ", to_variant(object_construct('answer', object_construct('type', 'noul', 'instructions', instructions)))):answers:answer:noul::float\n"
      ~ '$$'
    ) %}

    {% do statements.append(
      'create or replace function ' ~ jevflake.function_name('jev_noul') ~ '(state ' ~ state_type ~ ', instructions varchar, criteria variant)\n'
      ~ 'returns float\n'
      ~ 'as\n$$\n'
      ~ ask ~ '(' ~ state ~ ", to_variant(object_construct('answer', object_construct('type', 'noul', 'instructions', instructions, 'criteria', criteria)))):answers:answer:noul::float\n"
      ~ '$$'
    ) %}

    {% for kind in ['choice', 'score'] %}
      {% do statements.append(
        'create or replace function ' ~ jevflake.function_name('jev_' ~ kind) ~ '(state ' ~ state_type ~ ', instructions varchar, criteria variant)\n'
        ~ 'returns variant\n'
        ~ 'as\n$$\n'
        ~ ask ~ '(' ~ state ~ ", to_variant(object_construct('answer', object_construct('type', '" ~ kind ~ "', 'instructions', instructions, 'criteria', criteria)))):answers:answer\n"
        ~ '$$'
      ) %}
    {% endfor %}
  {% endfor %}

  {% for role in grant_to %}
    {% for signature in jevflake.function_signatures() %}
      {% do statements.append('grant usage on function ' ~ signature ~ ' to role ' ~ role) %}
    {% endfor %}
  {% endfor %}

  {{ return(statements) }}
{% endmacro %}
