#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
kpodsh - pick a pod (and container) and exec into it

Usage:
  kpodsh [-n NAMESPACE]
  kpodsh --help

Options:
  -n, --namespace NAMESPACE   Namespace to use. Defaults to current context's ns or 'default'.
EOF
}

NS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace) NS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Determine namespace
if [[ -z "${NS}" ]]; then
  NS="$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)"
  [[ -z "${NS}" ]] && NS="default"
fi

# Collect pods (prefer Running)
mapfile -t PODS < <(kubectl get pods -n "${NS}" --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
if [[ ${#PODS[@]} -eq 0 ]]; then
  echo "No Running pods in namespace '${NS}'. Showing all pods..." >&2
  mapfile -t PODS < <(kubectl get pods -n "${NS}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
fi
if [[ ${#PODS[@]} -eq 0 ]]; then
  echo "No pods found in namespace '${NS}'." >&2
  exit 1
fi

pick_from_list() {
  local prompt="$1"; shift
  local -a items=("$@")

  if command -v fzf >/dev/null 2>&1; then
    printf "%s\n" "${items[@]}" | fzf --prompt="${prompt} " --height=20 --reverse
    return
  fi

  # Numbered menu printed to STDERR; only the final choice goes to STDOUT
  echo "${prompt}" >&2
  local i=1
  for it in "${items[@]}"; do
    printf "%2d) %s\n" "$i" "$it" >&2
    ((i++))
  done
  local choice
  while true; do
    read -r -p "#? " choice </dev/tty
    [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Enter a number." >&2; continue; }
    (( choice >= 1 && choice <= ${#items[@]} )) || { echo "Out of range." >&2; continue; }
    printf "%s\n" "${items[choice-1]}"
    return
  done
}

POD="$(pick_from_list "Select pod in ${NS}:" "${PODS[@]}")"
[[ -z "${POD}" ]] && { echo "No pod selected." >&2; exit 1; }

# Containers in the pod
mapfile -t CONTAINERS < <(kubectl get pod -n "${NS}" "${POD}" -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}')
if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
  echo "No containers found in pod ${POD}." >&2
  exit 1
fi

CONTAINER=""
if [[ ${#CONTAINERS[@]} -eq 1 ]]; then
  CONTAINER="${CONTAINERS[0]}"
else
  CONTAINER="$(pick_from_list "Select container in ${POD}:" "${CONTAINERS[@]}")"
fi
[[ -z "${CONTAINER}" ]] && { echo "No container selected." >&2; exit 1; }

echo "Exec into ${NS}/${POD} (container: ${CONTAINER}) ..." >&2
# Prefer /bin/sh; fall back to /bin/bash
kubectl -n "${NS}" exec -it "${POD}" -c "${CONTAINER}" -- /bin/sh 2>/dev/null || \
kubectl -n "${NS}" exec -it "${POD}" -c "${CONTAINER}" -- /bin/bash

