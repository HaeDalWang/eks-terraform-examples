import json
import boto3
import logging
import os
import random
import string
import time
from datetime import datetime
from botocore.exceptions import ClientError

# 로깅 설정
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    EventBridge Scheduler에서 호출되는 Lambda 핸들러
    RDS 비밀번호를 변경하고 ezl-app-server-secrets의 DB_PASSWORD를 업데이트
    """
    try:
        logger.info(f"비밀번호 로테이션 시작. 이벤트: {json.dumps(event)}")
        
        # 환경 변수에서 설정 값 가져오기
        db_instance_id = os.environ['DB_INSTANCE_IDENTIFIER']
        app_secret_name = os.environ['SECRETS_MANAGER_SECRET']
        
        # 1. 새로운 비밀번호 생성
        new_password = generate_secure_password()
        logger.info("새 비밀번호 생성 완료")
        
        # 2. RDS 인스턴스 비밀번호 변경
        change_rds_password(db_instance_id, new_password)
        
        # 3. RDS 변경이 적용될 때까지 대기
        wait_for_rds_modification(db_instance_id)
        
        # 4. ezl-app-server-secrets의 DB_PASSWORD 업데이트
        update_app_secret_password(app_secret_name, new_password)
        
        # 5. RDS 상태 확인 (연결 테스트는 제거)
        verify_rds_status(db_instance_id)
        
        logger.info("비밀번호 로테이션 성공적으로 완료")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': '비밀번호 로테이션 완료',
                'db_instance': db_instance_id,
                'secret_name': app_secret_name,
                'timestamp': context.aws_request_id,
                'updated_at': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"비밀번호 로테이션 실패: {str(e)}")
        
        # 실패 알림 (SNS 등으로 확장 가능)
        send_failure_notification(str(e), context.aws_request_id)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': '비밀번호 로테이션 실패',
                'message': str(e)
            })
        }

def generate_secure_password(length=16):
    """
    안전한 비밀번호 생성
    RDS 요구사항에 맞는 비밀번호 생성 (대문자, 소문자, 숫자, 특수문자 포함)
    """
    # RDS에서 허용하는 특수문자만 사용
    special_chars = "!@#$%^&*()_+-=[]{}|;:,.<>?"
    
    # 각 문자 유형에서 최소 개수 보장
    password_chars = []
    password_chars.extend(random.choices(string.ascii_uppercase, k=4))  # 대문자 4개
    password_chars.extend(random.choices(string.ascii_lowercase, k=4))  # 소문자 4개
    password_chars.extend(random.choices(string.digits, k=4))           # 숫자 4개
    password_chars.extend(random.choices(special_chars, k=4))           # 특수문자 4개
    
    # 나머지 길이 채우기
    remaining_length = length - len(password_chars)
    if remaining_length > 0:
        all_chars = string.ascii_letters + string.digits + special_chars
        password_chars.extend(random.choices(all_chars, k=remaining_length))
    
    # 순서 섞기
    random.shuffle(password_chars)
    
    return ''.join(password_chars)

def change_rds_password(db_instance_id, new_password):
    """
    RDS 인스턴스의 마스터 사용자 비밀번호 변경
    """
    try:
        rds_client = boto3.client('rds')
        
        logger.info(f"RDS 인스턴스 {db_instance_id}의 비밀번호 변경 중...")
        
        response = rds_client.modify_db_instance(
            DBInstanceIdentifier=db_instance_id,
            MasterUserPassword=new_password,
            ApplyImmediately=True  # 즉시 적용
        )
        
        logger.info(f"RDS 비밀번호 변경 요청 완료. 수정 상태: {response['DBInstance']['DBInstanceStatus']}")
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"RDS 비밀번호 변경 실패: {error_code} - {error_message}")
        raise Exception(f"RDS 비밀번호 변경 실패: {error_message}")

def wait_for_rds_modification(db_instance_id, max_wait_time=300):
    """
    RDS 인스턴스 수정이 완료될 때까지 대기
    """
    try:
        rds_client = boto3.client('rds')
        start_time = time.time()
        
        logger.info("RDS 인스턴스 수정 완료 대기 중...")
        
        while time.time() - start_time < max_wait_time:
            response = rds_client.describe_db_instances(
                DBInstanceIdentifier=db_instance_id
            )
            
            db_instance = response['DBInstances'][0]
            status = db_instance['DBInstanceStatus']
            
            logger.info(f"현재 RDS 상태: {status}")
            
            if status == 'available':
                logger.info("RDS 인스턴스 수정 완료")
                return
            elif status in ['failed', 'incompatible-parameters']:
                raise Exception(f"RDS 수정 실패: {status}")
            
            time.sleep(30)  # 30초 대기
        
        raise Exception(f"RDS 수정 완료 대기 시간 초과 ({max_wait_time}초)")
        
    except ClientError as e:
        logger.error(f"RDS 상태 확인 실패: {e}")
        raise

def update_app_secret_password(secret_name, new_password):
    """
    ezl-app-server-secrets의 DB_PASSWORD 값 업데이트
    """
    try:
        secrets_client = boto3.client('secretsmanager')
        
        logger.info(f"시크릿 {secret_name}의 DB_PASSWORD 업데이트 중...")
        
        try:
            # 현재 시크릿 값 가져오기
            response = secrets_client.get_secret_value(SecretId=secret_name)
            current_secret = json.loads(response['SecretString'])
            
            # DB_PASSWORD 값 업데이트
            current_secret['DB_PASSWORD'] = new_password
            current_secret['DB_PASSWORD_UPDATED_AT'] = datetime.now().isoformat()
            current_secret['DB_PASSWORD_TYPE'] = "rotated"
            
            # 업데이트된 시크릿 저장
            secrets_client.put_secret_value(
                SecretId=secret_name,
                SecretString=json.dumps(current_secret)
            )
            
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                # 시크릿이 존재하지 않으면 새로 생성
                logger.info(f"시크릿 {secret_name}이 존재하지 않음. 새로 생성 중...")
                
                new_secret = {
                    'DB_PASSWORD': new_password,
                    'DB_PASSWORD_UPDATED_AT': datetime.now().isoformat(),
                    'DB_PASSWORD_TYPE': 'created'
                }
                
                secrets_client.create_secret(
                    Name=secret_name,
                    Description=f"Database password for {secret_name}",
                    SecretString=json.dumps(new_secret)
                )
                
                logger.info(f"시크릿 {secret_name} 새로 생성 완료")
            else:
                raise
        
        logger.info(f"시크릿 {secret_name}의 DB_PASSWORD 업데이트 완료")
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"시크릿 업데이트 실패: {error_code} - {error_message}")
        raise Exception(f"시크릿 업데이트 실패: {error_message}")

def verify_rds_status(db_instance_id):
    """
    RDS 인스턴스 상태 확인 (간단한 boto3만 사용)
    """
    try:
        rds_client = boto3.client('rds')
        
        # RDS 인스턴스 상태 확인
        response = rds_client.describe_db_instances(
            DBInstanceIdentifier=db_instance_id
        )
        
        db_instance = response['DBInstances'][0]
        status = db_instance['DBInstanceStatus']
        engine = db_instance['Engine']
        endpoint = db_instance['Endpoint']['Address']
        
        logger.info(f"RDS 상태 확인 완료: {engine} - {status}")
        logger.info(f"RDS 엔드포인트: {endpoint}")
        
        if status == 'available':
            logger.info("RDS 인스턴스가 정상 상태입니다")
        else:
            logger.warning(f"RDS 인스턴스 상태: {status}")
        
    except Exception as e:
        logger.error(f"RDS 상태 확인 실패: {str(e)}")
        # 상태 확인 실패는 전체 프로세스를 중단시키지 않음
        logger.warning("RDS 상태 확인 실패했지만 로테이션은 완료됨")

def send_failure_notification(error_message, request_id):
    """
    실패 알림 전송 (SNS, 슬랙 등으로 확장 가능)
    """
    try:
        # 여기에 SNS, 슬랙, 이메일 등 알림 로직 추가 가능
        logger.error(f"알림 전송: 비밀번호 로테이션 실패 - {error_message} (RequestId: {request_id})")
        
        # 예시: SNS로 알림 전송
        # sns_client = boto3.client('sns')
        # sns_client.publish(
        #     TopicArn='arn:aws:sns:region:account:topic-name',
        #     Message=f'RDS 비밀번호 로테이션 실패: {error_message}',
        #     Subject='RDS Password Rotation Failed'
        # )
        
    except Exception as e:
        logger.error(f"알림 전송 실패: {str(e)}")
