{#- The sales star (design 03, D3-D5). The refs declare the star's tables to
    dbt at parse time; render_semantic checks they match the definition. -#}
{%- set star = [ref('fct_order_lines'), ref('dim_customers'), ref('dim_products')] -%}
{{ render_semantic('fct_order_lines') }}
