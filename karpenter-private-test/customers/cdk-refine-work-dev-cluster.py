from constructs import Construct
from aws_cdk import Stack, CfnTag, Fn, CfnOutput, Tags
from aws_cdk import aws_secretsmanager as secretsmanager

import aws_cdk.aws_ec2 as ec2
import aws_cdk.aws_iam as iam
import aws_cdk.aws_eks as eks

from .lib.aws_lib import get_secret_value

from aws_cdk.lambda_layer_kubectl_v31 import KubectlV31Layer
from aws_cdk.lambda_layer_kubectl_v32 import KubectlV32Layer

import yaml, json
import requests


class WorkDevStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # 이미 생성된 VPC 불러오기
        vpc = ec2.Vpc.from_lookup(self, "vpc",
            vpc_id="vpc-071605fa0b8f9a9cc"
        )

        # 프라이빗 서브넷 생성
        private_subnet_a = ec2.CfnSubnet(self, "private_subnet_a",
            availability_zone ="ap-northeast-2a",
            cidr_block="10.151.121.0/24",
            vpc_id=vpc.vpc_id,
            tags=[
                CfnTag(
                    key="Name",
                    value="eks-work-dev-subnet-a"
                )
            ]
        )

        # 프라이빗 서브넷 생성
        private_subnet_a2 = ec2.CfnSubnet(self, "private_subnet_a2",
            availability_zone ="ap-northeast-2a",
            cidr_block="10.151.122.0/24",
            vpc_id=vpc.vpc_id,
            tags=[
                CfnTag(
                    key="Name",
                    value="eks-work-dev-subnet-a2"
                )
            ]
        )

        private_subnet_c = ec2.CfnSubnet(self, "private_subnet_c",
            availability_zone ="ap-northeast-2c",
            cidr_block="10.151.123.0/24",
            vpc_id=vpc.vpc_id,
            tags=[
                CfnTag(
                    key="Name",
                    value="eks-work-dev-subnet-c"
                )
            ]
        )

        private_subnet_c2 = ec2.CfnSubnet(self, "private_subnet_c2",
            availability_zone ="ap-northeast-2c",
            cidr_block="10.151.124.0/24",
            vpc_id=vpc.vpc_id,
            tags=[
                CfnTag(
                    key="Name",
                    value="eks-work-dev-subnet-c2"
                )
            ]
        )

        # 기존에 생성된 라우팅 테이블 불러오기
        private_route_table_id = "rtb-0619b31b76b32d325"

        # 위에서 생성한 프라이빗 서브넷에 라우팅 테이블 연동
        private_subnet_a_rta = ec2.CfnSubnetRouteTableAssociation(self, "private_subnet_a_rta",
            route_table_id=private_route_table_id,
            subnet_id=private_subnet_a.ref
        )


        private_subnet_c_rta = ec2.CfnSubnetRouteTableAssociation(self, "private_subnet_c_rta",
            route_table_id=private_route_table_id,
            subnet_id=private_subnet_c.ref
        )
    
        private_subnet_a2_rta = ec2.CfnSubnetRouteTableAssociation(self, "private_subnet_a2_rta",
            route_table_id=private_route_table_id,
            subnet_id=private_subnet_a2.ref
        )

        private_subnet_c2_rta = ec2.CfnSubnetRouteTableAssociation(self, "private_subnet_c2_rta",
            route_table_id=private_route_table_id,
            subnet_id=private_subnet_c2.ref
        )


        ## EKS 클러스터 구성 요소

        # system:masters 그룹에 추가될 IAM 역할
        eks_master_role = iam.Role(self, "eks_master_role",
            assumed_by=iam.CompositePrincipal(
                iam.AccountPrincipal(self.account),
                iam.AccountPrincipal("032559872243")
            )
        )

        # EKS 클러스터 생성
        cluster = eks.Cluster(self, "cluster",
            cluster_name="work-dev",
            vpc=vpc,
            vpc_subnets=[
                ec2.SubnetSelection(subnets=[
                    ec2.Subnet.from_subnet_id(self, "eks-subnet1", private_subnet_a.ref),
                    ec2.Subnet.from_subnet_id(self, "eks-subnet2", private_subnet_c.ref)
                ])
            ],
            endpoint_access=eks.EndpointAccess.PRIVATE,
            version=eks.KubernetesVersion.V1_32,
            default_capacity=0,
            masters_role=eks_master_role,
            output_masters_role_arn=True,
            prune=False,
            kubectl_layer=KubectlV32Layer(self, "kubectl")
        )
        
        ########## EKS Addons ########## 
        kube_proxy_addon = eks.CfnAddon(self, "kube_proxy_addon",
            addon_name="kube-proxy",
            cluster_name=cluster.cluster_name,
            addon_version="v1.32.6-eksbuild.8",
            resolve_conflicts="OVERWRITE"
        )

        vpc_cni_addon = eks.CfnAddon(self, "vpc_cni_addon",
            addon_name="vpc-cni",
            cluster_name=cluster.cluster_name,
            addon_version="v1.20.1-eksbuild.3",
            resolve_conflicts="OVERWRITE"
        )


        corefile_content = """
        .:53 {
            errors
            health {
                lameduck 5s
            }
            ready
            kubernetes cluster.local in-addr.arpa ip6.arpa {
                pods insecure
                fallthrough in-addr.arpa ip6.arpa
            }
            prometheus :9153
            forward . /etc/resolv.conf
            cache 30
            loop
            reload
            loadbalance
        
            hosts {
                211.233.9.190 deposit-insu-alpha-v.toss.im
                fallthrough
            }
        }
        """

        coredns_config = {
            "corefile": corefile_content,
            "nodeSelector": {
                "node-group": "worker-critical"
            },
            "tolerations": [
                {
                    "key": "CriticalAddonsOnly",
                    "operator": "Exists",
                    "effect": "NoSchedule"
                }
            ],
            "affinity": {
                "podAntiAffinity": {
                    "requiredDuringSchedulingIgnoredDuringExecution": [
                        {
                            "labelSelector": {
                                "matchLabels": {
                                    "k8s-app": "kube-dns"
                                }
                            },
                            "topologyKey": "kubernetes.io/hostname"
                        }
                    ]
                }
            }                      
            
        }

        coredns_addon = eks.CfnAddon(self, "coredns_addon",
            addon_name="coredns",
            cluster_name=cluster.cluster_name,
            addon_version="v1.11.4-eksbuild.22",
            resolve_conflicts="OVERWRITE",
            configuration_values=json.dumps(coredns_config)
            # configuration_values="{\"computeType\":\"Fargate\"}"
        )

        ebs_csi_config = {
            "controller": {
                "nodeSelector": {
                    "node-group": "worker-critical"
                }                
            }
        }

        ebs_csi_addon = eks.CfnAddon(self, "ebs_csi_addon",
            addon_name="aws-ebs-csi-driver",
            cluster_name=cluster.cluster_name,
            addon_version="v1.48.0-eksbuild.1",
            resolve_conflicts="OVERWRITE",
            configuration_values=json.dumps(ebs_csi_config)
        )


        # 기존에 생성되어 있던 IAM 역할을 system:masters 그룹에 연동
        masters_roles = [
            {"id": "cross_role_eks", "role_arn": "arn:aws:iam::" + self.account + ":role/CrossRoleEKS"},
            {"id": "cross_role_sso", "role_arn": "arn:aws:iam::" + self.account + ":role/AWSReservedSSO_infra-team_a9691823b3c12a5c"}
        ]

        for role_info in masters_roles:
            cluster.aws_auth.add_role_mapping(
                role=iam.Role.from_role_arn(self, role_info["id"], role_arn=role_info["role_arn"]),
                groups=["system:masters"]
            )

        # EKS 클러스터(API 서버)에 연결된 보안그룹 불러오기
        control_plane_sg = cluster.connections.security_groups[1]

        control_plane_sg.add_ingress_rule(
            ec2.Peer.ipv4("10.251.0.0/16"),
            ec2.Port.tcp(443)
        )
        
        control_plane_sg.add_ingress_rule(
            ec2.Peer.ipv4("10.15.2.0/24"),
            ec2.Port.tcp(443)
        )

        # SSM 세션 매니저에서 사용할 유저를 추가하는 스크립트 불러오기
        scripts = open("scripts/karpenter-adduser-cw-disable.sh", "r").read()

        # 노드그룹에서 사용할 시작 템플릿 생성
        worker_node_group_launch_template = ec2.CfnLaunchTemplate(self, "worker_node_group_launch_template",
            launch_template_data=ec2.CfnLaunchTemplate.LaunchTemplateDataProperty(
                block_device_mappings=[
                    ec2.CfnLaunchTemplate.BlockDeviceMappingProperty(
                        device_name="/dev/xvda",
                        ebs=ec2.CfnLaunchTemplate.EbsProperty(
                            volume_size=60,
                            volume_type="gp3",
                            encrypted=True
                        )
                    )
                ],
                security_group_ids=[
                    "sg-0dd3d8a91e534b3f9",
                    cluster.cluster_security_group_id
                ],
                tag_specifications=[
                    ec2.CfnLaunchTemplate.TagSpecificationProperty(
                        resource_type="instance",
                        tags=[
                            CfnTag(
                                key="Name",
                                value="work-dev-worker-critical"
                            )
                        ]
                    ),
                    ec2.CfnLaunchTemplate.TagSpecificationProperty(
                        resource_type="volume",
                        tags=[
                            CfnTag(
                                key="Name",
                                value="work-dev-worker-critical"
                            )
                        ]
                    )
                ],
                metadata_options=ec2.CfnLaunchTemplate.MetadataOptionsProperty(
                    http_put_response_hop_limit=2,
                ),
                user_data=Fn.base64(scripts)
            )
        )

        # 노드그룹에 부여할 IAM 역할 생성
        nodegroup_role = iam.Role(self, "nodegroup_role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com")
        )

        # 노드그룹에 요구되는 필수 권한 부여
        nodegroup_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonEKSWorkerNodePolicy"
            )
        )

        nodegroup_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonEC2ContainerRegistryReadOnly"
            )
        )

        nodegroup_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonEKS_CNI_Policy"
            )
        )

        # SSM 접근에 필요한 권한 부여
        nodegroup_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonSSMManagedInstanceCore"
            )
        )

        # EBS CSI Driver를 통해서 EBS 볼륨을 쿠버네티스 PV로 사용하는데 필요한 권한 부여
        nodegroup_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AmazonEBSCSIDriverPolicy"
            )
        )

        # S3 접근 권한 부여
        nodegroup_role.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Action": [
                        "s3:PutObject",
                        "s3:GetObject",
                        "kms:GenerateDataKey",
                        "es:ESHttp*",
                        "es:ESHttpPost",
                        "bedrock:InvokeModel",
                        "bedrock:InvokeModelWithResponseStream"
                    ],
                    "Resource": "*",
                    "Effect": "Allow"
                }
            )
        )

        # 노드그룹에서 사용할 서브넷 목록
        nodegroup_subnet = ec2.SubnetSelection(
            subnets=[
                ec2.Subnet.from_subnet_id(self, "worker-ng-subnet-2a", private_subnet_a.ref),
                ec2.Subnet.from_subnet_id(self, "worker-ng-subnet-2c", private_subnet_c.ref),
                ec2.Subnet.from_subnet_id(self, "worker-ng-subnet-2a2", private_subnet_a2.ref),
                ec2.Subnet.from_subnet_id(self, "worker-ng-subnet-2c2", private_subnet_c2.ref),
            ]
        )

        # 크리티컬 노드그룹 생성
        worker_node_group = cluster.add_nodegroup_capacity("worker_node_group",
            ami_type=eks.NodegroupAmiType.AL2023_ARM_64_STANDARD,
            labels={
                "node-group": "worker-critical"
            },
            launch_template_spec=eks.LaunchTemplateSpec(
                id=worker_node_group_launch_template.ref,
                version=worker_node_group_launch_template.attr_latest_version_number
            ),
            subnets=nodegroup_subnet,
            instance_types=[ec2.InstanceType.of(
                ec2.InstanceClass.T4G,
                ec2.InstanceSize.MEDIUM
                )
            ],
            node_role=nodegroup_role,
            release_version="1.32.7-20250829",
            min_size=2,
            desired_size=2,
            max_size=3,
            taints=[eks.TaintSpec(
                effect=eks.TaintEffect.NO_SCHEDULE,
                key="CriticalAddonsOnly",
                value="true"
            )
            ],
            # https://docs.aws.amazon.com/cdk/api/v2/python/aws_cdk.aws_eks/NodegroupAmiType.html
            #ami_type=eks.NodegroupAmiType.AL2023_X86_64_STANDARD,
        )

        worker_node_group_onoff = cluster.add_nodegroup_capacity("worker_node_group_onoff",
            ami_type=eks.NodegroupAmiType.AL2023_X86_64_STANDARD,        
            labels={
                "node-group": "worker",
                "onoff": "true"
            },
            launch_template_spec=eks.LaunchTemplateSpec(
                id=worker_node_group_launch_template.ref,
                version=worker_node_group_launch_template.attr_latest_version_number
            ),
            subnets=nodegroup_subnet,
            instance_types=[ec2.InstanceType.of(
                ec2.InstanceClass.M7I,
                ec2.InstanceSize.XLARGE
                )
            ],
            node_role=nodegroup_role,
            release_version="1.32.7-20250829",
            min_size=0,
            desired_size=0,
            max_size=10,
            taints=[eks.TaintSpec(
                effect=eks.TaintEffect.NO_SCHEDULE,
                key="onoff",
                value="true"
            )
            ],
        )

        worker_node_group_spot = cluster.add_nodegroup_capacity("worker_node_group_spot",
            ami_type=eks.NodegroupAmiType.AL2023_X86_64_STANDARD,        
            labels={
                "node-group": "worker"
            },
            launch_template_spec=eks.LaunchTemplateSpec(
                id=worker_node_group_launch_template.ref,
                version=worker_node_group_launch_template.attr_latest_version_number
            ),
            subnets=nodegroup_subnet,
            instance_types=[
                ec2.InstanceType.of(
                    ec2.InstanceClass.M7I_FLEX,
                    ec2.InstanceSize.XLARGE
                ),
                ec2.InstanceType.of(
                    ec2.InstanceClass.M7I,
                    ec2.InstanceSize.XLARGE
                ),
            ],
            capacity_type=eks.CapacityType.SPOT,
            node_role=nodegroup_role,
            release_version="1.32.7-20250829",
            min_size=0,
            desired_size=0,
            max_size=20,
        )

        # 메트릭 서버
        metrics_server = cluster.add_helm_chart("metrics_server",
            repository="https://kubernetes-sigs.github.io/metrics-server",
            chart="metrics-server",
            release="metrics-server",
            namespace="kube-system",
            version="3.10.0"
        )

        # 클러스터 오토스케일러에 부여할 서비스 어카운트 생성
        cluster_autoscaler_sa = cluster.add_service_account("cluster_autoscaler_sa",
            name="cluster-autoscaler",
            namespace="kube-system"
        )

        # 클러스터 오토스케일러에 필요한 권한 부여
        cluster_autoscaler_sa.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Action": [
                        "autoscaling:DescribeAutoScalingGroups",
                        "autoscaling:DescribeAutoScalingInstances",
                        "autoscaling:DescribeLaunchConfigurations",
                        "autoscaling:DescribeTags",
                        "autoscaling:SetDesiredCapacity",
                        "autoscaling:TerminateInstanceInAutoScalingGroup",
                        "ec2:DescribeLaunchTemplateVersions",
                        "ec2:DescribeInstanceTypes"
                    ],
                    "Resource": "*",
                    "Effect": "Allow"
                }
            )
        )

        # 클러스터 오토스케일러 헬름 차트 설치
        cluster_autoscaler = cluster.add_helm_chart("cluster_autoscaler",
            repository="https://kubernetes.github.io/autoscaler",
            chart="cluster-autoscaler",
            release="cluster-autoscaler",
            namespace="kube-system",
            version="9.29.1",
            values={
                "fullnameOverride": "cluster-autoscaler",
                "replicaCount": 0,
                "awsRegion": self.region,
                "autoDiscovery": {
                    "clusterName": cluster.cluster_name
                },
                "service": {
                    "create": True
                },
                "rbac": {
                    "serviceAccount": {
                        "create": False,
                        "name": "cluster-autoscaler"
                    }
                },
                "extraArgs": {
                    "expander": "priority"
                },
                "expanderPriorities": {
                    "10": [worker_node_group.nodegroup_name, worker_node_group_onoff.nodegroup_name],
                    "20": [worker_node_group_spot.nodegroup_name]
                },
                "serviceMonitor": {
                    "enabled": True,
                    "interval": "60s",
                    "namespace": "cattle-monitoring-system"
                }
            }
        )

        # 디스케줄러        
        descheduler = cluster.add_helm_chart("descheduler",
            repository="https://kubernetes-sigs.github.io/descheduler/",
            chart="descheduler",
            release="descheduler",
            namespace="infra-batch",
            version="0.32.2",
            values={
                "resources": {
                    "requests": {
                        "cpu": "100m",
                        "memory": "256Mi"
                    },
                    "limits": {
                        "memory": "256Mi"
                    }
                },                
                "schedule": "50 10-23 * * *",
                "timeZone": "Etc/UTC",
                "successfulJobsHistoryLimit": 1,
                "failedJobsHistoryLimit": 1,                
                "cmdOptions": {
                    "v": 3,
                    "client-connection-qps": 50,
                    "client-connection-burst": 100
                },
                "deschedulerPolicy": {
                    "profiles": [
                        {
                            "name": "default",
                            "pluginConfig": [
                                {
                                    "name": "DefaultEvictor",
                                    "args": {
                                        "ignorePvcPods": True,
                                        "evictLocalStoragePods": True
                                    }
                                },
                                {
                                    "name": "RemoveDuplicates"
                                },
                                {
                                    "name": "RemovePodsHavingTooManyRestarts",
                                    "args": {
                                        "podRestartThreshold": 20,
                                        "includingInitContainers": True
                                    }
                                },
                                {
                                    "name": "RemovePodsViolatingNodeAffinity",
                                    "args": {
                                        "nodeAffinityType": [
                                            "requiredDuringSchedulingIgnoredDuringExecution"
                                        ]
                                    }
                                },
                                {
                                    "name": "RemovePodsViolatingNodeTaints"
                                },
                                {
                                    "name": "RemovePodsViolatingInterPodAntiAffinity"
                                },
                                {
                                    "name": "RemovePodsViolatingTopologySpreadConstraint"
                                }
                            ],
                            "plugins": {
                                "balance": {
                                    "enabled": [
                                        "RemoveDuplicates",
                                        "RemovePodsViolatingTopologySpreadConstraint"
                                    ]
                                },
                                "deschedule": {
                                    "enabled": [
                                        "RemovePodsHavingTooManyRestarts",
                                        "RemovePodsViolatingNodeTaints",
                                        "RemovePodsViolatingNodeAffinity",
                                        "RemovePodsViolatingInterPodAntiAffinity"
                                    ]
                                }
                            }
                        }
                    ]
                }
            }
        )


        # AWS 로드밸런서 컨트롤러가 ALB/NLB를 생성할 서브넷에 태그 부여
        Tags.of(private_subnet_a).add("kubernetes.io/role/internal-elb", "1")
        Tags.of(private_subnet_a).add("kubernetes.io/cluster/work-dev", "owned")
        Tags.of(private_subnet_c).add("kubernetes.io/role/internal-elb", "1")
        Tags.of(private_subnet_c).add("kubernetes.io/cluster/work-dev", "owned")

        # AWS 로드밸런서 컨트롤러
        aws_load_balancer_controller = eks.AlbController(self, "aws_load_balancer_controller",
            cluster=cluster,
            version=eks.AlbControllerVersion.of(
                helm_chart_version="1.6.1",
                version="v2.6.1"
            ),
            policy=requests.get(
                "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.1/docs/install/iam_policy.json"
            ).json()

        )


        # B2B 서비스용 NGINX 인그레스 컨트롤러 (NLB)에 부여할 보안그룹 생성
        b2b_service_nginx_ingress_controller_sg = ec2.SecurityGroup(self, "b2b_service_nginx_ingress_controller_sg",
            vpc=vpc,
            security_group_name="b2b-service-nginx-ingress-controller",
            description="b2b service nginx ingress controller",
            allow_all_outbound=False
        )

        Tags.of(b2b_service_nginx_ingress_controller_sg).add("Name", "b2b-service-nginx-ingress-controller")

        # B2B 서비스용 NGINX 인그레스 컨트롤러 보안그룹 인바운드 규칙
        b2b_service_white_list = [
            {"ip":"117.52.4.30/32","description":"Toss Core from cdk"},
            {"ip":"10.151.31.57/32","description":"dev-infra-eureka-a-57, kakao-hug-api from cdk"},
            {"ip":"10.1.3.0/24","description":"from cdk"},
            {"ip":"10.1.4.0/24","description":"from cdk"},
            {"ip":"10.1.8.0/24","description":"from cdk"},
            {"ip":"10.151.0.0/16","description":"eks subnet from cdk"},
            {"ip":"10.171.0.0/16","description":" from cdk"},
            {"ip":"10.15.1.0/24","description":"office 1F from cdk"},
            {"ip":"10.15.2.0/24","description":"office 2F from cdk"},
            {"ip":"20.20.20.0/24","description":"office outsourcing from cdk"},
            {"ip":"211.62.190.37/32","description":"Kakapay Ins dev from cdk"},
            {"ip":"211.62.190.38/32","description":"Kakapay Ins qa from cdk"}
        ]

        for source in b2b_service_white_list:
            b2b_service_nginx_ingress_controller_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(80),
                description=source["description"]
            )

            b2b_service_nginx_ingress_controller_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(443),
                description=source["description"]
            )

        # B2B 서비스용 NGINX 인그레스 컨트롤러 보안그룹 아웃바운드 규칙
        b2b_service_nginx_ingress_controller_sg.add_egress_rule(
            ec2.Peer.security_group_id(cluster.cluster_security_group_id),
            ec2.Port.tcp(80)
        )

        # 노드그룹에 연결된 보안그룹 불러오기
        node_group_sg = cluster.connections.security_groups[0]

        # B2B 서비스용 NGINX 인그레스 컨트롤러(NLB)에서 노드그룹으로 들어오는 트래픽 허용
        node_group_sg.add_ingress_rule(
            ec2.Peer.security_group_id(b2b_service_nginx_ingress_controller_sg.security_group_id),
            ec2.Port.tcp(80)
        )

        # B2B 서비스용 NGINX 인그레스 컨트롤러를 설치할 네임스페이스 생성
        b2b_service_nginx_ingress_controller_ns = cluster.add_manifest("b2b_service_nginx_ingress_controller_ns",
            {
                "kind": "Namespace",
                "apiVersion": "v1",
                "metadata": {
                    "name": "b2b-service-ingress-nginx",
                    "labels": {
                        "elbv2.k8s.aws/pod-readiness-gate-inject": "enabled"
                    }
                }
            }
        )

        # B2B 서비스용 인그레스 NGINX 컨트롤러 헬름 차트 설치
        b2b_service_nginx_ingress_controller = cluster.add_helm_chart("b2b_service_nginx_ingress_controller",
            repository="https://kubernetes.github.io/ingress-nginx",
            chart="ingress-nginx",
            release="b2b-service-ingress-nginx",
            namespace="b2b-service-ingress-nginx",
            version="4.12.0",
            values={
                "controller": {
                    "image": {
                        "registry": "032559872243.dkr.ecr.ap-northeast-2.amazonaws.com",
                        "image": "ingress-nginx-controller",
                        "tag": "v1.12.1",
                        "digest": "sha256:466e6b255d776c237286f013efe14da1477b172a2f444ca6806d66c9fad27111"
                    },
                    "allowSnippetAnnotations": True,
                    "electionID": "b2b-service-nginx",
                    "ingressClass": "b2b-service-nginx",
                    "ingressClassResource": {
                        "name": "b2b-service-nginx",
                        "controllerValue": "k8s.io/b2b-service-ingress-nginx"
                    },
                    "autoscaling": {
                        "enabled": True,
                        "minReplicas": 2, # 최소 Pod 갯수가 1개 이상일때 PDB가 생성됨
                        "maxReplicas": 10,
                        "targetMemoryUtilizationPercentage": 80
                    },
                    "resources": {
                        "requests": {
                            "cpu": "100m",
                            "memory": "150Mi"
                        },
                        "limits": {
                            "memory": "150Mi"
                        }
                    },
                    "config": {
                        "annotations-risk-level": "Critical",
                        "log-format-upstream": '$remote_addr $host $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_length $request_time [$proxy_upstream_name] [$proxy_alternative_upstream_name] $upstream_addr $upstream_response_length $upstream_response_time $upstream_status $opentelemetry_trace_id $opentelemetry_span_id $req_id',
                        "use-proxy-protocol": "true",
                        "proxy-body-size": "35m",
                        "enable-opentelemetry": "true",
                        "opentelemetry-operation-name": "HTTP $request_method $service_name $uri",
                        "opentelemetry-trust-incoming-span": "true",
                        "otlp-collector-host": "otel-collector-collector.otel.svc.cluster.local",
                        "otlp-collector-port": "4317",
                        "otel-max-queuesize": "2048",
                        "otel-schedule-delay-millis": "5000",
                        "otel-max-export-batch-size": "512",
                        "otel-service-name": "b2b-service-ingress-nginx",
                        "otel-sampler": "AlwaysOn",
                        "otel-sampler-ratio": "1.0",
                        "otel-sampler-parent-based": "true"                        
                    },
                    "service": {
                        "targetPorts": {
                            "http": "http",
                            "https": "http"
                        },
                        "annotations": {
                            "service.beta.kubernetes.io/aws-load-balancer-type": "external",
                            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type": "ip",
                            "service.beta.kubernetes.io/aws-load-balancer-scheme": "internal",
                            "service.beta.kubernetes.io/aws-load-balancer-name": "work-dev-b2b-service",
                            "service.beta.kubernetes.io/aws-load-balancer-backend-protocol": "tcp",
                            "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled": "true",
                            "service.beta.kubernetes.io/aws-load-balancer-ssl-ports": "443",
                            "service.beta.kubernetes.io/aws-load-balancer-ssl-cert": "arn:aws:acm:ap-northeast-2:231256011503:certificate/0b936266-35da-4726-9f79-94f34c44d2a2,arn:aws:acm:ap-northeast-2:231256011503:certificate/bd3db117-3236-4857-9e9d-c8514c3a279c",
                            "service.beta.kubernetes.io/aws-load-balancer-subnets": "subnet-09cdac6d6550a3b03,subnet-0405741cca5b109aa,subnet-06c817566f9133d22",
                            "service.beta.kubernetes.io/aws-load-balancer-private-ipv4-addresses": "10.151.21.231,10.151.22.232,10.151.23.233",
                            "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol": "*",
                            "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes": "preserve_client_ip.enabled=false",
                            "service.beta.kubernetes.io/aws-load-balancer-security-groups": b2b_service_nginx_ingress_controller_sg.security_group_id
                        }
                    },
                    "extraEnvs": [
                        {
                            "name": "TZ",
                            "value": "Asia/Seoul"
                        }
                    ],
                    "metrics": {
                        "port": 10254,
                        "portName": "metrics",
                        "enabled": False,
                        "serviceMonitor": {
                            "enabled": False
                        }
                    },
                    "opentelemetry": {
                        "enabled": True
                    }
                }
            }
        )

        b2b_service_nginx_ingress_controller.node.add_dependency(b2b_service_nginx_ingress_controller_ns)

        # 내부 유저용 NGINX 인그레스 컨트롤러 (NLB)에 부여할 보안그룹 생성
        user_service_nginx_ingress_controller_sg = ec2.SecurityGroup(self, "user_service_nginx_ingress_controller_sg",
            vpc=vpc,
            security_group_name="user-service-nginx-ingress-controller",
            description="user service nginx ingress controller",
            allow_all_outbound=False
        )

        Tags.of(user_service_nginx_ingress_controller_sg).add("Name", "user-service-nginx-ingress-controller")

        # 내부 유저용 NGINX 인그레스 컨트롤러 보안그룹 인바운드 규칙
        user_service_white_list = [
            {"ip":"10.171.0.0/16","description":"from cdk"},
            {"ip":"10.251.0.0/16","description":"from cdk"},
            {"ip":"10.1.3.0/24","description":"from cdk"},
            {"ip":"10.1.4.0/24","description":"from cdk"},
            {"ip":"10.1.5.0/24","description":"from cdk"},
            {"ip":"10.1.6.0/24","description":"from cdk"},
            {"ip":"10.1.8.0/24","description":"from cdk"},
            {"ip":"10.1.9.0/24","description":"from cdk"},
            {"ip":"10.1.103.0/24","description":"from cdk"},
            {"ip":"10.85.0.0/16","description":"from cdk"},
            {"ip":"10.151.0.0/16","description":"from cdk"},
            {"ip":"117.52.4.30/32","description":"Toss Core from cdk"},
            {"ip":"10.181.1.21/32","description":"from cdk"},
            {"ip":"10.20.60.50/32","description":"PTSV3-A from cdk"},
            {"ip":"10.1.1.198/32","description":"dev-ml-server from cdk"},
            {"ip":"10.19.1.31/32","description":"dev-ai-server from cdk"},
            {"ip":"10.15.8.0/24","description":"office B2F from cdk"},
            {"ip":"10.15.9.0/24","description":"office B1F from cdk"},
            {"ip":"10.15.1.0/24","description":"office 1F from cdk"},
            {"ip":"10.15.2.0/24","description":"office 2F from cdk"},
            {"ip":"10.15.3.0/24","description":"office 3F from cdk"},
            {"ip":"10.15.4.0/24","description":"office 4F from cdk"},
            {"ip":"10.15.5.0/24","description":"office 5F from cdk"},
            {"ip":"10.15.6.0/24","description":"office 6F from cdk"},
            {"ip":"20.20.20.0/24","description":"office outsourcing from cdk"},
            {"ip":"55.55.30.11/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.12/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.13/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.14/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.15/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.16/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.17/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.18/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.19/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.20/32","description":"office rpa from cdk"},
            {"ip":"55.55.30.21/32","description":"office rpa from cdk"},
            {"ip":"30.30.31.121/32","description":"office AI from cdk"},
            {"ip":"30.30.31.160/32","description":"office CallBot Test from cdk"},
            {"ip":"10.19.1.103/32","description":"SK CTI2 del from cdk"},
            {"ip":"10.19.1.102/32","description":"SK CTI1 del from cdk"},
            {"ip":"30.30.31.142/32","description":"office fax-active from cdk"},
            {"ip":"30.30.31.143/32","description":"office fax-standby from cdk"},              
            {"ip":"10.253.1.253/32","description":"office CTI2 Test from cdk"},
            {"ip":"10.253.1.252/32","description":"office CTI1 Test from cdk"},
            {"ip":"30.30.31.141/32","description":"office fax-vip from cdk"},
            {"ip":"10.253.1.241/32","description":"office CTI VIP from cdk"},
            {"ip":"10.253.1.242/32","description":"office CTI1 from cdk"},
            {"ip":"10.253.1.243/32","description":"office CTI2 Test from cdk"},
        ]

        for source in user_service_white_list:
            user_service_nginx_ingress_controller_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(80),
                description=source["description"]
            )

            user_service_nginx_ingress_controller_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(443),
                description=source["description"]
            )

        # 내부 유저용 NGINX 인그레스 컨트롤러 보안그룹 아웃바운드 규칙
        user_service_nginx_ingress_controller_sg.add_egress_rule(
            ec2.Peer.security_group_id(cluster.cluster_security_group_id),
            ec2.Port.tcp(80)
        )

        # 내부 유저용 NGINX 인그레스 컨트롤러(NLB)에서 노드그룹으로 들어오는 트래픽 허용
        node_group_sg.add_ingress_rule(
            ec2.Peer.security_group_id(user_service_nginx_ingress_controller_sg.security_group_id),
            ec2.Port.tcp(80)
        )
        # 내부 유저용 NGINX 인그레스 컨트롤러를 설치할 네임스페이스 생성
        user_service_nginx_ingress_controller_ns = cluster.add_manifest("user_service_nginx_ingress_controller_ns",
            {
                "kind": "Namespace",
                "apiVersion": "v1",
                "metadata": {
                    "name": "user-service-ingress-nginx"
                }
            }
        )

        # 내부 유저용 인그레스 NGINX 컨트롤러 헬름 차트 설치
        user_service_nginx_ingress_controller = cluster.add_helm_chart("user_service_nginx_ingress_controller",
            repository="https://kubernetes.github.io/ingress-nginx",
            chart="ingress-nginx",
            release="user-service-ingress-nginx",
            namespace="user-service-ingress-nginx",
            version="4.12.0",
            values={
                "controller": {
                    "image": {
                        "registry": "032559872243.dkr.ecr.ap-northeast-2.amazonaws.com",
                        "image": "ingress-nginx-controller",
                        "tag": "v1.12.1",
                        "digest": "sha256:466e6b255d776c237286f013efe14da1477b172a2f444ca6806d66c9fad27111"
                    },
                    "allowSnippetAnnotations": True,
                    "electionID": "user-service-nginx",
                    "ingressClass": "user-service-nginx",
                    "ingressClassResource": {
                        "name": "user-service-nginx",
                        "controllerValue": "k8s.io/user-service-ingress-nginx"
                    },
                    "autoscaling": {
                        "enabled": True,
                        "minReplicas": 2,
                        "maxReplicas": 10,
                        "targetMemoryUtilizationPercentage": 80
                    },
                    "resources": {
                        "requests": {
                            "cpu": "100m",
                            "memory": "150Mi"
                        },
                        "limits": {
                            "memory": "150Mi"
                        }
                    },
                    "config": {
                        "annotations-risk-level": "Critical",
                        "log-format-upstream": '$remote_addr $host $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_length $request_time [$proxy_upstream_name] [$proxy_alternative_upstream_name] $upstream_addr $upstream_response_length $upstream_response_time $upstream_status $opentelemetry_trace_id $opentelemetry_span_id $req_id',
                        "use-proxy-protocol": "true",
                        "proxy-body-size": "35m",
                        "enable-opentelemetry": "true",
                        "opentelemetry-operation-name": "HTTP $request_method $service_name $uri",
                        "opentelemetry-trust-incoming-span": "true",
                        "otlp-collector-host": "otel-collector-collector.otel.svc.cluster.local",
                        "otlp-collector-port": "4317",
                        "otel-max-queuesize": "2048",
                        "otel-schedule-delay-millis": "5000",
                        "otel-max-export-batch-size": "512",
                        "otel-service-name": "user-service-ingress-nginx",
                        "otel-sampler": "AlwaysOn",
                        "otel-sampler-ratio": "1.0",
                        "otel-sampler-parent-based": "true"                           
                    },
                    "service": {
                        "targetPorts": {
                            "http": "http",
                            "https": "http"
                        },
                        "annotations": {
                            "service.beta.kubernetes.io/aws-load-balancer-type": "external",
                            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type": "ip",
                            "service.beta.kubernetes.io/aws-load-balancer-scheme": "internal",
                            "service.beta.kubernetes.io/aws-load-balancer-name": "work-dev-user-service",
                            "service.beta.kubernetes.io/aws-load-balancer-backend-protocol": "tcp",
                            "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled": "true",
                            "service.beta.kubernetes.io/aws-load-balancer-ssl-ports": "443",
                            "service.beta.kubernetes.io/aws-load-balancer-ssl-cert": "arn:aws:acm:ap-northeast-2:231256011503:certificate/3363642d-db5e-4aad-bb1f-71ea0dc7796d,arn:aws:acm:ap-northeast-2:231256011503:certificate/7e887838-0003-4667-b07b-26301e732c49,arn:aws:acm:ap-northeast-2:231256011503:certificate/0b936266-35da-4726-9f79-94f34c44d2a2",
                            "service.beta.kubernetes.io/aws-load-balancer-subnets": "subnet-06e0f724ce2b49ced,subnet-0e220bbc85128bca0,subnet-0a88e343084e1674d",
                            "service.beta.kubernetes.io/aws-load-balancer-private-ipv4-addresses": "10.151.111.60,10.151.112.60,10.151.113.60",
                            "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol": "*",
                            "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes": "preserve_client_ip.enabled=false",
                            "service.beta.kubernetes.io/aws-load-balancer-security-groups": user_service_nginx_ingress_controller_sg.security_group_id,
                            "service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout": '600'
                        }
                    },
                    "extraEnvs": [
                        {
                            "name": "TZ",
                            "value": "Asia/Seoul"
                        }
                    ],
                    "metrics": {
                        "port": 10254,
                        "portName": "metrics",
                        "enabled": False,
                        "serviceMonitor": {
                            "enabled": False
                        }
                    },
                    "opentelemetry": {
                        "enabled": True
                    }                    
                }
            }
        )

        user_service_nginx_ingress_controller.node.add_dependency(user_service_nginx_ingress_controller_ns)



        # test 서비스용 NGINX 인그레스 컨트롤러 (NLB)에 부여할 보안그룹 생성
        test_service_nginx_ingress_controller_sg = ec2.SecurityGroup(self, "test_service_nginx_ingress_controller_sg",
            vpc=vpc,
            security_group_name="test-service-nginx-ingress-controller",
            description="test service nginx ingress controller",
            allow_all_outbound=False
        )

        Tags.of(test_service_nginx_ingress_controller_sg).add("Name", "test-service-nginx-ingress-controller")

        # test 서비스용 NGINX 인그레스 컨트롤러 보안그룹 인바운드 규칙
        test_service_white_list = [
            {"ip":"117.52.4.30/32","description":"test Toss Core from cdk"},
            {"ip":"10.151.31.57/32","description":"test dev-infra-eureka-a-57, kakao-hug-api from cdk"},
            {"ip":"10.1.3.0/24","description":"test from cdk"},
            {"ip":"10.1.4.0/24","description":"test from cdk"},
            {"ip":"10.1.8.0/24","description":"test from cdk"},
            {"ip":"10.151.0.0/16","description":"test eks subnet from cdk"},
            {"ip":"10.171.0.0/16","description":"test from cdk"},
            {"ip":"10.15.1.0/24","description":"test office 1F from cdk"},
            {"ip":"10.15.2.0/24","description":"test office 2F from cdk"},
            {"ip":"20.20.20.0/24","description":"test office outsourcing from cdk"},
            {"ip":"211.62.190.37/32","description":"test Kakapay Ins dev from cdk"},
            {"ip":"211.62.190.38/32","description":"test Kakapay Ins qa from cdk"}
        ]

        for source in test_service_white_list:
            test_service_nginx_ingress_controller_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(80),
                description=source["description"]
            )

            test_service_nginx_ingress_controller_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(443),
                description=source["description"]
            )

        # test 서비스용 NGINX 인그레스 컨트롤러 보안그룹 아웃바운드 규칙
        test_service_nginx_ingress_controller_sg.add_egress_rule(
            ec2.Peer.security_group_id(cluster.cluster_security_group_id),
            ec2.Port.tcp(80)
        )

        # 노드그룹에 연결된 보안그룹 불러오기
        node_group_sg = cluster.connections.security_groups[0]

        # test 서비스용 NGINX 인그레스 컨트롤러(NLB)에서 노드그룹으로 들어오는 트래픽 허용
        node_group_sg.add_ingress_rule(
            ec2.Peer.security_group_id(test_service_nginx_ingress_controller_sg.security_group_id),
            ec2.Port.tcp(80)
        )

        # test 서비스용 NGINX 인그레스 컨트롤러를 설치할 네임스페이스 생성
        test_service_nginx_ingress_controller_ns = cluster.add_manifest("test_service_nginx_ingress_controller_ns",
            {
                "kind": "Namespace",
                "apiVersion": "v1",
                "metadata": {
                    "name": "test-service-ingress-nginx",
                    "labels": {
                        "elbv2.k8s.aws/pod-readiness-gate-inject": "enabled"
                    }
                }
            }
        )

        # B2B 서비스용 인그레스 NGINX 컨트롤러 헬름 차트 설치
        test_service_nginx_ingress_controller = cluster.add_helm_chart("test_service_nginx_ingress_controller",
            repository="https://kubernetes.github.io/ingress-nginx",
            chart="ingress-nginx",
            release="test-service-ingress-nginx",
            namespace="test-service-ingress-nginx",
            version="4.12.0",
            values={
                "controller": {
                    "image": {
                        "registry": "032559872243.dkr.ecr.ap-northeast-2.amazonaws.com",
                        "image": "ingress-nginx-controller",
                        "tag": "v1.12.1",
                        "digest": "sha256:466e6b255d776c237286f013efe14da1477b172a2f444ca6806d66c9fad27111"
                    },
                    "allowSnippetAnnotations": True,
                    "electionID": "test-service-nginx",
                    "ingressClass": "test-service-nginx",
                    "ingressClassResource": {
                        "name": "test-service-nginx",
                        "controllerValue": "k8s.io/test-service-ingress-nginx"
                    },
                    "autoscaling": {
                        "enabled": True,
                        "minReplicas": 1, # 최소 Pod 갯수가 1개 이상일때 PDB가 생성됨
                        "maxReplicas": 10,
                        "targetMemoryUtilizationPercentage": 80
                    },
                    "resources": {
                        "requests": {
                            "cpu": "100m",
                            "memory": "150Mi"
                        },
                        "limits": {
                            "memory": "150Mi"
                        }
                    },
                    "config": {
                        "annotations-risk-level": "Critical",
                        "log-format-upstream": '$remote_addr $host $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_length $request_time [$proxy_upstream_name] [$proxy_alternative_upstream_name] $upstream_addr $upstream_response_length $upstream_response_time $upstream_status $opentelemetry_trace_id $opentelemetry_span_id $req_id',
                        "use-proxy-protocol": "true",
                        "proxy-body-size": "35m",
                        "enable-opentelemetry": "true",
                        "opentelemetry-operation-name": "HTTP $request_method $service_name $uri",
                        "opentelemetry-trust-incoming-span": "true",
                        "otlp-collector-host": "otel-collector-collector.otel.svc.cluster.local",
                        "otlp-collector-port": "4317",
                        "otel-max-queuesize": "2048",
                        "otel-schedule-delay-millis": "5000",
                        "otel-max-export-batch-size": "512",
                        "otel-service-name": "test-service-ingress-nginx",
                        "otel-sampler": "AlwaysOn",
                        "otel-sampler-ratio": "1.0",
                        "otel-sampler-parent-based": "true"                        
                    },
                    "service": {
                        "targetPorts": {
                            "http": "http",
                            "https": "http"
                        },
                        "annotations": {
                            "service.beta.kubernetes.io/aws-load-balancer-type": "external",
                            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type": "ip",
                            "service.beta.kubernetes.io/aws-load-balancer-scheme": "internal",
                            "service.beta.kubernetes.io/aws-load-balancer-name": "work-dev-test-service",
                            "service.beta.kubernetes.io/aws-load-balancer-backend-protocol": "tcp",
                            "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled": "true",
                            "service.beta.kubernetes.io/aws-load-balancer-ssl-ports": "443",
                            "service.beta.kubernetes.io/aws-load-balancer-ssl-cert": "arn:aws:acm:ap-northeast-2:231256011503:certificate/0b936266-35da-4726-9f79-94f34c44d2a2,arn:aws:acm:ap-northeast-2:231256011503:certificate/bd3db117-3236-4857-9e9d-c8514c3a279c",
                            "service.beta.kubernetes.io/aws-load-balancer-subnets": "subnet-09cdac6d6550a3b03,subnet-0405741cca5b109aa,subnet-06c817566f9133d22",
                            "service.beta.kubernetes.io/aws-load-balancer-private-ipv4-addresses": "10.151.21.232,10.151.22.233,10.151.23.234",
                            "service.beta.kubernetes.io/aws-load-balancer-proxy-protocol": "*",
                            "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes": "preserve_client_ip.enabled=false",
                            "service.beta.kubernetes.io/aws-load-balancer-security-groups": test_service_nginx_ingress_controller_sg.security_group_id
                        }
                    },
                    "extraEnvs": [
                        {
                            "name": "TZ",
                            "value": "Asia/Seoul"
                        }
                    ],
                    "metrics": {
                        "port": 10254,
                        "portName": "metrics",
                        "enabled": False,
                        "serviceMonitor": {
                            "enabled": False
                        }
                    },
                    "opentelemetry": {
                        "enabled": True
                    }
                }
            }
        )

        test_service_nginx_ingress_controller.node.add_dependency(test_service_nginx_ingress_controller_ns)



        # External DNS 헬름 차트 설치
        external_dns = cluster.add_helm_chart("external_dns",
            repository="https://kubernetes-sigs.github.io/external-dns",
            chart="external-dns",
            release="external-dns",
            namespace="kube-system",
            version="1.13.0",
            values={
                "serviceAccount": {
                    "annotations": {
                        "eks.amazonaws.com/role-arn": "arn:aws:iam::032559872243:role/ExternalDNSRole"
                    }
                },
                "txtOwnerId": cluster.cluster_name,
                "domainFilters": [
                    "refinedev.io"
                ],
                "extraArgs": [
                    "--aws-zone-type=private"
                ]
            }
        )

        # FluentBit을 설치할 네임스페이스 생성
        logging_ns = cluster.add_manifest("logging_ns",
            {
                "kind": "Namespace",
                "apiVersion": "v1",
                "metadata": {
                    "name": "logging"
                }
            }
        )

        # FluentBit 헬름 차트에 사용할 변수 파일 불러오기
        with open("kubernetes/helm/work-dev/fluentbit.yaml", "r") as stream:
            fluentbit_values = yaml.safe_load(stream)

        # FluentBit 헬름 차트 설치
        fluentbit = cluster.add_helm_chart("fluentbit",
            repository="https://fluent.github.io/helm-charts",
            chart="fluent-bit",
            release="fluent-bit",
            namespace="logging",
            version="0.48.9",
            values=fluentbit_values
        )

        # kubepromstack 헬름 차트에 사용할 변수 파일 불러오기
        with open("kubernetes/helm/work-dev/kubepromstack.yaml", "r") as stream:
            kps_values = yaml.safe_load(stream)

        # kubePromStack 헬름 차트 설치
        kubePromStack = cluster.add_helm_chart("kps",
            repository="https://prometheus-community.github.io/helm-charts",
            chart="kube-prometheus-stack",
            release="kps",
            namespace="monitoring",
            version="72.5.1",
            values=kps_values
        )

        # kubepromstack 헬름 차트에 사용할 변수 파일 불러오기
        with open("kubernetes/helm/work-dev/kubecost.yaml", "r") as stream:
            kubecost_values = yaml.safe_load(stream)

        # kubecost 헬름 차트 설치
        kubecost = cluster.add_helm_chart("kubecost",
            repository="https://kubecost.github.io/cost-analyzer",
            chart="cost-analyzer",
            release="kubecost",
            namespace="monitoring",
            version="2.7.2",
            values=kubecost_values
        )
        
        # Outputs
        CfnOutput(self, "clusterOpenIdConnectIssuerUrl",
            value=cluster.cluster_open_id_connect_issuer_url
        )

        # Export
        self.eks_cluster = cluster
        self.vpc = vpc

        # EKS 클러스터 및 노드그룹에 연결된 메인 보안그룹 불러오기
        control_plane_main_sg = cluster.connections.security_groups[0]

        # Service 객체에 연동된 모든 Pod의 프로토콜 및 포트 목록
        pod_proto_port_pairs = [
            ["TCP",10250],
            ["TCP",10254],
            ["TCP",10255],
            ["TCP",2020],
            ["TCP",4194],
            ["TCP",443],
            ["TCP",444],
            ["TCP",53],
            ["TCP",6443],
            ["TCP",7902],
            ["TCP",7979],
            ["TCP",80],
            ["TCP",8001],
            ["TCP",8080],
            ["TCP",8081],
            ["TCP",8443],
            ["TCP",9000],
            ["TCP",9002],
            ["TCP",9090],
            ["TCP",9093],
            ["TCP",9094],
            ["TCP",9153],
            ["TCP",9443],
            ["TCP",9796],
            ["UDP",53],
            ["UDP",9094]
        ]
        
        # 0.0.0.0 제거 후 RMQ LB SG로 아웃바운드 테스트 해야함
        # 인/아웃바운드 규칙 추가
        for pair in pod_proto_port_pairs:
            # 인바운드 규칙
            if pair[0] == "TCP":
                control_plane_main_sg.add_ingress_rule(
                    control_plane_main_sg,
                    ec2.Port.tcp(pair[1])
                )
            if pair[0] == "UDP":
                control_plane_main_sg.add_ingress_rule(
                    control_plane_main_sg,
                    ec2.Port.udp(pair[1])
                )
                
            # sg-09ca282f923102651
            # CDK의 경우 보안그룹 객체의 allowAllOutbound 값이 True일 경우 아웃바운드 규칙을 추가할수 없으므로 CloudFormation 객체로 생성
            # https://github.com/aws/aws-cdk/issues/9740
            ec2.CfnSecurityGroupEgress(self, f'{control_plane_main_sg.unique_id}-{pair[0]}-{pair[1]}',
                group_id=control_plane_main_sg.security_group_id,
                ip_protocol=pair[0].lower(),
                destination_security_group_id=control_plane_main_sg.security_group_id,
                from_port=pair[1],
                to_port=pair[1]
            )


        # CoreDNS에 부여할 보안그룹 설정
        # coredns_sg_policy = cluster.add_manifest("coredns_sg_policy",
        #     {
        #         "apiVersion": "vpcresources.k8s.aws/v1beta1",
        #         "kind": "SecurityGroupPolicy",
        #         "metadata": {
        #             "name": "coredns-security-group-policy",
        #             "namespace": "kube-system"
        #         },
        #         "spec": {
        #             "podSelector": {
        #                 "matchLabels": {
        #                     "k8s-app": "kube-dns"
        #                 }
        #             },
        #             "securityGroups": {
        #                 "groupIds": [
        #                     "sg-0dd3d8a91e534b3f9",
        #                     cluster.cluster_security_group_id
        #                 ]
        #             }
        #         }
        #     }
        # )

        ## Karpenter ##
        # CoreDNS TOSS CM
        # hosts custom.hosts deposit-insu-alpha-v.toss.im {
        #   211.233.9.190 deposit-insu-alpha-v.toss.im
        #   fallthrough
        # }
        
        ### 삭제 예정 CoreDNS Fargate 프로필
        # coredns_fargate_profile = cluster.add_fargate_profile("coredns_fargate_profile",
        #     selectors=[
        #         eks.Selector(
        #             namespace="kube-system",
        #             labels={
        #                 "k8s-app": "kube-dns2"
        #             }
        #         )
        #     ]
        # )

        # karpenter fargate excue
        karpenter_fargate_excute_role = iam.Role(self, "karpenter_fargate_excute_role",
            assumed_by=iam.ServicePrincipal("eks-fargate-pods.amazonaws.com")
        )

        # EKS 노드에 요구되는 필수 권한 부여
        karpenter_fargate_excute_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonEKSFargatePodExecutionRolePolicy"
            )
        )

        karpenter_fargate_excute_role.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Action": "es:*",
                    "Resource": "*",
                    "Effect": "Allow"
                }
            )
        )
      
        ### 삭제 예정 Karpenter Fargate 프로필
        # karpenter_fargate_profile = cluster.add_fargate_profile("karpenter_fargate_profile",
        #     selectors=[
        #         eks.Selector(
        #             namespace="karpenter2"
        #         )
        #     ],
        #     pod_execution_role = karpenter_fargate_excute_role
        # )

        # 노드에 부여할 IAM 역할 생성
        karpenter_node_role = iam.Role(self, "karpenter_node_role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com")
        )

        # EKS 노드에 요구되는 필수 권한 부여
        karpenter_node_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonEKSWorkerNodePolicy"
            )
        )

        karpenter_node_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonEC2ContainerRegistryReadOnly"
            )
        )

        karpenter_node_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonEKS_CNI_Policy"
            )
        )

        # SSM 접근에 필요한 권한 부여
        karpenter_node_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonSSMManagedInstanceCore"
            )
        )

        # CloudWatch로 로그 및 지표를 보내는데 필요한 권한 부여
        karpenter_node_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "CloudWatchAgentServerPolicy"
            )
        )

        # EBS CSI Driver를 통해서 EBS 볼륨을 쿠버네티스 PV로 사용하는데 필요한 권한 부여
        karpenter_node_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AmazonEBSCSIDriverPolicy"
            )
        )

        karpenter_node_role.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Action": [
                        "s3:PutObject",
                        "s3:GetObject",
                        "s3:GetObjectTagging",
                        "s3:PutObjectTagging",
                        "kms:GenerateDataKey",
                        "es:ESHttp*",
                        "es:ESHttpPost",
                        "bedrock:InvokeModel",
                        "bedrock:InvokeModelWithResponseStream"
                    ],
                    "Resource": "*",
                    "Effect": "Allow"
                }
            )
        )


        karpenter_node_role.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "BucketLevelActions",
                    "Effect": "Allow",
                    "Action": "s3:ListBucket",
                    "Resource": [
                        "arn:aws:s3:::refine-fax",
                        "arn:aws:s3:::rf-files",
                        "arn:aws:s3:::pts-inf-dev"
                    ]
                }
            )
        )

        karpenter_node_role.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "BucketLevelActionsDelete",
                    "Effect": "Allow",
                    "Action": "s3:DeleteObject",
                    "Resource": "arn:aws:s3:::pts-inf-dev/*"
                }
            )
        )
        
        karpenter_node_role.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "AllowSpecificDynamoDBTableActions",
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:UpdateItem",
                        "dynamodb:Scan",
                        "dynamodb:Query"
                    ],
                    "Resource": "arn:aws:dynamodb:ap-northeast-2:231256011503:table/*"
                }
            )
        )        
        # 노드에 부여할 IAM 역할에 EKS 클러스터 접근 권한 부여
        cluster.aws_auth.add_role_mapping(
            role=karpenter_node_role,
            username="system:node:{{EC2PrivateDNSName}}",
            groups=[
                "system:bootstrappers",
                "system:nodes"
            ]
        )

        # Karpenter를 설치할 네임스페이스 생성
        karpenter_ns = cluster.add_manifest("karpenter_ns",
            {
                "kind": "Namespace",
                "apiVersion": "v1",
                "metadata": {
                    "name": "karpenter"
                }
            }
        )
        
        # Karpenter에 부여할 보안그룹 설정
        # karpenter_sg_policy = cluster.add_manifest("karpenter_sg_policy",
        #     {
        #         "apiVersion": "vpcresources.k8s.aws/v1beta1",
        #         "kind": "SecurityGroupPolicy",
        #         "metadata": {
        #             "name": "karpenter-security-group-policy",
        #             "namespace": "karpenter"
        #         },
        #         "spec": {
        #             "podSelector": {
        #                 "matchLabels": {
        #                     "app.kubernetes.io/name": "karpenter"
        #                 }
        #             },
        #             "securityGroups": {
        #                 "groupIds": [
        #                     "sg-0dd3d8a91e534b3f9",
        #                     cluster.cluster_security_group_id
        #                 ]
        #             }
        #         }
        #     }
        # )

        # Karpenter에 부여할 서비스 어카운트 생성
        karpenter_sa = cluster.add_service_account("karpenter_sa",
            name="karpenter",
            namespace="karpenter"
        )

        karpenter_sa.node.add_dependency(karpenter_ns)

        # Karpenter에 필요한 권한 부여
        karpenter_sa.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "Karpenter",
                    "Effect": "Allow",
                    "Resource": "*",
                    "Action": [
                        "ssm:GetParameter",
                        "ec2:DescribeImages",
                        "ec2:RunInstances",
                        "ec2:DescribeSubnets",
                        "ec2:DescribeSecurityGroups",
                        "ec2:DescribeLaunchTemplates",
                        "ec2:DescribeInstances",
                        "ec2:DescribeInstanceTypes",
                        "ec2:DescribeInstanceTypeOfferings",
                        "ec2:DescribeAvailabilityZones",
                        "ec2:DeleteLaunchTemplate",
                        "ec2:CreateTags",
                        "ec2:CreateLaunchTemplate",
                        "ec2:CreateFleet",
                        "ec2:DescribeSpotPriceHistory",
                        "pricing:GetProducts"
                    ]
                }
            )
        )

        karpenter_sa.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "ConditionalEC2Termination",
                    "Effect": "Allow",
                    "Resource": "*",
                    "Action": "ec2:TerminateInstances",
                    "Condition": {
                        "StringLike": {
                            "ec2:ResourceTag/karpenter.sh/nodepool": "*"
                        }
                    }
                }
            )
        )

        karpenter_sa.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "PassNodeIAMRole",
                    "Effect": "Allow",
                    "Action": "iam:PassRole",
                    "Resource": f"{karpenter_node_role.role_arn}"
                }
            )
        )

        karpenter_sa.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "EKSClusterEndpointLookup",
                    "Effect": "Allow",
                    "Action": "eks:DescribeCluster",
                    "Resource": f"{cluster.cluster_arn}"
                }
            )
        )

        karpenter_sa.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "AllowScopedInstanceProfileCreationActions",
                    "Effect": "Allow",
                    "Resource": "*",
                    "Action": [
                        "iam:CreateInstanceProfile"
                    ],
                    "Condition": {
                        "StringEquals": {
                            "aws:RequestTag/kubernetes.io/cluster/work-dev": "owned",
                            "aws:RequestTag/topology.kubernetes.io/region": self.region
                        },
                        "StringLike": {
                            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
                        }
                    }
                }
            )
        )

        karpenter_sa.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "AllowScopedInstanceProfileTagActions",
                    "Effect": "Allow",
                    "Resource": "*",
                    "Action": [
                        "iam:TagInstanceProfile"
                    ],
                    "Condition": {
                        "StringEquals": {
                            "aws:RequestTag/kubernetes.io/cluster/work-dev": "owned",
                            "aws:ResourceTag/topology.kubernetes.io/region": self.region,
                            "aws:RequestTag/kubernetes.io/cluster/work-dev": "owned",
                            "aws:RequestTag/topology.kubernetes.io/region": self.region
                        },
                        "StringLike": {
                            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*",
                            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
                        }
                    }
                }
            )
        )

        karpenter_sa.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "AllowScopedInstanceProfileActions",
                    "Effect": "Allow",
                    "Resource": "*",
                    "Action": [
                        "iam:AddRoleToInstanceProfile",
                        "iam:RemoveRoleFromInstanceProfile",
                        "iam:DeleteInstanceProfile"
                    ]
                }
            )
        )

        karpenter_sa.add_to_principal_policy(
            iam.PolicyStatement.from_json(
                {
                    "Sid": "AllowInstanceProfileReadActions",
                    "Effect": "Allow",
                    "Resource": "*",
                    "Action": "iam:GetInstanceProfile"
                }
            )
        )

        # Karpenter
        karpenter = cluster.add_helm_chart("karpenter",
            repository="oci://public.ecr.aws/karpenter/karpenter",
            chart="karpenter",
            release="karpenter",
            namespace="karpenter",
            version="1.0.1",
            values={
                "controller":{
                    "resources": {
                        "requests": {
                            "cpu": "100m",
                            "memory": "500Mi"
                        },
                        "limits": {
                            "memory": "1Gi"
                        }
                    }
                },
                "settings": {
                    "clusterName": cluster.cluster_name
                },
                "serviceMonitor": {
                    "enabled": True,
                    "additionalLabels": {
                        "cluster": "work-dev"
                    },
                    "endpointConfig": {
                        "interval": "30s"
                    }
                },
                "serviceAccount": {
                    "create": False,
                    "name": "karpenter"
                },
                "nodeSelector": {
                    "node-group": "worker-critical"
                },
                "tolerations": [
                    {
                        "key": "CriticalAddonsOnly",
                        "operator": "Exists"
                    }
                ]                
            }
        )

        karpenter.node.add_dependency(karpenter_sa)
        # karpenter.node.add_dependency(karpenter_fargate_profile)

        # 도커 설치 및 SSM 세션 매니저에서 사용할 유저를 추가하는 스크립트 불러오기
        karpenter_scripts = open("scripts/karpenter-adduser.sh", "r").read()

        # EC2NodeClass
        karpenter_ec2_nodeclasss = cluster.add_manifest("karpenter_ec2_nodeclasss",
            {
                "apiVersion": "karpenter.k8s.aws/v1",
                "kind": "EC2NodeClass",
                "metadata": {
                    "name": "default"
                },
                "spec": {
                    "amiSelectorTerms": [
                        {
                            "alias": "al2023@v20250829"
                        }
                    ],
                    "role": karpenter_node_role.role_name,
                    "subnetSelectorTerms": [
                        {
                            "id": private_subnet_a.ref
                        },
                        {
                            "id": private_subnet_c.ref
                        },
                        {
                            "id": private_subnet_a2.ref
                        },
                        {
                            "id": private_subnet_c2.ref
                        }
                    ],
                    "securityGroupSelectorTerms": [
                        {
                            "id": "sg-0dd3d8a91e534b3f9"
                        },
                        {
                            "id": cluster.cluster_security_group_id
                        }
                    ],
                    "blockDeviceMappings": [
                        {
                            "deviceName": "/dev/xvda",
                            "ebs": {
                                "volumeSize": "60Gi",
                                "volumeType": "gp3",
                                "encrypted": True
                            }
                        }
                    ],
                    "userData": karpenter_scripts,
                    "metadataOptions": {
                        "httpEndpoint": "enabled",
                        "httpPutResponseHopLimit": 2,
                        "httpTokens": "optional"
                    },
                    "tags": {
                        "Name": "work-dev-worker",
                        "Env" : "work",
                        "Type" : "ec2",
                    }
                }
            }
        )

        karpenter_ec2_nodeclasss.node.add_dependency(karpenter)

        # 도커 설치 및 SSM 세션 매니저에서 사용할 유저를 추가하는 스크립트 불러오기
        karpenter_cw_scripts = open("scripts/karpenter-adduser-cw-disable.sh", "r").read()

        # EC2NodeClass
        karpenter_ec2_mq_nodeclass = cluster.add_manifest("karpenter_ec2_mq_nodeclass",
            {
                "apiVersion": "karpenter.k8s.aws/v1",
                "kind": "EC2NodeClass",
                "metadata": {
                    "name": "default-cw-disable"
                },
                "spec": {
                    "amiSelectorTerms": [
                        {
                            "alias": "al2023@v20250829"
                        }
                    ],
                    "role": karpenter_node_role.role_name,
                    "subnetSelectorTerms": [
                        {
                            "id": private_subnet_a.ref
                        },
                        {
                            "id": private_subnet_c.ref
                        },
                        {
                            "id": private_subnet_a2.ref
                        },
                        {
                            "id": private_subnet_c2.ref
                        }
                    ],
                    "securityGroupSelectorTerms": [
                        {
                            "id": "sg-0dd3d8a91e534b3f9"
                        },
                        {
                            "id": cluster.cluster_security_group_id
                        }
                    ],
                    "blockDeviceMappings": [
                        {
                            "deviceName": "/dev/xvda",
                            "ebs": {
                                "volumeSize": "60Gi",
                                "volumeType": "gp3",
                                "encrypted": True
                            }
                        }
                    ],
                    "userData": karpenter_cw_scripts,
                    "metadataOptions": {
                        "httpEndpoint": "enabled",
                        "httpPutResponseHopLimit": 2,
                        "httpTokens": "optional"
                    },
                    "tags": {
                        "Name": "work-dev-worker-mq",
                        "Env" : "work",
                        "Type" : "ec2",
                    }
                }
            }
        )

        karpenter_ec2_mq_nodeclass.node.add_dependency(karpenter)

        # NodePool
        karpenter_default_nodepool = cluster.add_manifest("karpenter_default_nodepool",
            {
                "apiVersion": "karpenter.sh/v1",
                "kind": "NodePool",
                "metadata": {
                    "name": "default"
                },
                "spec": {
                    "template": {
                        "spec": {
                            "expireAfter": "2160h",
                            "terminationGracePeriod": "1h",                            
                            "requirements": [
                                {
                                    "key": "kubernetes.io/arch",
                                    "operator": "In",
                                    "values": [
                                        "amd64"
                                    ]
                                },
                                {
                                    "key": "kubernetes.io/os",
                                    "operator": "In",
                                    "values": [
                                        "linux"
                                    ]
                                },
                                {
                                    "key": "karpenter.sh/capacity-type",
                                    "operator": "In",
                                    "values": [
                                        "on-demand"
                                    ]
                                },
                                {
                                    "key": "node.kubernetes.io/instance-type",
                                    "operator": "In",
                                    "values": [
                                        "r5a.large",
                                    ]
                                }
                            ],
                            "nodeClassRef": {
                                "group": "karpenter.k8s.aws",
                                "kind": "EC2NodeClass",
                                "name": "default"
                            }
                        }
                    },
                    "disruption": {
                      "consolidationPolicy": "WhenEmptyOrUnderutilized",
                      "consolidateAfter": "5m",
                      "budgets": [
                        {
                          "nodes": "0",
                          "schedule": "0 0 * * mon-fri",
                          "duration": "10h",
                          "reasons": [
                            "Drifted"
                          ]
                        },
                        {
                          "nodes": "0",
                          "schedule": "0 0 * * mon-fri",
                          "duration": "2h30m",
                          "reasons": [
                            "Underutilized"
                          ]
                        },
                        {
                          "nodes": "0",
                          "schedule": "0 4 * * mon-fri",
                          "duration": "6h",
                          "reasons": [
                            "Underutilized"
                          ]
                        },
                        {
                          "nodes": "2",
                          "reasons": [
                            "Drifted",
                            "Underutilized"
                          ]
                        },
                        {
                          "nodes": "30%",
                          "reasons": [
                            "Drifted",
                            "Underutilized"
                          ]
                        },
                        {
                          "nodes": "100%",
                          "reasons": [
                            "Empty"
                          ]
                        }
                      ]
                    }
                }
            }
        )

        karpenter_default_nodepool.node.add_dependency(karpenter_ec2_nodeclasss)

        karpenter_onoff_nodepool = cluster.add_manifest("karpenter_onoff_nodepool",
            {
                "apiVersion": "karpenter.sh/v1",
                "kind": "NodePool",
                "metadata": {
                    "name": "onoff"
                },
                "spec": {
                    "template": {
                        "metadata": {
                            "labels": {
                                "onoff": "true"
                            }
                        },
                        "spec": {
                            "expireAfter": "2160h",
                            "terminationGracePeriod": "1h",                            
                            "taints": [
                                {
                                    "key": "onoff",
                                    "value": "true",
                                    "effect": "NoSchedule"
                                }
                            ],
                            "requirements": [
                                {
                                    "key": "kubernetes.io/arch",
                                    "operator": "In",
                                    "values": [
                                        "amd64"
                                    ]
                                },
                                {
                                    "key": "kubernetes.io/os",
                                    "operator": "In",
                                    "values": [
                                        "linux"
                                    ]
                                },
                                {
                                    "key": "karpenter.sh/capacity-type",
                                    "operator": "In",
                                    "values": [
                                        "on-demand"
                                    ]
                                },
                                {
                                    "key": "node.kubernetes.io/instance-type",
                                    "operator": "In",
                                    "values": [
                                        "r5a.large",
                                    ]
                                }
                            ],
                            "nodeClassRef": {
                                "group": "karpenter.k8s.aws",
                                "kind": "EC2NodeClass",
                                "name": "default"
                            }
                        }
                    },
                    "disruption": {
                      "consolidationPolicy": "WhenEmptyOrUnderutilized",
                      "consolidateAfter": "5m",
                      "budgets": [
                        {
                          "nodes": "0",
                          "schedule": "0 0 * * mon-fri",
                          "duration": "10h",
                          "reasons": [
                            "Drifted"
                          ]
                        },
                        {
                          "nodes": "0",
                          "schedule": "0 0 * * mon-fri",
                          "duration": "2h30m",
                          "reasons": [
                            "Underutilized"
                          ]
                        },
                        {
                          "nodes": "0",
                          "schedule": "0 4 * * mon-fri",
                          "duration": "6h",
                          "reasons": [
                            "Underutilized"
                          ]
                        },                         
                        {
                          "nodes": "2",
                          "reasons": [
                            "Drifted",
                            "Underutilized"
                          ]
                        },
                        {
                          "nodes": "30%",
                          "reasons": [
                            "Drifted",
                            "Underutilized"
                          ]
                        },
                        {
                          "nodes": "100%",
                          "reasons": [
                            "Empty"
                          ]
                        }
                      ]
                    } 
                }
            }
        )

        karpenter_onoff_nodepool.node.add_dependency(karpenter_ec2_nodeclasss)

        karpenter_rmq_nodepool = cluster.add_manifest("karpenter_rmq_nodepool",
            {
                "apiVersion": "karpenter.sh/v1",
                "kind": "NodePool",
                "metadata": {
                    "name": "rmq"
                },
                "spec": {
                    "template": {
                        "metadata": {
                            "labels": {
                                "rmq": "true"
                            }
                        },
                        "spec": {
                            "expireAfter": "Never",
                            "terminationGracePeriod": "1h",                            
                            "taints": [
                                {
                                    "key": "rmq",
                                    "value": "true",
                                    "effect": "NoSchedule"
                                }
                            ],
                            "requirements": [
                                {
                                    "key": "kubernetes.io/arch",
                                    "operator": "In",
                                    "values": [
                                        "arm64"
                                    ]
                                },
                                {
                                    "key": "kubernetes.io/os",
                                    "operator": "In",
                                    "values": [
                                        "linux"
                                    ]
                                },
                                {
                                    "key": "karpenter.sh/capacity-type",
                                    "operator": "In",
                                    "values": [
                                        "on-demand"
                                    ]
                                },
                                {
                                    "key": "node.kubernetes.io/instance-type",
                                    "operator": "In",
                                    "values": [
                                        "t4g.medium"
                                    ]
                                },
                            ],
                            "nodeClassRef": {
                                "group": "karpenter.k8s.aws",
                                "kind": "EC2NodeClass",
                                "name": "default-cw-disable"
                            }
                        }
                    },
                    "disruption": {
                        "consolidationPolicy": "WhenEmpty",
                        "consolidateAfter": "3m"
                    }
                }
            }
        )

        karpenter_rmq_nodepool.node.add_dependency(karpenter_ec2_mq_nodeclass)

        # MQ NLB에 부여할 보안그룹 생성
        work_dev_mq_sg = ec2.SecurityGroup(self, "work_dev_mq_sg",
            vpc=vpc,
            security_group_name="work-dev-mq-sg",
            description="EKS Work dev RabbitMQ",
            allow_all_outbound=False
        )

        Tags.of(work_dev_mq_sg).add("Name", "work-dev-mq-sg")

        # MQ NLB 5672, 15672, 9419 보안그룹 인바운드 규칙
        work_dev_mq_all_white_list = [
            {"ip":"10.15.2.0/24","description":"office 2F from cdk"},
        ]
        
        # MQ NLB 5672 보안그룹 인바운드 규칙
        work_dev_mq_data_white_list = [
            {"ip":"10.151.21.32/32","description":"dev-net-hf-a-32 from cdk"},
            {"ip":"20.20.20.0/24","description":"Office IT outsourcing from cdk"},
            {"ip":"10.15.2.0/24","description":"Office IT from cdk"},
        ]

        for source in work_dev_mq_all_white_list:
            work_dev_mq_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(5672),
                description=source["description"]
            )

            work_dev_mq_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(9419),
                description=source["description"]
            )

            work_dev_mq_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(443),
                description=source["description"]
            )

        for source in work_dev_mq_data_white_list:
            work_dev_mq_sg.add_ingress_rule(
                ec2.Peer.ipv4(source["ip"]),
                ec2.Port.tcp(5672),
                description=source["description"]
            )

        work_dev_mq_sg.add_ingress_rule(
            ec2.Peer.security_group_id(cluster.cluster_security_group_id),
            ec2.Port.tcp(5672)
        )

        mq_ports = [5672, 15672, 9419]
        
        # MQ NLB 보안그룹 아웃바운드 규칙
        for port in mq_ports:
            work_dev_mq_sg.add_egress_rule(
                ec2.Peer.security_group_id(cluster.cluster_security_group_id),
                ec2.Port.tcp(port)
            )
        
        # NodeGroup 보안그룹 인바운드 규칙  work_dev_mq_sg => NodeGroup
        for port in mq_ports:
            node_group_sg.add_ingress_rule(
                ec2.Peer.security_group_id(work_dev_mq_sg.security_group_id),
                ec2.Port.tcp(port)
            )

       # NodeGroup 보안그룹 아웃바운드 규칙  NodeGroup => MQ LB SG
        ec2.CfnSecurityGroupEgress(self, f'{control_plane_main_sg.unique_id}-rmq',
            group_id=control_plane_main_sg.security_group_id,
            ip_protocol="tcp",
            destination_security_group_id=work_dev_mq_sg.security_group_id,
            from_port=5672,
            to_port=5672
        )

        # 안되서 추가한거 위를 추가햇더니 없어져서 아래를 추가한것!

       # NodeGroup 보안그룹 아웃바운드 규칙  NodeGroup => ALL
        ec2.CfnSecurityGroupEgress(self, f'{control_plane_main_sg.unique_id}-all-out',
            group_id=control_plane_main_sg.security_group_id,
            ip_protocol="-1",
            cidr_ip="0.0.0.0/0"
        )

        rmq_ns = cluster.add_manifest("rmq_ns",
            {
                "kind": "Namespace",
                "apiVersion": "v1",
                "metadata": {
                    "name": "rabbitmq"
                }
            }
        )


        # mq_secret = secretsmanager.Secret.from_secret_name_v2(
        #     self, "WorkDevMqSecret", secret_name="dev/eks/work-dev/rabbitmq-password-secret"
        # )

        # mq_admin_password = mq_secret.secret_value_from_json("admin-password").unsafe_unwrap()
        # mq_user_password = mq_secret.secret_value_from_json("user-password").unsafe_unwrap()
        # mq_app_password = mq_secret.secret_value_from_json("app-password").unsafe_unwrap()
        # mq_erlang_cookie = mq_secret.secret_value_from_json("erlang-cookie").unsafe_unwrap()
        # mq_erlang_cookie2 = mq_secret.secret_value.to_string()


        rmq_secret = cluster.add_manifest("rmq_secret", 
            {
                "apiVersion": "v1",
                "kind": "Secret",
                "metadata": {
                    "name": "rabbitmq-password-secret",
                    "namespace": "rabbitmq"
                },
                "type": "Opaque",
                "data": {
                    "rabbitmq-admin-password": "d2pzdGtzdGxmMTI=",
                    "rabbitmq-app-password": "V2pzdGtzdGxmMQ==",
                    "rabbitmq-erlang-cookie": "VW1WbWFXNWxNVEFL",
                    "rabbitmq-password": "d2pzdGtzdGxmMTI=",
                    "rabbitmq-user-password": "d2pzdGtzdGxmMTI=",
                }
            }
        )
        
        rmq_secret.node.add_dependency(rmq_ns)
        
      # rabbitmq 헬름 차트에 사용할 변수 파일 불러오기
        with open("kubernetes/helm/work-dev/rabbitmq.yaml", "r") as stream:
            rmq_values = yaml.safe_load(
                stream.read().replace("${work_dev_mq_sg.id}", work_dev_mq_sg.security_group_id)
            )            

        # kubePromStack 헬름 차트 설치
        rabbitmq = cluster.add_helm_chart("rabbitmq",
            repository="https://charts.bitnami.com/bitnami",
            chart="rabbitmq",
            release="rabbitmq",
            namespace="rabbitmq",
            version="16.0.2",
            values=rmq_values
        )
        
        rabbitmq.node.add_dependency(rmq_ns)
                    