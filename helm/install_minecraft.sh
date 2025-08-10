helm repo add itzg https://itzg.github.io/minecraft-server-charts
helm repo update

kubectl create ns minecraft

helm install mc itzg/minecraft -n minecraft -f minecraft_values.yaml
