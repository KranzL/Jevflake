create schema if not exists ANALYTICS.jevflake;
create network rule if not exists ANALYTICS.jevflake.jev_egress
  mode = egress
  type = host_port
  value_list = ('api.typesafe.ai:443');
create or replace external access integration jev_access
  allowed_network_rules = (ANALYTICS.jevflake.jev_egress)
  allowed_authentication_secrets = (ANALYTICS.jevflake.jev_api_key)
  enabled = true;
grant usage on integration jev_access to role builder;
grant read on secret ANALYTICS.jevflake.jev_api_key to role builder;
grant usage on schema ANALYTICS.jevflake to role builder;
grant create function on schema ANALYTICS.jevflake to role builder;
grant usage on schema ANALYTICS.jevflake to role caller
