{% macro sql_string(value) %}
  {{ return("'" ~ (value | string | replace("\\", "\\\\") | replace("'", "''")) ~ "'") }}
{% endmacro %}


{% macro assert_identifier(value, label) %}
  {% set first = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_' %}
  {% set rest = first ~ '0123456789' %}
  {% set state = namespace(ok=value is string and value | length > 0 and value[0] in first) %}
  {% if value is string %}
    {% for char in value if state.ok %}
      {% if char not in rest %}
        {% set state.ok = false %}
      {% endif %}
    {% endfor %}
  {% endif %}
  {% if not state.ok %}
    {{ exceptions.raise_compiler_error('jevflake: ' ~ label ~ ' must use only letters, digits, and underscores, starting with a letter or underscore: ' ~ value) }}
  {% endif %}
  {{ return(value) }}
{% endmacro %}


{% macro assert_dotted_name(value, label) %}
  {% if value is not string or value | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: ' ~ label ~ ' must be a dot separated name: ' ~ value) }}
  {% endif %}
  {% for part in value.split('.') %}
    {% do jevflake.assert_identifier(part, label) %}
  {% endfor %}
  {{ return(value) }}
{% endmacro %}


{% macro assert_number(value, label) %}
  {% if value is not number %}
    {{ exceptions.raise_compiler_error('jevflake: ' ~ label ~ ' must be a number: ' ~ value) }}
  {% endif %}
  {{ return(value) }}
{% endmacro %}


{% macro json_literal(value) %}
  {{ return('parse_json(' ~ jevflake.sql_string(tojson(value, sort_keys=true)) ~ ')') }}
{% endmacro %}


{% macro state_expression(state) %}
  {% if state is string %}
    {{ return('to_variant(' ~ state ~ ')') }}
  {% endif %}
  {% set pairs = [] %}
  {% if state is mapping %}
    {% for label, expression in state.items() %}
      {% do pairs.append(jevflake.sql_string(label) ~ ', ' ~ expression) %}
    {% endfor %}
  {% else %}
    {% for column in state %}
      {% do jevflake.assert_identifier(column, 'state column') %}
      {% do pairs.append(jevflake.sql_string(column) ~ ', ' ~ column) %}
    {% endfor %}
  {% endif %}
  {% if pairs | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: state needs a SQL expression, a list of columns, or a mapping of labels to expressions') }}
  {% endif %}
  {{ return('to_variant(object_construct_keep_null(' ~ pairs | join(', ') ~ '))') }}
{% endmacro %}


{% macro state_not_null_predicate(state) %}
  {% if state is string %}
    {{ return('(' ~ state ~ ' is not null)') }}
  {% endif %}
  {% set parts = [] %}
  {% if state is mapping %}
    {% for label, expression in state.items() %}
      {% do parts.append('(' ~ expression ~ ' is not null)') %}
    {% endfor %}
  {% else %}
    {% for column in state %}
      {% do jevflake.assert_identifier(column, 'state column') %}
      {% do parts.append('(' ~ column ~ ' is not null)') %}
    {% endfor %}
  {% endif %}
  {% if parts | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: state needs a SQL expression, a list of columns, or a mapping of labels to expressions') }}
  {% endif %}
  {{ return('(' ~ parts | join(' or ') ~ ')') }}
{% endmacro %}
