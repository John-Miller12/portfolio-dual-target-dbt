{#
    Salted, deterministic, one-way pseudonym for an identifier column
    (02A section 3): sha2(salt || ':' || value, 256) as 64-char hex.

    DuckDB: salt from the PII_SALT env var, with a fixed dev fallback. Local,
    synthetic data only.
    Snowflake / Databricks: call governance.pseudonymize(), a warehouse
    function created by bootstrap() that holds the salt, so the salt never
    appears in compiled SQL (02A section 4). Any other target raises, so it
    can never silently pass raw IDs through.
#}
{% macro pseudonymize(column) %}
    {{ return(adapter.dispatch('pseudonymize', 'retail')(column)) }}
{% endmacro %}

{% macro default__pseudonymize(column) %}
    {{ exceptions.raise_compiler_error(
        "pseudonymize() is not implemented for target type '" ~ target.type ~ "' (02A section 3)"
    ) }}
{% endmacro %}

{% macro duckdb__pseudonymize(column) %}
    {%- set salt = env_var('PII_SALT', 'dev-only-salt-not-secret') | replace("'", "''") -%}
    sha256('{{ salt }}' || ':' || {{ column }})
{%- endmacro %}

{% macro snowflake__pseudonymize(column) %}
    {{ target.database }}.governance.pseudonymize({{ column }})
{%- endmacro %}

{% macro databricks__pseudonymize(column) %}
    {{ target.database }}.governance.pseudonymize({{ column }})
{%- endmacro %}
