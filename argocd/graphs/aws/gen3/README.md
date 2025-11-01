# Gen3 ResourceGraphDefinitions (RGDs)

RGD specifications for Gen3 infrastructure on AWS. Deploy these first to register CRDs before creating instances.

## Quick Reference

| RGD | Kind | Purpose | Sync Wave | Dependencies |
|-----|------|---------|-----------|--------------|
| vpc-rgd.yaml | Gen3Vpc | VPC, subnets, IGW, NAT | -1 | None |
| kms-rgd.yaml | Gen3KMS | Encryption keys | -1 | None |
| s3bucket-rgd.yaml | Gen3S3Bucket | S3 buckets | 0 | None |
| sns-rgd.yaml | Gen3SNS | Notification topics | 0 | None |
| sqs-rgd.yaml | Gen3SQS | Message queues | 0 | None |
| secretsmanager-rgd.yaml | Gen3SecretsManager | Secrets storage | 0 | None |
| cloudwatch-logs-rgd.yaml | Gen3CloudWatchLogs | Log groups | 0 | None |
| route53-rgd.yaml | Gen3Route53 | DNS zones | 0 | None |
| rds-rgd.yaml | Gen3RDS | PostgreSQL databases | 1 | VPC |
| aurora-rgd.yaml | Gen3Aurora | Aurora clusters | 1 | VPC |
| elasticache-rgd.yaml | Gen3ElastiCache | Redis/Memcached | 1 | VPC |
| opensearch-rgd.yaml | Gen3OpenSearch | Search domains | 1 | VPC |
| efs-rgd.yaml | Gen3EFS | File systems | 1 | VPC |
| cloudtrail-rgd.yaml | Gen3CloudTrail | Audit logging | 1 | None |
| waf-rgd.yaml | Gen3WAF | Web ACLs | 1 | None |
| eks-rgd.yaml | Gen3EKS | Kubernetes clusters | 2 | VPC |

## Deployment

```bash
# Deploy all RGDs
kubectl apply -f argocd/graphs/aws/gen3/

# Verify
kubectl get rgd -n kro-system | grep gen3
```

## RGD Specifications

### Foundation (Sync Wave: -1)

#### Gen3Vpc

**Parameters**:
- `name` (required): Resource prefix
- `region` (required): AWS region
- `cidr.vpcCidr` (optional): VPC CIDR (default: "10.0.0.0/16")
- `cidr.publicSubnet1Cidr` (optional): Public subnet 1 (default: "10.0.1.0/24")
- `cidr.publicSubnet2Cidr` (optional): Public subnet 2 (default: "10.0.2.0/24")
- `cidr.privateSubnet1Cidr` (optional): Private subnet 1 (default: "10.0.11.0/24")
- `cidr.privateSubnet2Cidr` (optional): Private subnet 2 (default: "10.0.12.0/24")

**Status Exports**:
- `vpcID`, `publicSubnet1ID`, `publicSubnet2ID`, `privateSubnet1ID`, `privateSubnet2ID`
- `internetGatewayID`, `natGateway1ID`, `natGateway2ID`

#### Gen3KMS

**Parameters**:
- `name` (required): Key name
- `region` (required): AWS region
- `description` (optional): Key description
- `enableKeyRotation` (optional): Enable rotation (default: true)

**Status Exports**: `keyARN`, `keyID`, `aliasARN`

### Storage & Messaging (Sync Wave: 0)

#### Gen3S3Bucket

**Parameters**:
- `name` (required): Globally unique bucket name
- `region` (required): AWS region
- `access` (optional): "write" or "read" (default: "write")

**Status Exports**: `s3ARN`, `s3Name`, `s3PolicyARN`

#### Gen3SNS

**Parameters**:
- `name` (required): Topic name
- `region` (required): AWS region
- `displayName` (optional): Display name
- `subscriptions` (optional): Array of subscriptions

**Status Exports**: `topicARN`, `topicName`

#### Gen3SQS

**Parameters**:
- `name` (required): Queue name
- `region` (required): AWS region
- `visibilityTimeout` (optional): Seconds (default: 30)
- `messageRetentionPeriod` (optional): Seconds (default: 345600)
- `fifoQueue` (optional): Boolean (default: false)

**Status Exports**: `queueARN`, `queueURL`, `queueName`

#### Gen3SecretsManager

**Parameters**:
- `name` (required): Secret name
- `region` (required): AWS region
- `description` (optional): Secret description
- `kmsKeyID` (optional): Encryption key ID

**Status Exports**: `secretARN`, `secretName`

#### Gen3CloudWatchLogs

**Parameters**:
- `name` (required): Log group name
- `region` (required): AWS region
- `retentionInDays` (optional): Days (default: 30)
- `kmsKeyID` (optional): Encryption key ID

**Status Exports**: `logGroupARN`, `logGroupName`

#### Gen3Route53

**Parameters**:
- `name` (required): Resource name
- `region` (required): AWS region
- `zoneName` (required): DNS zone (e.g., example.com)
- `privateZone` (optional): Boolean (default: false)
- `vpcID` (optional): VPC for private zone

**Status Exports**: `hostedZoneID`, `hostedZoneARN`, `nameServers`

### Infrastructure Services (Sync Wave: 1)

#### Gen3RDS

**Parameters**:
- `name` (required): Resource prefix
- `region` (required): AWS region
- `vpcID` (required): VPC ID
- `subnetIDs` (required): Subnet IDs array
- `databaseName` (required): Database name
- `engine` (optional): Engine (default: "postgres")
- `engineVersion` (optional): Version (default: "15.4")
- `instanceClass` (optional): Instance type (default: "db.t3.micro")
- `allocatedStorage` (optional): GB (default: 20)

**Status Exports**: `dbInstanceARN`, `dbInstanceID`, `endpoint`, `port`, `subnetGroupName`

#### Gen3Aurora

**Parameters**:
- `name` (required): Resource prefix
- `region` (required): AWS region
- `vpcID` (required): VPC ID
- `subnetIDs` (required): Subnet IDs array
- `databaseName` (required): Database name
- `engine` (optional): Engine (default: "aurora-postgresql")
- `engineVersion` (optional): Version (default: "15.4")
- `instanceClass` (optional): Instance type (default: "db.r5.large")
- `instanceCount` (optional): Instances (default: 2)

**Status Exports**: `clusterARN`, `clusterID`, `clusterEndpoint`, `readerEndpoint`, `port`

#### Gen3ElastiCache

**Parameters**:
- `name` (required): Resource prefix
- `region` (required): AWS region
- `vpcID` (required): VPC ID
- `subnetIDs` (required): Subnet IDs array
- `engine` (optional): "redis" or "memcached" (default: "redis")
- `engineVersion` (optional): Version (default: "7.0")
- `nodeType` (optional): Instance type (default: "cache.t3.micro")
- `numCacheNodes` (optional): Nodes (default: 1)

**Status Exports**: `cacheClusterARN`, `cacheClusterID`, `endpoint`, `port`, `subnetGroupName`

#### Gen3OpenSearch

**Parameters**:
- `name` (required): Resource prefix
- `region` (required): AWS region
- `vpcID` (required): VPC ID
- `subnetIDs` (required): Subnet IDs array (1 for single-AZ, 2+ for multi-AZ)
- `engineVersion` (optional): Version (default: "OpenSearch_2.11")
- `instanceType` (optional): Instance type (default: "t3.small.search")
- `instanceCount` (optional): Instances (default: 1)
- `volumeSize` (optional): GB (default: 10)

**Status Exports**: `domainARN`, `domainName`, `endpoint`, `kibanaEndpoint`

#### Gen3EFS

**Parameters**:
- `name` (required): Resource prefix
- `region` (required): AWS region
- `vpcID` (required): VPC ID
- `subnetIDs` (required): Subnet IDs array
- `performanceMode` (optional): Mode (default: "generalPurpose")
- `throughputMode` (optional): Mode (default: "bursting")
- `encrypted` (optional): Boolean (default: true)
- `kmsKeyID` (optional): Encryption key ID

**Status Exports**: `fileSystemARN`, `fileSystemID`, `mountTargetIDs`

#### Gen3CloudTrail

**Parameters**:
- `name` (required): Trail name
- `region` (required): AWS region
- `s3BucketName` (required): Log bucket
- `includeGlobalServiceEvents` (optional): Boolean (default: true)
- `isMultiRegionTrail` (optional): Boolean (default: true)
- `enableLogFileValidation` (optional): Boolean (default: true)

**Status Exports**: `trailARN`, `trailName`

#### Gen3WAF

**Parameters**:
- `name` (required): Web ACL name
- `region` (required): AWS region
- `scope` (optional): "REGIONAL" or "CLOUDFRONT" (default: "REGIONAL")
- `defaultAction` (optional): "ALLOW" or "BLOCK" (default: "ALLOW")

**Status Exports**: `webACLARN`, `webACLID`, `webACLName`

### Compute (Sync Wave: 2)

#### Gen3EKS

**Parameters**:
- `name` (required): Resource prefix
- `region` (required): AWS region
- `vpcID` (required): VPC ID
- `subnetIDs` (required): Subnet IDs array
- `version` (optional): K8s version (default: "1.28")
- `nodeGroupInstanceTypes` (optional): Instance types (default: ["t3.medium"])
- `nodeGroupDesiredSize` (optional): Nodes (default: 2)
- `nodeGroupMinSize` (optional): Min nodes (default: 1)
- `nodeGroupMaxSize` (optional): Max nodes (default: 4)

**Status Exports**: `clusterARN`, `clusterName`, `clusterEndpoint`, `clusterCertificateAuthority`, `nodeGroupARN`, `nodeGroupStatus`

## Required ACK Controllers

Install these controllers before deploying RGDs:
- EC2, EKS, RDS, ElastiCache, OpenSearch
- S3, EFS, SNS, SQS
- KMS, SecretsManager, IAM
- CloudWatchLogs, CloudTrail, WAFv2, Route53

## Documentation

Complete guide: [Gen3 KRO Guide](../../../docs/guides/gen3-kro.md)
