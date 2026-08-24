param(
  [string[]]$Contexts = @("kind-devops-uat", "kind-devops-demo")
)

$ErrorActionPreference = "Stop"
$manifest = "https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.39.1/controller.yaml"

foreach ($context in $Contexts) {
  kubectl --context $context apply -f $manifest
  kubectl --context $context wait --for=condition=Established `
    crd/sealedsecrets.bitnami.com --timeout=90s
  kubectl --context $context -n kube-system rollout status `
    deployment/sealed-secrets-controller --timeout=180s
}
