# Global constants
set kubdee_base_image images:ubuntu/jammy
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

function create_storage_pool
  set -l cluster_name $argv[1]
  set -l driver $argv[2]
  test -z $driver; and set driver dir
  if ! incus storage show $cluster_name &>/dev/null
    log_info "Creating new storage pool for kubdee ..."
    incus storage create $cluster_name $driver
  end
end

function fetch_k3s
  set -l cache_dir $kubdee_cache_dir/k3s/$k3s_version
  mkdir -p $cache_dir
  test -e $cache_dir/k3s ; and return
  begin
    cd_or_exit_error $cache_dir
    log_info "Fetching k3s $k3s_version ..."
    if ! curl -fsSLI "https://github.com/k3s-io/k3s/releases/download/$k3s_version/k3s" >/dev/null
      exit_error "K3s version '$k3s_version' not found on https://github.com/k3s-io" 1
    end
    curl -fsSL -o k3s "https://github.com/k3s-io/k3s/releases/download/$k3s_version/k3s"
    chmod a+x k3s
  end
end

function fetch_k3s_binaries
  set -l cluster_name $argv[1]
  fetch_k3s
  set -l cache_dir $kubdee_cache_dir/k3s/$k3s_version
  set -l target_dir $kubdee_dir/clusters/$cluster_name/rootfs/usr/local/bin
  mkdir -p $target_dir
  copyl_or_exit_error $target_dir $cache_dir/k3s
end

function container_status_code
  set -l container_name $argv[1]
  incus list --format json | jq -r ".[] | select(.name == \"$container_name\").state.status_code"
end

function container_ip4_address
  set -l container_name $argv[1]
  incus list --format json | jq -r ".[] | select(.name == \"$container_name\").state.network.eth0.addresses[] | select(.family == \"inet\").address"
end

function container_wait_running
  set -l container_name $argv[1]
  while test (container_status_code $container_name) != "$incus_status_code_running"
    log_info "Waiting for $container_name to reach state running ..."
    sleep 3
  end
  while test -z (container_ip4_address $container_name)
    log_info "Waiting for $container_name to get IPv4 address ..."
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
  incus image info $kubdee_container_image &>/dev/null ; and return
  log_info "Preparing kubdee container image ..."
  incus delete -f $kubdee_container_image-setup &>/dev/null ; or true
  incus launch \
    --storage kubdee \
    --profile default \
    $kubdee_base_image $kubdee_container_image-setup
  container_wait_running $kubdee_container_image-setup
  begin
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
  end &>/dev/null
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
  incus config device add $container_name kmsg unix-char source=/dev/kmsg path=/dev/kmsg
end

function configure_controller
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  container_wait_running $container_name
  begin
      echo "
      curl -sfL https://get.k3s.io | sh -s - server --disable servicelb --disable traefik --write-kubeconfig-mode 644
      " | incus exec $container_name -- bash
  end &>/dev/null
end

function configure_worker
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  container_wait_running $container_name
  incus config device add $container_name k3s-binary disk source=$kubdee_dir/clusters/$cluster_name/rootfs/usr/local/bin/k3s path=/usr/local/bin/k3s
  set -l controller_name kubdee-$cluster_name-controller
  set -l token (incus exec $controller_name -- cat /var/lib/rancher/k3s/server/node-token)
  or exit_error "k3s server token not found on $controller_name. Dose the server run?" 1
  set -l server_ip4 (container_ip4_address $controller_name)
  begin
      incus exec $container_name -- k3s agent --server https://$server_ip4:6443 --token $token &
  end &>/dev/null
  or exit_error "Faild to start k3s agent on $container_name. " 1
end