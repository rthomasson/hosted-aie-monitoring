#!/bin/bash

curl https://raw.githubusercontent.com/abe-hpe/hosted-aie-monitoring/refs/heads/main/aiemon.sh > ~/.aiemon/aiemon.sh
curl https://raw.githubusercontent.com/abe-hpe/hosted-aie-monitoring/refs/heads/main/aiemon.sh > ~/.aiemon/aiemon_grafana.sh
curl https://raw.githubusercontent.com/abe-hpe/hosted-aie-monitoring/refs/heads/main/mail.json > ~/.aiemon/mail.json
curl https://raw.githubusercontent.com/abe-hpe/hosted-aie-monitoring/refs/heads/main/slack.json > ~/.aiemon/slack.json
curl https://raw.githubusercontent.com/abe-hpe/hosted-aie-monitoring/refs/heads/main/slack.json > ~/.aiemon/graphite.json
chmod a+x ~/.aiemon/aiemon_grafana.sh
chmod a+x ~/.aiemon/aiemon.sh
~/.aiemon/aiemon.sh
