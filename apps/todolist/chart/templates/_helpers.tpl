{{- define "todolist.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "todolist.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "todolist.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
