# PostgreSQL 與 PVC 操作手冊

## 目前拓撲

每個環境各有一套獨立 PostgreSQL：

| 環境 | Cluster | Namespace | StatefulSet | PVC |
|---|---|---|---|---|
| UAT | `kind-devops-uat` | `hello-api-uat` | `hello-api-uat-hello-api-postgres` | `data-hello-api-uat-hello-api-postgres-0` |
| 正式 | `kind-devops-demo` | `hello-api` | `hello-api-hello-api-postgres` | `data-hello-api-hello-api-postgres-0` |

兩份資料庫帳密以各 Cluster 的 Sealed Secrets Controller 公鑰加密；Git 僅保存密文。Controller 在各自 Namespace 建立 `hello-api-postgres-auth` Secret。

## 儲存設定

- PostgreSQL：單一副本 StatefulSet。
- Volume：`volumeClaimTemplates` 建立 `ReadWriteOnce` PVC。
- StorageClass：`standard`（kind 的 `rancher.io/local-path`）。
- 容量：`1Gi`。
- StatefulSet Pod 重啟時，PVC 保留並重新掛載。
- `standard` 的 ReclaimPolicy 是 `Delete`；手動刪除 PVC 時，對應 local-path Volume 會一併清除。

## API 驗證

UAT 新版 API 提供：

```powershell
# PostgreSQL 連線狀態（不輸出帳密）
curl.exe -H "Host: uat.hello-api.test" http://127.0.0.1:8082/db-status

# 寫入一筆示範資料
curl.exe -X POST -H "Host: uat.hello-api.test" -H "Content-Type: application/json" `
  -d '{"content":"UAT persistence check"}' http://127.0.0.1:8082/notes

# 讀取持久化資料
curl.exe -H "Host: uat.hello-api.test" http://127.0.0.1:8082/notes
```

## PVC 持久化測試

```powershell
kubectl --context kind-devops-uat -n hello-api-uat delete pod hello-api-uat-hello-api-postgres-0
kubectl --context kind-devops-uat -n hello-api-uat rollout status statefulset/hello-api-uat-hello-api-postgres
curl.exe -H "Host: uat.hello-api.test" http://127.0.0.1:8082/notes
```

若重建後 `/notes` 仍可讀到先前資料，即表示 PVC 持久化正常。
