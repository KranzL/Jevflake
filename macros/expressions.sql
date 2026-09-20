{% macro ask(state, questions) %}
  {{ return(jevflake.function_name('jev_ask') ~ '(' ~ jevflake.state_expression(state) ~ ', ' ~ jevflake.json_literal(questions) ~ ')') }}
{% endmacro %}


{% macro noul(state, instructions, criteria=none) %}
  {% set questions = {'answer': jevflake.noul_question(instructions, criteria)} %}
  {{ return('(' ~ jevflake.ask(state, questions) ~ ':answers:answer:noul::float)') }}
{% endmacro %}


{% macro choice(state, instructions, criteria) %}
  {% set questions = {'answer': jevflake.choice_question(instructions, criteria)} %}
  {{ return('(' ~ jevflake.ask(state, questions) ~ ':answers:answer:choice::varchar)') }}
{% endmacro %}


{% macro score(state, instructions, criteria) %}
  {% set questions = {'answer': jevflake.score_question(instructions, criteria)} %}
  {{ return('(' ~ jevflake.ask(state, questions) ~ ':answers:answer:score::float)') }}
{% endmacro %}
