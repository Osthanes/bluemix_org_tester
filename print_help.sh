#!/bin/bash

#********************************************************************************
# Copyright 2014 IBM
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#********************************************************************************

#############
# Colors    #
#############
export green='\e[0;32m'
export red='\e[0;31m'
export label_color='\e[0;33m'
export no_color='\e[0m' # No Color

echo -e "${label_color}We are sorry you are having trouble. ${no_color}"

if [ -n "$ERROR_LOG_FILE" ]; then
    if [ -e "${ERROR_LOG_FILE}" ]; then
        ERROR_COUNT=`wc "${ERROR_LOG_FILE}" | awk '{print $1}'` 
        if [ ${ERROR_COUNT} -eq 1 ]; then
            echo -e "${label_color}There was ${ERROR_COUNT} error recorded during execution:${no_color}"
        else
            echo -e "${label_color}There were ${ERROR_COUNT} errors recorded during execution:${no_color}"
        fi
        cat "${ERROR_LOG_FILE}"
    fi
fi

echo -e "There are a number of ways that you can get help:"
echo -e "1. Post a question on ${label_color} https://developer.ibm.com/answers/ ${no_color} and 'Ask a question' with tags 'docker', 'containers' and 'devops-services'"
echo -e "2. Open a Work Item in our public devops project: ${label_color} https://hub.jazz.net/project/alchemy/Alchemy-Ostanes ${no_color}"
echo 
echo -e "You can also review and fork our sample scripts on ${label_color} https://github.com/Osthanes ${no_color}"