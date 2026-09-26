{% macro setup(grant_to=[], dry_run=false, preserve_grants=true) %}
  {% do jevflake.apply_statements(jevflake.network_statements([], grant_to), dry_run) %}
  {% set roles = jevflake.resolve_function_roles(grant_to, dry_run, preserve_grants) %}
  {% do jevflake.apply_statements(jevflake.function_statements(roles), dry_run) %}
{% endmacro %}


{% macro setup_network(grant_to=[], callers=[], dry_run=false) %}
  {% do jevflake.apply_statements(jevflake.network_statements(grant_to, callers), dry_run) %}
{% endmacro %}


{% macro setup_functions(grant_to=[], dry_run=false, preserve_grants=true) %}
  {% set roles = jevflake.resolve_function_roles(grant_to, dry_run, preserve_grants) %}
  {% do jevflake.apply_statements(jevflake.function_statements(roles), dry_run) %}
{% endmacro %}


{% macro resolve_function_roles(grant_to, dry_run, preserve_grants) %}
  {% set roles = grant_to | list %}
  {% if preserve_grants and not dry_run %}
    {% for role in jevflake.current_function_roles() %}
      {% if role | upper not in roles | map('upper') | list %}
        {% do roles.append(role) %}
      {% endif %}
    {% endfor %}
    {% if roles | length > grant_to | length %}
      {{ log('jevflake: keeping grants for roles from the previous install: ' ~ roles | join(', '), info=true) }}
    {% endif %}
  {% endif %}
  {{ return(roles) }}
{% endmacro %}


{% macro functions_exist() %}
  {% do run_query("show functions like 'JEV\\_ASK\\_JSON' in schema " ~ jevflake.namespace()) %}
  {% set probe = run_query("select count(*) from table(result_scan(last_query_id())) where name = 'JEV_ASK_JSON'") %}
  {{ return(probe.rows | length > 0 and probe.rows[0][0] > 0) }}
{% endmacro %}


{% macro function_roles() %}
  {% do run_query('show grants on function ' ~ jevflake.function_name('jev_ask_json') ~ '(varchar, varchar)') %}
  {% set grants = run_query("select distinct grantee_name from table(result_scan(last_query_id())) where granted_to = 'ROLE' and privilege = 'USAGE'") %}
  {% set roles = [] %}
  {% for row in grants.rows %}
    {% do roles.append(row[0]) %}
  {% endfor %}
  {{ return(roles) }}
{% endmacro %}


{% macro current_function_roles() %}
  {% if jevflake.functions_exist() %}
    {{ return(jevflake.function_roles()) }}
  {% endif %}
  {{ return([]) }}
{% endmacro %}


{% macro check_grants(grant_to=[], dry_run=false) %}
  {% for role in grant_to %}
    {% do jevflake.assert_identifier(role, 'role') %}
  {% endfor %}
  {% if dry_run %}
    {{ print("show functions like 'JEV\\_ASK\\_JSON' in schema " ~ jevflake.namespace() ~ ';\n') }}
    {{ print('show grants on function ' ~ jevflake.function_name('jev_ask_json') ~ '(varchar, varchar);\n') }}
  {% else %}
    {% if not jevflake.functions_exist() %}
      {{ exceptions.raise_compiler_error('jevflake: no functions found in ' ~ jevflake.namespace() ~ '. Run jevflake.setup first.') }}
    {% endif %}
    {% set actual = jevflake.function_roles() %}
    {% set upper_actual = actual | map('upper') | list %}
    {% set missing = [] %}
    {% for role in grant_to %}
      {% if role | upper not in upper_actual %}
        {% do missing.append(role) %}
      {% endif %}
    {% endfor %}
    {% if missing | length > 0 %}
      {{ exceptions.raise_compiler_error('jevflake: these roles cannot use the functions: ' ~ missing | join(', ')) }}
    {% endif %}
    {% set upper_expected = grant_to | map('upper') | list %}
    {% set extra = [] %}
    {% for role in actual %}
      {% if role | upper not in upper_expected %}
        {% do extra.append(role) %}
      {% endif %}
    {% endfor %}
    {% if extra | length > 0 %}
      {{ log('jevflake: these roles also have access: ' ~ extra | join(', '), info=true) }}
    {% endif %}
    {{ log('jevflake: all ' ~ grant_to | length ~ ' expected roles can use the functions', info=true) }}
  {% endif %}
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
    {% do jevflake.assert_identifier(role, 'role') %}
    {% do statements.append('grant usage on integration ' ~ jevflake.integration_name() ~ ' to role ' ~ role) %}
    {% do statements.append('grant read on secret ' ~ jevflake.secret_name() ~ ' to role ' ~ role) %}
    {% do statements.append('grant usage on schema ' ~ jevflake.namespace() ~ ' to role ' ~ role) %}
    {% do statements.append('grant create function on schema ' ~ jevflake.namespace() ~ ' to role ' ~ role) %}
  {% endfor %}
  {% for role in callers %}
    {% do jevflake.assert_identifier(role, 'role') %}
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
    {% do jevflake.assert_identifier(role, 'role') %}
    {% for signature in jevflake.function_signatures() %}
      {% do statements.append('grant usage on function ' ~ signature ~ ' to role ' ~ role) %}
    {% endfor %}
  {% endfor %}

  {{ return(statements) }}
{% endmacro %}
