{% macro sql_string(value) %}
  {{ return("'" ~ (value | string | replace("\\", "\\\\") | replace("'", "''")) ~ "'") }}
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
      {% do pairs.append(jevflake.sql_string(column) ~ ', ' ~ column) %}
    {% endfor %}
  {% endif %}
  {% if pairs | length == 0 %}
    {{ exceptions.raise_compiler_error('jevflake: state needs a SQL expression, a list of columns, or a mapping of labels to expressions') }}
  {% endif %}
  {{ return('to_variant(object_construct_keep_null(' ~ pairs | join(', ') ~ '))') }}
{% endmacro %}
