function kgpn {
  if [ -z "$1" ]; then
    echo "Usage: kgpn <appselector>"
    echo "Kubernetes Get Pod Name:"
    echo "returns the addressable name of the pod selected"
    return 1
  else
    kubectl get pods --field-selector=status.phase=Running --selector=app=${1} --output=jsonpath={.items..metadata.name}
  fi
}

function krsh {
  if [ -z "$1" ]; then
    echo "Usage: krsh <node appselector> [<containername>]"
    echo "Kubernetes Run SH"
    return 1
  else
    if [ -z "$2" ]; then
      kubectl exec -it $(kgpn $1) -- /bin/sh
    else
      kubectl exec -it $(kgpn $1) -c "$2" -- /bin/sh
    fi
  fi
}
