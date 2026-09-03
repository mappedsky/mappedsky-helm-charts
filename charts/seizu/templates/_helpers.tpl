{{/*
Expand the name of the chart.
*/}}
{{- define "seizu.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "seizu.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "seizu.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "seizu.labels" -}}
helm.sh/chart: {{ include "seizu.chart" . }}
{{ include "seizu.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "seizu.selectorLabels" -}}
app.kubernetes.io/name: {{ include "seizu.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Service account name.
*/}}
{{- define "seizu.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "seizu.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
ConfigMap name.
*/}}
{{- define "seizu.configMapName" -}}
{{- printf "%s-config" (include "seizu.fullname" .) -}}
{{- end -}}

{{/*
Secret name.
*/}}
{{- define "seizu.secretName" -}}
{{- default (printf "%s-secret" (include "seizu.fullname" .)) .Values.secrets.existingSecret -}}
{{- end -}}

{{/*
Image reference.
*/}}
{{- define "seizu.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}

{{/*
Cartography worker image reference.
*/}}
{{- define "seizu.cartographyWorkerImage" -}}
{{- $tag := default .Chart.AppVersion .Values.cartographyWorker.image.tag -}}
{{- printf "%s:%s" .Values.cartographyWorker.image.repository $tag -}}
{{- end -}}

{{/*
Cartography worker workload name.
*/}}
{{- define "seizu.cartographyWorkerFullname" -}}
{{- printf "%s-cartography-worker" (include "seizu.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Cartography worker ConfigMap name.
*/}}
{{- define "seizu.cartographyWorkerConfigMapName" -}}
{{- printf "%s-cartography-worker-config" (include "seizu.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Cartography worker Secret name.
*/}}
{{- define "seizu.cartographyWorkerSecretName" -}}
{{- default (printf "%s-cartography-worker-secret" (include "seizu.fullname" .) | trunc 63 | trimSuffix "-") .Values.cartographyWorker.secrets.existingSecret -}}
{{- end -}}

{{/*
Render a scalar as a quoted environment-variable value.

Helm parses every unquoted YAML number in a values file as a float64, and Go
renders a float64 of 1e6 or more in scientific notation -- "1e+06" -- which
Seizu's int_env()/float_env() then reject with a ValueError at import, so the
container crashloops. (Values passed with --set arrive as int64 and were never
affected, which is why this only ever bit values-file users.) Integral numbers
are therefore formatted as plain integers; genuine fractions and all other
types render unchanged.
*/}}
{{- define "seizu.envValue" -}}
{{- if kindIs "float64" . -}}
{{- if eq . (floor .) -}}
{{- printf "%.0f" . | quote -}}
{{- else -}}
{{- /* %v would also go exponential on a large fraction, so fix the precision
       and trim the padding back off. */ -}}
{{- $f := trimSuffix "." (regexReplaceAll "0+$" (printf "%.10f" .) "") -}}
{{- default "0" $f | quote -}}
{{- end -}}
{{- else -}}
{{- . | quote -}}
{{- end -}}
{{- end -}}
