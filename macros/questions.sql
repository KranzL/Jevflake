{% macro noul_question(instructions, criteria=none) %}
  {% set question = {'type': 'noul', 'instructions': instructions} %}
  {% if criteria is not none %}
    {% do question.update({'criteria': criteria}) %}
  {% endif %}
  {{ return(question) }}
{% endmacro %}


{% macro choice_question(instructions, criteria) %}
  {% if criteria is mapping %}
    {% set options = criteria %}
  {% else %}
    {% set options = {} %}
    {% for option in criteria %}
      {% do options.update({option: option}) %}
    {% endfor %}
  {% endif %}
  {% if options | length < 2 %}
    {{ exceptions.raise_compiler_error('jevflake: a choice question needs at least two options') }}
  {% endif %}
  {{ return({'type': 'choice', 'instructions': instructions, 'criteria': options}) }}
{% endmacro %}


{% macro score_question(instructions, criteria) %}
  {% if criteria is string or criteria is mapping or criteria | length < 2 %}
    {{ exceptions.raise_compiler_error('jevflake: a score question needs an ordered list of at least two levels') }}
  {% endif %}
  {{ return({'type': 'score', 'instructions': instructions, 'criteria': criteria}) }}
{% endmacro %}
