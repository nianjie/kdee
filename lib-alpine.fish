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

function configure_cgroup
  set -l container_name $argv[1]
  begin
    set -l cgroup_path /sys/fs/cgroup
    set -l processes (incus exec $container_name -- cat $cgroup_path/cgroup.procs )
    test -z "$processes" ; and exit_error "Faild to configure $container_name." 1
    incus exec $container_name -- mkdir -p $cgroup_path/init.scope
    and for p in $processes
      incus exec $container_name -- sh -c "echo $p > $cgroup_path/init.scope/cgroup.procs"
    end
    and incus exec $container_name -- sh -c  "echo '+cpuset +cpu +io +memory +hugetlb +pids +rdma' >$cgroup_path/cgroup.subtree_control"
  end
end

function configure_controller_impl
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  begin
    configure_cgroup $argv[2]
    incus exec $container_name -- sh -c 'rc-service k3s start'
   end &>/dev/null
end

function configure_worker_impl
  set -l cluster_name $argv[1]
  set -l container_name $argv[2]
  set -l controller_name kubdee-$cluster_name-controller
  set -l token (incus exec $controller_name -- cat /var/lib/rancher/k3s/server/node-token)
  or exit_error "k3s server token not found on $controller_name. Dose the server run?" 1
  set -l server_ip4 (container_ipv4_address $controller_name)
  begin
    configure_cgroup $container_name
    incus exec $container_name -- sh -c "echo '# k3s options
export PATH=\"/usr/libexec/cni/:\$PATH\"
K3S_EXEC=\"agent\"
K3S_OPTS=\"--server https://$server_ip4:6443 --token $token \"
' > /etc/conf.d/k3s
"
    incus exec $container_name -- rc-service k3s start
  end &>/dev/null
end