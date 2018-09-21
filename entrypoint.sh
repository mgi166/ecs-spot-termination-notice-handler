#!/bin/sh

which cut

# Set VERBOSE=1 to get more output
VERBOSE=${VERBOSE:-0}
function verbose () {
  [[ ${VERBOSE} -eq 1 ]] && return 0 || return 1
}

echo 'This script polls the "EC2 Spot Instance Termination Notices" endpoint to gracefully stop and then reschedule all the tasks running on this container instance, up to 2 minutes before the EC2 Spot Instance backing this node is terminated.'
echo 'See https://aws.amazon.com/blogs/aws/new-ec2-spot-instance-termination-notices/ for more information.'

AGENT_URL=${AGENT_URL:-http://localhost:51678/v1/metadata}
ECS_CLUSTER=$(curl -s ${AGENT_URL} | jq .Cluster | tr -d \")
if [ "${ECS_CLUSTER}" == "" ]; then
  echo "[ERROR] Unable to fetch the name of the cluster. Maybe a bug?: " 1>&2
  exit 1
fi

CONTAINER_INSTANCE=$(curl -s ${AGENT_URL} | jq .ContainerInstanceArn | tr -d \")
if [ "${CONTAINER_INSTANCE}" == "" ]; then
  echo "[ERROR] Unable to fetch the arn of the container instance. Maybe a bug?: " 1>&2
  exit 1
fi

ECS_REGION=$(echo ${CONTAINER_INSTANCE} | cut -f 4 -d ':')
if [ "${ECS_REGION}" == "" ]; then
  echo "[ERROR] Unable to fetch the name of the cluster region. Maybe a bug?: " 1>&2
  exit 1
fi

# Gather some information
AZ_URL=${AZ_URL:-http://169.254.169.254/latest/meta-data/placement/availability-zone}
AZ=$(curl -s ${AZ_URL})
INSTANCE_ID_URL=${INSTANCE_ID_URL:-http://169.254.169.254/latest/meta-data/instance-id}
INSTANCE_ID=$(curl -s ${INSTANCE_ID_URL})

echo "\`aws ecs update-container-instances-state\` will be executed once a termination notice is made."

POLL_INTERVAL=${POLL_INTERVAL:-5}

NOTICE_URL=${NOTICE_URL:-http://169.254.169.254/latest/meta-data/spot/termination-time}

echo "Polling ${NOTICE_URL} every ${POLL_INTERVAL} second(s)"

# To whom it may concern: http://superuser.com/questions/590099/can-i-make-curl-fail-with-an-exitcode-different-than-0-if-the-http-status-code-i
while http_status=$(curl -o /dev/null -w '%{http_code}' -sL ${NOTICE_URL}); [ ${http_status} -ne 200 ]; do
  verbose && echo $(date): ${http_status}
  sleep ${POLL_INTERVAL}
done

echo $(date): ${http_status}
MESSAGE="Spot Termination ${ECS_CLUSTER}: ${CONTAINER_INSTANCE}, Instance: ${INSTANCE_ID}, AZ: ${AZ}"

# Notify Hipchat
# Set the HIPCHAT_ROOM_ID & HIPCHAT_AUTH_TOKEN variables below.
# Further instructions at https://www.hipchat.com/docs/apiv2/auth
if [ "${HIPCHAT_AUTH_TOKEN}" != "" ]; then
  curl -H "Content-Type: application/json" \
     -H "Authorization: Bearer $HIPCHAT_AUTH_TOKEN" \
     -X POST \
     -d "{\"color\": \"purple\", \"message_format\": \"text\", \"message\": \"${MESSAGE}\" }" \
     https://api.hipchat.com/v2/room/$HIPCHAT_ROOM_ID/notification
fi

# Notify Slack incoming-webhook
# Docs: https://api.slack.com/incoming-webhooks
# Setup: https://slack.com/apps/A0F7XDUAZ-incoming-webhooks
#
# You will have to set SLACK_URL as an environment variable via PodSpec.
# The URL should look something like: https://hooks.slack.com/services/T67UBFNHQ/B4Q7WQM52/1ctEoFjkjdjwsa22934
#
if [ "${SLACK_URL}" != "" ]; then
  curl -X POST --data "payload={\"text\": \":warning: ${MESSAGE}\"}" ${SLACK_URL}
fi

# Drain the container instance.
aws ecs update-container-instances-state --region $ECS_REGION \
      --cluster $ECS_CLUSTER --container-instances $CONTAINER_INSTANCE --status DRAINING

# Sleep for 200 seconds to prevent this script from looping.
# The instance should be terminated by the end of the sleep.
sleep 200
