terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.6.5"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.16.1"
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
    mkdir -p bin

    (
      cd
      for repo in $INIT_DEFAULT_REPOS; do (git-clone-structured "https://github.com/$repo" || true); done
    ) | tee repo-clone.log &

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh  | tee code-server-install.log
    code-server --auth none --port 13337 | tee code-server-install.log &
  EOT
}

variable "repos" {
  type        = string
  description = "GitHub repos to clone; i.e: kubernetes/kubernetes, cncf/k8s-conformance"
  default     = "kubernetes/kubernetes"
}

# code-server
resource "coder_app" "code-server" {
  slug         = "code-server"
  subdomain    = true
  display_name = "Code Server"
  agent_id     = coder_agent.main.id
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder"
  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

data "kubernetes_namespace" "workspace" {
  # count = data.coder_workspace.me.start_count
  metadata {
    name = "coder-workspaces"
  }
}

resource "kubernetes_manifest" "cluster" {
  manifest = {
    "apiVersion" = "cluster.x-k8s.io/v1beta1"
    "kind"       = "Cluster"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
      "labels" = {
        "cluster-name" = data.coder_workspace.me.name
      }
    }
    "spec" = {
      "controlPlaneRef" = {
        "apiVersion" = "controlplane.cluster.x-k8s.io/v1beta1"
        "kind"       = "TalosControlPlane"
        "name"       = data.coder_workspace.me.name
        "namespace"  = data.kubernetes_namespace.workspace.metadata[0].name
      }
      "infrastructureRef" = {
        "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
        "kind"       = "KubevirtCluster"
        "name"       = data.coder_workspace.me.name
        "namespace"  = data.kubernetes_namespace.workspace.metadata[0].name
      }
      "clusterNetwork" = {
        "pods" = {
          "cidrBlocks" = [
            "10.244.0.0/16",
          ]
        }
        "services" = {
          "cidrBlocks" = [
            "10.96.0.0/12",
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "kvcluster" {
  manifest = {
    "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
    "kind"       = "KubevirtCluster"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
    }
    "spec" = {
      "controlPlaneServiceTemplate" = {
        "spec" = {
          "type" = "ClusterIP"
        }
      }
    }
  }
}

resource "kubernetes_manifest" "kubevirtmachinetemplate_control_plane" {
  manifest = {
    "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
    "kind"       = "KubevirtMachineTemplate"
    "metadata" = {
      "name"      = "${data.coder_workspace.me.name}-cp"
      "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
    }
    "spec" = {
      "template" = {
        "spec" = {
          "virtualMachineTemplate" = {
            "metadata" = {
              "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
            }
            "spec" = {
              "runStrategy" = "Always"
              "dataVolumeTemplates" = [
                {
                  "metadata" = {
                    "name" = "vmdisk-dv"
                  }
                  "spec" = {
                    "pvc" = {
                      "accessModes" = ["ReadWriteOnce"]
                      "resources" = {
                        "requests" = {
                          "storage" = "50Gi"
                        }
                      }
                    }
                    "source" = {
                      "registry" = {
                        "url" = "docker://quay.io/containercraft/talos/nocloud@sha256:4b68854f63b15fa2ebd57b53dc293ce17babb6a0f2d77373cdc30e964bb65ca3"
                      }
                    }
                  }
                },
              ]
              "template" = {
                "spec" = {
                  "domain" = {
                    "cpu" = {
                      "cores" = 2
                    }
                    "devices" = {
                      "interfaces" = [
                        {
                          "name"   = "default"
                          "bridge" = {}
                        }
                      ]
                      "disks" = [
                        {
                          "disk" = {
                            "bus" = "scsi"
                          }
                          "bootOrder" = 1
                          "name"      = "vmdisk"
                        },
                      ]
                      "rng" = {}
                    }
                    "memory" = {
                      "guest" = "4Gi"
                    }
                  }
                  "evictionStrategy" = "External"
                  "networks" = [
                    {
                      "name" = "default"
                      "pod"  = {}
                    }
                  ]
                  "volumes" = [
                    {
                      "cloudInitNoCloud" = {}
                      "name"             = "cloudinitvolume"
                    },
                    {
                      "dataVolume" = {
                        "name" = "vmdisk-dv"
                      }
                      "name" = "vmdisk"
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
}

resource "kubernetes_manifest" "taloscontrolplane_talos_em_control_plane" {
  manifest = {
    "apiVersion" = "controlplane.cluster.x-k8s.io/v1alpha3"
    "kind"       = "TalosControlPlane"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
    }
    "spec" = {
      "controlPlaneConfig" = {
        "controlplane" = {
          "generateType" = "controlplane"
          "configPatches" = [
            {
              "op"    = "add"
              "path"  = "/debug"
              "value" = true
            },
            {
              "op"   = "add"
              "path" = "/machine/network"
              "value" = {
                "nameservers" = ["8.8.8.8", "1.1.1.1"]
              }
            },
            {
              "op"   = "replace"
              "path" = "/machine/install"
              "value" = {
                "bootloader"      = true
                "wipe"            = false
                "disk"            = "/dev/sda"
                "image"           = "ghcr.io/siderolabs/installer:v1.2.5"
                "extraKernelArgs" = ["console=ttyS0"]
              }
            },
            {
              "op"   = "add"
              "path" = "/cluster/apiServer/admissionControl/0/configuration"
              "value" = {
                "apiVersion" = "pod-security.admission.config.k8s.io/v1alpha1"
                "kind"       = "PodSecurityConfiguration"
                "defaults" = {
                  "enforce"         = "privileged"
                  "enforce-version" = "latest"
                  "audit"           = "restricted"
                  "audit-version"   = "latest"
                  "warn"            = "restricted"
                  "warn-version"    = "latest"
                }
                "exemptions" = {
                  "usernames"      = []
                  "runtimeClasses" = []
                  "namespaces"     = ["kube-system"]
                }
              }
            },
            # {
            #   "op"   = "add"
            #   "path" = "/machine/kubelet/extraArgs"
            #   "value" = {
            #     "cloud-provider" = "external"
            #   }
            # },
            # {
            #   "op"   = "add"
            #   "path" = "/cluster/apiServer/extraArgs"
            #   "value" = {
            #     "cloud-provider" = "external"
            #   }
            # },
            # {
            #   "op"   = "add"
            #   "path" = "/cluster/controllerManager/extraArgs"
            #   "value" = {
            #     "cloud-provider" = "external"
            #   }
            # },
            {
              "op"    = "add"
              "path"  = "/cluster/allowSchedulingOnControlPlanes"
              "value" = true
            }
          ]
        }
        "init" = {
          "configPatches" = [
            {
              "op"   = "replace"
              "path" = "/machine/install"
              "value" = {
                "bootloader"      = true
                "wipe"            = false
                "disk"            = "/dev/sda"
                "image"           = "ghcr.io/siderolabs/installer:v1.2.5"
                "extraKernelArgs" = ["console=ttyS0"]
              }
            },
            {
              "op"   = "add"
              "path" = "/cluster/apiServer/admissionControl/0/configuration"
              "value" = {
                "apiVersion" = "pod-security.admission.config.k8s.io/v1alpha1"
                "kind"       = "PodSecurityConfiguration"
                "defaults" = {
                  "enforce"         = "privileged"
                  "enforce-version" = "latest"
                  "audit"           = "restricted"
                  "audit-version"   = "latest"
                  "warn"            = "restricted"
                  "warn-version"    = "latest"
                }
                "exemptions" = {
                  "usernames"      = []
                  "runtimeClasses" = []
                  "namespaces"     = ["kube-system"]
                }
              }
            },
            {
              "op"    = "add"
              "path"  = "/debug"
              "value" = true
            },
            {
              "op"   = "add"
              "path" = "/machine/network"
              "value" = {
                "nameservers" = ["8.8.8.8", "1.1.1.1"]
              }
            },
            # {
            #   "op"   = "add"
            #   "path" = "/machine/kubelet/extraArgs"
            #   "value" = {
            #     "cloud-provider" = "external"
            #   }
            # },
            # {
            #   "op"   = "add"
            #   "path" = "/cluster/apiServer/extraArgs"
            #   "value" = {
            #     "cloud-provider" = "external"
            #   }
            # },
            # {
            #   "op"   = "add"
            #   "path" = "/cluster/controllerManager/extraArgs"
            #   "value" = {
            #     "cloud-provider" = "external"
            #   }
            # },
            {
              "op"    = "add"
              "path"  = "/cluster/allowSchedulingOnControlPlanes"
              "value" = true
            },
          ]
          "generateType" = "init"
        }
      }
      "infrastructureTemplate" = {
        "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
        "kind"       = "KubevirtMachineTemplate"
        "name"       = "${data.coder_workspace.me.name}-cp"
      }
      "replicas" = 1
      "version"  = "v1.25.2"
    }
  }
}

resource "kubernetes_manifest" "kubevirtmachinetemplate_md_0" {
  manifest = {
    "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
    "kind"       = "KubevirtMachineTemplate"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
    }
    "spec" = {
      "template" = {
        "spec" = {
          "virtualMachineTemplate" = {
            "metadata" = {
              "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
            }
            "spec" = {
              "runStrategy" = "Always"
              "dataVolumeTemplates" = [
                {
                  "metadata" = {
                    "name" = "vmdisk-dv"
                  }
                  "spec" = {
                    "pvc" = {
                      "accessModes" = [
                        "ReadWriteOnce"
                      ]
                      "resources" = {
                        "requests" = {
                          "storage" = "50Gi"
                        }
                      }
                    }
                    "source" = {
                      "registry" = {
                        "url" = "docker://quay.io/containercraft/talos/nocloud@sha256:4b68854f63b15fa2ebd57b53dc293ce17babb6a0f2d77373cdc30e964bb65ca3"
                      }
                    }
                  }
                },
              ]
              "template" = {
                "spec" = {
                  "domain" = {
                    "cpu" = {
                      "cores" = 2
                    }
                    "devices" = {
                      "interfaces" = [
                        {
                          "name"   = "default"
                          "bridge" = {}
                        }
                      ]
                      "disks" = [
                        {
                          "disk" = {
                            "bus" = "virtio"
                          }
                          "name" = "vmdisk"
                        },
                      ]
                      "rng" = {}
                    }
                    "memory" = {
                      "guest" = "4Gi"
                    }
                  }
                  "evictionStrategy" = "External"
                  "networks" = [
                    {
                      "name" = "default"
                      "pod"  = {}
                    }
                  ]
                  "volumes" = [
                    {
                      "cloudInitNoCloud" = {}
                      "name"             = "cloudinitvolume"
                    },
                    {
                      "dataVolume" = {
                        "name" = "vmdisk-dv"
                      }
                      "name" = "vmdisk"
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
}

resource "kubernetes_manifest" "talosconfigtemplate_talos_em_worker_a" {
  manifest = {
    "apiVersion" = "bootstrap.cluster.x-k8s.io/v1alpha3"
    "kind"       = "TalosConfigTemplate"
    "metadata" = {
      "labels" = {
        "cluster.x-k8s.io/cluster-name" = data.coder_workspace.me.name
      }
      "name"      = data.coder_workspace.me.name
      "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
    }
    "spec" = {
      "template" = {
        "spec" = {
          "generateType" = "join"
          "talosVersion" = "v1.2.5"
        }
      }
    }
  }
}

resource "kubernetes_manifest" "machinedeployment_md_0" {
  manifest = {
    "apiVersion" = "cluster.x-k8s.io/v1beta1"
    "kind"       = "MachineDeployment"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
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
              "kind"       = "TalosConfigTemplate"
              "name"       = data.coder_workspace.me.name
              "namespace"  = data.kubernetes_namespace.workspace.metadata[0].name
            }
          }
          "clusterName" = "kv1"
          "infrastructureRef" = {
            "apiVersion" = "infrastructure.cluster.x-k8s.io/v1alpha1"
            "kind"       = "KubevirtMachineTemplate"
            "name"       = data.coder_workspace.me.name
            "namespace"  = data.kubernetes_namespace.workspace.metadata[0].name
          }
          "version" = "v1.23.5"
        }
      }
    }
  }
}

resource "kubernetes_manifest" "configmap_capi_init" {
  manifest = {
    "kind" = "ConfigMap"
    "metadata" = {
      "name"      = "${data.coder_workspace.me.name}-capi-init"
      "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
    }
    "apiVersion" = "v1"
    "data" = {
      "namespaces" = templatefile("namespaces.yaml", {})
      "cool.yaml" = templatefile("cool.template.yaml",
        {
          coder_command = jsonencode(["sh", "-c", coder_agent.main.init_script]),
          coder_token   = coder_agent.main.token
          instance_name = data.coder_workspace.me.name
          repos         = var.repos
      })
      "ingress-nginx" = templatefile("ingress-nginx.yaml", {})
    }
  }
}

resource "kubernetes_manifest" "clusterresourceset_capi_init" {
  manifest = {
    "apiVersion" = "addons.cluster.x-k8s.io/v1beta1"
    "kind"       = "ClusterResourceSet"
    "metadata" = {
      "name"      = data.coder_workspace.me.name
      "namespace" = data.kubernetes_namespace.workspace.metadata[0].name
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
          "name" = "${data.coder_workspace.me.name}-capi-init"
        },
        # {
        #   "kind" = "Secret"
        #   "name" = "vcluster-kubeconfig"
        # },
      ]
      "strategy" = "ApplyOnce"
    }
  }
}

resource "kubernetes_service" "cluster_port_web_traffic" {
  metadata {
    name      = "${data.coder_workspace.me.name}-web"
    namespace = data.kubernetes_namespace.workspace.metadata[0].name
  }
  spec {
    selector = {
      "cluster.x-k8s.io/cluster-name" = data.coder_workspace.me.name
    }
    port {
      name        = "http"
      port        = "80"
      target_port = "31080"
    }
    port {
      name        = "https"
      port        = "31443"
      target_port = "443"
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "cluster_port_web_traffic" {
  metadata {
    name      = "${data.coder_workspace.me.name}-web"
    namespace = data.kubernetes_namespace.workspace.metadata[0].name
    annotations = {
      "test_a" = data.coder_workspace.me.access_url
    }
  }
  spec {
    rule {
      host = "${data.coder_workspace.me.name}.coder.sharing.io"
      http {
        path {
          path      = "/"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "${data.coder_workspace.me.name}-web"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
    rule {
      host = "*.${data.coder_workspace.me.name}.coder.sharing.io"
      http {
        path {
          path      = "/"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "${data.coder_workspace.me.name}-web"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

# resource "time_sleep" "wait_50_seconds" {
#   create_duration = "50s"
# }
# data "kubernetes_secret_v1" "kubeconfig" {
#   metadata {
#     name      = "${data.coder_workspace.me.name}-kubeconfig"
#     namespace = data.coder_workspace.me.name
#   }

#   depends_on = [
#     kubernetes_manifest.clusterresourceset_capi_init,
#     kubernetes_manifest.taloscontrolplane_talos_em_control_plane,
#     kubernetes_manifest.kvcluster,
#     kubernetes_manifest.cluster,
#     time_sleep.wait_50_seconds
#   ]
# }

# resource "coder_metadata" "kubeconfig" {
#   count       = data.coder_workspace.me.start_count
#   resource_id = data.kubernetes_namespace.workspace[0].id
#   item {
#     key   = "description"
#     value = "The kubeconfig to connect to the cluster with"
#   }
#   item {
#     key       = "kubeconfig"
#     value     = data.kubernetes_secret_v1.kubeconfig == null ? "" : data.kubernetes_secret_v1.kubeconfig.data.value
#     sensitive = true
#   }

#   depends_on = [
#     data.kubernetes_secret_v1.kubeconfig,
#     time_sleep.wait_50_seconds
#   ]
# }
