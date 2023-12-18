# kubdee
#### A tool to setup multi-nodes k8s clusters on [linux containers](https://linuxcontainers.org/) on a single machine or vm.

## Requirements
* [incus](https://github.com/lxc/incus)
* [fish](https://github.com/fish-shell/fish-shell)
* [jq](https://stedolan.github.io/jq/)
* kubectl

## Installation


## Usage

### Notice on environment where default alpine repository is not reachable
* The `profiles/apk-repo-mirrors.profile.yaml` contains apk package repository mirrors configuration. Import this file as the default profile because the profile used to launch containers are supposed to be the default one.
  * In order not to replace current default profile, create a separate project with `features.profiles` enabled on incus would be better.
  * The mirror is http://mirrors.tuna.tsinghua.edu.cn/alpine/. You could select your favorite one from the mirrors list:
    * https://mirrors.alpinelinux.org/

### Notice on `images-repo` volume
* Create the volume
```sh
$ incus storage volume create [cluster-name] images-repo
```
* Prepare image archives
```sh
# $STORAGE_POOL_LOCATION stands for storage pools location, default location is /var/lib/incus/storage-pools
$ cp my-container-images.tar $STORAGE_POOL_LOCATION/[cluster-name]/custom/default_images-repo
``` 
### Notice on `k3s-pv` volume
This volume is prepared for provision of local persistent volume for k8s containers. It is attached at `/mnt/disks/ssd1` on each k8s node.
* Create the volume
```sh
$ incus storage volume create [cluster-name] k3s-pv
```

## Release Notes
* v0.1 - Implemented basic commands, including `create`, `start`, `start-worker`, `up`, and `delete`.
* v0.2 - Improved process of containers configuration required for running k8s by converting profile-applying into config-options-applying at launching phase.
* v0.3 - Implemented integration of kubeconfig configuration feature, with it you can access with kubectl outside the cluster.
* v0.4 - Implemented feature of automation of importing local container images. 
  * If any container images exported from repository is prepared in a custom volume named as `images-repo`, they are imported into k8s nodes automatically.
* v0.5 - Implemented feature of supporting local k3s binary specification. This will be helpful in case of being unable to download k3s online. 
  * As the k3s binary will be cached in local, no need to specify local option again from next run.
* v0.6 - Implement selection of base image between ubuntu, alpine.
  * The default is alpine.
* v0.7 - Customize one of k3s packaged components(i.e. traefik), as well do some tweaks on openrc services of alpine.