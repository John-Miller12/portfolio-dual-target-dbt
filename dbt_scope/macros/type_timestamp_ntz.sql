{#
    A timestamp without time zone, on every target (design 02, R7).
    Databricks' plain TIMESTAMP carries a session time zone, so it gets the
    explicit NTZ type; DuckDB's TIMESTAMP is already zone-less.
#}
{% macro type_timestamp_ntz() %}
    {{ return(adapter.dispatch('type_timestamp_ntz', 'retail')()) }}
{% endmacro %}

{% macro default__type_timestamp_ntz() %}timestamp{% endmacro %}

{% macro snowflake__type_timestamp_ntz() %}timestamp_ntz{% endmacro %}

{% macro databricks__type_timestamp_ntz() %}timestamp_ntz{% endmacro %}
