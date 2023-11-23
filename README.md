# kubdee
#### A tool to setup multi-nodes k8s clusters on [linux containers](https://linuxcontainers.org/) on a single machine or vm.

## Requirements
* [incus](https://github.com/lxc/incus)
* [fish](https://github.com/fish-shell/fish-shell)
* [jq](https://stedolan.github.io/jq/)
* kubectl

## Installation


## Usage


## Release Notes
* v0.1 - Implemented basic commands, including `create`, `start`, `start-worker`, `up`, and `delete`.
* v0.2 - Improved process of containers configuration required for running k8s by converting profile-applying into config-options-applying at launching phase.
* v0.3 - Implemented integration of kubeconfig configuration feature, with it you can access with kubectl outside the cluster.
* v0.4 - Implemented feature of automation of importing local container images. 
  * If any container images exported from repository is prepared in a custom volume named as `images-repo`, they are imported into k8s nodes automatically.
* v0.5 - Implemented feature of supporting local k3s binary specification. This will be helpful in case of being unable to download k3s online. 
  * As the k3s binary will be cached in local, no need to specify local option again from next run.
* v0.6 - Implement selection of base image between ubuntu, alpine.