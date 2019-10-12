#!/bin/bash

info()
{
    echo "Info: $*"
}

warn()
{
    echo "Warning: $*"
}

fatal()
{
    echo "Fatal: $*"
}

wait_for_couchdb()
{
  local n=15

  while [ "$n" -gt 0 ]; do
    curl "`get_couchdb_url`" &>/dev/null
    [ "$?" -eq 0 ] && return 0
    sleep 1
    n=$[$n-1]
  done

  return 1
}

is_setup_needed()
{
  ! is_existing_user 'medic-api'
}

is_existing_user()
{
  local user="$1"
  shift 1

  test -f "`get_user_password_file "$user"`"
}

get_couchdb_url()
{
  echo "http://$COUCHDB_USER:$COUCHDB_PASSWORD@$COUCHDB_SERVICE_NAME:5985"
}

get_password_directory()
{
  mkdir -p "/opt/couchdb/etc/local.d/passwd"
  echo "/opt/couchdb/etc/local.d/passwd"
}

get_user_password_file()
{
  local user="$1"
  shift 1

  echo "`get_password_directory`/$user"
}

read_password()
{
  local user="$1"
  shift 1

  cat "`get_user_password_file "$user"`"
}

write_password()
{
  local passwd="$1"
  local passwd_file="$2"
  shift 2

  # Fix me: this shows up in `ps`
  echo "$passwd" > "$passwd_file"
}

generate_random_password()
{
  local file="$1"
  local bytes="$2"
  shift 1

  if [ -z "$bytes" ]; then
    bytes='8'
  fi

  openssl rand -hex -out "$file" "$bytes"
} 

create_couchdb_put()
{
  local should_auth="$1"
  local payload="$2"
  local payload_is_file="$3"

  local cmd='cat'

  if [ -z "$payload_is_file" ]; then
    cmd='echo'
  fi

  # Authenticate if needed
  if [ "$should_auth" ]; then
    echo -n 'user = "admin:' &&
    cat "`get_password_directory`/admin" &&
    echo '"'
  fi

  # Send JSON-encoded string payload if provided
  if [ "$#" -gt 1 ]; then
    echo -n 'data = "\"' &&
    "$cmd" "$payload" &&
    echo '\""'
  fi
}

create_couchdb_admin()
{
  local user="$1"
  local passwd="$2"
  shift 2

  # Refuse to overwrite password
  #if is_existing_user "$user"; then
  #  return 1
  #fi

  # Target file for new password
  #local passwd_file="`get_password_directory`/$user"

  #if [ ! -z "$passwd" ]; then
    # Password specified on command line
  #  write_password "$passwd" "$passwd_file"
  #else
    # Password randomly generated
  #  generate_random_password "$passwd_file"
  #fi

  #if [ "$?" -ne 0 ]; then
  #  return 2
  #fi

  # Authorize if admin exists
  local should_auth=''

  if is_existing_user 'admin' && [ "$user" != 'admin' ]; then
    should_auth='t'
  fi

  # Create administrative account
  #chmod 0400 "$passwd_file" &&
  #local config_url="`get_couchdb_config_url`" &&
  #create_couchdb_put "$should_auth" "$passwd_file" 't' \
  #  | curl -K- -sfX PUT "http://$COUCHDB_USER:$COUCHDB_PASSWORD@$COUCHDB_SERVICE_NAME:5985/_node/couchdb@127.0.0.1/_config/admins/$user" >/dev/null
  #curl -sX PUT http://$COUCHDB_USER:$COUCHDB_PASSWORD@$COUCHDB_SERVICE_NAME:5985/_node/couchdb@127.0.0.1/_config/admins/$user -d '"$(cat /opt/couchdb/etc/local.d/passwd/$user)"'

  #if [ ${PIPESTATUS[1]} -ne 0 ]; then
  #  return 127
  #fi

  # Create user document for administrator
  local url="`get_couchdb_url`" &&
  local id="org.couchdb.user:$user" &&
  \
  local doc="{
    \"id\": \"$id\", \"roles\": [],
    \"type\": \"user\", \"name\": \"$user\"
  }" &&
  \
  create_couchdb_put 't' \
    | curl -K- -sfX PUT -H 'Content-Type: application/json' \
        --data-binary "$doc" "$url/_users/$id" >/dev/null

  if [ ${PIPESTATUS[1]} -ne 0 ]; then
    return 126
  fi

  return 0
}

_perform_couchdb_lockdown()
{
  local section_name="$1"
  shift 1

  local base_url="`get_couchdb_url`" &&
  local url="$base_url/_node/couchdb@127.0.0.1/_config/$section_name/require_valid_user" &&
  \
  create_couchdb_put 't' 'true' \
    | curl -K- -sfX PUT "$url" >/dev/null
}

perform_couchdb_lockdown()
{
 # if [ "`get_couchdb_major_version`" -gt 1 ]; then
 #   _perform_couchdb_lockdown 'chttpd' || return "$?"
 # fi
  #_perform_couchdb_lockdown 'chttpd' || return "$?"
  #_perform_couchdb_lockdown 'couch_httpd_auth' || return "$?"
  curl -X PUT http://$COUCHDB_USER:$COUCHDB_PASSWORD@$COUCHDB_SERVICE_NAME:5985/_node/couchdb@127.0.0.1/_config/chttpd/require_valid_user -d '"true"'
}

create_system_databases()
{
  local url="`get_couchdb_url`" &&
  for db in _users _replicator _global_changes; do
    if ! curl -sfX PUT "$url/$db" >/dev/null; then
      warn "Failed to created system database '$db'"
      return "$?"
    fi
  done
}

postinstall()
{
  wait_for_couchdb

  info 'Creating system databases' &&
  create_system_databases \
    || fatal 'Failed to create one or more system databases'

  info 'Restricting CouchDB to authorized users only' &&
  perform_couchdb_lockdown

  if [ "$?" -ne 0 ]; then
    fatal "Failed to lock out invalid CouchDB users"
  fi

  info 'Creating CouchDB service accounts'

  create_couchdb_admin 'medic-api' &&
  create_couchdb_admin 'medic-couch2pg' &&
  create_couchdb_admin 'medic-sentinel' &&
  create_couchdb_admin 'horticulturalist'

  if [ "$?" -ne 0 ]; then
    fatal "Failed to create one or more service accounts"
  fi
 
  create_couchdb_admin 'medic'

  if [ "$?" -ne 0 ]; then
    fatal "Failed to create interactive admin account"
  fi

  info 'New CouchDB Administrative User: medic'
  info "New CouchDB Administrative Password: `read_password medic`"

  info 'CouchDB first run setup successful'
}

# below needs to be changed to check for user docs and create if not present
#if is_setup_needed; then
#    info 'Running CouchDB Setup'
#    postinstall "$@"
#fi
info 'Running CouchDB Setup'
postinstall "$@"

export COUCH_URL=http://medic-api:$(cat /opt/couchdb/etc/local.d/passwd/medic-api)@$COUCHDB_SERVICE_NAME:5985/medic
export NODE_PATH=/app/api/node_modules

node /app/api/server.js