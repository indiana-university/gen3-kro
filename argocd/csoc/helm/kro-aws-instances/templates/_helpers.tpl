{{/*
gen3kro.instance — render a single KRO CR instance document.

Usage:
  {{- include "gen3kro.instance" (list . .Values.instances.network "AwsGen3Network") }}

Arguments (positional via list):
  0  .          — the Helm root context (provides .Values.global)
  1  $inst      — the per-instance values block (enabled, version, syncWave, spec)
  2  $kindBase  — the Kind base name WITHOUT the version suffix
                  e.g. "AwsGen3Network" → rendered as "AwsGen3Network1" when version="1"

Rendered spec:
  • name and namespace come from .Values.global (immutable after first deploy)
  • metadataName may override metadata.name when multiple instances of the same
    RGD kind are needed; spec.name still remains .Values.global.name.
  • All fields under $inst.spec are templated with the Helm root context and
    then passed through. These are the safe-to-change fields: adoptionPolicy,
    deletionPolicy, *BridgeName, repo URLs, etc.
  • If $inst.spec is empty the KRO CR still renders correctly because every
    non-required field has a default in the RGD schema.
*/}}
{{- define "gen3kro.instance" -}}
{{- $ctx      := index . 0 -}}
{{- $inst     := index . 1 -}}
{{- $kindBase := index . 2 -}}
{{- if $inst.enabled }}
{{- $metadataName := default $ctx.Values.global.name $inst.metadataName -}}
---
apiVersion: kro.run/v1alpha1
kind: {{ $kindBase }}{{ $inst.version }}
metadata:
  name: {{ tpl $metadataName $ctx }}
  namespace: {{ $ctx.Values.global.namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: {{ $inst.syncWave | quote }}
    argocd.argoproj.io/sync-options: ServerSideApply=true
spec:
  name: {{ $ctx.Values.global.name }}
  namespace: {{ $ctx.Values.global.namespace }}
  {{- with $inst.spec }}
  {{- tpl (toYaml .) $ctx | nindent 2 }}
  {{- end }}
{{ end }}
{{- end }}
