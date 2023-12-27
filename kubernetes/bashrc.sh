export BASH_SILENCE_DEPRECATION_WARNING=1
export USE_GKE_GCLOUD_AUTH_PLUGIN=True

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
    echo "klistvms                           # list the VMs in the project"    
    echo "kgpn <selector>                    # get pod name(s) for selector"
    echo "krsh <selector> [<container>]      # get a shell on the named kubernetes container"
    echo "kbash                              # fire up a new valet-based container with an interactive shell"
    echo "kpf <selector> <port>              # forward localhost port to pod port"
    echo "klog <selector>                    # show logs for container"
    echo "kdrachtio                          # find the running drachtio VMs"
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

function kdrachtio {
    gcloud compute instances list --project $KPROJECT --format=json | \
        jq -r 'map(select(.status=="RUNNING"))|map(select(.name | contains("drachtiovm")))|.[].name'
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

function klistvms {
    gcloud compute instances list --project ${KPROJECT} --zone ${KZONE} --format=json | jq -r .[].name
}
    
# like krsh, except for VMs
function kssh {
    if [ -z "$1" ]; then
	echo "Usage: kssh vnname"
	return 1
    else
	gcloud compute ssh $1 --project ${KPROJECT} --zone ${KZONE} --tunnel-through-iap
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

function kupdate {
  if [ -z "$1" ]; then
    echo "Usage: kupdate <branch:dts.version>"
    echo "Update everything to the specified version"
    return 1
  fi

  targetversion=($(echo $1 |  sed 's/\([a-z0-9]*\)\:\(.*\)$/\1 \2/'))
  echo "Updating:"
  echo "  Branch = ${targetversion[0]}"
  echo "  Version = ${targetversion[1]}"

  # redeploy
  # echo deployment | jq 'del(.spec.selector)' | jq 'del(.spec.template.metadata.labels)' | kubectl replace --force -f -
  for d in $( kubectl get deployment --no-headers -o custom-columns=":metadata.name" ) ; do
      rf="${d}-$(openssl rand -hex 3)"
      of="/tmp/${rf}.orig.yaml"
      nf="/tmp/${rf}.new.yaml"
      kubectl get deployment "${d}" --output json > "${of}"
      cp ${of} ${nf}
      for m in $(cat $of | jq -r '.spec.template.spec.containers[].image'); do
          # turn "us.gcr.io/ce-avoke-appdev-01/hennessy2/api:20230105.cf24f6e"
          # into "us.gcr.io/ce-avoke-appdev-01 hennessy2 api 20230105.cf24f6e"
          ov=($(echo ${m} | sed 's/^\(.*\)\/\([a-z0-9]*\)\/\([a-z0-9]*\)\:\(.*\)$/\1 \2 \3 \4/g'))
          newversion="${ov[0]}/${targetversion[0]}/${ov[2]}:${targetversion[1]}"
          echo "${m} -> ${newversion}"
          sed -I "" "s%${m}%${newversion}%g" $nf
      done
      diff -u $of $nf
      rm $of $nf
  done
  
  for c in $( kubectl get cronjob --no-headers -o custom-columns=":metadata.name" ) ; do
      echo $c
  done
}

function kbash {
    # TODO: maybe we should support running a command instead of just interactive here.
    # we could do this with something like:
    # arglist="\"/bin/bash\", \"-c\", \"$@\""
    arglist="\"/bin/bash\""

    # get the right image to use - assume it is from remindercj, which is a valet based cronjob
    whole=$(kubectl get cronjob remindercj --output json)
    template=$(echo "${whole}" | jq .spec.jobTemplate.spec.template.spec.containers[0])
    pvolumes=$(echo "${whole}" | jq .spec.jobTemplate.spec.template.spec.volumes)
    image=$(echo "${template}" | jq -r .image)
    penv=$(echo "${template}" | jq -r .env)
    penvfrom=$(echo "${template}" | jq -r .envFrom)
    pmounts=$(echo "${template}" | jq -r .volumeMounts)

    # make a nice random pod podname
    #podname="manual-$(mktemp -u XXXXXX|tr [A-Z] [a-z])"
    podname="manual-$(openssl rand -hex 3)"
    overrides=$(cat <<-END
{"apiVersion": "v1",
 "spec": { 
   "containers": [ {
     "name": "${podname}",
     "args": [ ${arglist} ],
     "image": "${image}",
     "stdin": true,
     "stdinOnce": true,
     "tty": true,
     "env": ${penv},
     "envFrom": ${penvfrom},
     "volumeMounts": ${pmounts}
    } ],
    "volumes": ${pvolumes}
 } }

END
             )

    echo "Starting pod ${podname}"
    kubectl run -i --tty --rm ${podname} --image="${image}" --restart=Never --overrides="${overrides}"
}

function khack {
    # TODO: maybe we should support running a command instead of just interactive here.
    # we could do this with something like:
    # arglist="\"/bin/bash\", \"-c\", \"$@\""
    arglist="\"/bin/bash\""

    # get the right image to use - assume it is from remindercj, which is a valet based cronjob
    whole=$(kubectl get cronjob remindercj --output json)
    template=$(echo "${whole}" | jq .spec.jobTemplate.spec.template.spec.containers[0])
    pvolumes=$(echo "${whole}" | jq .spec.jobTemplate.spec.template.spec.volumes)
    image="us.gcr.io/ce-avoke-appdev-01/icaco/wscr:20230912.6c33ea6"
    penv=$(echo "${template}" | jq -r .env)
    penvfrom=$(echo "${template}" | jq -r .envFrom)
    pmounts=$(echo "${template}" | jq -r .volumeMounts)

    # make a nice random pod podname
    #podname="manual-$(mktemp -u XXXXXX|tr [A-Z] [a-z])"
    podname="manual-$(openssl rand -hex 3)"
    overrides=$(cat <<-END
{"apiVersion": "v1",
 "spec": { 
   "containers": [ {
     "name": "${podname}",
     "args": [ ${arglist} ],
     "image": "${image}",
     "stdin": true,
     "stdinOnce": true,
     "tty": true,
     "env": ${penv},
     "envFrom": ${penvfrom},
     "volumeMounts": ${pmounts}
    } ],
    "volumes": ${pvolumes}
 } }

END
             )

    echo "Starting pod ${podname}"
    kubectl run -i --tty --rm ${podname} --image="${image}" --restart=Never --overrides="${overrides}"
}


function kstarter {
    # get the right image to use - assume it is from remindercj, which is a valet based cronjob
    whole=$(kubectl get cronjob remindercj --output json)
    template=$(echo "${whole}" | jq .spec.jobTemplate.spec.template.spec.containers[0])
    pvolumes=$(echo "${whole}" | jq .spec.jobTemplate.spec.template.spec.volumes)
    image=$(echo "${template}" | jq -r .image)
    penv=$(echo "${template}" | jq -r .env)
    penvfrom=$(echo "${template}" | jq -r .envFrom)
    pmounts=$(echo "${template}" | jq -r .volumeMounts)

    # make a nice random pod podname
    #podname="manual-$(mktemp -u XXXXXX|tr [A-Z] [a-z])"
    podname="manual-$(openssl rand -hex 3)"
    overrides=$(cat <<-END
{"apiVersion": "v1",
 "spec": { 
   "containers": [ {
     "name": "${podname}",
     "args": [ ${arglist} ],
     "image": "${image}",
     "stdin": true,
     "stdinOnce": true,
     "tty": true,
     "env": ${penv},
     "envFrom": ${penvfrom},
     "volumeMounts": ${pmounts}
    } ],
    "volumes": ${pvolumes}
 } }

END
             )

    echo "Starting pod ${podname}"
    kubectl run -i --tty --rm ${podname} --image="${image}" --restart=Never --overrides="${overrides}"
}

function klogs {
    f=0
    if [ "-f" == "$1" ]; then
        f=1
        shift
    fi
    if [ -z "$1" ]; then
        echo "Usage: klogs [-f] <selector> [container]"
        echo "   alias for 'kubectl logs [-f] $(kgpn selector)"
        return 1
    fi
    tail=""
    if [ ! -z "$2" ]; then
        tail="-c $2"
    fi
    
    if [ "$f" == "1" ]; then
        kubectl logs -f $(kgpn $1) $tail
    else
        kubectl logs $(kgpn $1) $tail
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
  kubectl port-forward $(kgpn 'queue') 8161 61616
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

# 
function setup_utility {
    if [[ "$(kubectl get deployment utility --ignore-not-found)" == "" ]]; then
        echo "no utility deployment.  Creating"
        kubectl get deployment loader --output json \
            | jq 'del(.status)' \
            | jq 'del(.metadata)' \
            | jq '.metadata.name="utility"' \
            | jq '.spec.selector.matchLabels.app="utility"' \
            | jq '.spec.template.metadata.labels.app="utility"' \
            | jq '.spec.template.metadata.name="utility"' \
            | jq '.spec.template.spec.containers[0].name="utility"' \
            | jq '.spec.template.spec.containers[0].image|=sub("loader";"valet")' \
            | jq '.spec.template.spec.containers[0].command=["/bin/bash", "-c", "--"]' \
            | jq '.spec.template.spec.containers[0].args=["while true; do sleep 60; done;"]' \
            | kubectl apply -f -
    else
        echo "utility deployment already exists"
    fi
}

# authorize me!
kauth

