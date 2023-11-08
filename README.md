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