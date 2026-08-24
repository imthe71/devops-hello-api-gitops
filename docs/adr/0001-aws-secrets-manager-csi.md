# ADR-0001: Runtime secrets from AWS Secrets Manager via CSI files

**Status:** Accepted  
**Scope:** Future Amazon EKS deployment. The local kind clusters continue to use
Sealed Secrets and environment variables until the EKS cutover.

## Decision

Use Amazon EKS Pod Identity, the Secrets Store CSI Driver, and the AWS Secrets
and Configuration Provider (ASCP) to expose runtime secrets as read-only files
in application Pods. GitOps manifests contain only secret names/ARNs, mount
paths, and IAM identity references; they do not contain secret values.

```text
AWS Secrets Manager
  -> EKS Pod Identity for hello-api ServiceAccount
  -> Secrets Store CSI Driver + ASCP
  -> /mnt/secrets-store/<KEY>
  -> Hello API reads the file
```

## IAM boundaries

| Identity | Permission |
| --- | --- |
| GitHub Actions CI role | Build/deploy permissions only; no `secretsmanager:GetSecretValue` for runtime secrets. |
| `hello-api` Pod Identity role | `secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret` limited to its environment's exact Secret ARN. |
| UAT and production roles | Separate IAM roles and separate Secrets Manager paths. |

Use these environment-specific secret names:

```text
hello-api/uat/runtime
hello-api/prod/runtime
```

Store a JSON object in each secret, for example with `APP_DEMO_TOKEN` and
`DB_PASSWORD` keys. AWS IAM policy resources must reference only the matching
environment Secret ARN.

## EKS platform prerequisites

1. Install the EKS Pod Identity Agent.
2. Install the Secrets Store CSI Driver and AWS ASCP provider.
3. Create an IAM role granting the application only `GetSecretValue` and
   `DescribeSecret` for its environment secret.
4. Associate the IAM role with the `hello-api` ServiceAccount through EKS Pod
   Identity.
5. Apply the `SecretProviderClass` before deploying the application.

## GitOps contract

Each environment renders a `SecretProviderClass` equivalent to:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: hello-api-runtime
spec:
  provider: aws
  parameters:
    region: <AWS_REGION>
    usePodIdentity: "true"
    objects: |
      - objectName: "hello-api/<ENVIRONMENT>/runtime"
        objectType: "secretsmanager"
        jmesPath:
          - path: APP_DEMO_TOKEN
            objectAlias: APP_DEMO_TOKEN
          - path: DB_PASSWORD
            objectAlias: DB_PASSWORD
```

The Deployment then uses:

```yaml
spec:
  serviceAccountName: hello-api
  containers:
    - name: hello-api
      env:
        - name: APP_SECRETS_DIR
          value: /mnt/secrets-store
      volumeMounts:
        - name: runtime-secrets
          mountPath: /mnt/secrets-store
          readOnly: true
  volumes:
    - name: runtime-secrets
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: hello-api-runtime
```

## RD contract

RD reads one file per key from `APP_SECRETS_DIR` and must not log the value.
For example, `APP_DEMO_TOKEN` is read from:

```text
${APP_SECRETS_DIR}/APP_DEMO_TOKEN
```

Before EKS cutover, the application should support the file-based contract in a
release that still works with the current local deployment. After EKS cutover,
remove runtime secret values from environment-variable injection.

## Rotation and verification

1. Rotate the value in AWS Secrets Manager.
2. The CSI rotation reconciler updates the mounted file.
3. The application reloads its configuration, or the Deployment is restarted
   through an auditable GitOps change.
4. Verify file presence and application health without printing secret content.

## Rollback

Keep the current Sealed Secrets manifests during the migration window. If the
CSI provider, Pod Identity association, or IAM policy is unavailable, deploy
the last validated local-compatible application revision and investigate the
EKS identity or CSI controller status before proceeding.
