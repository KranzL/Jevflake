{% macro database_name() %}
  {{ return(var('jevflake_database', target.database)) }}
{% endmacro %}


{% macro schema_name() %}
  {{ return(var('jevflake_schema', 'jevflake')) }}
{% endmacro %}


{% macro namespace() %}
  {{ return(jevflake.database_name() ~ '.' ~ jevflake.schema_name()) }}
{% endmacro %}


{% macro function_name(name) %}
  {{ return(jevflake.namespace() ~ '.' ~ name) }}
{% endmacro %}


{% macro secret_name() %}
  {{ return(var('jevflake_secret', jevflake.namespace() ~ '.jev_api_key')) }}
{% endmacro %}


{% macro network_rule_name() %}
  {{ return(jevflake.namespace() ~ '.' ~ var('jevflake_network_rule', 'jev_egress')) }}
{% endmacro %}


{% macro integration_name() %}
  {{ return(var('jevflake_integration', 'jev_access')) }}
{% endmacro %}


{% macro model_name() %}
  {{ return(var('jevflake_model', 'jev-1.13.0')) }}
{% endmacro %}


{% macro function_signatures() %}
  {% set signatures = [jevflake.function_name('jev_ask_json') ~ '(varchar, varchar)'] %}
  {% for state_type in ['variant', 'varchar'] %}
    {% do signatures.append(jevflake.function_name('jev_ask') ~ '(' ~ state_type ~ ', variant)') %}
    {% do signatures.append(jevflake.function_name('jev_noul') ~ '(' ~ state_type ~ ', varchar)') %}
    {% do signatures.append(jevflake.function_name('jev_noul') ~ '(' ~ state_type ~ ', varchar, variant)') %}
    {% do signatures.append(jevflake.function_name('jev_choice') ~ '(' ~ state_type ~ ', varchar, variant)') %}
    {% do signatures.append(jevflake.function_name('jev_score') ~ '(' ~ state_type ~ ', varchar, variant)') %}
  {% endfor %}
  {{ return(signatures) }}
{% endmacro %}
