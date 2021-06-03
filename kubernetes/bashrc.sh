export BASH_SILENCE_DEPRECATION_WARNING=1

# we get the following from kactivate
# KTENANT=acme-foo
# TENANT=acme_foo (this should really be the in-cluster name of the tenant)
# KCLUSTER=cde

export CLOUDSDK_ACTIVE_CONFIG_NAME=${KTENANT}
export KUBECONFIG=${HOME}/.kube_${KTENANT}_${KCLUSTER}
touch ${KUBECONFIG}

GREEN="\[$(tput setaf 2)\]"
RESET="\[$(tput sgr0)\]"
PS1="${GREEN}${KTENANT}${RESET} \W\$ "

function khelp {
    echo ""
    echo "klogin <account>                   # tell the environment what account to use"
    echo "kssh <vmname>                      # get an ssh on the named VM"
    echo "kgpn <selector>                    # get pod name(s) for selector"
    echo "krsh <selector> [<container>]      # get a shell on a kubernetes container"
    echo "kpf <selector> <port>              # forward localhost port to pod port"
    echo "pfqueue                            # alias for kpf \$(kgpn queue) 8161"
    echo "pfsolr                             # alias for kpf \$(kgpn solr) 8983"
    echo "rmpod <name>                       # delete a named pod"
    echo "gcpods                             # delete old Succeeded pods"
    echo "gcfailedpods                       # delete old Failed pods"
    echo "gcevictedpods                      # delete old Evicted pods"
    echo "gcjobs                             # delete old jobs"
    echo "rerunjob <podname>                 # rerun a pod (e.g. a job)"
    echo ""
    echo "Environment variables:"
    echo "TENANT=${TENANT}"
    echo "KTENANT=${KTENANT}"
    echo "KPROJECT=${KPROJECT}"
    echo "KZONE=${KZONE}"
}

function kauth {
    if gcloud container clusters get-credentials ${KKLUSTER} --zone ${KZONE} --project ${KPROJECT}; then
	echo authorized
    else
	echo
	echo
	echo "run 'klogin <accountname>' to authorize"
    fi
}

function klogin {
    if [ -z "$1" ]; then
	echo "Usage: klogin <username>"
	return 1
    else
	if gcloud config set account $1 ; then
	    kauth
	else
	    echo "well that didn't work.  try again"
	    return 1
	fi
    fi
}

# like krsh, except for VMs
function kssh {
    if [ -z "$1" ]; then
	echo "Usage: kssh vnname"
	return 1
    else
	gcloud beta compute ssh $1 --project ${KPROJECT} --zone ${KZONE}
    fi
}
    


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

# kubectl cp $(kgpn migration):/home/avokeuser/storage/prompts targetdir

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

function kpf {
  if [ -z "$2" ]; then
    echo "Usage: kpf <node appselector> PORT"
    echo "port forward localhost PORT to pod PORT"
    return 1
  else
    kubectl port-forward $(kgpn $1) "$2"
  fi
}

function pfqueue {
  kubectl port-forward $(kgpn 'queue') 8161
}

function pfsolr {
  kubectl port-forward $(kgpn 'solr') 8983
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

function gcfailedpods {
  kubectl get pod --field-selector=status.phase==Failed
  echo "about to delete the above pods"
  sleep 5
  kubectl delete pod --field-selector=status.phase==Failed
}

function gcevictededpods {
  kubectl get pod --field-selector=status.phase==Evicted
  echo "about to delete the above pods"
  sleep 5
  kubectl delete pod --field-selector=status.phase==Evicted
}

function gcjobs {
  kubectl get jobs --field-selector status.successful=1 
  echo "about to delete the above jobs"
  sleep 5
  kubectl delete jobs --field-selector status.successful=1 
}


function rerunjob {
    if [ -z "$1" ]; then
	echo "Usage: rerunjob <podname>"
	return 1
    else
	f=/tmp/pod_$$.json
	echo "in case of emergency, the pod spec is in $f"
	kubectl get job $1 -o json > $f
	cat $f | jq 'del(.spec.selector)' | jq 'del(.spec.template.metadata.labels)' | kubectl replace --force -f -
    fi
}

# authorize me!
kauth

