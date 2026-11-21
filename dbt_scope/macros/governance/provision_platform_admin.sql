{#
    One-time account setup that genuinely needs ACCOUNTADMIN (02A section 5).
    Creates the scoped PLATFORM_ADMIN role and hands it everything bootstrap()
    needs, so ACCOUNTADMIN isn't used again.

        dbt run-operation provision_platform_admin --target snowflake_provision
            # prints the statements only (dry_run defaults to true)
        dbt run-operation provision_platform_admin --target snowflake_provision \
            --args '{dry_run: false}'

    Every statement is idempotent, so a rerun is safe.
    Arguments:
      dry_run         log the statements without running them (default true)
      warehouse       warehouse to create and hand over (default RETAIL_WH)
      monthly_credits resource monitor quota; X-Small uses 1 credit per hour
                      while running (default 10)
#}
{% macro provision_platform_admin(dry_run=true, warehouse='RETAIL_WH', monthly_credits=10) %}
    {{ return(adapter.dispatch('provision_platform_admin', 'retail')(dry_run, warehouse, monthly_credits)) }}
{% endmacro %}

{% macro default__provision_platform_admin(dry_run, warehouse, monthly_credits) %}
    {{ exceptions.raise_compiler_error(
        "provision_platform_admin() is not implemented for target type '" ~ target.type ~ "' (02A section 5)") }}
{% endmacro %}

{% macro snowflake__provision_platform_admin(dry_run, warehouse, monthly_credits) %}
    {%- if target.role | upper != 'ACCOUNTADMIN' -%}
        {{ exceptions.raise_compiler_error(
            "provision_platform_admin must run as ACCOUNTADMIN (--target snowflake_provision); this target uses " ~ target.role) }}
    {%- endif -%}
    {%- set monitor = warehouse ~ '_MONITOR' -%}
    {%- set statements = [
        "create role if not exists PLATFORM_ADMIN comment = 'Scoped admin for bootstrap and daily admin work (02A section 5)'",
        "grant role PLATFORM_ADMIN to role SYSADMIN",
        "grant role PLATFORM_ADMIN to user " ~ target.user,
        "grant create database on account to role PLATFORM_ADMIN",
        "grant create role on account to role PLATFORM_ADMIN",
        "grant create user on account to role PLATFORM_ADMIN",
        "create resource monitor if not exists " ~ monitor
            ~ " with credit_quota = " ~ monthly_credits
            ~ " frequency = monthly start_timestamp = immediately"
            ~ " triggers on 80 percent do notify on 100 percent do suspend on 110 percent do suspend_immediate",
        "create warehouse if not exists " ~ warehouse
            ~ " warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true",
        "alter warehouse " ~ warehouse ~ " set resource_monitor = " ~ monitor,
        "grant ownership on warehouse " ~ warehouse ~ " to role PLATFORM_ADMIN copy current grants",
        "alter account set cortex_enabled_cross_region = 'AWS_US'",
    ] -%}

    {%- do log("provision_platform_admin: " ~ ("DRY RUN, nothing executed" if dry_run else "executing") ~ " as " ~ target.user ~ " / " ~ target.role, info=true) -%}
    {%- for sql in statements -%}
        {%- do log("  [" ~ loop.index ~ "/" ~ statements | length ~ "] " ~ sql ~ ";", info=true) -%}
        {%- if not dry_run -%}
            {%- do run_query(sql) -%}
        {%- endif -%}
    {%- endfor -%}
    {%- do log("provision_platform_admin: done" ~ (". Rerun with --args '{dry_run: false}' to apply." if dry_run else "."), info=true) -%}
{% endmacro %}
