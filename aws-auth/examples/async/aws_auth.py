import asyncio
import base64
import datetime
import hmac
import json
import os
from hashlib import sha256
from dataclasses import dataclass
from typing import Dict, Tuple

import aioboto3
import aiohttp
from botocore.credentials import Credentials as AwsCreds


_VaultToken = str
_TTL = int

VAULT_ADDR = os.environ["VAULT_ADDR"]
VAULT_AUTH_ROLE = os.environ[
    "VAULT_AUTH_ROLE"
]  # TODO: configure with the named Vault (auth) role configured on Vault's AWS auth mount
VAULT_AUTH_MOUNT = os.environ.get("VAULT_AUTH_MOUNT", "auth/aws")


@dataclass
class HttpRequest:
    """This isn't a full definition of an HTTP request's components, but it will work for our needs for presigned URLs for AWS auth"""

    method: str
    url: str
    headers: Dict[str, str]
    body: str

    def normalize(self) -> "HttpRequest":
        self.calculate_content_length()

        return self

    def calculate_content_length(self) -> None:
        self.headers["Content-Length"] = str(len(self.body.encode("utf-8")))


GetCallerIdentity = HttpRequest(
    method="POST",
    url="https://sts.amazonaws.com/",
    headers={
        "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
        "Host": "sts.amazonaws.com",
    },
    body="Action=GetCallerIdentity&Version=2011-06-15",
).normalize()


@dataclass
class VaultAwsIamAuthBody:
    iam_http_request_method: str
    iam_request_url: str
    iam_request_headers: str
    iam_request_body: str
    role: str


# NOTE: This is a very long and confusing method that encapsulates
def generate_presigned_request(
    creds: AwsCreds, region: str = "us-east-1"
) -> HttpRequest:
    """
    This is a very long and confusing function definition that encapsulates AWS's arcane presigned url
    algorithm, the specification of which has been made publicly available. Best to leave it alone unless
    you really know what you're doing.

    The content uses AWS credentials (access_key, secret_key, and session token if given) to hash some
    values several times. This is all done without network I/O and is unlikely to benefit from async/await
    wrapping. The input and output datatypes have been kept as generic as possible to ensure portability
    between different python-based HTTP clients.

    Credit where due, a majority of this code is directly yanked from the `hvac.aws_utils` module.
    """
    unsigned = HttpRequest(
        method="POST",
        url="https://sts.amazonaws.com/",
        headers={
            # NOTE: to support custom header, uncomment the line below and hardcode the custom header value
            # "X-Vault-AWS-IAM-Server-ID": "",
            "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
            "Host": "sts.amazonaws.com",
        },
        body="Action=GetCallerIdentity&Version=2011-06-15",
    ).normalize()

    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    unsigned.headers["X-Amz-Date"] = timestamp
    if creds.token:
        unsigned.headers["X-Amz-Security-Token"] = creds.token

    # https://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
    canonical_headers = "".join(
        f"{k.lower()}:{unsigned.headers[k]}\n" for k in sorted(unsigned.headers)
    )
    signed_headers = ";".join(k.lower() for k in sorted(unsigned.headers))
    payload_hash = sha256(unsigned.body.encode("utf-8")).hexdigest()
    canonical_request = "\n".join(
        [unsigned.method, "/", "", canonical_headers, signed_headers, payload_hash]
    )

    # https://docs.aws.amazon.com/general/latest/gr/sigv4-create-string-to-sign.html
    algorithm = "AWS4-HMAC-SHA256"
    credential_scope = "/".join([timestamp[0:8], region, "sts", "aws4_request"])
    canonical_request_hash = sha256(canonical_request.encode("utf-8")).hexdigest()
    string_to_sign = "\n".join(
        [algorithm, timestamp, credential_scope, canonical_request_hash]
    )

    # https://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
    key = f"AWS4{creds.secret_key}".encode()
    key = hmac.new(key, timestamp[0:8].encode("utf-8"), sha256).digest()
    key = hmac.new(key, region.encode("utf-8"), sha256).digest()
    key = hmac.new(key, b"sts", sha256).digest()
    key = hmac.new(key, b"aws4_request", sha256).digest()
    signature = hmac.new(key, string_to_sign.encode("utf-8"), sha256).hexdigest()

    authorization = f"{algorithm} Credential={creds.access_key}/{credential_scope}, SignedHeaders={signed_headers}, Signature={signature}"

    unsigned.headers["Authorization"] = authorization

    return unsigned  # NOTE: once we added the `Authorization` header, it became signed


# NOTE: `region` keyword argument must match how Vault server has the AWS auth method
# configured, not the region of where the workload authenticating itself is positioned.
# If unsure, stick with "us-east-1".
async def aws_login(
    http: aiohttp.ClientSession,
    creds: AwsCreds,
    auth_role: str,
    mount_path: str = "auth/aws",
    region: str = "us-east-1",
) -> Tuple[_VaultToken, _TTL]:
    signed = generate_presigned_request(creds, region=region)

    # {'foo': 'bar'} -> {'foo': ['bar']} to accomodate Vault
    headers = json.dumps({k: [signed.headers[k]] for k in signed.headers})
    params = {
        "iam_http_request_method": signed.method,
        "iam_request_url": base64.b64encode(signed.url.encode("utf-8")).decode("utf-8"),
        "iam_request_headers": base64.b64encode(headers.encode("utf-8")).decode(
            "utf-8"
        ),
        "iam_request_body": base64.b64encode(signed.body.encode("utf-8")).decode(
            "utf-8"
        ),
        "role": auth_role,
    }

    async with http.post(
        f"/v1/{mount_path}/login", headers={"Accept": "application/json"}, json=params
    ) as resp:
        resp.raise_for_status()
        data = await resp.json()

        try:
            return (data["auth"]["client_token"], data["auth"]["lease_duration"])
        except Exception as e:
            raise ValueError("Unable to authenticate to Vault") from e


async def main():
    session = aioboto3.Session()
    creds = session.get_credentials()
    if not creds or not creds.access_key or not creds.secret_key:
        raise RuntimeError("Unable to get AWS credentials")

    async with aiohttp.ClientSession(base_url=VAULT_ADDR) as http:
        token, ttl = await aws_login(http, creds, auth_role=VAULT_AUTH_ROLE)

        # NOTE: After `ttl` seconds from time of authentication (now), the given token will
        # expire. Will need to authenticate to Vault again prior to that deadline to ensure
        # continuity of access.
        http.headers["X-Vault-Token"] = token

        # NOTE: Can specify as a header, or prefix every request path with the Vault Namespace. Choose one, not both.
        # http.headers["X-Vault-Namespace"] = os.environ["VAULT_NAMESPACE"]

        # TODO: Whatever you'd like to do with the Vault API
        ...


if __name__ == "__main__":
    asyncio.run(main())
