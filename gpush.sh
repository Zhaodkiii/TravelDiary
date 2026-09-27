#!/bin/bash

# 一步提交并推送
# 用法: ./gpush.sh "提交信息"

# 如果没写提交信息，默认用 "更新"
msg=${1:-"更新"}

git add .
git commit -m "$msg"

