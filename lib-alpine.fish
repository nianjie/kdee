# Global constants
set -g kubdee_base_image 'images:alpine/3.18' # require explicit global option as is sourced within a function body.

function launch_container_image_setup
  set -l cluster_name $argv[1]
  incus launch \
    --storage $cluster_name \
    --profile default \
    $kubdee_base_image $kubdee_container_image-setup
  container_wait_running $kubdee_container_image-setup
  begin
    echo "
    apk add k3s
  " | incus exec $kubdee_container_image-setup -- ash
  end &>/dev/null
end

function configure_controller_impl
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  begin
    set -l cgroup_path /sys/fs/cgroup
    set -l processes (incus exec $container_name -- cat $cgroup_path/cgroup.procs )
    test -z "$processes" ; and exit_error "Faild to configure control-plane node." 1
    incus exec $container_name -- mkdir -p $cgroup_path/init.scope
    and for p in $processes
      incus exec $container_name -- sh -c "echo $p > $cgroup_path/init.scope/cgroup.procs"
    end
    and incus exec $container_name -- sh -c  "echo '+cpuset +cpu +io +memory +hugetlb +pids +rdma' >$cgroup_path/cgroup.subtree_control"
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