# Global constants
set incus_status_code_running 103
set incus_driver_version (incus info | awk '/[:space:]*driver_version/ {print $2}')

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

function cd_or_exit_error
  set -l target $argv[1]
  cd "$target" ; or exit_error "Failed to cd to $target"  
end

function copyl_or_exit_error
  set -l target $argv[1]
  for f in $argv[2..]
    if ! cp -l "$f" "$target" &>/dev/null
      if ! cp "$f" "$target" &>/dev/null
        exit_error "Failed to copy '$f' to '$target'" 1
      end
    end
  end
end

function validate_name
  set -l orig_name $argv[1]
  # We must be fairly strict about names, since they are used
  # for container's hostname
  if ! echo "$orig_name" | grep -qE '^[[:alnum:]_.-]{1,50}$'
    exit_error "Invalid cluster name (only '[[:alnum:]-]{1,50}' allowed): '$orig_name'" 1
  end
  # Do some normalization to allow input like 'v1.8.4' while
  # matching host name requirements
  set -l name (string replace -a -r [._] - $orig_name)
  if test "$orig_name" != "$name"
    log_warn "Normalized name '$orig_name' -> '$name'"
  end
  echo $name
end

function create_storage_pool
  set -l cluster_name $argv[1]
  set -l driver $argv[2]
  test -z $driver; and set driver dir
  if ! incus storage show $cluster_name &>/dev/null
    log_info "Creating new storage pool for kubdee ..."
    incus storage create $cluster_name $driver
  end
end

function fetch_k3s_binaries
  fetch_k3s_binaries_impl $argv
end

function container_status_code
  set -l container_name $argv[1]
  incus list --format json | jq -r ".[] | select(.name == \"$container_name\").state.status_code"
end

function container_ipv4_address
  set -l container_name $argv[1]
  incus list --format json | jq -r ".[] | select(.name == \"$container_name\").state.network.eth0.addresses[] | select(.family == \"inet\").address"
end

function container_wait_running
  set -l container_name $argv[1]
  while test (container_status_code $container_name) != "$incus_status_code_running"
    log_info "Waiting for $container_name to reach state running ..."
    sleep 3
  end
  while test -z (container_ipv4_address $container_name)
    log_info "Waiting for $container_name to get IPv4 address ..."
    sleep 3
  end
end

function controller_wait_running
  set -l container_name $argv[1]
  while true
    incus exec $container_name -- kubectl get nodes 2>/dev/null | fgrep -iq ready
    and break
    log_info "Waiting for $container_name to reach state Ready ..."
    sleep 3
  end
end

function prepare_container_image
  set -l cluster_name $argv[1]
  log_info "Pruning old kubdee container images ..."
  for c in (incus image list --format json | jq -r '.[].aliases[].name');
    if string match -q -e "kubdee-container-image-" $c 
      and ! test "$kubdee_container_image" = "$c"
      incus image delete "$c"
    end
  end
  incus image info $kubdee_container_image | fgrep -i $image_base &>/dev/null ; and return
  incus image delete $kubdee_container_image #delete anyway as a new one has to be created.
  log_info "Preparing kubdee container image ..."
  incus delete -f $kubdee_container_image-setup &>/dev/null ; or true
  launch_container_image_setup $argv
  incus snapshot create $kubdee_container_image-setup snap
  incus publish $kubdee_container_image-setup/snap --alias $kubdee_container_image
  incus delete -f $kubdee_container_image-setup
end

function launch_container 
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  incus info $container_name &>/dev/null ; and return
  incus launch \
    --storage kubdee \
    --profile default \
    --config security.privileged="true" \
    --config raw.lxc="
lxc.apparmor.profile=unconfined
lxc.mount.auto=proc:rw sys:rw cgroup:rw
lxc.cgroup.devices.allow=a
lxc.cap.drop=
" \
    $kubdee_container_image $container_name
  begin
    incus config device add $container_name kmsg unix-char source=/dev/kmsg path=/dev/kmsg
    incus config device add $container_name adisable1 disk source=/proc/sys/net/netfilter/nf_conntrack_max path=/proc/sys/net/netfilter/nf_conntrack_max
    incus config device add $container_name adisable2 disk source=/sys/bus/acpi/drivers/hardware_error_device/uevent path=/sys/bus/acpi/drivers/hardware_error_device/uevent
    incus config device add $container_name images-share disk source=$container_image_share_directory path=/data
    incus storage volume attach $cluster_name k3s-pv $container_name /mnt/disks/ssd1 # volume k3s-pv needs to be prepared at first.
  end &>/dev/null
end

function import_local_images
  set -l container_name $argv[1]
  begin
    set tars (incus exec $container_name -- sh -c 'ls /data/*.tar')
    for t in $tars
      incus exec $container_name -- ctr image import $t
    end
  end &>/dev/null
end

function configure_controller
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  container_wait_running $container_name
  configure_controller_impl $argv
  or exit_error "Faild to start k3s server on $container_name. " 1
  controller_wait_running $container_name
  import_local_images $container_name
end

function configure_worker
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  container_wait_running $container_name
  configure_worker_impl $argv
  or exit_error "Faild to start k3s agent on $container_name. " 1
  import_local_images $container_name
end

function fetch_k3s_certificate
  set -l cluster_name $argv[1]
  set -l source_dir kubdee-$cluster_name-controller//var/lib/rancher/k3s/server/tls
  set -l target_dir $kubdee_dir/clusters/$cluster_name/certificates
  incus file pull $source_dir/{server-ca.crt, client-admin.crt, client-admin.key} $target_dir/
  or exit_error "Faild to fetch k3s certificate from cluster: $cluster_name."
end

function configure_kubeconfig
  set -l cluster_name $argv[1]
  set -l cluster_context_name kubdee-$cluster_name
  set -l cluster_creds_name "$cluster_context_name-admin"
  set -l ip (container_ipv4_address kubdee-$cluster_name-controller)
  test -z $ip && exit_error "Failed to get IPv4 for kubdee-$cluster_name-controller"
  fetch_k3s_certificate $cluster_name 
  kubectl config set-cluster "$cluster_context_name" \
    --certificate-authority="$kubdee_dir/clusters/$cluster_name/certificates/server-ca.crt" \
    --server="https://$ip:6443"
  kubectl config set-credentials "$cluster_creds_name" \
    --client-certificate="$kubdee_dir/clusters/$cluster_name/certificates/client-admin.crt" \
    --client-key="$kubdee_dir/clusters/$cluster_name/certificates/client-admin.key"
  kubectl config set-context "$cluster_context_name" \
    --cluster="$cluster_context_name" \
    --user="$cluster_creds_name"
  kubectl config use-context "$cluster_context_name"
end