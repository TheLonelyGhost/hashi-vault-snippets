#!/usr/bin/env uv run
# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "httpx",
# ]
# ///

import argparse
import asyncio
import logging
import os
import pathlib

import httpx

log = logging.getLogger(__name__)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Configure an STS role for each listed AWS account number on Vault's AWS auth method"
    )
    parser.add_argument(
        "--fqdn",
        action="store",
        dest="vault_fqdn",
        help="Vault's fully-qualified domain name",
    )
    parser.add_argument(
        "-f",
        "--accounts-manifest",
        action="store",
        dest="accounts_manifest",
        help="Path to a file containing a line-delimited list of AWS account numbers",
    )
    parser.add_argument(
        "-m",
        "--auth-mount",
        action="store",
        dest="auth_mount",
        default="auth/aws",
        help="Path in Vault (including 'auth/') to the location where the AWS auth method is configured",
    )
    parser.add_argument(
        "-r",
        "--iam-role-name",
        action="store",
        dest="iam_role_name",
        default="VaultAuth",
        help="Target AWS account's IAM Role name (without the 'role/' prefix)",
    )

    return parser.parse_args()


async def setup_sts_role(
    http: httpx.AsyncClient,
    account_num: str,
    external_id: str,
    role_name: str = "VaultAuth",
    mount_path: str = "auth/aws",
):
    sts_role = f"arn:aws:iam::{account_num}:role/{role_name}"
    out = await http.get(f"/{mount_path}/config/sts/{account_num}")
    if out.status_code != 404:
        obj = out.raise_for_status().json()["data"]
        if obj["sts_role"] == sts_role and obj["external_id"] == external_id:
            log.info(f"Already configured for {account_num!r}")
            return

    (
        await http.post(
            f"/{mount_path}/config/sts/{account_num}",
            json={
                "sts_role": sts_role,
                "external_id": external_id,
            },
        )
    ).raise_for_status()


async def main() -> None:
    args = parse_args()
    if not args.vault_fqdn:
        raise ValueError
    if not args.accounts_manifest:
        raise ValueError
    if not args.auth_mount:
        raise ValueError
    if not args.iam_role_name:
        raise ValueError

    manifest = pathlib.Path(args.accounts_manifest)
    if not manifest.exists():
        raise ValueError

    client_args = {
        "base_url": f"{os.environ['VAULT_ADDR']}/v1",
        "headers": {
            "Accept": "application/json",
            "X-Vault-Token": os.environ["VAULT_TOKEN"],
        },
    }

    results = []

    async with httpx.AsyncClient(**client_args) as http:
        with manifest.open("r") as f:
            for account_num in f.readlines():
                account_num = account_num.strip()
                if not account_num:
                    continue

                results.append(
                    setup_sts_role(
                        http,
                        account_num,
                        args.vault_fqdn,
                        role_name=args.iam_role_name,
                        mount_path=args.auth_mount,
                    )
                )

    await asyncio.gather(*results)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
    asyncio.run(main())
