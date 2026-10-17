<#
.SYNOPSIS
    Creates the one-time AWS prerequisites for soadrian.com's production deploy.

.DESCRIPTION
    Creates the encrypted Terraform state bucket, lock table, and a GitHub Actions
    OIDC role scoped to this repository's prod environment. It reuses the account's
    GitHub OIDC provider when smart-margin or ResumePilot has already created it.
#>
[CmdletBinding()]
param(
    [string]$Region = "us-east-1",
    [string]$Repository = "adrianmeraz/soadrian.com",
    [string]$Route53ZoneName = "soadrian.com"
)

$ErrorActionPreference = "Stop"
$project = "soadrian-com"
$stateBucket = "$project-tfstate"
$lockTable = "$project-tflock"
$roleName = "$project-deploy-prod"

function Invoke-Aws {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & aws @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "aws $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Write-JsonTemp {
    param([Parameter(Mandatory)][object]$Value)
    $path = [System.IO.Path]::GetTempFileName()
    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    return $path
}

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "AWS CLI is required."
}

$identityJson = & aws sts get-caller-identity --output json
if ($LASTEXITCODE -ne 0) { throw "Unable to read the active AWS identity." }
$identity = $identityJson | ConvertFrom-Json
$accountId = $identity.Account
$oidcArn = "arn:aws:iam::${accountId}:oidc-provider/token.actions.githubusercontent.com"
$siteBucket = "$project-$accountId"

$zoneId = & aws route53 list-hosted-zones-by-name --dns-name $Route53ZoneName --query "HostedZones[?Name=='$Route53ZoneName.']|[0].Id" --output text
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($zoneId) -or $zoneId -eq "None") {
    throw "Unable to locate the public Route 53 zone $Route53ZoneName."
}
$zoneId = $zoneId -replace '^/hostedzone/', ''

Write-Host "AWS account: $accountId ($($identity.Arn))" -ForegroundColor Cyan
Write-Host "Region:      $Region" -ForegroundColor Cyan

$providersJson = & aws iam list-open-id-connect-providers --output json
if ($LASTEXITCODE -ne 0) { throw "Unable to list OIDC providers." }
$providers = ($providersJson | ConvertFrom-Json).OpenIDConnectProviderList.Arn
if ($oidcArn -notin $providers) {
    Write-Host "Creating the account-level GitHub OIDC provider" -ForegroundColor Cyan
    Invoke-Aws @(
        "iam", "create-open-id-connect-provider",
        "--url", "https://token.actions.githubusercontent.com",
        "--client-id-list", "sts.amazonaws.com",
        "--thumbprint-list", "6938fd4d98bab03faadb97b34396831e3780aea1",
        "--tags", "Key=Project,Value=$project", "Key=ManagedBy,Value=aws-cli-bootstrap"
    )
} else {
    Write-Host "Reusing GitHub OIDC provider $oidcArn" -ForegroundColor DarkGray
}

& aws s3api head-bucket --bucket $stateBucket 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating Terraform state bucket $stateBucket" -ForegroundColor Cyan
    Invoke-Aws @("s3api", "create-bucket", "--bucket", $stateBucket, "--region", $Region)
}

$encryptionPath = Write-JsonTemp @{
    Rules = @(@{ ApplyServerSideEncryptionByDefault = @{ SSEAlgorithm = "AES256" } })
}
try {
    Invoke-Aws @("s3api", "put-bucket-versioning", "--bucket", $stateBucket, "--versioning-configuration", "Status=Enabled")
    Invoke-Aws @("s3api", "put-bucket-encryption", "--bucket", $stateBucket, "--server-side-encryption-configuration", "file://$encryptionPath")
    Invoke-Aws @("s3api", "put-public-access-block", "--bucket", $stateBucket, "--public-access-block-configuration", "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true")
} finally {
    Remove-Item -LiteralPath $encryptionPath -Force -ErrorAction SilentlyContinue
}

& aws dynamodb describe-table --table-name $lockTable --region $Region 2>$null 1>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating Terraform lock table $lockTable" -ForegroundColor Cyan
    Invoke-Aws @(
        "dynamodb", "create-table",
        "--table-name", $lockTable,
        "--attribute-definitions", "AttributeName=LockID,AttributeType=S",
        "--key-schema", "AttributeName=LockID,KeyType=HASH",
        "--billing-mode", "PAY_PER_REQUEST",
        "--region", $Region,
        "--tags", "Key=Project,Value=$project", "Key=ManagedBy,Value=aws-cli-bootstrap"
    )
    Invoke-Aws @("dynamodb", "wait", "table-exists", "--table-name", $lockTable, "--region", $Region)
}

$trustPath = Write-JsonTemp @{
    Version = "2012-10-17"
    Statement = @(@{
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = @{ Federated = $oidcArn }
        Condition = @{
            StringEquals = @{
                "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
                "token.actions.githubusercontent.com:sub" = "repo:${Repository}:environment:prod"
            }
        }
    })
}

try {
    $existingRole = & aws iam get-role --role-name $roleName --query "Role.RoleName" --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and $existingRole -eq $roleName) {
        Write-Host "Updating deploy role $roleName" -ForegroundColor DarkGray
        Invoke-Aws @("iam", "update-assume-role-policy", "--role-name", $roleName, "--policy-document", "file://$trustPath")
    } else {
        Write-Host "Creating deploy role $roleName" -ForegroundColor Cyan
        Invoke-Aws @(
            "iam", "create-role",
            "--role-name", $roleName,
            "--assume-role-policy-document", "file://$trustPath",
            "--tags", "Key=Project,Value=$project", "Key=ManagedBy,Value=aws-cli-bootstrap"
        )
    }
} finally {
    Remove-Item -LiteralPath $trustPath -Force -ErrorAction SilentlyContinue
}

$policyPath = Write-JsonTemp @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Sid = "TerraformState"
            Effect = "Allow"
            Action = "s3:*"
            Resource = @("arn:aws:s3:::$stateBucket", "arn:aws:s3:::$stateBucket/*")
        },
        @{
            Sid = "TerraformLock"
            Effect = "Allow"
            Action = @("dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem")
            Resource = "arn:aws:dynamodb:${Region}:${accountId}:table/$lockTable"
        },
        @{
            Sid = "SiteBucket"
            Effect = "Allow"
            Action = "s3:*"
            Resource = @("arn:aws:s3:::$siteBucket", "arn:aws:s3:::$siteBucket/*")
        },
        @{
            Sid = "EdgeResources"
            Effect = "Allow"
            Action = @("acm:*", "cloudfront:*")
            Resource = "*"
        },
        @{
            Sid = "SiteDns"
            Effect = "Allow"
            Action = "route53:ChangeResourceRecordSets"
            Resource = "arn:aws:route53:::hostedzone/$zoneId"
        },
        @{
            Sid = "DnsAndAccountDiscovery"
            Effect = "Allow"
            Action = @(
                "route53:GetChange",
                "route53:GetHostedZone",
                "route53:ListHostedZones",
                "route53:ListHostedZonesByName",
                "route53:ListResourceRecordSets",
                "sts:GetCallerIdentity"
            )
            Resource = "*"
        }
    )
}

try {
    Invoke-Aws @(
        "iam", "put-role-policy",
        "--role-name", $roleName,
        "--policy-name", "$project-terraform",
        "--policy-document", "file://$policyPath"
    )
} finally {
    Remove-Item -LiteralPath $policyPath -Force -ErrorAction SilentlyContinue
}

$roleArn = & aws iam get-role --role-name $roleName --query "Role.Arn" --output text
if ($LASTEXITCODE -ne 0) { throw "Unable to read role $roleName." }

Write-Host ""
Write-Host "Bootstrap complete" -ForegroundColor Green
Write-Host "AWS_DEPLOY_ROLE_PROD=$roleArn"
