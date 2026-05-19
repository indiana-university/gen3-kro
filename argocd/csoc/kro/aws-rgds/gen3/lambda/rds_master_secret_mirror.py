import json
import logging
import os

import boto3
from botocore.exceptions import ClientError


LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


def _required_env(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def _resource_not_found(error):
    return error.response.get("Error", {}).get("Code") == "ResourceNotFoundException"


def _waiting(reason, **metadata):
    LOG.info("Mirror sync waiting: %s", reason, extra={"metadata": metadata})
    return {"status": "waiting", "reason": reason, **metadata}


def _load_source_secret(secretsmanager, source_secret_arn):
    response = secretsmanager.get_secret_value(SecretId=source_secret_arn)
    secret_string = response.get("SecretString")
    if not secret_string:
        raise ValueError("RDS managed secret did not contain SecretString JSON")

    source = json.loads(secret_string)
    if not source.get("password"):
        raise ValueError("RDS managed secret JSON did not contain password")
    return source


def _mirror_payload(cluster, source_secret):
    payload = {
        "username": source_secret.get("username") or cluster.get("MasterUsername"),
        "password": source_secret["password"],
        "host": cluster.get("Endpoint"),
        "port": str(cluster.get("Port") or "5432"),
    }

    optional_fields = {
        "engine": cluster.get("Engine"),
        "dbname": cluster.get("DatabaseName") or source_secret.get("dbname"),
        "dbClusterIdentifier": cluster.get("DBClusterIdentifier"),
    }
    payload.update({key: value for key, value in optional_fields.items() if value})

    for key in ("username", "password", "host", "port"):
        if not payload.get(key):
            raise ValueError(f"Mirror payload is missing required key: {key}")
    return payload


def _ensure_mirror_secret(secretsmanager, mirror_name, mirror_string, kms_key_id, tags):
    try:
        description = secretsmanager.describe_secret(SecretId=mirror_name)
        if description.get("DeletedDate"):
            secretsmanager.restore_secret(SecretId=mirror_name)
            LOG.info("Restored mirror secret scheduled for deletion: %s", mirror_name)

        if kms_key_id:
            secretsmanager.update_secret(SecretId=mirror_name, KmsKeyId=kms_key_id)

        secretsmanager.put_secret_value(SecretId=mirror_name, SecretString=mirror_string)
        action = "updated"
    except ClientError as error:
        if not _resource_not_found(error):
            raise

        create_args = {
            "Name": mirror_name,
            "Description": "Gen3-compatible mirror of the RDS-managed Aurora master credential.",
            "SecretString": mirror_string,
            "Tags": tags,
        }
        if kms_key_id:
            create_args["KmsKeyId"] = kms_key_id

        try:
            secretsmanager.create_secret(**create_args)
            action = "created"
        except ClientError as create_error:
            if create_error.response.get("Error", {}).get("Code") != "ResourceExistsException":
                raise
            secretsmanager.put_secret_value(SecretId=mirror_name, SecretString=mirror_string)
            action = "updated"

    secretsmanager.tag_resource(SecretId=mirror_name, Tags=tags)
    return action


def handler(event, context):
    region = _required_env("AWS_REGION")
    cluster_identifier = _required_env("DB_CLUSTER_IDENTIFIER")
    mirror_name = _required_env("MIRROR_SECRET_NAME")
    kms_key_id = os.environ.get("MIRROR_SECRET_KMS_KEY_ID", "").strip()

    rds = boto3.client("rds", region_name=region)
    secretsmanager = boto3.client("secretsmanager", region_name=region)

    clusters = rds.describe_db_clusters(DBClusterIdentifier=cluster_identifier)["DBClusters"]
    if not clusters:
        return _waiting("cluster-not-found", db_cluster_identifier=cluster_identifier)

    cluster = clusters[0]
    cluster_status = cluster.get("Status")
    if cluster_status != "available":
        return _waiting(
            "cluster-not-available",
            db_cluster_identifier=cluster_identifier,
            cluster_status=cluster_status,
        )

    source_secret = cluster.get("MasterUserSecret") or {}
    source_secret_arn = source_secret.get("SecretArn")
    source_secret_status = source_secret.get("SecretStatus")
    if not source_secret_arn:
        return _waiting("source-secret-missing", db_cluster_identifier=cluster_identifier)
    if source_secret_status != "active":
        return _waiting(
            "source-secret-not-active",
            db_cluster_identifier=cluster_identifier,
            source_secret_status=source_secret_status,
        )
    if not cluster.get("Endpoint"):
        return _waiting("cluster-endpoint-missing", db_cluster_identifier=cluster_identifier)

    source_value = _load_source_secret(secretsmanager, source_secret_arn)
    mirror_value = _mirror_payload(cluster, source_value)
    mirror_string = json.dumps(mirror_value, sort_keys=True, separators=(",", ":"))

    tags = [
        {"Key": "ManagedBy", "Value": "Gen3KRO"},
        {"Key": "gen3.io/secret-purpose", "Value": "aurora-master-password-mirror"},
        {"Key": "gen3.io/source-secret-arn", "Value": source_secret_arn},
        {"Key": "gen3.io/mirror-ready", "Value": "true"},
    ]
    action = _ensure_mirror_secret(
        secretsmanager=secretsmanager,
        mirror_name=mirror_name,
        mirror_string=mirror_string,
        kms_key_id=kms_key_id,
        tags=tags,
    )

    LOG.info(
        "Mirror secret %s for cluster %s",
        action,
        cluster_identifier,
        extra={
            "metadata": {
                "mirror_secret_name": mirror_name,
                "db_cluster_identifier": cluster_identifier,
                "source_secret_arn": source_secret_arn,
            }
        },
    )
    return {
        "status": action,
        "mirror_secret_name": mirror_name,
        "db_cluster_identifier": cluster_identifier,
        "source_secret_arn": source_secret_arn,
    }
