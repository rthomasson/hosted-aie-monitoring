#!/bin/bash

#email alerts
sparkpostmail() {
  local JSON=$(sed "s/##SUBJECT##/$1/" ~/.aiemon/mail.json |sed "s/##BODY##/$2/")
  curl -X POST "https://api.sparkpost.com/api/v1/transmissions" -H "Authorization: $SPARKPOSTAPIKEY" -H "Content-Type: application/json" -d "$JSON"
}

#post to the slack channel
slackmessage() {
  local JSON=$(sed "s/##MESSAGE##/$1/" ~/.aiemon/slack.json)
  curl -X POST "https://hooks.slack.com/services/$SLACKPATH" -H "Content-Type: application/json" -d "$JSON"
}

#send metric to Grafana Cloud
send_metric() {
  if  [ $NO_METRICS -ne 1 ]; then
    printf "\nSending metrics to Grafana Cloud...\n"
    # Make sure the API Key has metrics:write permission and that you're using the correct user ID for the data source (i.e. Graphite)
    local API_KEY="2349880:glc_eyJvIjoiNjAyNTY1IiwibiI6Im1pZ3JhdGVkLW1ldHJpY3NfcHVibGlzaGVyLW1ldHJpY3MtcHVibGlzaGVyIiwiayI6InM5cDcyMTBYSUhPNWtrMUUxN0ZFMGpKcCIsIm0iOnsiciI6InVzIn19"
    # Each Grafana data source has it's own URL. This is for Graphite
    local URL="https://graphite-prod-36-prod-us-west-0.grafana.net/graphite/metrics"
    # Current time needed for each metric posted to Grafana Cloud
    local TIME=$(date +%s)
    metric_value "$3"
    # post metric to the Graphite data source in Grafana Cloud
    local JSON=$(sed "s/##CLUSTERNAME##/$1/g" ~/.aiemon/graphite.json |sed "s/##SERVICE##/$2/g" | sed "s/##METRICVALUE##/$METRIC_VALUE/g" | sed "s/##TIME##/$TIME/g")
    printf  "JSON Data for curl command: $JSON \n"
    curl -k -i -X POST -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" "$URL" -d "$JSON"
  else
    printf "\nSending metrics to Grafana Cloud has been disabled...\n"
  fi
}

metric_value() {
  if  [ $1 == "UP" ]; then
    METRIC_VALUE=1
  else
    METRIC_VALUE=0
  fi
}

send_alerts() {
  if  [ $NO_ALERTS -ne 1 ]; then
    printf "\nSending alerts to Slack and email...\n"
    sparkpostmail "$1" "$2"
    slackmessage "$2"
  else
    printf "\nSending alerts to Slack and email has been disabled...\n"
  fi
}

#check kubernetes resources
#if 'requests' of cpu, memory or ephemeral storage on any node in the workload cluster > 90% then return a DOWN state
check_kubernetes_resources() {
  KUBERESOURCES_NOW="UP"
  for requestpercentage in $(kubectl describe nodes | grep -A4 'Resource                   Requests         Limits'|grep %|awk '{print $3}'|grep -oP '\(\K[^%]+')
  do 
    if [ $requestpercentage -ge 90 ]; then KUBERESOURCES_NOW="DOWN";fi
  done
}


#the file that contains results of previous check cycle
STATUSFILE=~/.aiemon/status
#current date and time
now=$(date "+%Y-%m-%d %H:%M:%S")

#determine identity of this pcai from local kubeconfig
CLUSTERNAME=$(cat ~/.kube/config |grep '    cluster:'|awk '{print $2}')

if [ -z "${CLUSTERNAME}" ];then
  echo "Unable to determine cluster name from ~/.kube/config, please check kubeconfig is in place and is readable by $USER."
  echo "Exiting.."
  exit 1
fi

printf "\n\n########################################################################\nRunning status checks for cluster: $CLUSTERNAME at $now\n########################################################################\n"
printf "Commandline Arguments: \n"
NO_ALERTS=0
NO_METRICS=1
while [ "$1" != "" ]; do
    case $1 in
        up | UP)         printf "arg-- $1\n"
                         TOGGLE=$(echo "$1" | awk '{print toupper($0)}')
                         ;;
        down | DOWN)     printf "arg-- $1\n"
                         TOGGLE=$(echo "$1" | awk '{print toupper($0)}')
                         ;;
        -n | --no_alert) printf "arg-- $1\n"
                         NO_ALERTS=1
                         ;;
        -m | --metrics)  printf "arg-- $1\n"
                         NO_METRICS=0
                         ;;
        * )              printf "Invalid commandline parameter:'$1'. Exiting... \n"
                         exit1
                         ;; 
                   
    esac
    shift
done
if [[ ( -n TOGGLE ) && ( "$TOGGLE" == "UP" || "$TOGGLE" == "DOWN" ) ]]; then
  printf "Force status to: $TOGGLE \n"
else
  TOGGLE=""   
fi  

#read the previous status of each check or set UNKNOWN
KUBEAPI_PREV=$(cat $STATUSFILE|grep KUBEAPI|awk '{print $2}'); if [ -z $KUBEAPI_PREV ]; then KUBEAPI_PREV="UNKNOWN";fi
KUBENODES_PREV=$(cat $STATUSFILE|grep KUBENODES|awk '{print $2}'); if [ -z $KUBENODES_PREV ]; then KUBENODES_PREV="UNKNOWN";fi
WEBUI_PREV=$(cat $STATUSFILE|grep WEBUI|awk '{print $2}'); if [ -z $WEBUI_PREV ]; then WEBUI_PREV="UNKNOWN";fi
KUBERESOURCES_PREV=$(cat $STATUSFILE|grep KUBERESOURCES|awk '{print $2}'); if [ -z $KUBERESOURCES_PREV ]; then KUBERESOURCES_PREV="UNKNOWN";fi
printf "\nPrevious state:\n"
echo "KUBEAPI       = $KUBEAPI_PREV"
echo "KUBENODES     = $KUBENODES_PREV"
echo "WEBUI         = $WEBUI_PREV"
echo "KUBERESOURCES = $KUBERESOURCES_PREV"

######################################################
#Check 1: get the status of the KUBEAPI
######################################################
printf "\n\n########################################################################\n"
printf "Check 1: Getting the status of the Kube API \n"
printf "########################################################################\n"
if [ $? -ne 0 ]; then
  KUBEAPI_NOW="DOWN"
else
  KUBEAPI_NOW="UP"
fi
printf "Current state of KUBEAPI = $KUBEAPI_NOW \n"

#########################################
# THE FOLLOWING LINES ARE FOR TESTING ONLY
if [ -n "${TOGGLE}" ]; then
  if [ $TOGGLE == "UP" ];then
    KUBEAPI_NOW="UP"
    KUBEAPI_PREV="DOWN"
  elif [ $TOGGLE == "DOWN" ]; then
    KUBEAPI_NOW="DOWN"
    KUBEAPI_PREV="UP"
  fi
  printf "Toggle KUBEAPI to $TOGGLE \n"
fi

send_metric "$CLUSTERNAME" "kubeapi" "$KUBEAPI_NOW"
#send alert if there was a state change
if [ $KUBEAPI_NOW != $KUBEAPI_PREV ]; then
  printf "\nAIE kubeapi status has changed! Kubeapi has changed from $KUBEAPI_PREV to $KUBEAPI_NOW Sending alerts..."
  send_alerts "$CLUSTERNAME Kubeapi $KUBEAPI_NOW" "$CLUSTERNAME ALERT $now: Kubeapi has changed from $KUBEAPI_PREV to $KUBEAPI_NOW"
fi

# Run the KUBEAPI check again, so that the other checks can run if the kube API is up - even if for testing purposes it was toggled to DOWN
if [ $? -ne 0 ]; then
  KUBEAPI_NOW="DOWN"
else
  KUBEAPI_NOW="UP"
fi
printf "\nCurrent state of KUBEAPI after reset: $KUBEAPI_NOW \n\n"

if [ $KUBEAPI_NOW == "UP" ];then
  ######################################################
  #Check 2: check the AIE homepage is accessible
  ######################################################
  printf "\n########################################################################\n"
  printf "Check 2 - determine if the AIE homepage is accessible \n"
  printf "########################################################################\n"

  # get the homepage URL using a kubeapi request
  AIEHOME=$(kubectl --request-timeout=5s -n ui get virtualservice ezaf-ui-vs -o jsonpath="{.spec.hosts[]}")
  if [ -z "${AIEHOME}" ];then
    echo "Unable to determine status of AIE virtual service... please check to see that AIE is installed and is readable by $USER."
    echo "Exiting..."
  #  exit 1
  else
    printf "AIE home is: $AIEHOME \n"  
  fi
  echo "Accessing AIE home: $AIEHOME at $now"
  WEBSTATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://$AIEHOME)
  echo "Got a status of $WEBSTATUS"

  if [ $WEBSTATUS -eq 200 ]; then
    WEBUI_NOW="UP"
  else
    WEBUI_NOW="DOWN"
  fi
  printf "Current state WEBUI = $WEBUI_NOW \n"

  #########################################
  # THE FOLLOWING LINES ARE FOR TESTING ONLY
  if [ -n "${TOGGLE}" ]; then
    if [ $TOGGLE == "UP" ];then
      WEBUI_NOW="UP"
      WEBUI_PREV="DOWN"
    elif [ $TOGGLE == "DOWN" ]; then
      WEBUI_NOW="DOWN"
      WEBUI_PREV="UP"
    fi
    printf "Toggle WEBUI to $TOGGLE \n"
  fi

  send_metric "$CLUSTERNAME" "webui" "$WEBUI_NOW"
  #send alert if there was a state change
  if [ $WEBUI_NOW != $WEBUI_PREV ]; then
    printf "\nAIE home page status has changed! WebUI status has changed from: $WEBUI_PREV to: $WEBUI_NOW  Sending alerts..."
    send_alerts "$CLUSTERNAME Web UI $WEBUI_NOW" "$CLUSTERNAME ALERT $now: Web interface has changed from $WEBUI_PREV to $WEBUI_NOW"
  fi

  ######################################################
  #Check 3: check for any nodes that are NotReady
  ######################################################
  printf "\n########################################################################\n"
  printf "Check 3 - check for any nodes that are NotReady \n"
  printf "########################################################################\n"

  NODES_NOT_READY=$(kubectl get nodes | tail -n+2 | grep NotReady |wc -l)
  if [ $NODES_NOT_READY -eq 0 ]; then
    KUBENODES_NOW="UP"
  else
    KUBENODES_NOW="DOWN"
  fi
  printf "Current state KUBENODES = $KUBENODES_NOW \n"

  #########################################
  # THE FOLLOWING LINES ARE FOR TESTING ONLY
  if [ -n "${TOGGLE}" ]; then
    if [ $TOGGLE == "UP" ];then
      KUBENODES_NOW="UP"
      KUBENODES_PREV="DOWN"
    elif [ $TOGGLE == "DOWN" ]; then
      KUBENODES_NOW="DOWN"
      KUBENODES_PREV="UP"
    fi
    printf "Toggle KUBENODES to $TOGGLE \n"
  fi

  send_metric "$CLUSTERNAME" "nodes" "$KUBENODES_NOW"
  #send alert if there was a state change
  if [ $KUBENODES_NOW != $KUBENODES_PREV ]; then
    printf "\nAIE node readiness has changed! KUBENODES status has changed from: $KUBENODES_PREV to: $KUBENODES_NOW  Sending alerts..."
    send_alerts "$CLUSTERNAME Kubernetes Nodes $KUBENODES_NOW" "$CLUSTERNAME ALERT $now: Kubernetes node state has changed from $KUBENODES_PREV to $KUBENODES_NOW"
  fi
  
  ######################################################
  #Check 4: see if any resource requests exceeds 90%
  ######################################################
  printf "\n########################################################################\n"
  printf "Check 4 - see if any resource requests exceed 90 percent \n"
  printf "########################################################################\n"
  check_kubernetes_resources
  printf "Current state KUBERESOURCES = $KUBERESOURCES_NOW \n"

  #########################################
  # THE FOLLOWING LINES ARE FOR TESTING ONLY
  if [ -n "${TOGGLE}" ]; then
    if [ $TOGGLE == "UP" ];then
      KUBERESOURCES_NOW="UP"
      KUBERESOURCES_PREV="DOWN"
    elif [ $TOGGLE == "DOWN" ]; then
      KUBERESOURCES_NOW="DOWN"
      KUBERESOURCES_PREV="UP"
    fi
    printf "Toggle KUBERESOURCES to $TOGGLE \n"
  fi

  send_metric "$CLUSTERNAME" "resources" "$KUBERESOURCES_NOW"
  #send alert if there was a state change
  if [ $KUBERESOURCES_NOW != $KUBERESOURCES_PREV ]; then
    printf "\nAIE Resource utilization has changed! KUBERESOURCES status has changed from: $KUBERESOURCES_PREV to: $KUBERESOURCES_NOW  Sending alerts..."
    send_alerts  "$CLUSTERNAME Kubernetes Resources $KUBERESOURCES_NOW" "$CLUSTERNAME ALERT $now: Kubernetes resource requests on one or more nodes have changed from $KUBERESOURCES_PREV to $KUBERESOURCES_NOW"
  fi
  
fi

#update status file with current statuses
echo "KUBEAPI $KUBEAPI_NOW" > ~/.aiemon/status
echo "KUBENODES $KUBENODES_NOW" >> ~/.aiemon/status
echo "WEBUI $WEBUI_NOW" >> ~/.aiemon/status
echo "KUBERESOURCES $KUBERESOURCES_NOW" >> ~/.aiemon/status
printf "\n\nCurrent state:\n"
echo "KUBEAPI       = $KUBEAPI_NOW"
echo "KUBENODES     = $KUBENODES_NOW"
echo "WEBUI         = $WEBUI_NOW"
echo "KUBERESOURCES = $KUBERESOURCES_NOW"
