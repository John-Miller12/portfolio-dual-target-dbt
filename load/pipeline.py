"""Load data/raw/*.csv into the `raw` schema of one target (design 01).

    uv run python load/pipeline.py duckdb|snowflake|databricks

Everything table-specific comes from load/tables.yml. After the load, each
table is checked against its CSV: row count, and exact SUM for any declared
checksum columns. Any mismatch exits non-zero.
"""

import argparse
import csv
import os
import sys
from decimal import Decimal
from pathlib import Path

import dlt
import yaml
from dlt.common.normalizers.naming.snake_case import NamingConvention
from dlt.sources.filesystem import filesystem, read_csv

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "raw"
CONTRACT = yaml.safe_load((ROOT / "load" / "tables.yml").read_text())
DUCKDB_PATH = ROOT / ".local" / "dev.duckdb"


def read_source(spec: dict) -> tuple[list[str], list[dict]]:
    """Read a CSV as dlt will see it: BOM stripped, headers snake_cased."""
    naming = NamingConvention()
    with open(DATA / spec["file"], encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = [naming.normalize_identifier(h) for h in next(reader)]
        rows = [dict(zip(header, r)) for r in reader]
    return header, rows


def check_header(table: str, spec: dict, header: list[str]) -> None:
    """Fail before loading if the CSV columns differ from the contract."""
    if header != list(spec["columns"]):
        sys.exit(f"{table}: CSV columns {header} != contract {list(spec['columns'])}")


def resource(table: str, spec: dict):
    # dtype=str + keep_default_na=False: pandas passes every value through as
    # text (no float rounding, and 'None' stays the string 'None'). dlt then
    # coerces each value to the type declared in the contract.
    pipe = filesystem(bucket_url=DATA.as_uri(), file_glob=spec["file"]) | read_csv(
        encoding="utf-8-sig", dtype=str, keep_default_na=False
    )
    pipe.apply_hints(
        table_name=table,
        columns=spec["columns"],
        primary_key=spec["primary_key"],
        write_disposition="replace",
        # A value that cannot be coerced to its declared type would create a
        # new "variant" column; freezing columns and types turns that into a
        # load failure instead.
        schema_contract={"columns": "freeze", "data_type": "freeze"},
    )
    return pipe.with_name(table)


def verify(pipeline, table: str, spec: dict, rows: list[dict]) -> list[str]:
    """Compare row count and checksum SUMs between the CSV and the target."""
    expected = {"row_count": Decimal(len(rows))}
    for col in spec.get("checksums", []):
        expected[col] = sum(Decimal(r[col]) for r in rows)

    selects = ["count(*)"] + [f"sum({c})" for c in spec.get("checksums", [])]
    with pipeline.sql_client() as client:
        qualified = client.make_qualified_table_name(table)
        result = client.execute_sql(f"select {', '.join(selects)} from {qualified}")[0]
    actual = {k: Decimal(str(v)) for k, v in zip(expected, result)}

    failures = []
    for k in expected:
        status = "ok" if expected[k] == actual[k] else "MISMATCH"
        print(f"  {table}.{k}: csv={expected[k]} target={actual[k]} {status}")
        if status != "ok":
            failures.append(f"{table}.{k}")
    return failures


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", choices=["duckdb", "snowflake", "databricks"])
    target = parser.parse_args().target

    if target == "duckdb":
        DUCKDB_PATH.parent.mkdir(exist_ok=True)
        destination = dlt.destinations.duckdb(credentials=str(DUCKDB_PATH))
    elif target == "snowflake":
        # You, as LOADER, through the same browser sign-in and env vars as
        # dbt (02A sections 5-6). No secret is stored. CI's key-pair loader
        # comes in phase 4.
        destination = dlt.destinations.snowflake(
            credentials={
                "host": os.environ["SNOWFLAKE_ACCOUNT"],
                "username": os.environ["SNOWFLAKE_USER"],
                "authenticator": "oauth_authorization_code",
                "role": "LOADER",
                "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "RETAIL_WH"),
                "database": os.environ.get("SNOWFLAKE_DATABASE", "RETAIL"),
            }
        )
    else:
        destination = target  # credentials from env vars / .dlt/secrets.toml

    sources = {}
    for table, spec in CONTRACT.items():
        header, rows = read_source(spec)
        check_header(table, spec, header)
        sources[table] = rows

    pipeline = dlt.pipeline(
        pipeline_name=f"retail_{target}", destination=destination, dataset_name="raw"
    )
    # A failed run leaves its package pending, and dlt would retry it instead
    # of extracting fresh data. Every run is a full reload from the CSVs, so
    # leftovers are always stale: discard them.
    pipeline.drop_pending_packages()
    print(pipeline.run([resource(t, s) for t, s in CONTRACT.items()]))

    print("Verifying against CSV:")
    failures = []
    for table, spec in CONTRACT.items():
        failures += verify(pipeline, table, spec, sources[table])
    if failures:
        sys.exit(f"Verification failed: {', '.join(failures)}")
    print("All checks passed.")


if __name__ == "__main__":
    main()
