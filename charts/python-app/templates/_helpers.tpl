{{/*
Expand the name of the chart.
*/}}
{{- define "app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" | lower }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" | lower }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" | lower }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" | lower }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" | lower }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "app.labels" -}}
helm.sh/chart: {{ include "app.chart" . }}
{{ include "app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Validate PodDisruptionBudget configuration.
Called from pdb.yaml when podDisruptionBudget is enabled.
*/}}
{{- define "app.validatePdb" -}}

{{/* Determine effective replica count */}}
{{- $effectiveReplicas := int .Values.replicaCount }}
{{- if .Values.autoscaling.enabled }}
  {{- $effectiveReplicas = int .Values.autoscaling.minReplicas }}
{{- end }}

{{/* Validate: at least one of maxUnavailable or minAvailable must be set */}}
{{- if and (not (hasKey .Values.podDisruptionBudget "maxUnavailable")) (not (hasKey .Values.podDisruptionBudget "minAvailable")) }}
  {{ fail "podDisruptionBudget is enabled but neither maxUnavailable nor minAvailable is set. Please set exactly one." }}
{{- end }}

{{/* Validate: maxUnavailable and minAvailable are mutually exclusive */}}
{{- if and (hasKey .Values.podDisruptionBudget "maxUnavailable") (hasKey .Values.podDisruptionBudget "minAvailable") }}
  {{ fail "podDisruptionBudget: maxUnavailable and minAvailable are mutually exclusive. Please set only one." }}
{{- end }}

{{/* Validate maxUnavailable: replicaCount - maxUnavailable must be > 0 */}}
{{/* Numeric check handles both float64 (YAML values files) and int64 (--set flag) */}}
{{- if hasKey .Values.podDisruptionBudget "maxUnavailable" }}
  {{- if or (kindIs "float64" .Values.podDisruptionBudget.maxUnavailable) (kindIs "int64" .Values.podDisruptionBudget.maxUnavailable) }}
    {{- $maxUnavailable := int .Values.podDisruptionBudget.maxUnavailable }}
    {{- if le $maxUnavailable 0 }}
      {{ fail (printf "podDisruptionBudget.maxUnavailable must be a positive integer, got %d" $maxUnavailable) }}
    {{- end }}
    {{- if ge $maxUnavailable $effectiveReplicas }}
      {{ fail (printf "podDisruptionBudget.maxUnavailable (%d) must be strictly less than the effective replica count (%d). Difference must be > 0." $maxUnavailable $effectiveReplicas) }}
    {{- end }}
  {{- end }}
{{- end }}

{{/* Validate minAvailable: replicaCount - minAvailable must be > 0 */}}
{{- if hasKey .Values.podDisruptionBudget "minAvailable" }}
  {{- if or (kindIs "float64" .Values.podDisruptionBudget.minAvailable) (kindIs "int64" .Values.podDisruptionBudget.minAvailable) }}
    {{- $minAvailable := int .Values.podDisruptionBudget.minAvailable }}
    {{- if le $minAvailable 0 }}
      {{ fail (printf "podDisruptionBudget.minAvailable must be a positive integer, got %d" $minAvailable) }}
    {{- end }}
    {{- if ge $minAvailable $effectiveReplicas }}
      {{ fail (printf "podDisruptionBudget.minAvailable (%d) must be strictly less than the effective replica count (%d). Difference must be > 0." $minAvailable $effectiveReplicas) }}
    {{- end }}
  {{- end }}
{{- end }}

{{- end }}
