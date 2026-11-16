{#
    Salted, deterministic, one-way pseudonym for an identifier column
    (02A section 3): sha2(salt || ':' || value, 256) as 64-char hex.

    DuckDB: salt from the PII_SALT env var, with a fixed dev fallback. Local,
    synthetic data only.
    Snowflake / Databricks: phase 3. They will call governance.pseudonymize(),
    a warehouse function holding the salt, so the salt never appears in
    compiled SQL (02A section 4). Until then the default raises, so an
    unimplemented target can never silently pass raw IDs through.
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
