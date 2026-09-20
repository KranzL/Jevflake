{{ config(materialized='view') }}

{{ jevflake.review_queue(ref('ticket_judgments')) }}
