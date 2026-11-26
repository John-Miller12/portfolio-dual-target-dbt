{#
    Post-hook for semantic models: grant SELECT on this object to the reader
    role only (02A section 6, control 2).

    DuckDB has no roles, so it is a no-op. Snowflake: SELECT on the semantic
    view, which is all READER needs to query it. Databricks: design 03, turn 4.
    The default raises so a semantic model can't be built on a warehouse
    without its grant being defined.
#}
{% macro grant_reader() %}
    {{ return(adapter.dispatch('grant_reader', 'retail')()) }}
{% endmacro %}

{% macro default__grant_reader() %}
    {{ exceptions.raise_compiler_error(
        "grant_reader() is not implemented for target type '" ~ target.type ~ "' (02A section 6)"
    ) }}
{% endmacro %}

{% macro duckdb__grant_reader() %}{% endmacro %}

{% macro snowflake__grant_reader() %}
    grant select on semantic view {{ this }} to role READER
{%- endmacro %}
