# backend 사내 쿠버네티스에 배포하는 순서

1. Dockerfile 작성 후 도커이미지를 생성한다.
- 어플리케이션에 맞도록 Dockerfile 수정 후 도커이미지 빌드

```
docker build -t appname:tagname -f Dockerfile .
```

2. namespace를 생성한다
3. 실행전 helmchart 파일 구성하기
```
1. helmchart의 값설정 파일인 values.yaml 에서 필요한 값들을 적절히 수정한다.


2. (PV가 필요한 경우) app-local-pv.yaml, app-local-pvc.yaml 파일 내용을 수정하고, 적절하게 pv,pvc를 생성한다

### pv는 전역 설정
$ kubectl apply -f app-local-pv.yaml

### pvc는 namespace별 생성
$ kubectl apply -n app-jsms -f app-local-pv.yaml

## pvc 이름 확인
$ kubectl get pvc -n app-jsms
NAME    STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
dev-jsms   Bound    jsms    10Gi       RWX            jsms          115m


3. (PV가 필요한 경우) jsms container에 pvc연결하기

values.yaml 파일에 아래 부분 주석 해제하고 PVC이름, 경로를 맞춰준다
#  persistentVolumeClaim: # pvc
#    claimName: jtbchistory
#    containerMountPoint: /data
```

4. ingress설정 추가
- values.yaml 파일에서 ingress 부분 수정

5. helmchart 실행전 문법검사

```
helm install -n 네임스페이스명 헬름차트명 현재폴더 --dry-run
ex) helm install -n app-jsms jsms . --dry-run

```

6. helmchart 실행

```
helm install -n app-jsms jsms .
```

7. 실행 결과 확인

```
$ kubectl get all -n app-jsms

```

8. (SSL인증서 사용시) secret 생성

```
도메인에 맞는 tls인증서를 직접 namespace에 생성해준다

```

9. 실제 운영환경에 맞도록 CICD 파이프라인 구성을 한다.

```
app 실행이 잘되었으면 helm uninstall 하고 argocd로 배포 구성을 다시 한다. (CD툴)

# helm 삭제
ex) helm uninstall jsms -n -n app-jsms

```

# secret 관리

매뉴얼 : https://docs.google.com/presentation/d/1mUtY_EdwRGbSBxAkQ9BeSUECthcR1ybYTGfi1Fb7_Qo/edit#slide=id.p1

```
인증서 파일 위치 : bastion서버 : ~/workspace/ssl
인증서 생성 : kubectl create -n [각 어플리케이션별 namespace] secret tls [도메인별 secret 이름] --key {SSL.key} --cert {SSL.crt}
           ex) ex) kubectl create -n app-jtbcmediatech-hm secret tls tls-jtbcmediatech.com --key key.pem --cert cert.pem
```
