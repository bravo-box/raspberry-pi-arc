#!/usr/bin/env bash

kubectl create serviceaccount demo-user -n default

kubectl create clusterrolebinding demo-user-binding --clusterrole cluster-admin --serviceaccount default:demo-user

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: demo-user-secret
  annotations:
    kubernetes.io/service-account.name: demo-user
type: kubernetes.io/service-account-token
EOF

TOKEN=$(kubectl get secret demo-user-secret -o jsonpath='{$.data.token}' | base64 -d)

if [ -z "$TOKEN" ]; then
  echo "Error: Failed to extract token from secret" >&2
  exit 1
fi

echo "$TOKEN"