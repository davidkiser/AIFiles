    export LOCAL_PORT=8080
    export POD_NAME=$(kubectl get pods -n ai -l "app.kubernetes.io/component=open-webui" -o jsonpath="{.items[0].metadata.name}")
    export CONTAINER_PORT=$(kubectl get pod -n ai $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
    kubectl -n ai port-forward $POD_NAME $LOCAL_PORT:$CONTAINER_PORT

