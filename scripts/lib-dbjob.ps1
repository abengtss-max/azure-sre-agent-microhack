#Requires -Version 7.0
# Aetherion AirOps - run a SQL statement against the platform database from
# inside the cluster, using the credentials the workloads already mount.
#
# Dot-source this file, then:
#   Invoke-AetherionDbSql -Sql 'CREATE INDEX ...' -Name 'crew-index'

function Invoke-AetherionDbSql {
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$TimeoutSec = 300
    )

    $ns = 'aetherion'
    $jobName = "$Name-$([guid]::NewGuid().ToString('N').Substring(0, 6))"

    $manifest = @"
apiVersion: batch/v1
kind: Job
metadata:
  name: $jobName
  namespace: $ns
  labels: { component: db-maintenance }
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels: { component: db-maintenance }
    spec:
      restartPolicy: Never
      containers:
        - name: psql
          image: postgres:16-alpine
          env:
            - { name: PGHOST, valueFrom: { secretKeyRef: { name: aetherion-secrets, key: PGHOST } } }
            - { name: PGUSER, valueFrom: { secretKeyRef: { name: aetherion-secrets, key: PGUSER } } }
            - { name: PGPASSWORD, valueFrom: { secretKeyRef: { name: aetherion-secrets, key: PGPASSWORD } } }
            - { name: PGDATABASE, valueFrom: { configMapKeyRef: { name: aetherion-config, key: PGDATABASE } } }
            - { name: PGPORT, valueFrom: { configMapKeyRef: { name: aetherion-config, key: PGPORT } } }
            - { name: PGSSLMODE, value: "require" }
          command: ["psql", "-v", "ON_ERROR_STOP=1", "-c", "$Sql"]
          resources: { requests: { cpu: "50m", memory: "64Mi" }, limits: { cpu: "500m", memory: "256Mi" } }
"@

    $manifest | kubectl apply -f - 2>$null | Out-Null
    kubectl wait --for=condition=complete "job/$jobName" -n $ns --timeout="${TimeoutSec}s" 2>$null | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    if (-not $ok) {
        Write-Warning "Database maintenance job '$jobName' did not complete. Logs:"
        kubectl logs "job/$jobName" -n $ns --tail=20 2>$null
    }
    kubectl delete "job/$jobName" -n $ns --ignore-not-found 2>$null | Out-Null
    return $ok
}
