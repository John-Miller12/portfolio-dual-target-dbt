{#
    Reads one star from the dbt semantic definition (graph) into a neutral
    catalog that both platform renderers use (design 03, D3-D6):

      tables         [{alias, model, unique_id, primary_key, is_fact}]
      relationships  [{from_alias, from_column, to_alias}]
      dimensions     [{name, table, column, grain, description, synonyms}]
      description    semantic model meta.description, else the fact's
      instructions   semantic model meta.ai_instructions
      metrics        [{name, kind, agg, column, numerator, denominator,
                       description, synonyms}]

    Logical-table aliases are entity names, so MetricFlow's customer__region
    is Snowflake's customer.region and Databricks' region (S1).

    Checks (S1-S3). All failures are collected and raised together:
      - names are unique snake_case across dimensions and metrics
      - metrics are simple (sum, count, count_distinct) or a ratio of two
        simple metrics, with no filters
      - every metric expr and dimension is a column documented on its model
      - each joined entity has exactly one semantic model with it as primary

    Returns none at parse time, when the graph isn't populated.
#}
{% macro semantic_catalog(semantic_model_name) %}
    {%- if not execute -%}{{ return(none) }}{%- endif -%}

    {%- set errors = [] -%}
    {%- set grains = ['week', 'month', 'quarter', 'year'] -%}
    {%- set aggs = {'sum': 'sum', 'count': 'count', 'count_distinct': 'count_distinct'} -%}

    {#- Index semantic models by name and by primary entity. -#}
    {%- set by_name = {} -%}
    {%- set by_primary = {} -%}
    {%- for sm in graph.semantic_models.values() -%}
        {%- do by_name.update({sm.name: sm}) -%}
        {%- for e in sm.entities if e.type == 'primary' -%}
            {%- do by_primary.setdefault(e.name, []).append(sm) -%}
        {%- endfor -%}
    {%- endfor -%}

    {%- if semantic_model_name not in by_name -%}
        {{ exceptions.raise_compiler_error("semgen: no semantic model named '" ~ semantic_model_name ~ "'") }}
    {%- endif -%}
    {%- set fact = by_name[semantic_model_name] -%}

    {%- set tables = [] -%}
    {%- set relationships = [] -%}
    {%- set dimensions = [] -%}
    {%- set metrics = [] -%}

    {#- One table per semantic model: the fact, then each joined entity. -#}
    {%- set members = [{'sm': fact, 'is_fact': true}] -%}
    {%- for e in fact.entities if e.type == 'foreign' -%}
        {%- set candidates = by_primary.get(e.name, []) -%}
        {%- if candidates | length != 1 -%}
            {%- do errors.append("entity '" ~ e.name ~ "' must be the primary entity of exactly one semantic model, found " ~ candidates | length) -%}
        {%- else -%}
            {%- do members.append({'sm': candidates[0], 'is_fact': false}) -%}
            {%- set fact_alias = (fact.entities | selectattr('type', 'equalto', 'primary') | first).name -%}
            {%- do relationships.append({'from_alias': fact_alias, 'from_column': e.expr or e.name, 'to_alias': e.name}) -%}
        {%- endif -%}
    {%- endfor -%}

    {%- for member in members -%}
        {%- set sm = member.sm -%}
        {%- set node = graph.nodes[sm.depends_on.nodes[0]] -%}
        {%- set documented = node.columns.keys() | list -%}
        {%- set pk = sm.entities | selectattr('type', 'equalto', 'primary') | first -%}
        {%- do tables.append({
            'alias': pk.name, 'model': node.name, 'unique_id': node.unique_id,
            'primary_key': pk.expr or pk.name, 'is_fact': member.is_fact,
            'description': node.description}) -%}

        {%- for d in sm.dimensions -%}
            {%- set column = d.expr or d.name -%}
            {%- if column not in documented -%}
                {%- do errors.append("dimension '" ~ d.name ~ "': column '" ~ column ~ "' is not documented on " ~ node.name) -%}
            {%- endif -%}
            {%- set col_doc = node.columns.get(column, {}) -%}
            {%- set meta = (d.config or {}).get('meta', {}) -%}
            {%- set dim = {
                'name': d.name, 'table': pk.name, 'column': column, 'grain': none,
                'description': d.description or col_doc.get('description', ''),
                'synonyms': meta.get('synonyms', [])} -%}
            {%- do dimensions.append(dim) -%}
            {%- if d.type == 'time' -%}
                {#- S2: grains as named dimensions; order_date -> order_month. -#}
                {%- set stem = d.name[:-5] if d.name.endswith('_date') else d.name -%}
                {%- for g in grains -%}
                    {%- do dimensions.append({
                        'name': stem ~ '_' ~ g, 'table': pk.name, 'column': column, 'grain': g,
                        'description': dim.description ~ ' Truncated to the ' ~ g ~ (' (weeks start Monday).' if g == 'week' else '.'),
                        'synonyms': []}) -%}
                {%- endfor -%}
            {%- endif -%}
        {%- endfor -%}
    {%- endfor -%}

    {#- Metrics: simple metrics on the fact, then ratios of those. -#}
    {%- set fact_node = graph.nodes[fact.depends_on.nodes[0]] -%}
    {%- set fact_meta = (fact.config or {}).get('meta', {}) -%}
    {%- set simple_names = [] -%}
    {%- set ratios = [] -%}
    {%- for m in graph.metrics.values() -%}
        {%- set params = m.type_params -%}
        {%- set agg_params = params.metric_aggregation_params or {} -%}
        {%- set meta = (m.config or {}).get('meta', {}) -%}
        {%- if m.type == 'simple' and agg_params.get('semantic_model') == fact.name -%}
            {%- set agg = agg_params.get('agg') -%}
            {%- if agg not in aggs -%}
                {%- do errors.append("metric '" ~ m.name ~ "': aggregation '" ~ agg ~ "' is not supported (S3: sum, count, count_distinct)") -%}
            {%- endif -%}
            {%- if m.filter -%}
                {%- do errors.append("metric '" ~ m.name ~ "': filters are not supported (S3); make the logic a mart column") -%}
            {%- endif -%}
            {%- if params.expr not in fact_node.columns -%}
                {%- do errors.append("metric '" ~ m.name ~ "': expr '" ~ params.expr ~ "' is not a column documented on " ~ fact_node.name) -%}
            {%- endif -%}
            {%- do simple_names.append(m.name) -%}
            {%- do metrics.append({
                'name': m.name, 'kind': 'simple', 'agg': agg, 'column': params.expr,
                'numerator': none, 'denominator': none,
                'description': m.description, 'synonyms': meta.get('synonyms', [])}) -%}
        {%- elif m.type == 'ratio' -%}
            {%- do ratios.append(m) -%}
        {%- elif agg_params.get('semantic_model') == fact.name -%}
            {%- do errors.append("metric '" ~ m.name ~ "': type '" ~ m.type ~ "' is not supported (S3)") -%}
        {%- endif -%}
    {%- endfor -%}
    {%- for m in ratios -%}
        {%- set num = m.type_params.numerator -%}
        {%- set den = m.type_params.denominator -%}
        {%- if num.name in simple_names or den.name in simple_names -%}
            {%- if num.name not in simple_names or den.name not in simple_names -%}
                {%- do errors.append("metric '" ~ m.name ~ "': a ratio's inputs must both be simple metrics of '" ~ fact.name ~ "' (S3)") -%}
            {%- endif -%}
            {%- if num.filter or den.filter -%}
                {%- do errors.append("metric '" ~ m.name ~ "': filtered ratio inputs are not supported (S3)") -%}
            {%- endif -%}
            {%- set meta = (m.config or {}).get('meta', {}) -%}
            {%- do metrics.append({
                'name': m.name, 'kind': 'ratio', 'agg': none, 'column': none,
                'numerator': num.name, 'denominator': den.name,
                'description': m.description, 'synonyms': meta.get('synonyms', [])}) -%}
        {%- endif -%}
    {%- endfor -%}

    {#- S1: unique snake_case names across dimensions and metrics. -#}
    {%- set seen = [] -%}
    {%- for item in dimensions + metrics -%}
        {%- if not modules.re.match('^[a-z][a-z0-9_]*$', item.name) -%}
            {%- do errors.append("'" ~ item.name ~ "' is not snake_case (S1)") -%}
        {%- endif -%}
        {%- if item.name in seen -%}
            {%- do errors.append("name '" ~ item.name ~ "' is used more than once (S1)") -%}
        {%- endif -%}
        {%- do seen.append(item.name) -%}
    {%- endfor -%}

    {%- if errors -%}
        {{ exceptions.raise_compiler_error(
            "semgen: semantic model '" ~ semantic_model_name ~ "' failed " ~ errors | length ~ " check(s):\n  - "
            ~ errors | join("\n  - ")) }}
    {%- endif -%}

    {{ return({
        'name': fact.name,
        'description': fact_meta.get('description') or fact_node.description,
        'instructions': fact_meta.get('ai_instructions', ''),
        'tables': tables,
        'relationships': relationships,
        'dimensions': dimensions,
        'metrics': metrics}) }}
{% endmacro %}
