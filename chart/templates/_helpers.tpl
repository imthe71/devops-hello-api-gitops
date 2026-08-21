{{- define "hello-api.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "hello-api.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "hello-api.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "hello-api.labels" -}}
app.kubernetes.io/name: {{ include "hello-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end }}

{{- define "hello-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hello-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
