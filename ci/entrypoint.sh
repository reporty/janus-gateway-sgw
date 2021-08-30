#!/bin/bash

EC2_PUBLIC_IPV4=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
HEALTH_LOG_PATH=/home/ubuntu/logs/health_log.log
function get_aws_credentials() {
    # AWS_CREDENTIALS_ACCESS_KEY_ID=-1 Declared above
    # AWS_CREDENTIALS_SECRET_ACCESS_KEY=-1 Declared above
    SAVE_CREDENTIALS=-1
    echo "[+] Searching in aws credentials for profile=${AWS_CREDENTIALS_PROFILE_NAME}"
    while read line; do
        if [[ "$line" =~ "${AWS_CREDENTIALS_PROFILE_NAME}" ]]; then
            SAVE_CREDENTIALS=0
        elif [ "$SAVE_CREDENTIALS" == 0 ]; then
            if [ "$AWS_CREDENTIALS_ACCESS_KEY_ID" == -1 ]; then
                AWS_CREDENTIALS_ACCESS_KEY_ID=$(echo ${line} | sed 's/aws_access_key_id = //' | sed 's/aws_access_key_id=//')
            elif [ "$AWS_CREDENTIALS_SECRET_ACCESS_KEY" == -1 ]; then
                AWS_CREDENTIALS_SECRET_ACCESS_KEY=$(echo ${line} | sed 's/aws_secret_access_key = //' | sed 's/aws_secret_access_key=//')
                SAVE_CREDENTIALS=-1
            else
                break
            fi
        fi
    done <$AWS_CREDENTIALS_FILE_PATH
    echo "[+] Retrieved credentials are:"
    echo -e "\taccessKeyID=${AWS_CREDENTIALS_ACCESS_KEY_ID}"
    echo -e "\tsecretAccess=${AWS_CREDENTIALS_SECRET_ACCESS_KEY}"
}

function download_configurations_from_s3() {

    if [[ "$JANUS_ENV" == "local" ]]; then
        aws s3 cp s3://carbyne-deployment-conf/wgw-service/dev/deployment$DEPLOYMENT_CONF_VERSION.conf /home/ubuntu --profile ${AWS_CREDENTIALS_PROFILE_NAME}
        aws s3 cp s3://carbyne-deployment-conf/wgw-service/dev/wgw_carbyneapi-dev_com_cert.pem /home/ubuntu --profile ${AWS_CREDENTIALS_PROFILE_NAME}
        aws s3 cp s3://carbyne-deployment-conf/wgw-service/dev/wgw_carbyneapi-dev_com_key.pem /home/ubuntu --profile ${AWS_CREDENTIALS_PROFILE_NAME}
    elif [[ "$JANUS_ENV" == "prod" || "$JANUS_ENV" == "gov" ]]; then
        aws s3 cp s3://carbyne-deployment-conf-prod/wgw-service/deployment$DEPLOYMENT_CONF_VERSION.conf /home/ubuntu
        aws s3 cp s3://carbyne-deployment-conf-prod/wgw-service/wgw_carbyneapi_com_cert.pem /home/ubuntu
        aws s3 cp s3://carbyne-deployment-conf-prod/wgw-service/wgw_carbyneapi_com_key.pem /home/ubuntu
    elif [[ "$JANUS_ENV" == "stage" || "$JANUS_ENV" == "qa" || "$JANUS_ENV" == "dev" || "$JANUS_ENV" == "feature" ]]; then
        if [[ "$JANUS_ENV" == "feature" ]]; then
            JANUS_ENV="dev"
        fi
        aws s3 cp s3://carbyne-deployment-conf/wgw-service/$JANUS_ENV/deployment$DEPLOYMENT_CONF_VERSION.conf /home/ubuntu
        aws s3 cp s3://carbyne-deployment-conf/wgw-service/$JANUS_ENV/wgw_carbyneapi-dev_com_cert.pem /home/ubuntu
        aws s3 cp s3://carbyne-deployment-conf/wgw-service/$JANUS_ENV/wgw_carbyneapi-dev_com_key.pem /home/ubuntu
    else
        echo "[-] Invalid Configured Environment for WGWService: env=${JANUS_ENV}"
        exit 1
    fi

    echo "[+] Used deployment.conf following configurations:"
    cat /home/ubuntu/deployment$DEPLOYMENT_CONF_VERSION.conf
}

function install_certifications() {
    mkdir $JANUS_CERT_PATH
    if [[ "$JANUS_ENV" == "stage" || "$JANUS_ENV" == "qa" || "$JANUS_ENV" == "dev" || "$JANUS_ENV" == "feature" || "$JANUS_ENV" == "local"  ]]; then
        cp /home/ubuntu/wgw_carbyneapi-dev_com_cert.pem $CERT_PATH
        cp /home/ubuntu/wgw_carbyneapi-dev_com_key.pem $KEY_PATH
    elif [[ "$JANUS_ENV" == "prod" || "$JANUS_ENV" == "gov" ]]; then
        cp /home/ubuntu/wgw_carbyneapi_com_cert.pem $CERT_PATH
        cp /home/ubuntu/wgw_carbyneapi_com_key.pem $KEY_PATH
    fi
}

function update_public_ip_on_route_53() {
    EC2_INSTANCE_ID="$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id || terminate \"wget instance-id has failed: $?\")"
    EC2_REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')

    # Grab tag value
    EC2_DOMAIN_URL=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$EC2_INSTANCE_ID" "Name=key,Values=UrlTag" --region=$EC2_REGION --output=text | cut -f5)
    EC2_HOSTED_ZONE=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$EC2_INSTANCE_ID" "Name=key,Values=HostedZoneId" --region=$EC2_REGION --output=text | cut -f5)

    if [[ $JANUS_ENV == "prod" || $JANUS_ENV == "stage" || $JANUS_ENV == "qa" || $JANUS_ENV == "dev" || $JANUS_ENV == "feature" ]]; then
        aws route53 change-resource-record-sets --hosted-zone-id $EC2_HOSTED_ZONE --change-batch '{ "Comment": "Testing creating a record set", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name":  "'"$EC2_DOMAIN_URL"'", "Type": "A", "TTL":60, "ResourceRecords": [ { "Value": "'"$EC2_PUBLIC_IPV4"'" } ] } } ] }'

    elif [[ $JANUS_ENV == "gov" ]]; then
        aws configure set default.region us-east-1 --profile route53 --region aws-global
        aws configure set aws_access_key_id $AWS_CREDENTIALS_ACCESS_KEY_ID --profile route53 --region aws-global
        aws configure set aws_secret_access_key $AWS_CREDENTIALS_SECRET_ACCESS_KEY --profile route53 --region aws-global
        aws route53 change-resource-record-sets --hosted-zone-id $EC2_HOSTED_ZONE --change-batch '{ "Comment": "Testing creating a record set", "Changes": [ { "Action": "UPSERT", "ResourceRecordSet": { "Name":  "'"$EC2_DOMAIN_URL"'", "Type": "A", "TTL":60, "ResourceRecords": [ { "Value": "'"$EC2_PUBLIC_IPV4"'" } ] } } ] }' --profile route53 --region aws-global
        aws configure set default.region $EC2_REGION
    else
        echo "[-] Not a valid env value configured, use a proper one from the following - local, feature, dev, qa, stage, prod, gov"
        exit
    fi
    echo "[+] Updated Route53 ..."
}

function configure_application() {
    cd /home/ubuntu
    cp janus.transport.http.jcfg "$TRANSPORT_HTTP_CFG_PATH"

    local FILE1="/opt/janus/etc/janus/janus.jcfg"
    local admin_secret=$(get_conf_entry "token.admin_secret")
    local NEW_LINE="admin_secret = ${admin_secret}    # String that all Janus requests must contain"
    echo "About to Update parameter in janus.jcfg .." "$NEW_LINE"
    sed -i '/admin_secret/c\'"$NEW_LINE" "${FILE1}"

    echo 'rtp_port_range = "'$MIN_PORT'-'$MAX_PORT'"'
    local NEW_LINE2='rtp_port_range = "'$MIN_PORT'-'$MAX_PORT'"'
    echo "About to Update parameter in janus.jcfg .. " "$NEW_LINE2"
    sed -i '/rtp_port_range/c\'"$NEW_LINE2" "${FILE1}"

    local NEW_LINE3='token_auth = true         # Enable a token based authentication'
    sed -i '/token_auth =/c\'"$NEW_LINE3" "${FILE1}"

    local NEW_LINE4='turn_server ="'${WGW_URL}'"'
    echo "About to Update parameter in janus.jcfg .. " "$NEW_LINE3"
    sed -i '/turn_server =/c\'"$NEW_LINE4" "${FILE1}"

    local NEW_LINE5='nat_1_1_mapping ="'${WGW_URL}'"'
    echo "About to Update parameter in janus.jcfg .. " "$NEW_LINE3"
    sed -i '/nat_1_1_mapping =/c\'"$NEW_LINE5" "${FILE1}"

    local janus_token=$(get_conf_entry "token.janus_token")
    NEW_LINE4="token_auth_secret = ${janus_token}"

    echo "About to Update parameter in janus.jcfg .. " "$NEW_LINE4"
    sed -i '/token_auth_secret =/c\'"$NEW_LINE4" "${FILE1}"

    local sanity_token=$(get_conf_entry "token.sanity_health_check_token")
    NEW_LINE42="sanity_hc_auth_secret =${sanity_token}" # prod: sanity_hc_auth_secret'

    echo "About to Update parameter in janus.jcfg .. " "$NEW_LINE42"
    sed -i '/sanity_hc_auth_secret/c\'"$NEW_LINE42" "${FILE1}"
    local plugin_token=$(get_conf_entry "token.plugin_videoroom_token")
    local FILE2="/opt/janus/etc/janus/janus.plugin.videoroom.jcfg"
    NEW_LINE5="plugin_auth_secret=${plugin_token}"

    echo "About to Update parameter in janus.plugin.videoroom.jcfg .. " "$NEW_LINE5"
    sed -i '/plugin_auth_secret=/c\'"$NEW_LINE5" "${FILE2}"
    SGW_CREDS=$(get_conf_entry "sgw_creds")
    SGW_CREDS="${SGW_CREDS%\"}"
    SGW_CREDS_WITHOUT_QUOTES="${SGW_CREDS#\"}"
    if [[ "$JANUS_ENV" == "local" ]]; then
        SGW_CREDS_WITHOUT_QUOTES=""
    fi
    NEW_LINE6='rtsp_url="rtsp://'${SGW_CREDS_WITHOUT_QUOTES}''$SGW_URL':'$SGW_PORT'/'$SGW_APPLICATION'/" '
    sed -i '/rtsp_url=/c\'"$NEW_LINE6" "${FILE2}"

}

function update_configuration() {
    cd /home/ubuntu
    cp janus.transport.http.jcfg /opt/janus/etc/janus/.
    cp janus.transport.websockets.jcfg /opt/janus/etc/janus/.
    cp janus.jcfg /opt/janus/etc/janus/.
    cp janus.plugin.videoroom.jcfg /opt/janus/etc/janus/.
}

function configure_websockets() {

    local FILE1="/opt/janus/etc/janus/janus.transport.websockets.jcfg"

    # NEW_LINE='cert_pem = "'$CERT_PATH'"'
    # echo "About to Update..CERT_PATH" "$NEW_LINE"
    # sed -i '/cert_pem/c\'"$NEW_LINE" "${FILE1}"

    # NEW_LINE='cert_key = "'$KEY_PATH'"'
    # echo "About to Update..KEY_PATH" "$NEW_LINE"
    # sed -i '/cert_key/c\'"$NEW_LINE" "${FILE1}"

    NEW_LINE="wss_port = 8989;			# WebSockets server secure port, if enabled"
    echo "About to Update parameters .." "$NEW_LINE"
    sed -i '/#wss_port = 8989/c\'"$NEW_LINE" "${FILE1}"

    NEW_LINE="wss = true                           #  Whether to enable secure WebSockets"
    echo "About to Update..KEY_PATH" "$NEW_LINE"
    sed -i '/# Whether to enable secure WebSockets/c\'"$NEW_LINE" "${FILE1}"
    echo "UPDATE-02 DONE."
}

function run_application() {
    if [[ "$JANUS_ENV" != "local" ]]; then
        python3 /usr/bin/systemctl start coturn
        python3 /usr/bin/systemctl status coturn
        python3 /usr/bin/systemctl restart amazon-cloudwatch-agent
        if [ "${WGW_MACHINE_IP}" == -1 ]; then
            WGW_MACHINE_IP=$EC2_PUBLIC_IPV4
        fi
    else
        if [ "${WGW_MACHINE_IP}" == -1 ]; then
            echo "[-] Missing Machine/PC IP address!"
            exit 1
        fi
    fi

    /home/ubuntu/WGWService/janus --nat-1-1=${WGW_MACHINE_IP} >>$WGW_LOG_FILE_PATH 2>&1 &
}

function get_conf_entry() {
    local env_value=$(cat /home/ubuntu/deployment${DEPLOYMENT_CONF_VERSION}.conf | jq ".${1}")
    echo $env_value
}

function configure_cloud_watch() {
    CW_WGW_LOG_FILE_PATH_NEW_VALUE="\"file_path\": \"${WGW_LOG_FILE_PATH}\","
    CW_WGW_STATS_LOG_FILE_PATH_NEW_VALUE="\"file_path\": \"${HEALTH_LOG_PATH}\","

    if [[ "$JANUS_ENV" == "gov" ]]; then
        LOG_GROUP_NEW_VALUE="\"log_group_name\": \"WGW_prod\","
    else
        LOG_GROUP_NEW_VALUE="\"log_group_name\": \"WGW_${JANUS_ENV}\","
    fi
    sed -i '/"file_path": "{{WGW_LOG_FILE_PATH}}",/c\'"$CW_WGW_LOG_FILE_PATH_NEW_VALUE" amazon-cloudwatch-agent.json
    sed -i '/"file_path": "{{WGW_STATS_LOG_FILE_PATH}}",/c\'"$CW_WGW_STATS_LOG_FILE_PATH_NEW_VALUE" amazon-cloudwatch-agent.json
    sed -i '/"log_group_name": "WGW_{{JANUS_ENV}}",/c\'"$LOG_GROUP_NEW_VALUE" amazon-cloudwatch-agent.json
    sed -i '/"log_group_name": "WGW_{{JANUS_ENV}}_HEALTH_CHECK",/c\'"$LOG_GROUP_NEW_VALUE" amazon-cloudwatch-agent.json

    EC2_ID_NEW_VALUE="\"log_stream_name\": \"${EC2_ID}"
    sed -i '/"log_stream_name": "{{EC2_ID}}"/c\'"$EC2_ID_NEW_VALUE\"" amazon-cloudwatch-agent.json
    sed -i '/"log_stream_name": "{{EC2_ID}}_HEALTH_CHECK"/c\'"$EC2_ID_NEW_VALUE\"" amazon-cloudwatch-agent.json

    mkdir -p /usr/share/collectd
    mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
    touch /usr/share/collectd/types.db

    mv amazon-cloudwatch-agent.json /opt/aws/amazon-cloudwatch-agent/etc/
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
}

function configure_log_rotate() {
    #LOGROTATE
    mkdir /home/ubuntu/application-logrotate/

    local LOG_ROTATE_CONFIG_FILE_PATH=/home/ubuntu/application-logrotate/application.logrotate.conf
    local LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH=/home/ubuntu/application-logrotate/application.logrotate
    echo "${WGW_LOG_FILE_PATH} {" >${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "        su root root" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "        size 100M" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "        copytruncate" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "        rotate 1" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "}" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "${HEALTH_LOG_PATH} {" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "        su root root" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "        size 100M" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "        copytruncate" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "        rotate 1" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo "}" >>${LOG_ROTATE_CONFIG_FILE_PATH}
    echo '#!/bin/sh' >${LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH}
    echo "" >>${LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH}
    echo "/usr/sbin/logrotate /home/ubuntu/application-logrotate/application.logrotate.conf > /dev/null 2>&1" >>${LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH}
    echo 'EXITVALUE=$?' >>${LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH}
    echo 'if [ $EXITVALUE != 0 ]; then' >>${LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH}
    echo '    /usr/bin/logger -t logrotate "ALERT exited abnormally with [$EXITVALUE]"' >>${LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH}
    echo "fi" >>${LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH}
    echo "exit 0" >>${LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH}

    chmod +x ${LOG_ROTATE_CRON_TAB_SCRIPT_TO_RUN_PATH}
    echo '* * * * * /home/ubuntu/application-logrotate/application.logrotate' >application-logrotate-cron
    crontab application-logrotate-cron
}

function configure_and_setup_crontab_scheduled_jobs() {
    echo "[+] Configuring crontab scheduled jobs with scripts to run..."
    service cron start
    configure_log_rotate
    (
        crontab -l
        echo "* * * * * /home/ubuntu/is_health.sh first"
    ) | crontab
    (
        crontab -l
        echo "* * * * * /home/ubuntu/admin_clean_room.sh"
    ) | crontab
}

function configure_coturn() {
    mv /etc/turnserver.conf /etc/turnserver.conf.original
    python3 /usr/bin/systemctl stop coturn
    rm /etc/default/coturn
    echo 'TURNSERVER_ENABLED=1' >/etc/default/coturn
    chmod 755 /etc/default/coturn
    echo "# /etc/turnserver.conf
    # STUN server port is 3478 for UDP and TCP, and 5349 for TLS.
    # Allow connection on the UDP port 3478
    listening-port=1937
    # Require authentication
    fingerprint
    lt-cred-mech
    # Specify the server name and the realm that will be used
    # if is your first time configuring, just use the domain as name
    server-name='$WGW_URL'
    realm='$WGW_URL'
    turn_server='$WGW_URL'
    # Important
    # Create a test user if you want
    # You can remove this user after testing
    user=user7zhawVO86892vb6sZa7b:pwdjkdSfjkdDHIs67WJIK4S5LKJ3BFG
    total-quota=100
    stale-nonce=600
    # Specify the process user and group
    proc-user=turnserver
    proc-group=turnserver" >/etc/turnserver.conf
    chmod 755 /etc/turnserver.conf

}

function main() {

    if [ "${WGW_URL}" == -1 ]; then

        if [[ "$JANUS_ENV" != "local" ]]; then
            WGW_URL=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$EC2_INSTANCE_ID" "Name=key,Values= UrlTag" --region=$EC2_REGION --output=text | cut -f5)
        fi

    fi
    echo "[+] Starting WGWContainer..."
    if [[ "$JANUS_ENV" == "local"]]; then
        if [[ "$AWS_CREDENTIALS_ACCESS_KEY_ID" == -1 || "$AWS_CREDENTIALS_SECRET_ACCESS_KEY" == -1 ]]; then

            get_aws_credentials

        else
            echo "[+] Using received AWS credentials:"
            echo -e "\taccessKeyID=${AWS_CREDENTIALS_ACCESS_KEY_ID}"
            echo -e "\tsecretAccess=${AWS_CREDENTIALS_SECRET_ACCESS_KEY}"
        fi
    fi

    download_configurations_from_s3

    install_certifications
    update_configuration
    configure_websockets
    configure_application

    if [[ "$JANUS_ENV" != "local" ]]; then
        configure_cloud_watch
        update_public_ip_on_route_53
        configure_coturn
    else
        echo "[+] Not configuring CloudWatch and also not updating Route53 due to running in local..."
    fi

    run_application
    configure_and_setup_crontab_scheduled_jobs
}

main
exec "$@"
