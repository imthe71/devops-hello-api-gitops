# Sealed Secrets 加密與使用方式

本專案使用 Bitnami Sealed Secrets，讓 GitOps Repository 可以保存加密後的參數，而不保存 Secret 明文。

## 整體流程

```text
管理者輸入明文參數
  → kubeseal 使用目標 Cluster 的公開憑證加密
  → 密文（Ag...）寫入 values.yaml 或 values-uat.yaml
  → Helm 產生 SealedSecret
  → Argo CD 套用到目標 Cluster
  → sealed-secrets-controller 解密
  → 建立一般 Kubernetes Secret
  → Deployment / StatefulSet / kubelet 使用 Secret
```

Helm 不負責加密；Helm 只把 values 中的密文放入 `SealedSecret.spec.encryptedData`。

## 本專案保護的資料

| Helm Template | 產生的 Kubernetes Secret | 使用位置 |
|---|---|---|
| `runtime-secret.yaml` | `hello-api-runtime` | FastAPI 的 `APP_DEMO_TOKEN` 環境變數。 |
| `registry-credentials.yaml` | `ghcr-pull` | `imagePullSecrets`，供 kubelet 拉取私有 GHCR Image。 |
| `postgres-secret.yaml` | `hello-api-postgres-auth` | PostgreSQL 與 FastAPI 的資料庫連線參數。 |

以 PostgreSQL 為例，`postgres-secret.yaml` 將下列三個 values 欄位放進 SealedSecret：

```yaml
postgres:
  auth:
    encryptedDatabase: "Ag..."
    encryptedUsername: "Ag..."
    encryptedPassword: "Ag..."
```

controller 解密後，會建立 `hello-api-postgres-auth`，其中有：

```text
POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
```

PostgreSQL StatefulSet 與 FastAPI Deployment 透過 `secretKeyRef` 讀取這些 Key。

## 私鑰存放位置

每個 Cluster 的 sealed-secrets-controller 都有獨立的一組金鑰。

```text
Namespace：kube-system
Secret 名稱：sealed-secrets-key*
Type：kubernetes.io/tls
內容：tls.crt（公開憑證）與 tls.key（私鑰）
```

私鑰是 Kubernetes Secret 資源，由 Kubernetes API Server 管理，controller 依 RBAC 權限讀取。`kubeseal` 只使用公開憑證加密，不會取得或保存私鑰。

UAT 與正式環境使用不同 Controller 金鑰，因此相同明文會產生不同密文，且不能互相解密。

## 為什麼使用 strict scope

本專案產生密文時使用：

```text
--scope strict
```

`strict` 會綁定目標的 Namespace 與 Secret 名稱。例如 UAT 的：

```text
Namespace：hello-api-uat
Secret：hello-api-postgres-auth
```

另外，密文使用目標 Cluster 的公開憑證加密，因此也只能由該 Cluster 的 controller 解密。將 UAT 的密文直接複製到正式環境不會成功解密；改 Secret 名稱或 Namespace 時，也必須重新加密。

## 建立或輪替 PostgreSQL Secret

以下範例建立 UAT 用的加密輸出。`DB_NAME`、`DB_USER`、`DB_PASSWORD` 只在管理者的本機操作階段出現；一般 Kubernetes Secret 明文不可提交 Git。

```powershell
$kubeseal = '.\kubeseal.exe'

kubectl --context kind-devops-uat -n hello-api-uat create secret generic hello-api-postgres-auth `
  --from-literal=POSTGRES_DB=DB_NAME `
  --from-literal=POSTGRES_USER=DB_USER `
  --from-literal=POSTGRES_PASSWORD=DB_PASSWORD `
  --dry-run=client -o yaml |
& $kubeseal `
  --context kind-devops-uat `
  --controller-name sealed-secrets-controller `
  --controller-namespace kube-system `
  --scope strict `
  --format yaml > postgres-sealed-uat.yaml
```

產出的檔案會有：

```yaml
spec:
  encryptedData:
    POSTGRES_DB: Ag...
    POSTGRES_USER: Ag...
    POSTGRES_PASSWORD: Ag...
```

將三個密文分別更新到 `chart/values-uat.yaml` 的 `encryptedDatabase`、`encryptedUsername`、`encryptedPassword`，再提交 Git。正式環境需以 `kind-devops-demo`、`hello-api` 重新產生一份密文，更新 `chart/values.yaml`。

## 驗證方式

```powershell
# 查看加密物件與 controller 解密後產生的 Secret；不輸出內容。
kubectl --context kind-devops-uat -n hello-api-uat get sealedsecret,secret

# 查看目前使用的 controller 金鑰 Secret 名稱，不輸出 tls.key。
kubectl --context kind-devops-uat -n kube-system get secret `
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active
```

若 Secret 尚未建立，先確認 SealedSecret 狀態與 controller Log：

```powershell
kubectl --context kind-devops-uat -n hello-api-uat describe sealedsecret hello-api-postgres-auth
kubectl --context kind-devops-uat -n kube-system logs deploy/sealed-secrets-controller
```

## 重要注意事項

- Kubernetes Secret 的資料欄位預設是 Base64 編碼，不等於靜態加密。雲端正式環境應啟用 Kubernetes Encryption at Rest，並以 KMS 保護資料儲存層。
- controller 私鑰遺失後，舊的 SealedSecret 密文無法再解開；正式環境應備份該 Key Secret，並嚴格限制 RBAC 存取。
- `APP_DEMO_TOKEN` 的變更目前會透過 Deployment checksum 觸發 App rollout。
- 資料庫密碼輪替要額外規劃：既有 PostgreSQL 資料目錄不會因為更新 Pod 環境變數而自動修改 DB Role 密碼。正確流程是先修改 DB Role、更新 SealedSecret，再重啟使用該帳密的應用程式。
- Sealed Secrets 適合 GitOps 的靜態或低頻率參數。雲端動態 Secret 可改用 AWS Secrets Manager 與 CSI Driver。
