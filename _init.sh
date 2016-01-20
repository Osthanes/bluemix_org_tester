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

########################################
# default values to build server names #
########################################
# beta servers
BETA_API_PREFIX="api-ice"
BETA_REG_PREFIX="registry-ice"
# default servers
DEF_API_PREFIX="containers-api"
DEF_REG_PREFIX="registry"

##################################################
# Simple function to only run command if DEBUG=1 # 
### ###############################################
debugme() {
  [[ $DEBUG = 1 ]] && "$@" || :
}

export -f debugme 
#########################################
# Configure log file to store errors  #
#########################################
if [ -z "$ERROR_LOG_FILE" ]; then
    ERROR_LOG_FILE="${EXT_DIR}/errors.log"
    export ERROR_LOG_FILE
fi

installwithpython27() {
    echo "Installing Python 2.7"
    sudo apt-get update &> /dev/null
    sudo apt-get -y install python2.7 &> /dev/null
    python --version 
    wget --no-check-certificate https://bootstrap.pypa.io/get-pip.py &> /dev/null
    python get-pip.py --user &> /dev/null
    export PATH=$PATH:~/.local/bin
    if [ -f icecli-3.0.zip ]; then 
        debugme echo "there was an existing icecli.zip"
        debugme ls -la 
        rm -f icecli-3.0.zip
    fi 
    wget https://static-ice.ng.bluemix.net/icecli-3.0.zip &> /dev/null
    pip install --user icecli-3.0.zip > cli_install.log 2>&1 
    debugme cat cli_install.log 
}

if [[ $DEBUG = 1 ]]; then 
    export ICE_ARGS="--verbose"
else
    export ICE_ARGS=""
fi 

set +e
set +x 

###############################
# Configure extension PATH    #
###############################
if [ -n $EXT_DIR ]; then 
    export PATH=$PATH:$EXT_DIR:
fi 

#########################################
# Configure log file to store errors  #
#########################################
if [ -z "$ERROR_LOG_FILE" ]; then
    ERROR_LOG_FILE="${EXT_DIR}/errors.log"
    export ERROR_LOG_FILE
fi

#################################
# Source git_util file          #
#################################
source ${EXT_DIR}/git_util.sh

################################
# get the extensions utilities #
################################
pushd . >/dev/null
cd $EXT_DIR 
git_retry clone https://github.com/Osthanes/utilities.git utilities
popd >/dev/null

#################################
# Source utilities sh files     #
#################################
source ${EXT_DIR}/utilities/ice_utils.sh
source ${EXT_DIR}/utilities/logging_utils.sh

################################
# Application Name and Version #
################################
# The build number for the builder is used for the version in the image tag 
# For deployers this information is stored in the $BUILD_SELECTOR variable and can be pulled out
if [ -z "$APPLICATION_VERSION" ]; then
    export SELECTED_BUILD=$(grep -Eo '[0-9]{1,100}' <<< "${BUILD_SELECTOR}")
    if [ -z $SELECTED_BUILD ]
    then 
        if [ -z $BUILD_NUMBER ]
        then 
            export APPLICATION_VERSION=$(date +%s)
        else 
            export APPLICATION_VERSION=$BUILD_NUMBER    
        fi
    else
        export APPLICATION_VERSION=$SELECTED_BUILD
    fi 
fi 
debugme echo "installing bc"
sudo apt-get install bc >/dev/null 2>&1
debugme echo "done installing bc"
if [ -n "$BUILD_OFFSET" ]; then 
    log_and_echo "$INFO" "Using BUILD_OFFSET of $BUILD_OFFSET"
    export APPLICATION_VERSION=$(echo "$APPLICATION_VERSION + $BUILD_OFFSET" | bc)
    export BUILD_NUMBER=$(echo "$BUILD_NUMBER + $BUILD_OFFSET" | bc)
fi 

log_and_echo "$INFO" "APPLICATION_VERSION: $APPLICATION_VERSION"

################################
# Setup archive information    #
################################
if [ -z $WORKSPACE ]; then 
    log_and_echo "$ERROR" "Please set WORKSPACE in the environment"
    ${EXT_DIR}/print_help.sh
    ${EXT_DIR}/utilities/sendMessage.sh -l bad -m "Failed to discover namespace. $(get_error_info)"
    exit 1
fi 

if [ -z $ARCHIVE_DIR ]; then
    log_and_echo "$LABEL" "ARCHIVE_DIR was not set, setting to WORKSPACE ${WORKSPACE}"
    export ARCHIVE_DIR="${WORKSPACE}"
fi

if [ "$ARCHIVE_DIR" == "./" ]; then
    log_and_echo "$LABEL" "ARCHIVE_DIR set relative, adjusting to current dir absolute"
    export ARCHIVE_DIR=`pwd`
fi

if [ -d $ARCHIVE_DIR ]; then
  log_and_echo "$INFO" "Archiving to $ARCHIVE_DIR"
else 
  log_and_echo "$INFO" "Creating archive directory $ARCHIVE_DIR"
  mkdir $ARCHIVE_DIR 
fi 
export LOG_DIR=$ARCHIVE_DIR

#############################
# Install Cloud Foundry CLI #
#############################
log_and_echo "$INFO" "Installing Cloud Foundry CLI"
pushd $EXT_DIR >/dev/null
gunzip cf-linux-amd64.tgz &> /dev/null
tar -xvf cf-linux-amd64.tar  &> /dev/null
${EXT_DIR}/cf help &> /dev/null
RESULT=$?
if [ $RESULT -ne 0 ]; then
    log_and_echo "$ERROR" "Could not install the Cloud Foundry CLI"
    ${EXT_DIR}/print_help.sh
    ${EXT_DIR}/utilities/sendMessage.sh -l bad -m "Failed to install Cloud Foundry CLI. $(get_error_info)"
    exit $RESULT
fi
popd >/dev/null
log_and_echo "$LABEL" "Successfully installed Cloud Foundry CLI"
${EXT_DIR}/cf target 
RESULT=$?
if [ $RESULT -ne 0 ]; then
    log_and_echo "$ERROR" "Not configured for Bluemix"
    cat ~/.
else 
    log_and_echo "$LABEL" "Successfully enabled with Cloud Foundry on Bluemix"
fi 

###############################################
# Check where the containers is supported     #
###############################################
if [ "$CF_TARGET_URL" == "https://api.stage1.ng.bluemix.net" ] || 
    [ "$CF_TARGET_URL" == "https://api.ng.bluemix.net" ] ||
    [ "$CF_TARGET_URL" == "https://api.eu-gb.bluemix.net" ]; then
   # containers is supported
    export CONTAINERS_SUPPORTED=true
else
    # containers is not supported
    export CONTAINERS_SUPPORTED=false
fi

if [ "$CONTAINERS_SUPPORTED" = true ]; then

    ######################
    # Install ICE CLI    #
    ######################
    log_and_echo "$INFO" "Installing IBM Container Service CLI"
    ice help &> /dev/null
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
        installwithpython27
        ice help &> /dev/null
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_and_echo "$ERROR" "Failed to install IBM Container Service CLI"
            debugme python --version
            ${EXT_DIR}/print_help.sh
            ${EXT_DIR}/utilities/sendMessage.sh -l bad -m "Failed to install IBM Container Service CLI. $(get_error_info)"
            exit $RESULT
        fi
        log_and_echo "$LABEL" "Successfully installed IBM Container Service CLI"
    fi
else
    log_and_echo "$INFO" "Containers is not supported in this target, we don't need to install IBM Container Service CLI"
fi

##########################################
# setup bluemix env
##########################################
# if user entered a choice, use that
if [ -n "$BLUEMIX_TARGET" ]; then
    # user entered target use that
    if [ "$BLUEMIX_TARGET" == "staging" ]; then 
        export BLUEMIX_API_HOST="api.stage1.ng.bluemix.net"
    elif [ "$BLUEMIX_TARGET" == "prod" ]; then 
        export BLUEMIX_API_HOST="api.ng.bluemix.net"
    else 
        log_and_echo "$ERROR" "Unknown Bluemix environment specified: ${BLUEMIX_TARGET}, Defaulting to production"
        export BLUEMIX_TARGET="prod"
        export BLUEMIX_API_HOST="api.ng.bluemix.net"
    fi 
else
    # try to auto-detect
    CF_API=`${EXT_DIR}/cf api`
    RESULT=$?
    debugme echo "cf api returned: $CF_API"
    if [ $RESULT -eq 0 ]; then
        # find the bluemix api host
        export BLUEMIX_API_HOST=`echo $CF_API  | awk '{print $3}' | sed '0,/.*\/\//s///'`
        echo $BLUEMIX_API_HOST | grep 'stage1'
        if [ $? -eq 0 ]; then
            # on staging, make sure bm target is set for staging
            export BLUEMIX_TARGET="staging"
        else
            # on prod, make sure bm target is set for prod
            export BLUEMIX_TARGET="prod"
        fi
    else 
        # failed, assume prod
        export BLUEMIX_TARGET="prod"
        export BLUEMIX_API_HOST="api.ng.bluemix.net"
    fi
fi
log_and_echo "$INFO" "Bluemix host is '${BLUEMIX_API_HOST}'"
log_and_echo "$INFO" "Bluemix target is '${BLUEMIX_TARGET}'"
# strip off the hostname to get full domain
CF_TARGET=`echo $BLUEMIX_API_HOST | sed 's/[^\.]*//'`

if [ "$CONTAINERS_SUPPORTED" = true ]; then
    if [ -z "$API_PREFIX" ]; then
        API_PREFIX=$DEF_API_PREFIX
    fi
    if [ -z "$REG_PREFIX" ]; then
        REG_PREFIX=$DEF_REG_PREFIX
    fi
    # build api server hostname
    export CCS_API_HOST="${API_PREFIX}${CF_TARGET}"
    # build registry server hostname
    export CCS_REGISTRY_HOST="${REG_PREFIX}${CF_TARGET}"
    # set up the ice cfg
    sed -i "s/ccs_host =.*/ccs_host = $CCS_API_HOST/g" $EXT_DIR/ice-cfg.ini
    sed -i "s/reg_host =.*/reg_host = $CCS_REGISTRY_HOST/g" $EXT_DIR/ice-cfg.ini
    sed -i "s/cf_api_url =.*/cf_api_url = $BLUEMIX_API_HOST/g" $EXT_DIR/ice-cfg.ini
    export ICE_CFG="ice-cfg.ini"

    ################################
    # Login to Container Service   #
    ################################
    login_to_container_service
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
        exit $RESULT
    fi
else
    log_and_echo "$INFO" "Containers is not supported in this target"
fi

############################
# enable logging to logmet #
############################
setup_met_logging "${BLUEMIX_USER}" "${BLUEMIX_PASSWORD}"
RESULT=$?
if [ $RESULT -ne 0 ]; then
    log_and_echo "$WARN" "LOGMET setup failed with return code ${RESULT}"
fi

###########################################
# Install cloud-cli for service providers #
###########################################
# setup cloud controller variable 
export CLOUD_CONTROLLER_API_HOST="https://ace${CF_TARGET}"
debugme echo "CLOUD_CONTROLLER_API_HOST:$CLOUD_CONTROLLER_API_HOST"

pushd . 
cd ${EXT_DIR}
if [ ! -f "cloudOECommandLine.zip" ]; then
    wget --no-check-certificate ace.ng.bluemix.net/doc/cl/downloads/cloudOECommandLine.zip &> /dev/null
fi
unzip cloudOECommandLine.zip -d cloud-cli &> /dev/null
# cloud-cli zip structure fluctuates
if [ ! -e "${EXT_DIR}/cloud-cli/bin" ]; then
    if [ -d "${EXT_DIR}/bin" ]; then
        ln -s ${EXT_DIR}/bin ${EXT_DIR}/cloud-cli/bin
    fi
fi
# check if the jre is included, if not then fake it
if [ ! -d ${EXT_DIR}/cloud-cli/cloud-cli/jre ]; then
    if [ -z `which java` ]; then
        log_and_echo "$LABEL" "Installing openjdk-7-jre to support cloud-cli"
        sudo apt-get -y install openjdk-7-jre &> /dev/null
    fi
    mkdir ${EXT_DIR}/cloud-cli/cloud-cli/jre
    mkdir ${EXT_DIR}/cloud-cli/cloud-cli/jre/bin
    ln -s `which java` ${EXT_DIR}/cloud-cli/cloud-cli/jre/bin/java
fi
export PATH=$PATH:${EXT_DIR}/cloud-cli/bin
cloud-cli target $CLOUD_CONTROLLER_API_HOST

popd

log_and_echo "$LABEL" "Initialization complete"
