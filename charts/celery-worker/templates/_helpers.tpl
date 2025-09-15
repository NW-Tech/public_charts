{{/*
Expand the name of the chart.
*/}}
{{- define "celery-worker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" | lower }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "celery-worker.fullname" -}}
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
{{- define "celery-worker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" | lower }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "celery-worker.labels" -}}
helm.sh/chart: {{ include "celery-worker.chart" . }}
{{ include "celery-worker.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "celery-worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "celery-worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "celery-worker.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "celery-worker.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the command array for the worker with proper base path substitution
*/}}
{{- define "celery-worker.command" -}}
{{- if .worker }}
{{- $basePath := .Values.workers.basePath | default "worker.celery_app" }}
{{- if eq .worker.type "worker" -}}
poetry run celery -A {{ $basePath }} worker --loglevel=info --concurrency=1
{{- else if eq .worker.type "beat" -}}
poetry run celery -A {{ $basePath }} beat -S celery_sqlalchemy_scheduler.schedulers:DatabaseScheduler -l info -s /tmp/celerybeat-schedule --pidfile=/tmp/celery-beat.pid
{{- else if .worker.cmd -}}
{{ .worker.cmd }}
{{- end }}
{{- end }}
{{- end -}}
