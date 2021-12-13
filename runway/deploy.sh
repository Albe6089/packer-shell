#!/bin/sh
# AWS region
export REGION=us-west-2
# Hard coded deploy environment
export DEPLOY_ENVIRONMENT=dev
# Used to build a unique deploy bucket id
export ACCOUNT_ID=$(aws --region $REGION sts get-caller-identity --query "Account" --output text)
# Disable interactive deployment
export CI=true

/usr/local/bin/pipenv sync
/usr/local/bin/pipenv run runway deploy
