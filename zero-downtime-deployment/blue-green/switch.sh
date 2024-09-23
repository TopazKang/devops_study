#!/bin/bash

CONTAINER_NAME="컨테이너 명"
CONTAINER_SETUP_DELAY_SECOND=10
MAX_RETRY_COUNT=15
RETRY_DELAY_SECOND=2
LOADING_SECOND=15
BLUE_SERVER_URL="http://127.0.0.1:블루"
GREEN_SERVER_URL="http://127.0.0.1:그린"
HEALTH_END_POINT="api 헬스 체크 엔트포인트"
COMPOSE_FILE_BLUE="blue 컨테이너에 대한 도커 컴포즈 파일명"
COMPOSE_FILE_GREEN="green 컨테이너에 대한 도커 컴포즈 파일명"
AWS_RULE_ARN="aws 로드밸런서 리스너 규칙 arn"
BLUE_TARGET_ARN="aws 블루에 대한 타겟 그룹 arn"
GREEN_TARGET_ARN="aws 그린에 대한 타겟 그룹 arn"


#health_check
health_check() {
	local REQUEST_URL=$1
	local RETRY_COUNT=0

	echo "$REQUEST_URL"

	while [ $RETRY_COUNT -lt $MAX_RETRY_COUNT ]; do
		echo "상태 검사 진행 시도 ( $REQUEST_URL ) ... $(( RETRY_COUNT + 1 ))"
		sleep $RETRY_DELAY_SECOND

		REQUEST=$(curl -o /dev/null -s -w "%{http_code}\n" $REQUEST_URL)
		if [ "$REQUEST" -eq 200 ]; then
			echo "상태 검사 성공"
			return 0
		fi

		RETRY_COUNT=$(( RETRY_COUNT + 1 ))
	done

	return 1
}

#switch_lb_listener_rule
switch_listener() {
	local RULE_ARN=$1
	echo "로드 밸런서 타깃 그룹 변경"

	if aws elbv2 modify-rule --actions Type=forward,TargetGroupArn=$TARGET_ARN --rule-arn $RULE_ARN; then
		echo "로드 밸런서 타깃 그룹 변경 성공"
	else
		echo "로드 밸런서 타깃 그룹 변경 실패"
		return 1
	fi
}

#start_Container
start_container() {
	local COLOR=$1
	local DOCKER_COMPOSE_FILE=$2
	local SERVER_URL=$3
	local TARGET_ARN=$4

	echo "환경 정리"
	docker image prune -a -f
	echo "$COLOR 컨테이너 작동 시작"
	docker-compose -f ${DOCKER_COMPOSE_FILE} pull
	docker-compose -p ${CONTAINER_NAME}-$COLOR -f ${DOCKER_COMPOSE_FILE} up -d
	echo "${CONTAINER_SETUP_DELAY_SECOND}초 대기"
	sleep $CONTAINER_SETUP_DELAY_SECOND

	echo "$COLOR 서버 상태 확인 시작"
	if ! health_check "$SERVER_URL$HEALTH_END_POINT"; then
		echo "$COLOR 배포 실패"
		echo "$COLOR 컨테이너 정리"
		docker-compose -p ${CONTAINER_NAME}-$COLOR -f ${DOCKER_COMPOSE_FILE} down
		exit 1
	else
		if switch_listener $AWS_RULE_ARN; then

			echo "변경 시간 ${LOADING_SECOND}초 소요"
			sleep $LOADING_SECOND

			echo "기존${ING_COLOR} 컨테이너 정리"
			echo "${ING_DOCKER_COMPOSE_FILE}"
			docker-compose -p ${CONTAINER_NAME}-${ING_COLOR} -f ${ING_DOCKER_COMPOSE_FILE} down
		else
			echo "$COLOR 배포 실패"
			echo "$COLOR 컨테이너 정리"
			docker-compose -p ${CONTAINER_NAME}-$COLOR -f ${DOCKER_COMPOSE_FILE} down
			exit 1
		fi
	fi
}

#main
if [ "$(docker ps -q -f name=${CONTAINER_NAME}-blue)" ]; then
	echo "blue >> green"
	ING_COLOR="blue"
	ING_DOCKER_COMPOSE_FILE=$COMPOSE_FILE_BLUE
	start_container "green" $COMPOSE_FILE_GREEN $GREEN_SERVER_URL $GREEN_TARGET_ARN
else
	echo "green >> blue"
	ING_COLOR="green"
	ING_DOCKER_COMPOSE_FILE=$COMPOSE_FILE_GREEN
	start_container "blue" $COMPOSE_FILE_BLUE $BLUE_SERVER_URL $BLUE_TARGET_ARN
fi
