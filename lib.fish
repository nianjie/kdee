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
  