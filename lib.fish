function exit_usage
  set command_name $argv[1]
  echo "
  kubdee Version: v$kubdee_version
  Usage:
    $command_name [options] controller-ip <cluster name>     print the IPv4 address of the controller node
    $command_name [options] create <cluster name>            create a cluster
    $command_name [options] create-admin-sa <cluster name>   create admin service account in cluster
    $command_name [options] create-user-sa <cluster name>    create user service account in cluster (has 'edit' privileges)
    $command_name [options] delete <cluster name>            delete a cluster
    $command_name [options] etcd-env <cluster name>          print etcdctl environment variables
    $command_name [options] kubectl-env <cluster name>       print kubectl environment variables
    $command_name [options] list                             list all clusters
    $command_name [options] smoke-test <cluster name>        smoke test a cluster
    $command_name [options] start <cluster name>             start a cluster
    $command_name [options] start-worker <cluster name>      start a new worker node in a cluster
    $command_name [options] up <cluster name>                create + start in one command
    $command_name [options] version                          print kubdee version and exit
  
  Options:
    --apiserver-extra-hostnames <hostname>[,<hostname>]   additional X509v3 Subject Alternative Name to set, comma separated
    --bin-dir <dir>                                       where to copy the k8s binaries from (default: ./_output/bin)
    --kubernetes-version <version>                        the release of Kubernetes to install, for example 'v1.12.0'
                                                          takes precedence over \`--bin-dir\`
    --no-set-context                                      prevent kubdee from adding a new kubeconfig context
    --num-worker <num>                                    number of worker nodes to start (default: 2)
  "
    exit 0
  end

function log_info 
  set message $argv[1]
  echo -e "\\033[1;37m==> $message\\033[0m"
end

function log_success 
  set message $argv[1]
  echo -e "\\033[1;32m==> $message\\033[0m"
end

function log_warn 
  set message $argv[1]
  echo -e "\\033[1;33m==> $message033[0m" >&2
end

function log_error 
  set message $argv[1]
  echo -e "\\033[1;31m==> $message\\033[0m" >&2
end

function exit_error 
  set message $argv[1]
  set code $argv[2]
  log_error "$message"
  exit $code
end

function validate_name
  set -l orig_name $argv[1]
  # We must be fairly strict about names, since they are used
  # for container's hostname
  if ! echo "$orig_name" | grep -qE '^[[:alnum:]_.-]{1,50}$'
    exit_error "Invalid name (only '[[:alnum:]-]{1,50}' allowed): $orig_name" 1
  end
  # Do some normalization to allow input like 'v1.8.4' while
  # matching host name requirements
  set -l name (string replace -a -r [._] - $orig_name)
  if test "$orig_name" != "$name"
    log_warn "Normalized name '$orig_name' -> '$name'"
  end
  echo $name
end

function prepare_cluster_dir
  set -l cluster_name (validate_name $argv[1])
  mkdir -p $kubdee_dir/clusters/$cluster_name
end

function container_wait_running
  echo $argv
end

function prepare_container_image
  set -l cluster_name $argv[1]
  log_info "Pruning old kubdee container images ..."
  for c in (incus image list --format json | jq -r '.[].aliases[].name');
    if string match -q -e "kubdee-container-image-" $c; and string match -q $kubdee_container_image $c ;
      incus image delete "$c"
    end
  end
  incus image info $kubdee_container_image &>/dev/null ; and return
  log_info "Preparing kubdee container image ..."
  incus delete -f $kubdee_container_image-setup &>/dev/null ; or true
  incus launch \
    --storage kubdee \
    --profile default \
    $kubdee_base_image $kubdee_container_image-setup
  container_wait_running $kubdee_container_image-setup
  echo "
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update

apt-get install -y curl

rm -rf /var/cache/apt
" | incus exec $kubdee_container_image-setup -- bash
  incus snapshot create $kubdee_container_image-setup snap
  incus publish $kubdee_container_image-setup/snap --alias $kubdee_container_image
  incus delete -f $kubdee_container_image-setup
end

function launch_container 
  echo $argv
end

function configure_controller
  echo $argv
end

function configure_worker
  echo $argv
end