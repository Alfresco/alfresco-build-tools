#!/bin/bash
set -e

if [ -n "${DESTINATION}" ]; then
  s3_destination="${DESTINATION}"
else
  echo "::warning::s3-bucket and s3-path are deprecated, use destination instead"
  if [ -z "${S3_BUCKET}" ]; then
    echo "::error::Either destination (preferred) or s3-bucket must be set"
    exit 1
  fi
  if [ -n "${S3_PATH}" ]; then
    s3_destination="s3://${S3_BUCKET}/${S3_PATH}"
  else
    s3_destination="s3://${S3_BUCKET}"
  fi
fi
if [[ "${s3_destination}" != s3://* ]]; then
  echo "::error::destination must be an s3:// URI, got ${s3_destination}"
  exit 1
fi
if [ -z "${SOURCE}" ]; then
  echo "::warning::deploy-dir is deprecated, use source instead"
fi
source_path="${SOURCE:-${DEPLOY_DIR}}"
if [[ "${source_path}" == s3://* ]]; then
  key="${source_path#s3://}"
  bucket="${key%%/*}"
  key="${key#"${bucket}"/}"
  if [[ -n "${key}" && "${key}" != */ && "${key}" != "${bucket}" ]] \
    && aws s3api head-object --bucket "${bucket}" --key "${key}" >/dev/null 2>&1; then
    echo "Copying object ${source_path} to ${s3_destination}/"
    aws s3 cp --acl private --copy-props "${COPY_PROPS}" "${source_path}" "${s3_destination%/}/"
  else
    echo "Copying from ${source_path} to ${s3_destination}"
    aws s3 cp --acl private --recursive --copy-props "${COPY_PROPS}" "${source_path}" "${s3_destination}"
  fi
elif [ -f "${source_path}" ]; then
  echo "Uploading file ${source_path} to ${s3_destination}/"
  aws s3 cp --acl private "${source_path}" "${s3_destination%/}/"
else
  echo "Uploading from ${source_path} to ${s3_destination}"
  aws s3 cp --acl private --recursive "${source_path}" "${s3_destination}"
fi
