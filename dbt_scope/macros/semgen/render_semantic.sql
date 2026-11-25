{#
    Renders one star of the semantic definition as the target platform's
    native object body (design 03, D5):
      snowflake  -> TABLES / RELATIONSHIPS / DIMENSIONS / METRICS clauses,
                    passed through by the dbt_semantic_view package
      databricks -> metric view YAML (version 1.1), wrapped by dbt-databricks

    The calling model must ref() every table in the star, so dbt knows the
    dependencies at parse time; this is checked here.
#}
{% macro render_semantic(semantic_model_name) %}
    {%- if not execute -%}{{ return('') }}{%- endif -%}
    {%- set cat = semantic_catalog(semantic_model_name) -%}
    {%- set missing = [] -%}
    {%- for t in cat.tables if t.unique_id not in model.depends_on.nodes -%}
        {%- do missing.append(t.model) -%}
    {%- endfor -%}
    {%- if missing -%}
        {{ exceptions.raise_compiler_error(
            "semgen: model '" ~ model.name ~ "' must ref() " ~ missing | join(', ') ~ " (the tables in '" ~ semantic_model_name ~ "')") }}
    {%- endif -%}
    {{ return(adapter.dispatch('render_semantic', 'retail')(cat)) }}
{% endmacro %}

{% macro default__render_semantic(cat) %}
    {{ exceptions.raise_compiler_error("semgen: no semantic layer on target type '" ~ target.type ~ "' (design 02, R8)") }}
{% endmacro %}


{#- Shared expression pieces. Weeks start Monday on all engines; ::DATE
    because DATE_TRUNC returns TIMESTAMP on Databricks and DuckDB (S2, F6). -#}
{% macro semgen_dimension_expr(dim, qualifier) %}
    {%- set col = (qualifier ~ '.' if qualifier else '') ~ dim.column -%}
    {%- if dim.grain -%}
        DATE_TRUNC('{{ dim.grain | upper }}', {{ col }})::DATE
    {%- else -%}
        {{ col }}
    {%- endif -%}
{% endmacro %}

{% macro semgen_aggregate(agg, col) %}
    {%- if agg == 'sum' -%} SUM({{ col }})
    {%- elif agg == 'count' -%} COUNT({{ col }})
    {%- elif agg == 'count_distinct' -%} COUNT(DISTINCT {{ col }})
    {%- endif -%}
{% endmacro %}

{% macro semgen_sql_string(text) -%}
    '{{ (text or '') | trim | replace('\n', ' ') | replace("'", "''") }}'
{%- endmacro %}


{% macro snowflake__render_semantic(cat) %}
{%- set fact = cat.tables | selectattr('is_fact') | first %}
TABLES (
{%- for t in cat.tables %}
  {{ t.alias }} AS {{ ref(t.model) }} PRIMARY KEY ({{ t.primary_key }}){{ ',' if not loop.last }}
{%- endfor %}
)
RELATIONSHIPS (
{%- for r in cat.relationships %}
  {{ r.from_alias }} ({{ r.from_column }}) REFERENCES {{ r.to_alias }}{{ ',' if not loop.last }}
{%- endfor %}
)
DIMENSIONS (
{%- for d in cat.dimensions %}
  {{ d.table }}.{{ d.name }} AS {{ semgen_dimension_expr(d, none) }}
    {%- if d.synonyms %} WITH SYNONYMS = ({% for s in d.synonyms %}{{ semgen_sql_string(s) }}{{ ', ' if not loop.last }}{% endfor %}){% endif %}
    {%- if d.description %} COMMENT = {{ semgen_sql_string(d.description) }}{% endif %}{{ ',' if not loop.last }}
{%- endfor %}
)
METRICS (
{%- for m in cat.metrics %}
  {{ fact.alias }}.{{ m.name }} AS
    {%- if m.kind == 'simple' %} {{ semgen_aggregate(m.agg, fact.alias ~ '.' ~ m.column) }}
    {%- else %} {{ fact.alias }}.{{ m.numerator }} / NULLIF({{ fact.alias }}.{{ m.denominator }}, 0)
    {%- endif %}
    {%- if m.synonyms %} WITH SYNONYMS = ({% for s in m.synonyms %}{{ semgen_sql_string(s) }}{{ ', ' if not loop.last }}{% endfor %}){% endif %}
    {%- if m.description %} COMMENT = {{ semgen_sql_string(m.description) }}{% endif %}{{ ',' if not loop.last }}
{%- endfor %}
)
COMMENT = {{ semgen_sql_string(cat.description) }}
{%- if cat.instructions %}
AI_SQL_GENERATION {{ semgen_sql_string(cat.instructions) }}
{%- endif %}
{% endmacro %}


{#- YAML scalars are double-quoted with backslashes and quotes escaped.
    Relations are left bare; dbt-databricks quotes their backticks. -#}
{% macro semgen_yaml_string(text) -%}
    "{{ (text or '') | trim | replace('\n', ' ') | replace('\\', '\\\\') | replace('"', '\\"') }}"
{%- endmacro %}

{% macro semgen_yaml_list(items) -%}
    [{% for i in items %}{{ semgen_yaml_string(i) }}{{ ', ' if not loop.last }}{% endfor %}]
{%- endmacro %}

{% macro databricks__render_semantic(cat) %}
{%- set fact = cat.tables | selectattr('is_fact') | first %}
version: 1.1
comment: {{ semgen_yaml_string(cat.description) }}
source: {{ ref(fact.model) }}
joins:
{%- for r in cat.relationships %}
{%- set t = cat.tables | selectattr('alias', 'equalto', r.to_alias) | first %}
  - name: {{ t.alias }}
    source: {{ ref(t.model) }}
    on: {{ semgen_yaml_string('source.' ~ r.from_column ~ ' = ' ~ t.alias ~ '.' ~ t.primary_key) }}
{%- endfor %}
dimensions:
{%- for d in cat.dimensions %}
  - name: {{ d.name }}
    expr: {{ semgen_yaml_string(semgen_dimension_expr(d, none if d.table == fact.alias else d.table)) }}
    {%- if d.description %}
    comment: {{ semgen_yaml_string(d.description) }}
    {%- endif %}
    {%- if d.synonyms %}
    synonyms: {{ semgen_yaml_list(d.synonyms) }}
    {%- endif %}
{%- endfor %}
measures:
{%- for m in cat.metrics %}
  - name: {{ m.name }}
    {%- if m.kind == 'simple' %}
    expr: {{ semgen_yaml_string(semgen_aggregate(m.agg, m.column)) }}
    {%- else %}
    expr: {{ semgen_yaml_string('MEASURE(' ~ m.numerator ~ ') / NULLIF(MEASURE(' ~ m.denominator ~ '), 0)') }}
    {%- endif %}
    {%- if m.description %}
    comment: {{ semgen_yaml_string(m.description) }}
    {%- endif %}
    {%- if m.synonyms %}
    synonyms: {{ semgen_yaml_list(m.synonyms) }}
    {%- endif %}
{%- endfor %}
{% endmacro %}
