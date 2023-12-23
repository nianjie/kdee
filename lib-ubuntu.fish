# Global constants
set -g kubdee_base_image images:ubuntu/jammy #require explicit global option, as being sourced within a function(main) body.

function fetch_k3s
  set -l cache_dir $kubdee_cache_dir/k3s/$k3s_version
  command mkdir -p $cache_dir
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

function fetch_k3s_binaries_impl
  set -l cache_dir $kubdee_cache_dir/k3s/$k3s_version
  set -l cluster_name $argv[1]
  set -l local_k3s_binary $argv[2]
  test -n $local_k3s_binary ; and copyl_or_exit_error $cache_dir $local_k3s_binary
  fetch_k3s
  set -l target_dir $kubdee_dir/clusters/$cluster_name/rootfs/usr/local/bin
  command mkdir -p $target_dir
  copyl_or_exit_error $target_dir $cache_dir/k3s
end

function launch_container_image_setup
  set -l cluster_name $argv[1]
  incus launch \
    --storage $cluster_name \
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
  end &>/dev/null
end

function configure_controller_impl
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  begin
    incus config device add $container_name k3s-binary disk source=$kubdee_dir/clusters/$cluster_name/rootfs/usr/local/bin/k3s path=/usr/local/bin/k3s
    incus exec $container_name -- chmod a+x /usr/local/bin/k3s
    incus exec $container_name -- ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
    incus exec $container_name -- ln -s /usr/local/bin/k3s /usr/local/bin/ctr
    incus exec $container_name -- ln -s /usr/local/bin/k3s /usr/local/bin/crictl
    incus exec $container_name -- sh -ic 'k3s server --write-kubeconfig-mode 644 &' # -i force interactive mode, otherwise the process to start server is interrupted.
  end # &>/dev/null # fail to start k3s server if output are closed.
end

function configure_worker_impl
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  begin
    incus config device add $container_name k3s-binary disk source=$kubdee_dir/clusters/$cluster_name/rootfs/usr/local/bin/k3s path=/usr/local/bin/k3s
  end &> /dev/null
  set -l controller_name kubdee-$cluster_name-controller
  set -l token (incus exec $controller_name -- cat /var/lib/rancher/k3s/server/node-token)
  or exit_error "k3s server token not found on $controller_name. Dose the server run?" 1
  set -l server_ip4 (container_ipv4_address $controller_name)
  begin
      incus exec $container_name -- k3s agent --server https://$server_ip4:6443 --token $token &
  end &>/dev/null
end