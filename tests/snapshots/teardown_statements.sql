drop function if exists ANALYTICS.jevflake.jev_score(varchar, varchar, variant);

drop function if exists ANALYTICS.jevflake.jev_choice(varchar, varchar, variant);

drop function if exists ANALYTICS.jevflake.jev_noul(varchar, varchar, variant);

drop function if exists ANALYTICS.jevflake.jev_noul(varchar, varchar);

drop function if exists ANALYTICS.jevflake.jev_ask(varchar, variant);

drop function if exists ANALYTICS.jevflake.jev_score(variant, varchar, variant);

drop function if exists ANALYTICS.jevflake.jev_choice(variant, varchar, variant);

drop function if exists ANALYTICS.jevflake.jev_noul(variant, varchar, variant);

drop function if exists ANALYTICS.jevflake.jev_noul(variant, varchar);

drop function if exists ANALYTICS.jevflake.jev_ask(variant, variant);

drop function if exists ANALYTICS.jevflake.jev_ask_json(varchar, varchar);

drop integration if exists jev_access;

drop network rule if exists ANALYTICS.jevflake.jev_egress;
