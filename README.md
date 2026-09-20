# OpsPilot Infrastructure

OpsPilot의 AWS 인프라와 Kubernetes 배포 설정을 관리하는 저장소입니다.
Terraform으로 네트워크·보안 그룹·EC2를 구성하고, GitHub Actions에서 K3s의 애플리케이션 이미지를 업데이트합니다.

## 구성 한눈에 보기

| 영역 | 현재 구성 | 위치 |
| --- | --- | --- |
| 네트워크 | VPC, AZ별 서브넷, Internet Gateway, 라우팅 테이블 및 연결 | `terraform/modules/network` |
| 보안 | VPC에 연결된 Security Group | `terraform/modules/security` |
| 컴퓨팅 | 인스턴스별 EC2, 퍼블릭 IP, 기존 `opsPilot` 키 페어 참조 | `terraform/modules/compute` |
| 운영 환경 | network → security → compute 모듈 연결 | `terraform/environments/prod` |
| 애플리케이션 | Deployment 1개, NodePort Service | `k8s/base` |
| 배포 자동화 | dispatch 이벤트 → SSH → 이미지 변경 → rollout 확인 | `.github/workflows/cd.yml` |

## 디렉터리 구조

```text
.
├── .github/workflows/
│   └── cd.yml
├── k8s/base/
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   └── service.yaml
└── terraform/
    ├── environments/prod/
    │   ├── main.tf
    │   ├── providers.tf
    │   ├── variables.tf
    │   ├── terraform.tfvars     # 로컬 설정 · Git 제외
    │   ├── outputs.tf
    │   └── .terraform.lock.hcl
    └── modules/
        ├── network/
        ├── security/
        └── compute/
            # 각 모듈: main.tf, variables.tf, outputs.tf
```

`prod/providers.tf`, `prod/outputs.tf`, `compute/outputs.tf`는 현재 빈 파일입니다.
데이터베이스 모듈은 현재 저장소 파일에 포함되어 있지 않습니다.

## Terraform

### 입력값

운영 환경 값은 `terraform/environments/prod/terraform.tfvars`에서 관리합니다.

| 변수 | 형식 | 용도 |
| --- | --- | --- |
| `vpc_cidr` | `string` | VPC CIDR |
| `vpc_name` | `string` | VPC Name 태그 |
| `public_subnets` | `map(object({ cidr = string, number = number }))` | AZ를 키로 사용하는 서브넷 정의 |
| `sg_name` | `string` | 보안 그룹 이름 |
| `ami_id` | `string` | EC2 AMI |
| `instances` | `map(object({ az = string, instance_type = string }))` | 인스턴스별 AZ와 타입 |

`instances`의 `az`는 `public_subnets`의 키와 일치해야 합니다.
루트의 `vpc_id`, `security_group_ids` 변수는 선언되어 있지만 현재 모듈 연결에서는 사용하지 않습니다. 모듈 출력값을 직접 전달합니다.

### 로컬 확인

AWS 인증 정보와 대상 리전은 실행 환경에서 준비합니다. 현재 코드에는 명시적인 provider 설정과 원격 backend 설정이 없습니다.

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/environments/prod init
terraform -chdir=terraform/environments/prod validate
terraform -chdir=terraform/environments/prod plan
```

`plan` 결과와 대상 계정을 확인한 후에만 별도로 `apply`를 실행합니다.
`.terraform.lock.hcl`은 provider 버전과 체크섬을 기록하므로 Git으로 관리합니다.

### 아직 구성되지 않은 부분

- public 라우팅 테이블에 Internet Gateway를 향하는 기본 경로가 없습니다.
- 보안 그룹에 ingress/egress 규칙이 정의되어 있지 않습니다.
- EC2의 K3s 설치 및 초기화 코드는 없습니다.
- 데이터베이스, 원격 state backend, 루트 출력값은 아직 구성되어 있지 않습니다.

따라서 현재 코드만으로 외부 접속과 애플리케이션 배포 준비가 모두 완료되지는 않습니다.

## Kubernetes

| 항목 | 설정 |
| --- | --- |
| Deployment / Service | `opspilot` |
| 이미지 | `jr31112/opspilot:latest` |
| 복제본 | 1 |
| Service | NodePort, 서비스·컨테이너 포트 `8080` |
| 환경변수 | Secret `opspilot-db`, ConfigMap `opspilot-config` |
| 요청 리소스 | CPU `100m`, 메모리 `128Mi` |
| 제한 리소스 | CPU `500m`, 메모리 `512Mi` |

배포할 namespace에 Secret과 ConfigMap을 먼저 준비해야 합니다. 해당 리소스의 정의는 이 저장소에 포함되어 있지 않습니다.
현재 매니페스트에는 namespace와 고정 NodePort 번호, health probe가 지정되어 있지 않습니다.

```bash
# 대상 클러스터 및 namespace 확인
kubectl config current-context
kubectl config view --minify

# 매니페스트 확인 및 배포
kubectl kustomize k8s/base
kubectl apply -k k8s/base
kubectl rollout status deployment/opspilot --timeout=120s
kubectl get pods,svc

# 로컬 접속
kubectl port-forward service/opspilot 8080:8080
```

## CD 흐름

```text
repository_dispatch (type: deploy, client_payload.image_tag)
    → production Environment
    → EC2 SSH 접속
    → kubectl set image
    → kubectl rollout status (120초)
```

`production` Environment에 승인 규칙이 설정돼 있으면 배포 전에 승인을 기다립니다.
워크플로에서 사용하는 GitHub Actions 시크릿은 다음과 같습니다.

| 시크릿 | 용도 |
| --- | --- |
| `EC2_SSH_KEY` | SSH 개인 키 |
| `EC2_HOST` | 접속할 EC2 호스트 |
| `EC2_USER` | SSH 사용자 |
| `DOCKERHUB_USER` | 이미지 저장소 사용자명 |

이미지 빌드·발행 및 dispatch 호출은 이 저장소의 워크플로에 포함되어 있지 않습니다.
CD는 기존 Deployment의 이미지만 변경합니다. 매니페스트 적용이나 Terraform 실행은 하지 않습니다.
원격 서버에서 `sudo kubectl`이 사용하는 컨텍스트와 namespace에 `opspilot` Deployment가 있어야 합니다.

복구할 때는 이전 이미지 태그로 dispatch를 보내거나, 대상 클러스터에서 다음을 실행합니다.

```bash
kubectl rollout undo deployment/opspilot
kubectl rollout status deployment/opspilot --timeout=120s
```

## Git 관리

- **포함:** Terraform 코드, provider lock 파일, Kubernetes 매니페스트, CD 워크플로
- **제외:** `terraform.tfvars`, `.env*`, Terraform state·plan, `.terraform/`, kubeconfig, Secret YAML

실제 환경 설정과 인증 정보는 로컬 또는 별도 시크릿 저장소에서 관리합니다.
