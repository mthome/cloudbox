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

function rmpod {
  if [ -z "$1" ]; then
    echo "Usage: rmpod <podname>"
    echo "  alias for kubectl delete --force --grace-period=0 pod <podname>"
    return 1
  else
    kubectl delete --force --grace-period=0 pod $1
  fi
}

function gcpods {
  kubectl get pod --field-selector=status.phase==Succeeded
  echo "about to delete the above pods"
  sleep 5
  kubectl delete pod --field-selector=status.phase==Succeeded
}
