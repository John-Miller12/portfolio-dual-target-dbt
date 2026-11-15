{#
    Use a node's custom schema exactly as written, on every target
    (design 01, D4; design 02, B7). dbt's default would prefix it with the
    target schema, turning `raw` into `main_raw`.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
