# UAT 至正式環境發版 SOP

本流程採用：**UAT 手動選版，正式環境在合併 `main` 後自動部署。**

## 1. 準備 UAT 版本

1. 在 App Repo 開發功能 Branch，提交並推送。
2. 執行本機測試：

```powershell
python -m pytest tests -q
```

3. 到 GitHub Actions 執行 `Deploy selected revision to UAT`，輸入要部署的 branch、tag 或 commit SHA。
4. 確認 Workflow 成功完成：測試、Image Push、更新 `values-uat.yaml`。

## 2. 驗證 UAT

1. 在 Argo CD UAT 確認 Application 為 `Synced`、`Healthy`。
2. 確認 Pod 已 Ready：

```powershell
kubectl --context kind-devops-uat -n hello-api-uat get deploy,pods,svc,ingress,hpa,pdb,sts,pvc
```

3. 驗證 API 與資料庫：

```powershell
curl.exe -H "Host: uat.hello-api.test" http://127.0.0.1:8082/healthz
curl.exe -H "Host: uat.hello-api.test" http://127.0.0.1:8082/db-status
curl.exe -H "Host: uat.hello-api.test" http://127.0.0.1:8082/notes
```

4. 若為資料庫相關功能，可在 UAT 新增一筆 `/notes` 資料，重建 PostgreSQL Pod 後再讀取一次，確認 PVC 保留資料。

## 3. 合併至正式環境

1. 建立 Pull Request，將功能 Branch 合併至 `main`。
2. 合併後，`CI and Production deploy` 會自動執行：
   - 跑測試
   - 建置並推送 commit-SHA Image 至私有 GHCR
   - 更新 GitOps Repo 的 `chart/values.yaml`
3. 到 GitHub Actions 確認三個 Job 都成功：`test`、`publish-production`、`update-production-image-tag`。

## 4. 驗證正式環境

1. 等候 Argo CD 讀取新的 GitOps Commit；Application 應回到 `Synced`、`Healthy`。
2. 確認正式環境 Image 已切換為本次 merge commit：

```powershell
kubectl --context kind-devops-demo -n argocd get application hello-api
kubectl --context kind-devops-demo -n hello-api get deploy,pods,svc,ingress,hpa,pdb,sts,pvc
kubectl --context kind-devops-demo -n hello-api get deployment hello-api-hello-api `
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

3. 驗證正式 API 與資料庫：

```powershell
curl.exe -H "Host: hello-api.test" http://127.0.0.1/healthz
curl.exe -H "Host: hello-api.test" http://127.0.0.1/db-status
curl.exe -H "Host: hello-api.test" http://127.0.0.1/notes
```

## 5. 回滾

1. 在 GitOps Repo 將對應環境 values 檔的 Image Tag 還原至前一個成功版本。
2. 提交並推送 GitOps Commit。
3. Argo CD 會自動將 Cluster 收斂至舊版 Image。
4. 重複「驗證正式環境」確認服務恢復。

> 不直接在正式 Cluster 修改 Deployment Image；Image 版本一律由 GitOps Repo 管理，避免手動變更與 Git 設定不一致。
