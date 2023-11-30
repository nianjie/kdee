# Global constants
set kubdee_base_image images:alpine/3.18

function launch_container_image_setup
  set -l cluster_name $argv[1]
  incus launch \
    --storage $cluster_name \
    --profile default \
    $kubdee_base_image $kubdee_container_image-setup
  container_wait_running $kubdee_container_image-setup
  begin
    echo "
    cat /etc/os-release
  " | incus exec $kubdee_container_image-setup -- ash
  end &>/dev/null
end
