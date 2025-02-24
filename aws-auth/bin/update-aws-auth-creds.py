#!/usr/bin/env -S uv run --script --native-tls
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

import httpx

log = logging.getLogger(__name__)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Configure Vault's AWS auth method with an IAM User account"
    )
    parser.add_argument(
        "--access-key",
        action="store",
        dest="access_key",
    )
    parser.add_argument(
        "--secret-key",
        action="store",
        dest="secret_key",
    )
    parser.add_argument(
        "-m",
        "--auth-mount",
        action="store",
        dest="auth_mount",
        default="auth/aws",
        help="Path in Vault (including 'auth/') to the location where the AWS auth method is configured",
    )
    return parser.parse_args()


async def main() -> None:
    args = parse_args()
    if not args.access_key:
        raise ValueError
    if not args.secret_key:
        raise ValueError
    if not args.auth_mount:
        raise ValueError

    client_args = {
        "base_url": f"{os.environ['VAULT_ADDR']}/v1",
        "headers": {
            "Accept": "application/json",
            "X-Vault-Token": os.environ["VAULT_TOKEN"],
        },
    }

    with httpx.Client(**client_args) as http:
        http.post(
            f"/{args.auth_mount}/config/client",
            json={
                "access_key": args.access_key,
                "secret_key": args.secret_key,
            },
        ).raise_for_status()
        log.info("Updated AWS client with new, user-supplied access keys")

        http.post(f"/{args.auth_mount}/config/rotate-root").raise_for_status()
        log.info(
            "Rotated user-supplied access keys for zero-knowledge AWS client credentials"
        )


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
    asyncio.run(main())
