{#
    Creates the project's database objects, runtime roles, service users,
    grants and the salted pseudonymize() function (02A sections 4-6).
    Run as PLATFORM_ADMIN. Idempotent, so a rerun is safe.

        read -s SALT          # from your password manager; not exported
        dbt --log-level-file none run-operation bootstrap --no-write-json \
            --target snowflake_admin --args "{salt: $SALT}"
            # prints the statements only (dry_run defaults to true)
        ... --args "{salt: $SALT, dry_run: false}"

    The two flags keep the salt out of logs/dbt.log and
    target/run_results.json (02A section 4); the macro refuses to run without
    them. Its own log lines show the salt as <redacted>. The guard stops the
    SQL from being logged, but dbt has already written --args by the time it
    fires: if you ever run without the flags, delete dbt_scope/logs/dbt.log
    and dbt_scope/target/run_results.json.

    Arguments:
      salt             64 lowercase hex characters (openssl rand -hex 32)
      svc_pipeline_key RSA public key for SVC_PIPELINE (body only, no
                       BEGIN/END lines). User skipped if not given.
      svc_mcp_key      the same for SVC_MCP
      dry_run          log the statements without running them (default true)
      database         default RETAIL
      warehouse        default RETAIL_WH (created by provisioning)
#}
{% macro bootstrap(salt, svc_pipeline_key=none, svc_mcp_key=none, dry_run=true, database='RETAIL', warehouse='RETAIL_WH') %}
    {%- set args = invocation_args_dict -%}
    {%- if (args.get('log_level_file') | string | lower) != 'none' or args.get('write_json', true) -%}
        {{ exceptions.raise_compiler_error(
            "bootstrap() takes the salt, so dbt must not write it to disk. Run as: "
            ~ "dbt --log-level-file none run-operation bootstrap --no-write-json ... (02A section 4)") }}
    {%- endif -%}
    {%- if not modules.re.fullmatch('[0-9a-f]{64}', salt | string) -%}
        {{ exceptions.raise_compiler_error("bootstrap(): salt must be 64 lowercase hex characters (openssl rand -hex 32)") }}
    {%- endif -%}
    {%- for key in [svc_pipeline_key, svc_mcp_key] if key is not none -%}
        {%- if not modules.re.fullmatch('[A-Za-z0-9+/=]+', key | string) -%}
            {{ exceptions.raise_compiler_error("bootstrap(): a service-user key must be the public key body only: base64, no BEGIN/END lines or line breaks") }}
        {%- endif -%}
    {%- endfor -%}
    {{ return(adapter.dispatch('bootstrap', 'retail')(salt, svc_pipeline_key, svc_mcp_key, dry_run, database, warehouse)) }}
{% endmacro %}

{% macro default__bootstrap(salt, svc_pipeline_key, svc_mcp_key, dry_run, database, warehouse) %}
    {{ exceptions.raise_compiler_error(
        "bootstrap() is not implemented for target type '" ~ target.type ~ "' (02A section 5)") }}
{% endmacro %}

{% macro snowflake__bootstrap(salt, svc_pipeline_key, svc_mcp_key, dry_run, database, warehouse) %}
    {%- if target.role | upper != 'PLATFORM_ADMIN' -%}
        {{ exceptions.raise_compiler_error(
            "bootstrap must run as PLATFORM_ADMIN (--target snowflake_admin); this target uses " ~ target.role) }}
    {%- endif -%}
    {%- set db = database -%}
    {%- set fn = db ~ '.governance.pseudonymize' -%}
    {%- set runtime_roles = ['LOADER', 'TRANSFORMER', 'READER'] -%}
    {%- set s = [] -%}

    {#- Database and schemas, owned by PLATFORM_ADMIN. -#}
    {%- do s.append("create database if not exists " ~ db) -%}
    {%- for schema in ['raw', 'staging', 'marts', 'semantic', 'governance'] -%}
        {%- do s.append("create schema if not exists " ~ db ~ "." ~ schema) -%}
    {%- endfor -%}

    {#- Runtime roles, kept under PLATFORM_ADMIN. All three use the warehouse and database. -#}
    {%- for role in runtime_roles -%}
        {%- do s.append("create role if not exists " ~ role ~ " comment = 'Runtime role (02A section 6)'") -%}
        {%- do s.append("grant role " ~ role ~ " to role PLATFORM_ADMIN") -%}
        {%- do s.append("grant usage on warehouse " ~ warehouse ~ " to role " ~ role) -%}
        {%- do s.append("grant usage on database " ~ db ~ " to role " ~ role) -%}
    {%- endfor -%}

    {#- LOADER: dlt writes raw and owns those tables. -#}
    {%- do s.append("grant usage, create table on schema " ~ db ~ ".raw to role LOADER") -%}

    {#- TRANSFORMER: reads raw (and seeds into it), builds staging, marts and semantic. -#}
    {%- do s.append("grant usage, create table on schema " ~ db ~ ".raw to role TRANSFORMER") -%}
    {%- do s.append("grant select on all tables in schema " ~ db ~ ".raw to role TRANSFORMER") -%}
    {%- do s.append("grant select on future tables in schema " ~ db ~ ".raw to role TRANSFORMER") -%}
    {%- for schema in ['staging', 'marts', 'semantic'] -%}
        {%- do s.append("grant usage, create table, create view on schema " ~ db ~ "." ~ schema ~ " to role TRANSFORMER") -%}
    {%- endfor -%}
    {%- do s.append("grant create semantic view on schema " ~ db ~ ".semantic to role TRANSFORMER") -%}
    {%- do s.append("grant usage on schema " ~ db ~ ".governance to role TRANSFORMER") -%}

    {#- READER: the semantic schema only. SELECT comes per view from grant_reader() (02A section 6). -#}
    {%- do s.append("grant usage on schema " ~ db ~ ".semantic to role READER") -%}

    {#- The salted function (02A section 4). IF NOT EXISTS: no silent salt rotation. -#}
    {%- set salt_marker = '__SALT__' -%}
    {%- do s.append("create secure function if not exists " ~ fn ~ "(value varchar) returns varchar"
        ~ " comment = 'Salted SHA-256 pseudonym (02A section 3)'"
        ~ " as $$ sha2('" ~ salt_marker ~ "' || ':' || value, 256) $$") -%}
    {%- do s.append("grant usage on function " ~ fn ~ "(varchar) to role TRANSFORMER") -%}

    {#- Service users, key pairs only, created when their key is given. -#}
    {%- set users = [
        ('SVC_PIPELINE', svc_pipeline_key, 'TRANSFORMER', ['TRANSFORMER', 'LOADER']),
        ('SVC_MCP', svc_mcp_key, 'READER', ['READER']),
    ] -%}
    {%- for name, key, default_role, roles in users if key is not none -%}
        {%- do s.append("create user if not exists " ~ name ~ " type = service default_role = " ~ default_role
            ~ " default_warehouse = " ~ warehouse ~ " comment = 'Service user (02A section 6)'") -%}
        {%- do s.append("alter user " ~ name ~ " set rsa_public_key = '" ~ key ~ "'") -%}
        {%- for role in roles -%}
            {%- do s.append("grant role " ~ role ~ " to user " ~ name) -%}
        {%- endfor -%}
    {%- endfor -%}

    {%- do log("bootstrap: " ~ ("DRY RUN, nothing executed" if dry_run else "executing") ~ " as " ~ target.user ~ " / " ~ target.role, info=true) -%}
    {%- for user, key in [('SVC_PIPELINE', svc_pipeline_key), ('SVC_MCP', svc_mcp_key)] if key is none -%}
        {%- do log("  (" ~ user ~ " skipped: no public key given)", info=true) -%}
    {%- endfor -%}
    {%- for sql in s -%}
        {%- do log("  [" ~ loop.index ~ "/" ~ s | length ~ "] " ~ sql | replace(salt_marker, '<redacted>') ~ ";", info=true) -%}
        {%- if not dry_run -%}
            {%- do run_query(sql | replace(salt_marker, salt)) -%}
        {%- endif -%}
    {%- endfor -%}
    {%- do log("bootstrap: done" ~ (". Rerun with dry_run: false in --args to apply." if dry_run else "."), info=true) -%}
{% endmacro %}
