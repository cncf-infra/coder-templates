terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.6.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.15.0"
    }
  }
}

# https://www.terraform.io/language/providers/configuration#provider-configuration-1
# > You can use expressions in the values of these configuration arguments,
# but can only reference values that are known before the configuration is applied.
# This means you can safely reference input variables, but not attributes
# exported by resources (with an exception for resource arguments that
# are specified directly in the configuration).
#### no data.X :(
# provider "kubernetes" {
#   alias                  = "vcluster"
#   host                   = yamldecode(data.kubernetes_resource.kubeconfig.data)["value"]["clusters"][0]["cluster"]["server"]
#   client_certificate     = base64decode(yamldecode(data.kubernetes_resource.kubeconfig.data)["value"]["users"][0]["user"]["client-certificate-data"])
#   client_key             = base64decode(yamldecode(data.kubernetes_resource.kubeconfig.data)["value"]["users"][0]["user"]["client-key-data"])
#   cluster_ca_certificate = base64decode(yamldecode(data.kubernetes_resource.kubeconfig.data)["value"]["clusters"][0]["cluster"]["certificate-authority-data"])
# }

# variable "base_domain" {
#   type    = string
#   default = "sanskar.pair.sharing.io"
# }

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  startup_script = <<EOT
    #!/bin/bash

    # home folder can be empty, so copying default bash settings
    if [ ! -f ~/.profile ]; then
      cp /etc/skel/.profile $HOME
    fi
    if [ ! -f ~/.bashrc ]; then
      cp /etc/skel/.bashrc $HOME
    fi
    echo 'export PATH="$PATH:$HOME/bin"' >> $HOME/.bashrc

    sudo apt-get install -y tmux ttyd libwebsockets-evlib-uv
    # start broadwayd and emacs
    broadwayd :5 2>&1 | tee broadwayd.log &
    GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 emacs 2>&1 | tee emacs.log &
    # start ttyd / tmux
    tmux new -d
    ttyd tmux at 2>&1 | tee ttyd.log &
    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh  | tee code-server-install.log
    code-server --auth none --port 13337 | tee code-server-install.log &
  EOT
}


# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  display_name = "code-server"
  slug         = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder"
  subdomain    = false

  # healthcheck {
  #   url       = "http://localhost:13337/healthz"
  #   interval  = 3
  #   threshold = 10
  # }
}

resource "kubernetes_namespace" "workspace" {
  count = data.coder_workspace.me.start_count
  metadata {
    name = data.coder_workspace.me.name
    labels = {
      cert-manager-tls = "sync"
    }
  }
}

resource "kubernetes_manifest" "cluster" {
  manifest = {
    "apiVersion" = "cluster.x-k8s.io/v1beta1"
    "kind"       = "Cluster"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.coder_workspace.me.name
      "labels" = {
        "cluster-name" = data.coder_workspace.me.name
      }
    }
    "spec" = {
      "controlPlaneRef" = {
        "apiVersion" = "controlplane.cluster.x-k8s.io/v1beta1"
        "kind"       = "KubeadmControlPlane"
        "name"       = data.coder_workspace.me.name
        "namespace"  = data.coder_workspace.me.name
      }
      "infrastructureRef" = {
        "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
        "kind"       = "KubevirtCluster"
        "name"       = data.coder_workspace.me.name
        "namespace"  = data.coder_workspace.me.name
      }
      "clusterNetwork" = {
        "pods" = {
          "cidrBlocks" = [
            "10.243.0.0/16",
          ]
        }
        "services" = {
          "cidrBlocks" = [
            "10.95.0.0/16",
          ]
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.workspace
  ]
}

resource "kubernetes_manifest" "kvcluster" {
  manifest = {
    "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
    "kind"       = "KubevirtCluster"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.coder_workspace.me.name
    }
    "spec" = {
      "controlPlaneServiceTemplate" = {
        "spec" = {
          "type" = "ClusterIP"
        }
      }
      # "controlPlaneEndpoint" = {
      #   "host" = ""
      #   "port" = 0
      # }
      # "kubernetesVersion" = "1.23.4"
      # "helmRelease" = {
      #   "chart" = {
      #     "name"    = null
      #     "repo"    = null
      #     "version" = null
      #   }
      #   "values" = <<-EOT
      #   service:
      #     type: NodePort
      #   securityContext:
      #     runAsUser: 12345
      #     runAsNonRoot: true
      #     privileged: false
      #   syncer:
      #     extraArgs:
      #       - --tls-san="${data.coder_workspace.me.name}.${var.base_domain}"
      #       - --tls-san="${data.coder_workspace.me.name}.${data.coder_workspace.me.name}.svc"
      #   EOT
      # }
    }
  }

  depends_on = [
    kubernetes_namespace.workspace
  ]
}

resource "kubernetes_manifest" "kubevirtmachinetemplate_control_plane" {
  manifest = {
    "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
    "kind"       = "KubevirtMachineTemplate"
    "metadata" = {
      "name"      = "${data.coder_workspace.me.name}-cp"
      "namespace" = data.coder_workspace.me.name
    }
    "spec" = {
      "template" = {
        "spec" = {
          "virtualMachineTemplate" = {
            "metadata" = {
              "namespace" = data.coder_workspace.me.name
            }
            "spec" = {
              "runStrategy" = "Always"
              "dataVolumeTemplates" = [
                {
                  "metadata" = {
                    "name"      = "${data.coder_workspace.me.name}-cp-dv"
                    "namespace" = data.coder_workspace.me.name
                  }
                  "spec" = {
                    "source" = {
                      "registry" = {
                        "url" = "docker://quay.io/capk/ubuntu-2004-container-disk:v1.22.0"
                      }
                    }
                    "pvc" = {
                      "accessModes" = ["ReadWriteOnce"]
                      "resources" = {
                        "requests" = {
                          "storage" = "500Gi"
                        }
                      }
                    }
                  }
                }
              ]
              "template" = {
                "spec" = {
                  "domain" = {
                    "cpu" = {
                      "cores" = 2
                    }
                    "devices" = {
                      "disks" = [
                        {
                          "disk" = {
                            "bus" = "virtio"
                          }
                          "name" = "containervolume"
                        },
                      ]
                    }
                    "memory" = {
                      "guest" = "12Gi"
                    }
                  }
                  "evictionStrategy" = "External"
                  "volumes" = [
                    {
                      "persistentVolumeClaim" = {
                        "claimName" = "${data.coder_workspace.me.name}-cp-dv"
                      }
                      "name" = "containervolume"
                    },
                  ]
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.workspace
  ]
}

resource "kubernetes_manifest" "kubeadmcontrolplane_control_plane" {
  manifest = {
    "apiVersion" = "controlplane.cluster.x-k8s.io/v1beta1"
    "kind"       = "KubeadmControlPlane"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.coder_workspace.me.name
    }
    "spec" = {
      "kubeadmConfigSpec" = {
        "clusterConfiguration" = {
          "networking" = {
            "podSubnet"     = "10.244.0.0/16"
            "serviceSubnet" = "10.95.0.0/16"
          }
        }
        "initConfiguration" = {
          "nodeRegistration" = {
            "criSocket" = "/var/run/containerd/containerd.sock"
          }
        }
        "joinConfiguration" = {
          "nodeRegistration" = {
            "criSocket" = "{CRI_PATH}"
          }
        }
        "postKubeadmCommands" = [
          "kubectl --kubeconfig=/etc/kubernetes/admin.conf taint nodes --all node-role.kubernetes.io/master-"
        ]
      }
      "machineTemplate" = {
        "infrastructureRef" = {
          "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
          "kind"       = "KubevirtMachineTemplate"
          "name"       = "${data.coder_workspace.me.name}-cp"
          "namespace"  = data.coder_workspace.me.name
        }
      }
      "replicas" = 1
      "version"  = "v1.23.5"
    }
  }

  depends_on = [
    kubernetes_namespace.workspace
  ]
}

resource "kubernetes_manifest" "vm-data-volume" {
  manifest = {
    "apiVersion" = "cdi.kubevirt.io/v1beta1"
    "kind"       = "DataVolume"
    "metadata" = {
      "name"      = "${data.coder_workspace.me.name}-dv"
      "namespace" = data.coder_workspace.me.name
    }
    "spec" = {
      "source" = {
        "registry" = {
          "url" = "docker://quay.io/capk/ubuntu-2004-container-disk:v1.22.0"
        }
      }
      "pvc" = {
        "accessModes" = ["ReadWriteOnce"]
        "resources" = {
          "requests" = {
            "storage" = "30Gi"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.workspace
  ]
}

resource "kubernetes_manifest" "kubevirtmachinetemplate_md_0" {
  manifest = {
    "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
    "kind"       = "KubevirtMachineTemplate"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.coder_workspace.me.name
    }
    "spec" = {
      "template" = {
        "spec" = {
          "virtualMachineTemplate" = {
            "spec" = {
              "runStrategy" = "Always"
              "dataVolumeTemplates" = [
                {
                  "metadata" = {
                    "name"      = "${data.coder_workspace.me.name}-dv"
                    "namespace" = data.coder_workspace.me.name
                  }
                  "spec" = {
                    "source" = {
                      "registry" = {
                        "url" = "docker://quay.io/capk/ubuntu-2004-container-disk:v1.22.0"
                      }
                    }
                    "pvc" = {
                      "accessModes" = ["ReadWriteOnce"]
                      "resources" = {
                        "requests" = {
                          "storage" = "500Gi"
                        }
                      }
                    }
                  }
                }
              ]
              "template" = {
                "spec" = {
                  "domain" = {
                    "cpu" = {
                      "cores" = 2
                    }
                    "devices" = {
                      "disks" = [
                        {
                          "disk" = {
                            "bus" = "virtio"
                          }
                          "name" = "containervolume"
                        },
                      ]
                    }
                    "memory" = {
                      "guest" = "12Gi"
                    }
                  }
                  "evictionStrategy" = "External"
                  "volumes" = [
                    {
                      "persistentVolumeClaim" = {
                        "claimName" = "${data.coder_workspace.me.name}-dv"
                      }
                      "name" = "containervolume"
                    },
                  ]
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.workspace,
    kubernetes_manifest.vm-data-volume
  ]
}

resource "kubernetes_manifest" "kubeadmconfigtemplate_md_0" {
  manifest = {
    "apiVersion" = "bootstrap.cluster.x-k8s.io/v1beta1"
    "kind"       = "KubeadmConfigTemplate"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.coder_workspace.me.name
    }
    # "spec" = {
    #   "template" = {
    #     "spec" = {
    #       "joinConfiguration" = {
    #         "nodeRegistration" = {
    #           #"kubeletExtraArgs" = {}
    #           "kubeletExtraArgs" = null
    #         }
    #       }
    #     }
    #   }
    # }
  }

  depends_on = [
    kubernetes_namespace.workspace
  ]
}

resource "kubernetes_manifest" "machinedeployment_md_0" {
  manifest = {
    "apiVersion" = "cluster.x-k8s.io/v1beta1"
    "kind"       = "MachineDeployment"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.coder_workspace.me.name
    }
    "spec" = {
      "clusterName" = data.coder_workspace.me.name
      "replicas"    = 0
      "selector" = {
        "matchLabels" = null
      }
      "template" = {
        "spec" = {
          "bootstrap" = {
            "configRef" = {
              "apiVersion" = "bootstrap.cluster.x-k8s.io/v1beta1"
              "kind"       = "KubeadmConfigTemplate"
              "name"       = data.coder_workspace.me.name
              "namespace"  = data.coder_workspace.me.name
            }
          }
          "clusterName" = "kv1"
          "infrastructureRef" = {
            "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
            "kind"       = "KubevirtMachineTemplate"
            "name"       = data.coder_workspace.me.name
            "namespace"  = data.coder_workspace.me.name
          }
          "version" = "v1.23.5"
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.workspace
  ]
}

resource "kubernetes_manifest" "configmap_capi_init" {
  manifest = {
    "kind" = "ConfigMap"
    "metadata" = {
      "name"      = "capi-init"
      "namespace" = data.coder_workspace.me.name
    }
    "apiVersion" = "v1"
    "data" = {
      "cool.yaml" = templatefile("cool.template.yaml",
        {
          coder_command = jsonencode(["sh", "-c", coder_agent.main.init_script]),
          coder_token   = coder_agent.main.token
          instance_name = data.coder_workspace.me.name
      })
      "flannel.yaml" = templatefile("flannel.yaml", {})
    }
  }

  depends_on = [
    kubernetes_namespace.workspace
  ]
}

# data "kubernetes_secret" "vcluster-kubeconfig" {
#   metadata {
#     name      = "${data.coder_workspace.me.name}-kubeconfig"
#     namespace = data.coder_workspace.me.name
#   }

#   depends_on = [
#     kubernetes_manifest.cluster,
#     kubernetes_manifest.vcluster,
#     kubernetes_manifest.clusterresourceset_capi_init
#   ]
# }

# // using a manifest instead of secret, so that the wait capability works
# resource "kubernetes_manifest" "configmap_capi_kubeconfig" {
#   manifest = {
#     "kind" = "Secret"
#     "metadata" = {
#       "name"      = "vcluster-kubeconfig"
#       "namespace" = data.coder_workspace.me.name
#     }
#     "apiVersion" = "v1"
#     "type"       = "addons.cluster.x-k8s.io/resource-set"
#     "data" = {
#       "kubeconfig.yaml" = base64encode(data.kubernetes_secret.vcluster-kubeconfig.data.value)
#     }
#   }

#   depends_on = [
#     kubernetes_manifest.cluster,
#     kubernetes_manifest.vcluster,
#     kubernetes_manifest.clusterresourceset_capi_init,
#     data.kubernetes_secret.vcluster-kubeconfig
#   ]

#   wait {
#     fields = {
#       "data[\"kubeconfig.yaml\"]" = "*"
#     }
#   }

#   timeouts {
#     create = "1m"
#   }
# }

resource "kubernetes_manifest" "clusterresourceset_capi_init" {
  manifest = {
    "apiVersion" = "addons.cluster.x-k8s.io/v1beta1"
    "kind"       = "ClusterResourceSet"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.coder_workspace.me.name
    }
    "spec" = {
      "clusterSelector" = {
        "matchLabels" = {
          "cluster-name" = data.coder_workspace.me.name
        }
      }
      "resources" = [
        {
          "kind" = "ConfigMap"
          "name" = "capi-init"
        },
        # {
        #   "kind" = "Secret"
        #   "name" = "vcluster-kubeconfig"
        # },
      ]
      "strategy" = "ApplyOnce"
    }
  }

  depends_on = [
    kubernetes_namespace.workspace
  ]
}
# data "kubernetes_resource" "cluster-kubeconfig" {
#   api_version = "v1"
#   kind        = "Secret"
#   metadata {
#     name      = "${data.coder_workspace.me.name}-kubeconfig"
#     namespace = data.coder_workspace.me.name
#   }

#   depends_on = [
#     kubernetes_namespace.workspace,
#     kubernetes_manifest.cluster,
#     kubernetes_manifest.vcluster
#   ]
# }

# This is generated from the vcluster...
# Need to find a way for it to wait before running, so that the secret exists

# We'll need to use the kubeconfig from above to provision the coder/pair environment
# resource "kubernetes_manifest" "ingress_vcluster" {
#   manifest = {
#     "apiVersion" = "projectcontour.io/v1"
#     "kind"       = "HTTPProxy"
#     "metadata" = {
#       "name"      = "${data.coder_workspace.me.name}-apiserver"
#       "namespace" = data.coder_workspace.me.name
#       "annotations" = {
#         "projectcontour.io/ingress.class" = "contour-external"
#       }
#     }
#     "spec" = {
#       "tcpproxy" = {
#         "services" = [
#           {
#             "name" = "${data.coder_workspace.me.name}"
#             "port" = 443
#           },
#         ]
#       }
#       "virtualhost" = {
#         "fqdn" = "${data.coder_workspace.me.name}.${var.base_domain}"
#         "tls" = {
#           "passthrough" = true
#         }
#       }
#     }
#   }
# }

# tmux
resource "coder_app" "tmux" {
  agent_id     = coder_agent.main.id
  display_name = "tmux"
  slug         = "tmux"
  icon         = "/icon/folder.svg" # let's maybe get an emacs.svg somehow
  command      = "tmux at"
  share        = "public"
}

# ttyd
resource "coder_app" "ttyd" {
  subdomain    = false
  share        = "public"
  slug         = "ttyd"
  display_name = "ttyd for tmux"
  icon         = "/icon/folder.svg" # let's maybe get an emacs.svg somehow
  agent_id     = coder_agent.main.id
  url          = "http://localhost:7681" # 7681 is the default ttyd port

  # healthcheck {
  #   # don't want to disconnect current session, but hopefully this will 200OK
  #   url       = "http://localhost:7681/"
  #   interval  = 3
  #   threshold = 10
  # }
}

# emacs-broadway
resource "coder_app" "emacs-broadway" {
  subdomain    = false
  share        = "public"
  agent_id     = coder_agent.main.id
  slug         = "emacs-broadway"
  display_name = "Emacs on Broadway"
  icon         = "/icon/folder.svg"      # let's maybe get an emacs.svg somehow
  url          = "http://localhost:8085" # port 8080 + BROADWAY_DISPLAY

  # healthcheck {
  #   # don't want to disconnect current session, but hopefully this will 200OK
  #   url       = "http://localhost:8085/"
  #   interval  = 3
  #   threshold = 10
  # }
}

resource "time_sleep" "wait_50_seconds" {
  create_duration = "50s"
}
data "kubernetes_secret_v1" "kubeconfig" {
  metadata {
    name      = "${data.coder_workspace.me.name}-kubeconfig"
    namespace = data.coder_workspace.me.name
  }

  depends_on = [
    kubernetes_manifest.clusterresourceset_capi_init,
    kubernetes_manifest.kubeadmcontrolplane_control_plane,
    kubernetes_manifest.kvcluster,
    kubernetes_manifest.cluster,
    time_sleep.wait_50_seconds
  ]
}

resource "coder_metadata" "kubeconfig" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_namespace.workspace[0].id
  item {
    key   = "description"
    value = "The kubeconfig to connect to the cluster with"
  }
  item {
    key       = "kubeconfig"
    value     = data.kubernetes_secret_v1.kubeconfig == null ? "" : data.kubernetes_secret_v1.kubeconfig.data.value
    sensitive = true
  }

  depends_on = [
    data.kubernetes_secret_v1.kubeconfig,
    time_sleep.wait_50_seconds
  ]
}

