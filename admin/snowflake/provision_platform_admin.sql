-- One-time account setup that genuinely needs ACCOUNTADMIN (design 02A section 5).
-- Run in a Snowsight worksheet, signed in with password + MFA, with "Run All".
-- Not a dbt macro: Snowflake blocks ACCOUNTADMIN from dbt's browser (OAuth)
-- sign-in, and we keep that block (02A revision 7).
--
-- Creates the scoped PLATFORM_ADMIN role and hands it everything bootstrap()
-- needs, so ACCOUNTADMIN isn't used again. Every statement is idempotent, so a
-- rerun is safe. The warehouse is X-Small (1 credit per running hour); the
-- monitor caps it at 10 credits a month. It doesn't cap Cortex Analyst.

use role ACCOUNTADMIN;
set me = current_user();

-- The scoped admin role, in the standard hierarchy, granted to you.
create role if not exists PLATFORM_ADMIN
    comment = 'Scoped admin for bootstrap and daily admin work (02A section 5)';
grant role PLATFORM_ADMIN to role SYSADMIN;
grant role PLATFORM_ADMIN to user identifier($me);

-- Account privileges bootstrap() needs. Deliberately no MANAGE GRANTS (02A section 5).
grant create database on account to role PLATFORM_ADMIN;
grant create role on account to role PLATFORM_ADMIN;
grant create user on account to role PLATFORM_ADMIN;

-- Warehouse with a monthly credit cap, then handed to PLATFORM_ADMIN.
create resource monitor if not exists RETAIL_WH_MONITOR
    with credit_quota = 10
    frequency = monthly
    start_timestamp = immediately
    triggers on 80 percent do notify
             on 100 percent do suspend
             on 110 percent do suspend_immediate;
create warehouse if not exists RETAIL_WH
    warehouse_size = xsmall
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true;
alter warehouse RETAIL_WH set resource_monitor = RETAIL_WH_MONITOR;
grant ownership on warehouse RETAIL_WH to role PLATFORM_ADMIN copy current grants;

-- Cortex Analyst isn't hosted in AWS ca-central-1; let it run in a US region.
-- Data stays stored in Canada (02A section 5, design 03 H10).
alter account set cortex_enabled_cross_region = 'AWS_US';

-- Checks. Expect one row for the integration dbt's browser sign-in uses (03 V11),
-- and no MANAGE GRANTS in PLATFORM_ADMIN's grants (02A section 8).
show security integrations like 'SNOWFLAKE$LOCAL_APPLICATION';
show grants to role PLATFORM_ADMIN;
