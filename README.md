# OpsPilot Infrastructure

OpsPilot 애플리케이션의 Kubernetes 배포 설정을 관리합니다. 애플리케이션 저장소의 GitHub Actions가 Docker Hub에 발행한 이미지를 사용합니다.

```text
k8s/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    └── prod/
terraform/
├── modules/
└── environments/
```

Terraform은 현재 폴더 구조만 준비했으며 AWS 리소스를 생성하는 코드는 없습니다.

## 환경별 설정

| 항목 | dev | prod |
| --- | --- | --- |
| Namespace | opspilot-dev | opspilot-prod |
| Spring profile | dev | prod |
| DDL_AUTO | update | validate |
| Pod 수 | 1 | 1 |
| 장애 테스트 API | 비활성 | 비활성 |
| Service | ClusterIP:80 → Pod:8080 | ClusterIP:80 → Pod:8080 |

기존 K3s 클러스터와 접근 가능한 MySQL이 필요합니다. MySQL/RDS, 외부 트래픽 라우팅, HPA는 이 구성에 포함되지 않습니다. prod는 배포 전에 애플리케이션이 요구하는 DB 스키마가 준비되어 있어야 합니다. `validate`는 테이블을 생성하지 않습니다.

현재 애플리케이션 이미지는 linux/amd64이므로 amd64 노드에 배치합니다. startup/liveness는 Actuator liveness, readiness는 readinessState와 DB 상태를 확인합니다. 메모리 limit은 512Mi이며 JVM 최대 힙 비율은 60%로 설정했습니다.

## 최초 배포

아래는 prod 기준입니다. dev를 배포할 때는 경로와 namespace를 dev로 바꿉니다. 먼저 `kubectl config current-context`로 대상 클러스터를 확인합니다.

1. `k8s/overlays/prod/kustomization.yaml`의 `images` 값을 실제 Docker Hub 이미지로 변경합니다.

```yaml
images:
  - name: opspilot
    newName: docker.io/YOUR_DOCKERHUB_USERNAME/opspilot
    newTag: sha-FULL_COMMIT_SHA
```

앱 저장소 CI가 발행한 `sha-<전체 커밋 SHA>` 태그를 지정합니다. placeholder는 배포 가능한 이미지가 아니므로 반드시 변경합니다. GitHub의 `Prod` Environment 시크릿은 Kubernetes에 자동 전달되지 않습니다.

2. namespace와 DB Secret을 준비합니다.

```bash
kubectl apply -f k8s/overlays/prod/namespace.yaml
cp k8s/overlays/prod/db.env.example k8s/overlays/prod/.env.db
# .env.db의 DB_HOST, DB_NAME, DB_USERNAME, DB_PASSWORD를 실제 값으로 편집
kubectl -n opspilot-prod create secret generic opspilot-db \
  --from-env-file=k8s/overlays/prod/.env.db \
  --dry-run=client -o yaml | kubectl apply -f -
```

`.env.db`는 Git에서 제외됩니다. DB 포트는 overlay의 `DB_PORT`로 설정합니다. Secret은 외부에서 관리하며 Kustomize 출력에 자격 증명을 포함하지 않습니다. DB Secret 변경 후에는 `kubectl -n opspilot-prod rollout restart deployment/opspilot`을 실행해야 환경변수가 다시 로드됩니다.

Docker Hub 이미지가 비공개라면 같은 namespace에 registry 인증 Secret을 생성하고 Deployment의 `spec.template.spec.imagePullSecrets`에 연결해야 합니다. CI의 Docker Hub 로그인은 클러스터의 이미지 pull 인증을 설정하지 않습니다.

3. 매니페스트를 확인하고 배포합니다.

```bash
kubectl kustomize k8s/overlays/prod
kubectl apply -k k8s/overlays/prod
kubectl -n opspilot-prod rollout status deployment/opspilot --timeout=300s
kubectl -n opspilot-prod get pods,svc
```

4. 로컬에서 접속을 확인합니다.

```bash
kubectl -n opspilot-prod port-forward service/opspilot 8080:80
# 다른 터미널
curl http://localhost:8080/actuator/health/readiness
```

Service는 클러스터 내부 전용입니다. 외부 접근용 NodePort/ALB는 네트워크 구성이 결정되면 추가합니다. prod 장애 테스트를 할 때는 접근 경로를 제한한 뒤 `FAULT_TESTS_ENABLED`를 명시적으로 변경합니다.

## 이미지 업데이트와 복구

새 SHA 태그로 overlay를 변경하고 `kubectl apply -k`로 배포합니다. 복구할 때는 overlay를 이전 이미지 태그로 되돌린 뒤 다시 적용합니다. 이 저장소에는 아직 자동 배포 워크플로가 없으며, 앱 저장소의 이미지 발행만으로 클러스터 배포가 실행되지는 않습니다.

## 검증

```bash
kubectl kustomize k8s/overlays/dev
kubectl kustomize k8s/overlays/prod
```

참고: [Kustomize 공식 문서](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/), [Probe 공식 문서](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/).
